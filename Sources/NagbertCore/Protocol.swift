import Foundation
import CryptoKit

public enum Level: String, Codable, Sendable {
    case info = "INFO"
    case warn = "WARN"
    case urgent = "URGENT"
}

public struct NotifyPayload: Codable, Sendable {
    public var id: String?
    public var title: String
    public var body: String?
    public var level: Level
    public var performAction: String?
    public var checkAction: String?
    public var documentation: String?
    public var hideAfter: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, body, level
        case performAction = "perform_action"
        case checkAction = "check_action"
        case documentation
        case hideAfter = "hide_after"
    }

    public init(
        id: String? = nil,
        title: String,
        body: String? = nil,
        level: Level = .info,
        performAction: String? = nil,
        checkAction: String? = nil,
        documentation: String? = nil,
        hideAfter: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.level = level
        self.performAction = performAction
        self.checkAction = checkAction
        self.documentation = documentation
        self.hideAfter = hideAfter
    }

    /// Effective identity: explicit `id` if provided, else a stable hash of the
    /// (title, body, level, perform, check) tuple.
    public var effectiveID: String {
        if let id, !id.isEmpty { return id }
        let parts = [
            title,
            body ?? "",
            level.rawValue,
            performAction ?? "",
            checkAction ?? "",
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(parts.utf8))
        return "auto-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public struct NotifyReply: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case shown, shaken, replaced, error
    }
    public var ok: Bool
    public var action: Action
    public var message: String?

    public init(ok: Bool, action: Action, message: String? = nil) {
        self.ok = ok
        self.action = action
        self.message = message
    }
}

public enum NagbertPaths {
    public static var supportDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Nagbert", isDirectory: true)
    }

    public static var socketPath: String {
        supportDir.appendingPathComponent("nagbert.sock").path
    }

    public static func ensureSupportDir() throws {
        try FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
