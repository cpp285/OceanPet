import AppKit
import SpriteKit

@MainActor
public final class PetScene: SKScene {
    private enum GazeDirection: Int, Hashable {
        case center, right, upRight, up, upLeft, left, downLeft, down, downRight

        var vector: CGVector {
            switch self {
            case .center: return .zero
            case .right: return CGVector(dx: 1, dy: 0)
            case .upRight: return CGVector(dx: 0.707, dy: 0.707)
            case .up: return CGVector(dx: 0, dy: 1)
            case .upLeft: return CGVector(dx: -0.707, dy: 0.707)
            case .left: return CGVector(dx: -1, dy: 0)
            case .downLeft: return CGVector(dx: -0.707, dy: -0.707)
            case .down: return CGVector(dx: 0, dy: -1)
            case .downRight: return CGVector(dx: 0.707, dy: -0.707)
            }
        }
    }

    private struct GazeTextureKey: Hashable {
        let frame: Int
        let direction: GazeDirection
    }

    private let sprite = SKSpriteNode()
    private var character: PetCharacter?
    private var sheetTexture: SKTexture?
    private var sheetImage: NSImage?
    private var sheetBitmap: NSBitmapImageRep?
    private var currentFrameIndex = 0
    private var visualState: PetVisualState = .idle
    private var eyeTrackingConfig: EyeTrackingConfig?
    private var eyeVisibleStates: Set<String> = []
    private var gazeTextureCache: [GazeTextureKey: SKTexture] = [:]
    private var currentGaze: GazeDirection = .center
    private var lastGazeCheck: TimeInterval = 0
    private var lastGazeChange: TimeInterval = 0

    public override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        sprite.position = CGPoint(x: size.width / 2, y: 8)
        addChild(sprite)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    public func apply(character: PetCharacter) throws {
        guard let image = NSImage(contentsOf: character.spriteSheetURL) else {
            throw PetPackageError.missingSprite
        }
        self.character = character
        let texture = SKTexture(image: image)
        texture.filteringMode = filteringMode(for: character.manifest)
        sheetTexture = texture
        sheetImage = image
        gazeTextureCache.removeAll()
        currentGaze = .center
        if let data = image.tiffRepresentation {
            sheetBitmap = NSBitmapImageRep(data: data)
        }
        let cellAspect = (image.size.width / CGFloat(character.manifest.grid.columns)) /
            (image.size.height / CGFloat(character.manifest.grid.rows))
        let targetHeight: CGFloat = min(size.height - 12, 210)
        sprite.size = CGSize(width: targetHeight * cellAspect, height: targetHeight)
        configureEyeTracking(character.manifest.eyeTracking)
        setState(.idle)
    }

