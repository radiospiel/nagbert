import AppKit
import SwiftUI
import NagbertCore

@main
struct NagbertApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var server: SocketServer!
    var manager: NotificationManager!

    func applicationDidFinishLaunching(_ note: Notification) {
        manager = NotificationManager()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Nagbert")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dismiss all", action: #selector(dismissAll), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nagbert", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        do {
            try NagbertPaths.ensureSupportDir()
            server = SocketServer(socketPath: NagbertPaths.socketPath) { [weak self] payload in
                guard let self else { return NotifyReply(ok: false, action: .error, message: "shutting down") }
                return self.manager.handle(payload: payload)
            }
            try server.start()
        } catch {
            NSLog("Nagbert: failed to start socket server: \(error)")
            NSApp.terminate(nil)
        }
    }

    @objc func dismissAll() { manager.dismissAll() }
    @objc func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) {
        server?.stop()
    }
}
