import AppKit

@MainActor
public final class GlobalPushToTalk {
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPressed = false

    public init() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == 49 else { return }
        switch event.type {
        case .keyDown:
            guard event.modifierFlags.contains(.option), !event.isARepeat, !isPressed else { return }
            isPressed = true
            onPress?()
        case .keyUp:
            guard isPressed else { return }
            isPressed = false
            onRelease?()
        default:
            break
        }
    }
}
