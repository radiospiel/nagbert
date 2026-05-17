import AppKit
import SwiftUI

final class NotificationPanel: NSPanel {
    let modelID: String
    private let hosting: NSHostingView<NotificationView>

    init(model: NotificationModel, manager: NotificationManager) {
        self.modelID = model.id
        self.hosting = NSHostingView(rootView: NotificationView(model: model, manager: manager))
        let initial = NSRect(x: 0, y: 0, width: 340, height: 120)
        super.init(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false

        hosting.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: initial)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container

        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func fadeOut(_ completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    /// Recompute height to fit current SwiftUI content.
    func updateSize() {
        let fitting = hosting.fittingSize
        var frame = self.frame
        let oldHeight = frame.size.height
        frame.size.width = 340
        frame.size.height = max(80, fitting.height)
        frame.origin.y += (oldHeight - frame.size.height)
        setFrame(frame, display: true, animate: false)
    }
}
