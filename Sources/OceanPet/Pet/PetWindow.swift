import AppKit

public final class PetWindow: NSPanel {
    public static let contentSize = NSSize(width: 210, height: 230)
    private static let edgeInset: CGFloat = 8

    public init(contentView: NSView, origin: CGPoint) {
        super.init(
            contentRect: NSRect(origin: origin, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        sharingType = .readOnly
        title = "OceanPet"
        self.contentView = contentView
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame else { return frameRect }
        var result = frameRect
        result.origin.x = min(max(result.origin.x, visible.minX + Self.edgeInset), visible.maxX - result.width - Self.edgeInset)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    public override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(constrainFrameRect(NSRect(origin: point, size: frame.size), to: screen).origin)
    }
}
