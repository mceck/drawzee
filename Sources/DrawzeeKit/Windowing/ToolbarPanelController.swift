import AppKit
import QuartzCore
import SwiftUI

/// The single draggable tool sidebar. It is a `.nonactivatingPanel` so it can
/// become key (needed for its own controls and for tool-shortcut keystrokes)
/// without activating Drawzee as the frontmost application, and sits one level
/// above the per-screen canvas panels so its clicks never leak through to the
/// canvas beneath it.
public final class ToolbarPanelController: NSObject {
    public weak var coordinator: DrawSessionCoordinator?

    private let panel: NSPanel
    private var hostingView: NSView?

    /// Full height showing every tool/action button; tuned by hand to match
    /// `ToolbarView`'s expanded content exactly (no dead draggable space below it).
    private let expandedHeight: CGFloat = 620
    /// Collapsed height showing just the color swatch and the collapse toggle; same
    /// tuning approach as `expandedHeight`, sized for a 26pt swatch and a 36pt button.
    private let collapsedHeight: CGFloat = 114

    public override init() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 68, height: 620),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        super.init()
    }

    public func show(on screen: NSScreen?) {
        guard let coordinator else { return }
        if hostingView == nil {
            let hosting = NSHostingView(rootView: ToolbarView(coordinator: coordinator))
            panel.contentView = hosting
            hostingView = hosting
        }
        if let screen {
            let origin = CGPoint(x: screen.frame.minX + 28, y: screen.frame.midY - panel.frame.height / 2)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// Resizes the panel keeping its top edge fixed, so collapsing/expanding only
    /// grows or shrinks it downward instead of shifting the whole toolbar (and the
    /// color swatch anchored at its top) up or down on screen. Uses an explicit,
    /// short duration (rather than the legacy `animate: true` heuristic) so callers
    /// can rely on it finishing before `DrawSessionCoordinator`'s content-fade delay.
    public func setCollapsed(_ collapsed: Bool) {
        let newHeight = collapsed ? collapsedHeight : expandedHeight
        var frame = panel.frame
        guard frame.height != newHeight else { return }
        let top = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = top - newHeight
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Restores key status to the toolbar after a canvas panel borrowed it for
    /// text editing (only meaningful while the toolbar is still on screen).
    public func reclaimKey() {
        guard panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    public var windowNumber: Int { panel.windowNumber }
}
