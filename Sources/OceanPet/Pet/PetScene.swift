import AppKit
import SpriteKit

struct PetWalkPose {
    let verticalOffset: CGFloat
    let rotation: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
}

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
    private var visualState: PetVisualState = .idle
    private var eyeTrackingConfig: EyeTrackingConfig?
    private var eyeVisibleStates: Set<String> = []
    private var gazeTextureCache: [GazeTextureKey: SKTexture] = [:]
    private var currentGaze: GazeDirection = .center
    private var lastGazeCheck: TimeInterval = 0
    private var lastGazeChange: TimeInterval = 0
    private let spriteBottomPadding: CGFloat = 10

    public override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        sprite.position = CGPoint(x: size.width / 2, y: spriteBottomPadding)
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
            let isPixelArt = character?.manifest.usesPixelArtFiltering ?? true
            let horizontalScale: CGFloat = isPixelArt ? 1.008 : 1.0
            let verticalScale: CGFloat = isPixelArt ? 1.012 : 1.004
            let verticalMovement: CGFloat = isPixelArt ? 1.0 : 0.5
            let duration: TimeInterval = isPixelArt ? 1.05 : 1.6
            let inhale = SKAction.group([
                .scaleX(to: horizontalScale, duration: duration),
                .scaleY(to: verticalScale, duration: duration),
                .moveBy(x: 0, y: verticalMovement, duration: duration)
            ])
            inhale.timingMode = .easeInEaseOut
            let exhale = SKAction.group([
                .scaleX(to: 1, duration: duration),
                .scaleY(to: 1, duration: duration),
                .moveBy(x: 0, y: -verticalMovement, duration: duration)
            ])
            exhale.timingMode = .easeInEaseOut
            sprite.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathing")
        case .walkLeft, .walkRight:
            let cycleDuration: TimeInterval = 0.60
            let direction: CGFloat = state == .walkLeft ? -1 : 1
            let restingPosition = sprite.position
            let walkCycle = SKAction.customAction(withDuration: cycleDuration) { node, elapsedTime in
                let pose = Self.walkPose(
                    progress: elapsedTime / CGFloat(cycleDuration),
                    direction: direction
                )
                node.position = CGPoint(
                    x: restingPosition.x,
                    y: restingPosition.y + pose.verticalOffset
                )
                node.zRotation = pose.rotation
                node.xScale = pose.xScale
                node.yScale = pose.yScale
            }
            sprite.run(.repeatForever(walkCycle), withKey: "walk-motion")
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

    static func walkPose(progress: CGFloat, direction: CGFloat = 1) -> PetWalkPose {
        let normalizedProgress = progress - floor(progress)
        let phase = normalizedProgress * 2 * .pi
        let stepPulse = pow(sin(phase), 2)
        return PetWalkPose(
            verticalOffset: stepPulse * 1.4,
            rotation: sin(phase) * 0.010 * direction,
            xScale: 1 + stepPulse * 0.004,
            yScale: 1 - stepPulse * 0.003
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

        // Slender characters can have large visual gaps between limbs and props.
        // Their optional core area makes the body dependable for menus and dragging.
        if let area = character.manifest.hitArea,
           u >= area.x, u <= area.x + area.width,
           v >= area.y, v <= area.y + area.height {
            return true
        }

        let columns = character.manifest.grid.columns
        let rows = character.manifest.grid.rows
        let cellWidth = bitmap.pixelsWide / columns
        let cellHeight = bitmap.pixelsHigh / rows
        let hitPadding = character.manifest.effectiveHitPadding
        let radiusX = max(Int(ceil(hitPadding / sprite.size.width * CGFloat(cellWidth))), 1)
        let radiusY = max(Int(ceil(hitPadding / sprite.size.height * CGFloat(cellHeight))), 1)

        // SpriteKit advances animated textures independently. Test the union of the
        // current state's frames so the visible pose and its clickable area never drift apart.
        let frameCount = columns * rows
        let frameIndices = Set(character.manifest.frames(for: visualState)).filter {
            $0 >= 0 && $0 < frameCount
        }
        for frameIndex in frameIndices {
            let column = frameIndex % columns
            let topRow = frameIndex / columns
            let pixelX = min(column * cellWidth + Int(u * CGFloat(cellWidth)), bitmap.pixelsWide - 1)
            let bottomRowOrigin = bitmap.pixelsHigh - (topRow + 1) * cellHeight
            let pixelY = min(bottomRowOrigin + Int(v * CGFloat(cellHeight)), bitmap.pixelsHigh - 1)
            let frameMinX = column * cellWidth
            let frameMaxX = frameMinX + cellWidth - 1
            let frameMinY = bottomRowOrigin
            let frameMaxY = frameMinY + cellHeight - 1

            for y in max(pixelY - radiusY, frameMinY)...min(pixelY + radiusY, frameMaxY) {
                for x in max(pixelX - radiusX, frameMinX)...min(pixelX + radiusX, frameMaxX) {
                    let dx = CGFloat(x - pixelX) / CGFloat(radiusX)
                    let dy = CGFloat(y - pixelY) / CGFloat(radiusY)
                    guard dx * dx + dy * dy <= 1 else { continue }
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.12 {
                        return true
                    }
                }
            }
        }
        return false
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
        sprite.texture = textures[0]
        if textures.count > 1 {
            let frameDuration: TimeInterval
            if visualState == .walkLeft || visualState == .walkRight {
                frameDuration = character.manifest.walkFrameDuration
                    ?? character.manifest.frameDuration
            } else {
                frameDuration = character.manifest.frameDuration
            }
            let animation = SKAction.animate(
                with: textures,
                timePerFrame: max(frameDuration, 0.08),
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
            config: config,
            interpolation: pixelArt ? .none : .high
        )
        moveOriginalPupil(
            source: source,
            sourceFrame: sourceRect,
            in: cellSize,
            center: config.rightEye,
            direction: direction,
            config: config,
            interpolation: pixelArt ? .none : .high
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
        config: EyeTrackingConfig,
        interpolation: NSImageInterpolation
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
            hints: [.interpolation: interpolation.rawValue]
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
        // Keep the complete texture rectangle inside the transparent window.
        // The extra padding also protects feet during walk/rotation animations.
        sprite.position = CGPoint(
            x: size.width / 2,
            y: sprite.anchorPoint.y * sprite.size.height + spriteBottomPadding
        )
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