    public func setState(_ state: PetVisualState) {
        guard character != nil, sheetTexture != nil else { return }
        visualState = state
        sprite.removeAllActions()
        resetSpritePose()
        applyFrameTextures()

        switch state {
        case .idle:
            let inhale = SKAction.group([
                .scaleX(to: 1.008, duration: 1.05),
                .scaleY(to: 1.012, duration: 1.05),
                .moveBy(x: 0, y: 1, duration: 1.05)
            ])
            inhale.timingMode = .easeInEaseOut
            let exhale = SKAction.group([
                .scaleX(to: 1, duration: 1.05),
                .scaleY(to: 1, duration: 1.05),
                .moveBy(x: 0, y: -1, duration: 1.05)
            ])
            exhale.timingMode = .easeInEaseOut
            sprite.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathing")
        case .walkLeft, .walkRight:
            let firstStep = SKAction.group([
                .moveBy(x: 0, y: 3, duration: 0.14),
                .rotate(toAngle: -0.022, duration: 0.14),
                .scaleX(to: 1.015, duration: 0.14)
            ])
            firstStep.timingMode = .easeOut
            let secondStep = SKAction.group([
                .moveBy(x: 0, y: -3, duration: 0.14),
                .rotate(toAngle: 0.022, duration: 0.14),
                .scaleX(to: 0.985, duration: 0.14)
            ])
            secondStep.timingMode = .easeInEaseOut
            let settle = SKAction.group([
                .rotate(toAngle: 0, duration: 0.08),
                .scaleX(to: 1, duration: 0.08)
            ])
            sprite.run(.repeatForever(.sequence([firstStep, secondStep, settle])), withKey: "walk-motion")
        case .happy:
            let up = SKAction.moveBy(x: 0, y: 9, duration: 0.14)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: 0, y: -9, duration: 0.14)
            down.timingMode = .easeIn
            sprite.run(.repeatForever(.sequence([up, down])), withKey: "motion")
        case .confused:
            let left = SKAction.rotate(byAngle: -0.055, duration: 0.22)
            let right = SKAction.rotate(byAngle: 0.11, duration: 0.44)
            let center = SKAction.rotate(toAngle: 0, duration: 0.22)
            sprite.run(.repeatForever(.sequence([left, right, center])), withKey: "motion")
        case .sleepy:
            sprite.run(.repeatForever(.sequence([
                .scale(to: 0.97, duration: 0.8),
                .scale(to: 1.0, duration: 0.8)
            ])), withKey: "motion")
        default:
            break
        }
    }

    public func playClickReaction() {
        sprite.removeAction(forKey: "click")
        let squash = SKAction.group([
            .scaleX(to: 1.10, duration: 0.08),
            .scaleY(to: 0.90, duration: 0.08)
        ])
        let spring = SKAction.group([
            .scaleX(to: 1.0, duration: 0.18),
            .scaleY(to: 1.0, duration: 0.18)
        ])
        spring.timingMode = .easeOut
        sprite.run(.sequence([squash, spring]), withKey: "click")
    }

    public override func update(_ currentTime: TimeInterval) {
        guard eyeVisibleStates.contains(visualState.rawValue),
              eyeTrackingConfig != nil,
              let window = view?.window,
              currentTime - lastGazeCheck >= 1.0 / 30.0 else { return }
        lastGazeCheck = currentTime
        let cursor = NSEvent.mouseLocation
        let eyeScreenCenter = CGPoint(x: window.frame.midX, y: window.frame.minY + window.frame.height * 0.63)
        let direction = Self.gazeDirection(
            delta: CGVector(dx: cursor.x - eyeScreenCenter.x, dy: cursor.y - eyeScreenCenter.y)
        )
        guard direction != currentGaze, currentTime - lastGazeChange >= 0.09 else { return }
        currentGaze = direction
        lastGazeChange = currentTime
        applyFrameTextures()
    }

    static func pupilOffset(delta: CGVector, maxOffset: CGSize) -> CGSize {
        let distance = hypot(delta.dx, delta.dy)
        guard distance > 0.001 else { return .zero }
        let strength = min(distance / 160, 1)
        return CGSize(
            width: (delta.dx / distance) * maxOffset.width * strength,
            height: (delta.dy / distance) * maxOffset.height * strength
        )
    }

    private static func gazeDirection(delta: CGVector) -> GazeDirection {
        let distance = hypot(delta.dx, delta.dy)
        guard distance >= 48 else { return .center }
        let sector = (Int(round(atan2(delta.dy, delta.dx) / (.pi / 4))) + 8) % 8
        switch sector {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4: return .left
        case 5: return .downLeft
        case 6: return .down
        default: return .downRight
        }
    }

    public func isOpaque(at scenePoint: CGPoint) -> Bool {
        guard let bitmap = sheetBitmap, let character else { return false }
        let local = sprite.convert(scenePoint, from: self)
        let u = (local.x + sprite.anchorPoint.x * sprite.size.width) / sprite.size.width
        let v = (local.y + sprite.anchorPoint.y * sprite.size.height) / sprite.size.height
        guard u >= 0, u < 1, v >= 0, v < 1 else { return false }

        let columns = character.manifest.grid.columns
        let rows = character.manifest.grid.rows
        let cellWidth = bitmap.pixelsWide / columns
        let cellHeight = bitmap.pixelsHigh / rows
        let column = currentFrameIndex % columns
        let topRow = currentFrameIndex / columns
        let pixelX = min(column * cellWidth + Int(u * CGFloat(cellWidth)), bitmap.pixelsWide - 1)
        let bottomRowOrigin = bitmap.pixelsHigh - (topRow + 1) * cellHeight
        let pixelY = min(bottomRowOrigin + Int(v * CGFloat(cellHeight)), bitmap.pixelsHigh - 1)
        return (bitmap.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0) > 0.12
    }

    private func configureEyeTracking(_ config: EyeTrackingConfig?) {
        eyeTrackingConfig = config
        eyeVisibleStates = Set(config?.visibleStates ?? [])
    }

    private func applyFrameTextures() {
        guard let character, let sheetTexture else { return }
        let frameIndices = character.manifest.frames(for: visualState)
        let usesGaze = eyeVisibleStates.contains(visualState.rawValue)
        let textures = frameIndices.compactMap { index -> SKTexture? in
            if usesGaze, let config = eyeTrackingConfig {
                return makeGazeTexture(
                    index: index,
                    direction: currentGaze,
                    config: config,
                    manifest: character.manifest
                )
            }
            return makeTexture(index: index, manifest: character.manifest, sheet: sheetTexture)
        }
        guard !textures.isEmpty else { return }

        sprite.removeAction(forKey: "frames")
        currentFrameIndex = frameIndices.first ?? 0
        sprite.texture = textures[0]
        if textures.count > 1 {
            let animation = SKAction.animate(
                with: textures,
                timePerFrame: max(character.manifest.frameDuration, 0.08),
                resize: false,
                restore: false
            )
            sprite.run(.repeatForever(animation), withKey: "frames")
        }
    }

    private func makeGazeTexture(
        index: Int,
        direction: GazeDirection,
        config: EyeTrackingConfig,
        manifest: PetManifest
    ) -> SKTexture? {
        let key = GazeTextureKey(frame: index, direction: direction)
        if let cached = gazeTextureCache[key] { return cached }
        guard let source = sheetImage else { return nil }

        let count = manifest.grid.columns * manifest.grid.rows
        guard index >= 0, index < count else { return nil }
        let cellSize = CGSize(
            width: source.size.width / CGFloat(manifest.grid.columns),
            height: source.size.height / CGFloat(manifest.grid.rows)
        )
        let column = index % manifest.grid.columns
        let topRow = index / manifest.grid.columns
        let sourceRect = CGRect(
            x: CGFloat(column) * cellSize.width,
            y: source.size.height - CGFloat(topRow + 1) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )

        let composed = NSImage(size: cellSize)
        composed.lockFocus()
        guard let context = NSGraphicsContext.current else {
            composed.unlockFocus()
            return nil
        }
        let pixelArt = manifest.usesPixelArtFiltering
        context.imageInterpolation = pixelArt ? .none : .high
        context.shouldAntialias = !pixelArt
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: cellSize).fill()
        source.draw(
            in: NSRect(origin: .zero, size: cellSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: (pixelArt ? NSImageInterpolation.none : .high).rawValue]
        )

        moveOriginalPupil(
            source: source,
            sourceFrame: sourceRect,
            in: cellSize,
            center: config.leftEye,
            direction: direction,
            config: config
        )
        moveOriginalPupil(
            source: source,
            sourceFrame: sourceRect,
            in: cellSize,
            center: config.rightEye,
            direction: direction,
            config: config
        )
        composed.unlockFocus()

        let texture = SKTexture(image: composed)
        texture.filteringMode = filteringMode(for: manifest)
        gazeTextureCache[key] = texture
        return texture
    }

    private func moveOriginalPupil(
        source: NSImage,
        sourceFrame: CGRect,
        in cellSize: CGSize,
        center: PetPoint,
        direction: GazeDirection,
        config: EyeTrackingConfig
    ) {
        let eyeCenter = CGPoint(x: center.x * cellSize.width, y: center.y * cellSize.height)
        let clearSize = CGSize(
            width: config.maskSize.x * cellSize.width,
            height: config.maskSize.y * cellSize.height
        )
        let pupilPatchSize = CGSize(
            width: config.pupilSize.x * cellSize.width,
            height: config.pupilSize.y * cellSize.height
        )
        let offset = CGPoint(
            x: direction.vector.dx * config.maxOffset.x * cellSize.width,
            y: direction.vector.dy * config.maxOffset.y * cellSize.height
        )
        let clearRect = centeredRect(at: eyeCenter, size: clearSize).integral
        let originalPupilPatch = centeredRect(at: eyeCenter, size: pupilPatchSize).integral
        NSColor.white.setFill()
        clearRect.fill()

        let sourcePatch = originalPupilPatch.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
        let movedPatch = originalPupilPatch.offsetBy(dx: round(offset.x), dy: round(offset.y))
        source.draw(
            in: movedPatch,
            from: sourcePatch,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.none.rawValue]
        )
    }

    private func centeredRect(at center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: round(center.x - size.width / 2),
            y: round(center.y - size.height / 2),
            width: round(size.width),
            height: round(size.height)
        )
    }

    private func resetSpritePose() {
        sprite.position = CGPoint(x: size.width / 2, y: 8)
        sprite.zRotation = 0
        sprite.xScale = 1
        sprite.yScale = 1
    }

    private func makeTexture(index: Int, manifest: PetManifest, sheet: SKTexture) -> SKTexture? {
        let count = manifest.grid.columns * manifest.grid.rows
        guard index >= 0, index < count else { return nil }
        let column = index % manifest.grid.columns
        let topRow = index / manifest.grid.columns
        let width = 1.0 / CGFloat(manifest.grid.columns)
        let height = 1.0 / CGFloat(manifest.grid.rows)
        let rect = CGRect(
            x: CGFloat(column) * width,
            y: 1.0 - CGFloat(topRow + 1) * height,
            width: width,
            height: height
        )
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = filteringMode(for: manifest)
        return texture
    }

    private func filteringMode(for manifest: PetManifest) -> SKTextureFilteringMode {
        manifest.usesPixelArtFiltering ? .nearest : .linear
    }
}
