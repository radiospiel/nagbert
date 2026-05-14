import Foundation
import SwiftUI
import NagbertCore

enum Phase: Equatable {
    case info
    case idle
    case performing
    case checking
    case resolved
    case failed
    case persistent
    case dismissed
}

@MainActor
final class NotificationModel: ObservableObject, Identifiable {
    let id: String
    @Published var payload: NotifyPayload
    @Published var phase: Phase
    @Published var errorBuffer: Data = Data()
    @Published var errorTruncated: Bool = false
    @Published var showFullError: Bool = false
    @Published var shaking: Bool = false

    static let softCap = 10 * 1024
    static let hardCap = 16 * 1024

    init(payload: NotifyPayload) {
        self.id = payload.effectiveID
        self.payload = payload
        self.phase = NotificationModel.initialPhase(for: payload)
    }

    static func initialPhase(for payload: NotifyPayload) -> Phase {
        let hasPerform = (payload.performAction?.isEmpty == false)
        let hasCheck = (payload.checkAction?.isEmpty == false)
        if !hasPerform && !hasCheck {
            return payload.level == .info ? .info : .persistent
        }
        if !hasPerform && hasCheck {
            return .checking
        }
        return .idle
    }

    func appendStderr(_ chunk: Data) {
        if errorBuffer.count >= NotificationModel.hardCap {
            errorTruncated = true
            return
        }
        let room = NotificationModel.hardCap - errorBuffer.count
        if chunk.count > room {
            errorBuffer.append(chunk.prefix(room))
            errorTruncated = true
        } else {
            errorBuffer.append(chunk)
        }
    }

    func clearError() {
        errorBuffer = Data()
        errorTruncated = false
        showFullError = false
    }

    var stderrString: String {
        var s = String(data: errorBuffer, encoding: .utf8) ?? ""
        if errorTruncated { s += "\n[…truncated]" }
        return s
    }

    var stderrPreview: String {
        let s = String(data: errorBuffer, encoding: .utf8) ?? ""
        let lines = s.split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(lines.prefix(2)).joined(separator: "\n")
    }
}
