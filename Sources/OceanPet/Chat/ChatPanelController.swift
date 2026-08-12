import AppKit
import SwiftUI

public final class ChatPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

@MainActor
public final class ChatPanelController {
    public let panel: ChatPanel
    public var onVisibilityChanged: ((Bool) -> Void)?
    private var petFrame: NSRect = .zero

    public init(
        store: ChatStore,
        onRecoverError: @escaping (ChatStore.ErrorRecoveryAction) -> Void
    ) {
        let panel = ChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 406, height: 426),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .readOnly
        panel.contentView = NSHostingView(rootView: ChatBubbleView(
            store: store,
            onClose: { [weak self, weak panel] in
                panel?.orderOut(nil)
                self?.onVisibilityChanged?(false)
            },
            onRecoverError: onRecoverError
        ))
    }

    public var isVisible: Bool { panel.isVisible }

    public func toggle(near petFrame: NSRect) {
        if panel.isVisible {
            hide()
        } else {
            show(near: petFrame)
        }
    }

    public func show(near petFrame: NSRect) {
        self.petFrame = petFrame
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChanged?(true)
    }

    public func hide() {
        panel.orderOut(nil)
        onVisibilityChanged?(false)
    }

    public func updateAnchor(petFrame: NSRect) {
        self.petFrame = petFrame
        guard panel.isVisible else { return }
        positionPanel()
    }

    private func positionPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        var origin = CGPoint(x: petFrame.minX - panel.frame.width - gap, y: petFrame.minY + 20)
        if origin.x < visible.minX {
            origin.x = petFrame.maxX + gap
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
    }
}
