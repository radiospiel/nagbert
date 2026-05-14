import AppKit
import Foundation
import NagbertCore

@MainActor
final class NotificationManager {
    private(set) var models: [NotificationModel] = []
    private var panels: [String: NotificationPanel] = [:]
    private var processes: [String: Process] = [:]
    private var checkTimers: [String: Timer] = [:]
    private var hideTimers: [String: Timer] = [:]
    private let stack = StackController()

    func handle(payload: NotifyPayload) -> NotifyReply {
        // Hop to main thread synchronously — the socket server runs on a
        // background queue but every UI mutation must happen here.
        var reply = NotifyReply(ok: true, action: .shown)
        let work = {
            reply = self._handle(payload: payload)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.sync(execute: work)
        }
        return reply
    }

    private func _handle(payload: NotifyPayload) -> NotifyReply {
        let id = payload.effectiveID
        if let existing = models.first(where: { $0.id == id }) {
            // Dedupe rules from DESIGN §4.
            let hasPerform = (existing.payload.performAction?.isEmpty == false)
            let alreadyPerformed = [.performing, .checking, .resolved, .failed].contains(existing.phase)
            if !hasPerform {
                shake(existing)
                return NotifyReply(ok: true, action: .shaken)
            }
            if !alreadyPerformed {
                shake(existing)
                return NotifyReply(ok: true, action: .shaken)
            }
            // Reset.
            cancelTimers(for: id)
            killProcess(for: id)
            existing.payload = payload
            existing.clearError()
            existing.phase = NotificationModel.initialPhase(for: payload)
            scheduleInitial(for: existing)
            return NotifyReply(ok: true, action: .replaced)
        }

        let model = NotificationModel(payload: payload)
        models.append(model)
        let panel = NotificationPanel(model: model, manager: self)
        panels[model.id] = panel
        stack.add(panel)
        scheduleInitial(for: model)
        return NotifyReply(ok: true, action: .shown)
    }

    private func scheduleInitial(for model: NotificationModel) {
        switch model.phase {
        case .info:
            let secs = model.payload.hideAfter ?? 5.0
            scheduleAutoHide(for: model, after: secs)
        case .checking:
            runCheck(for: model)
        case .idle, .persistent, .performing, .resolved, .failed, .dismissed:
            break
        }
    }

    // MARK: Actions

    func performAction(for model: NotificationModel) {
        guard let cmd = model.payload.performAction, !cmd.isEmpty else { return }
        model.clearError()
        model.phase = .performing
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", cmd]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        let id = model.id
        stderr.fileHandleForReading.readabilityHandler = { [weak self, weak model] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                guard let model else { return }
                MainActor.assumeIsolated {
                    model.appendStderr(data)
                    _ = self
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.processes.removeValue(forKey: id)
                    guard let m = self.models.first(where: { $0.id == id }) else { return }
                    if proc.terminationStatus == 0 {
                        if m.payload.checkAction?.isEmpty == false {
                            m.phase = .checking
                            self.runCheck(for: m)
                        } else {
                            m.phase = .resolved
                            self.scheduleAutoHide(for: m, after: 1.0)
                        }
                    } else {
                        m.phase = .failed
                    }
                }
            }
        }
        do {
            try process.run()
            processes[model.id] = process
        } catch {
            model.appendStderr(Data("failed to launch: \(error.localizedDescription)\n".utf8))
            model.phase = .failed
        }
    }

    func openDocumentation(for model: NotificationModel) {
        guard let s = model.payload.documentation, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    func dismiss(_ model: NotificationModel) {
        cancelTimers(for: model.id)
        killProcess(for: model.id)
        model.clearError()
        model.phase = .dismissed
        if let panel = panels.removeValue(forKey: model.id) {
            stack.remove(panel)
        }
        models.removeAll { $0.id == model.id }
    }

    func dismissAll() {
        for m in models { dismiss(m) }
    }

    // MARK: Internals

    private func runCheck(for model: NotificationModel) {
        guard let cmd = model.payload.checkAction, !cmd.isEmpty else { return }
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", cmd]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let id = model.id
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.processes.removeValue(forKey: id)
                    guard let m = self.models.first(where: { $0.id == id }) else { return }
                    if proc.terminationStatus == 0 {
                        m.phase = .resolved
                        self.scheduleAutoHide(for: m, after: 1.0)
                    } else {
                        self.scheduleRecheck(for: m)
                    }
                }
            }
        }
        do {
            try process.run()
            processes[id] = process
        } catch {
            scheduleRecheck(for: model)
        }
    }

    private func scheduleRecheck(for model: NotificationModel) {
        let id = model.id
        cancelCheckTimer(for: id)
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.checkTimers.removeValue(forKey: id)
                    if let m = self.models.first(where: { $0.id == id }) {
                        self.runCheck(for: m)
                    }
                }
            }
        }
        checkTimers[id] = t
    }

    private func scheduleAutoHide(for model: NotificationModel, after seconds: TimeInterval) {
        let id = model.id
        hideTimers[id]?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.hideTimers.removeValue(forKey: id)
                    if let m = self.models.first(where: { $0.id == id }) {
                        self.dismiss(m)
                    }
                }
            }
        }
        hideTimers[id] = t
    }

    private func cancelTimers(for id: String) {
        cancelCheckTimer(for: id)
        hideTimers[id]?.invalidate()
        hideTimers.removeValue(forKey: id)
    }

    private func cancelCheckTimer(for id: String) {
        checkTimers[id]?.invalidate()
        checkTimers.removeValue(forKey: id)
    }

    private func killProcess(for id: String) {
        if let p = processes.removeValue(forKey: id), p.isRunning {
            p.terminationHandler = nil
            p.terminate()
        }
    }

    private func shake(_ model: NotificationModel) {
        model.shaking = true
        let id = model.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let m = self.models.first(where: { $0.id == id }) {
                    m.shaking = false
                }
            }
        }
    }
}
