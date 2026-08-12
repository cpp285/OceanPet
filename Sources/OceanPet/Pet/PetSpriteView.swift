import AppKit
import SpriteKit

@MainActor
public final class PetSpriteView: SKView {
    public var onPrimaryClick: (() -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var menuProvider: (() -> NSMenu?)?
    public var onDragBegan: (() -> Void)?
    public var onDragEnded: (() -> Void)?

    private var downPoint: NSPoint?
    private var startingWindowOrigin: NSPoint?
    private var dragged = false
    private var pendingSingleClick: DispatchWorkItem?
    private var pointerProtectionUntil: TimeInterval = 0

    public private(set) var isPointerDown = false
    public var shouldKeepReceivingMouseEvents: Bool {
        isPointerDown || ProcessInfo.processInfo.systemUptime < pointerProtectionUntil
    }

    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        isPointerDown = true
        protectPointerEventsForDoubleClick()
        downPoint = NSEvent.mouseLocation
        startingWindowOrigin = window?.frame.origin
        dragged = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let downPoint, let startingWindowOrigin else { return }
        let point = NSEvent.mouseLocation
        if hypot(point.x - downPoint.x, point.y - downPoint.y) > 3 {
            if !dragged { onDragBegan?() }
            dragged = true
            window?.setFrameOrigin(NSPoint(
                x: startingWindowOrigin.x + point.x - downPoint.x,
                y: startingWindowOrigin.y + point.y - downPoint.y
            ))
        }
    }

    public override func mouseUp(with event: NSEvent) {
        defer {
            isPointerDown = false
            protectPointerEventsForDoubleClick()
            downPoint = nil
            startingWindowOrigin = nil
        }
        if dragged {
            pendingSingleClick?.cancel()
            onDragEnded?()
            return
        }
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick?()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.onPrimaryClick?()
            self?.pendingSingleClick = nil
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NSEvent.doubleClickInterval,
            execute: work
        )
    }

    public override func rightMouseDown(with event: NSEvent) {
        protectPointerEventsForDoubleClick()
        guard let menu = menuProvider?() else { return }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    private func protectPointerEventsForDoubleClick() {
        pointerProtectionUntil = ProcessInfo.processInfo.systemUptime
            + max(NSEvent.doubleClickInterval, 0.25)
    }
}
