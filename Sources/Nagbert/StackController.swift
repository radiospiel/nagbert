import AppKit

@MainActor
final class StackController {
    private var panels: [NotificationPanel] = []
    private let topInset: CGFloat = 36
    private let rightInset: CGFloat = 16
    private let gap: CGFloat = 10

    func add(_ panel: NotificationPanel) {
        panels.append(panel)
        panel.orderFrontRegardless()
        relayout()
        panel.fadeIn()
    }

    func remove(_ panel: NotificationPanel) {
        panels.removeAll { $0 === panel }
        panel.fadeOut { [weak panel] in
            panel?.orderOut(nil)
        }
        relayout()
    }

    func relayout() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var y = visible.maxY - topInset
        for panel in panels {
            panel.updateSize()
            let size = panel.frame.size
            let x = visible.maxX - rightInset - size.width
            let frame = NSRect(x: x, y: y - size.height, width: size.width, height: size.height)
            panel.setFrame(frame, display: true, animate: true)
            y -= (size.height + gap)
        }
    }
}
