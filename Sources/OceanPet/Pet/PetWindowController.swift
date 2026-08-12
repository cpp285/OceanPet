import AppKit
import QuartzCore
import SpriteKit

@MainActor
public final class PetWindowController: NSObject, NSWindowDelegate {
    public var onPrimaryClick: (() -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var menuProvider: (() -> NSMenu?)?
    public var onMove: ((NSRect) -> Void)?

    public let window: PetWindow
    public let scene: PetScene
    private let spriteView: PetSpriteView
    private var homeOrigin: CGPoint
    private var roamTimer: Timer?
    private var isRoaming = false
    private var isReturningHome = false
    private var isPerformingActivity = false
    private var activitiesRemaining = 0
    private var roamingPaused = false
    private var displayLink: CADisplayLink?
    private var roamTarget: CGPoint?
    private var roamPosition: CGPoint?
    private var roamVelocity = CGVector.zero
    private var lastRoamUpdateTime: TimeInterval?

    public private(set) var isRoamingEnabled: Bool {
        didSet { UserDefaults.standard.set(isRoamingEnabled, forKey: "oceanpet.roaming-enabled") }
    }

    public init(character: PetCharacter) throws {
        let size = PetWindow.contentSize
        scene = PetScene(size: size)
        spriteView = PetSpriteView(frame: NSRect(origin: .zero, size: size))
        spriteView.allowsTransparency = true
        spriteView.ignoresSiblingOrder = true
        spriteView.preferredFramesPerSecond = 60
        spriteView.presentScene(scene)

        let origin = Self.restoredOrigin(size: size)
        homeOrigin = origin
        if UserDefaults.standard.object(forKey: "oceanpet.roaming-enabled") == nil {
            isRoamingEnabled = true
        } else {
            isRoamingEnabled = UserDefaults.standard.bool(forKey: "oceanpet.roaming-enabled")
        }
        window = PetWindow(contentView: spriteView, origin: origin)
        super.init()
        window.delegate = self
        spriteView.onPrimaryClick = { [weak self] in
            self?.scene.playClickReaction()
            NSSound(named: NSSound.Name("Pop"))?.play()
            self?.onPrimaryClick?()
        }
        spriteView.onDoubleClick = { [weak self] in
            self?.scene.playClickReaction()
            self?.onDoubleClick?()
        }
        spriteView.menuProvider = { [weak self] in self?.menuProvider?() }
        spriteView.onDragBegan = { [weak self] in self?.beginUserDrag() }
        spriteView.onDragEnded = { [weak self] in self?.endUserDrag() }
        let displayLink = window.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        try scene.apply(character: character)
    }

    public func show() {
        window.orderFrontRegardless()
        scheduleRoam(after: 2.5)
    }

    public func apply(character: PetCharacter) throws {
        try scene.apply(character: character)
    }

    public func setState(_ state: PetVisualState) {
        scene.setState(state)
    }

    public func setRoamingEnabled(_ enabled: Bool) {
        isRoamingEnabled = enabled
        if enabled {
            scheduleRoam(after: 1.5)
        } else {
            cancelRoaming()
        }
    }

    public func setRoamingPaused(_ paused: Bool) {
        roamingPaused = paused
        if paused {
            cancelRoaming()
        } else {
            scheduleRoam(after: 2.0)
        }
    }

    public func moveHome(to origin: CGPoint) {
        cancelRoaming()
        window.setFrameOrigin(origin)
        homeOrigin = window.frame.origin
        persistHomeOrigin()
        scheduleRoam(after: 2.5)
    }

    public func reconcileAfterScreenChange() {
        cancelRoaming()
        window.setFrameOrigin(window.frame.origin)
        homeOrigin = window.frame.origin
        persistHomeOrigin()
        scheduleRoam(after: 2.5)
    }

    public func windowDidMove(_ notification: Notification) {
        onMove?(window.frame)
    }

    static func boundedRoamTarget(
        home: CGPoint,
        requestedOffset: CGVector,
        visibleFrame: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let horizontalRadius: CGFloat = 160
        let offsetX = min(max(requestedOffset.dx, -horizontalRadius), horizontalRadius)
        return CGPoint(
            x: min(max(home.x + offsetX, visibleFrame.minX + 8), visibleFrame.maxX - windowSize.width - 8),
            y: min(max(home.y, visibleFrame.minY), visibleFrame.maxY - windowSize.height)
        )
    }

    static func nextRoamStep(
        origin: CGPoint,
        velocity: CGVector,
        target: CGPoint,
        deltaTime: TimeInterval
    ) -> (origin: CGPoint, velocity: CGVector, reachedTarget: Bool) {
        let offset = CGVector(dx: target.x - origin.x, dy: target.y - origin.y)
        let distance = hypot(offset.dx, offset.dy)
        guard distance > 0.6 else {
            return (target, .zero, true)
        }

        let dt = CGFloat(min(max(deltaTime, 0), 1.0 / 20.0))
        guard dt > 0 else { return (origin, velocity, false) }

        let maximumSpeed: CGFloat = 78
        let acceleration: CGFloat = 165
        let braking: CGFloat = 210
        let desiredSpeed = min(maximumSpeed, sqrt(2 * braking * max(distance - 0.5, 0)))
        let desiredVelocity = CGVector(
            dx: offset.dx / distance * desiredSpeed,
            dy: offset.dy / distance * desiredSpeed
        )
        let velocityChange = CGVector(
            dx: desiredVelocity.dx - velocity.dx,
            dy: desiredVelocity.dy - velocity.dy
        )
        let velocityChangeLength = hypot(velocityChange.dx, velocityChange.dy)
        let currentSpeed = hypot(velocity.dx, velocity.dy)
        let changeRate = desiredSpeed < currentSpeed ? braking : acceleration
        let maximumChange = changeRate * dt
        let changeScale = velocityChangeLength > maximumChange && velocityChangeLength > 0
            ? maximumChange / velocityChangeLength
            : 1
        let nextVelocity = CGVector(
            dx: velocity.dx + velocityChange.dx * changeScale,
            dy: velocity.dy + velocityChange.dy * changeScale
        )
        let movement = CGVector(dx: nextVelocity.dx * dt, dy: nextVelocity.dy * dt)
        let movementLength = hypot(movement.dx, movement.dy)
        let movingTowardTarget = movement.dx * offset.dx + movement.dy * offset.dy > 0

        if movingTowardTarget && movementLength >= distance {
            return (target, .zero, true)
        }

        return (
            CGPoint(x: origin.x + movement.dx, y: origin.y + movement.dy),
            nextVelocity,
            false
        )
    }

    private func beginUserDrag() {
        cancelRoaming()
    }

    private func endUserDrag() {
        homeOrigin = window.frame.origin
        persistHomeOrigin()
        scene.setState(.idle)
        scheduleRoam(after: 2.5)
    }

    private func persistHomeOrigin() {
        UserDefaults.standard.set(homeOrigin.x, forKey: "oceanpet.position.x")
        UserDefaults.standard.set(homeOrigin.y, forKey: "oceanpet.position.y")
    }

    private func scheduleRoam(after delay: TimeInterval? = nil) {
        roamTimer?.invalidate()
        roamTimer = nil
        guard isRoamingEnabled, !roamingPaused, !isRoaming, !isPerformingActivity else { return }
        let interval = delay ?? Double.random(in: 4.5...10.5)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.beginActivityBurst() }
        }
        RunLoop.main.add(timer, forMode: .common)
        roamTimer = timer
    }

    private func beginActivityBurst() {
        guard isRoamingEnabled, !roamingPaused, !isRoaming, !isPerformingActivity else { return }
        activitiesRemaining = Int.random(in: 1...2)
        beginNextActivity()
    }

    private func beginNextActivity() {
        guard isRoamingEnabled, !roamingPaused, activitiesRemaining > 0 else {
            finishActivityBurst()
            return
        }
        isPerformingActivity = true
        let choice = Int.random(in: 0..<100)
        if choice < 45 {
            beginRoam()
            return
        }

        let state: PetVisualState
        let duration: TimeInterval
        switch choice {
        case 45..<67:
            state = .happy
            duration = 1.15
        case 67..<85:
            state = .confused
            duration = 1.35
        default:
            state = .talking
            duration = 1.0
        }
        scene.setState(state)
        scheduleActivityTimer(after: duration) { [weak self] in
            self?.completeActivityStep()
        }
    }

    private func scheduleActivityTimer(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        roamTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        roamTimer = timer
    }

    private func beginRoam() {
        guard isRoamingEnabled, !roamingPaused, !isRoaming,
              let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let direction: CGFloat = Bool.random() ? 1 : -1
        let requested = CGVector(
            dx: direction * CGFloat.random(in: 70...160),
            dy: 0
        )
        let target = Self.boundedRoamTarget(
            home: homeOrigin,
            requestedOffset: requested,
            visibleFrame: visible,
            windowSize: window.frame.size
        )
        let current = window.frame.origin
        let distance = hypot(target.x - current.x, target.y - current.y)
        guard distance > 18 else {
            completeActivityStep()
            return
        }

        startMovement(to: target, returningHome: false)
    }

    private func startMovement(to target: CGPoint, returningHome: Bool) {
        let current = window.frame.origin
        isRoaming = true
        isReturningHome = returningHome
        roamTarget = target
        roamPosition = current
        roamVelocity = .zero
        lastRoamUpdateTime = nil
        scene.setState(target.x < current.x ? .walkLeft : .walkRight)
    }

    @objc private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        updateRoaming(at: displayLink.timestamp)
        updateMousePassThrough()
    }

    private func updateMousePassThrough() {
        if spriteView.isPointerDown {
            window.ignoresMouseEvents = false
            return
        }
        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else {
            window.ignoresMouseEvents = true
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let scenePoint = scene.convertPoint(fromView: windowPoint)
        window.ignoresMouseEvents = !scene.isOpaque(at: scenePoint)
    }

    private func updateRoaming(at currentTime: TimeInterval) {
        guard isRoaming, let target = roamTarget, let position = roamPosition else {
            lastRoamUpdateTime = nil
            return
        }
        guard let previousTime = lastRoamUpdateTime else {
            lastRoamUpdateTime = currentTime
            return
        }
        lastRoamUpdateTime = currentTime

        let step = Self.nextRoamStep(
            origin: position,
            velocity: roamVelocity,
            target: target,
            deltaTime: currentTime - previousTime
        )
        roamPosition = step.origin
        roamVelocity = step.velocity
        window.setFrameOrigin(step.origin)

        if step.reachedTarget {
            isRoaming = false
            roamTarget = nil
            roamPosition = nil
            roamVelocity = .zero
            lastRoamUpdateTime = nil
            if isReturningHome {
                isReturningHome = false
                completeActivityStep()
            } else {
                scene.setState(.idle)
                scheduleActivityTimer(after: 0.35) { [weak self] in
                    self?.startMovement(to: self?.homeOrigin ?? step.origin, returningHome: true)
                }
            }
        }
    }

    private func completeActivityStep() {
        scene.setState(.idle)
        isPerformingActivity = false
        isReturningHome = false
        activitiesRemaining = max(activitiesRemaining - 1, 0)
        if activitiesRemaining > 0, isRoamingEnabled, !roamingPaused {
            scheduleActivityTimer(after: Double.random(in: 0.4...0.9)) { [weak self] in
                self?.beginNextActivity()
            }
        } else {
            finishActivityBurst()
        }
    }

    private func finishActivityBurst() {
        scene.setState(.idle)
        isPerformingActivity = false
        activitiesRemaining = 0
        scheduleRoam()
    }

    private func cancelRoaming() {
        roamTimer?.invalidate()
        roamTimer = nil
        isRoaming = false
        isReturningHome = false
        isPerformingActivity = false
        activitiesRemaining = 0
        roamTarget = nil
        roamPosition = nil
        roamVelocity = .zero
        lastRoamUpdateTime = nil
        scene.setState(.idle)
    }

    private static func restoredOrigin(size: NSSize) -> CGPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "oceanpet.position.x") != nil,
           defaults.object(forKey: "oceanpet.position.y") != nil {
            return CGPoint(
                x: defaults.double(forKey: "oceanpet.position.x"),
                y: defaults.double(forKey: "oceanpet.position.y")
            )
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return CGPoint(x: visible.maxX - size.width - 70, y: visible.minY + 54)
    }
}
