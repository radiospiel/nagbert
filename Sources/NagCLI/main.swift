import Foundation
import NagbertCore
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Argv parsing

struct CLIArgs {
    var id: String?
    var title: String?
    var body: String?
    var level: Level = .info
    var performAction: String?
    var checkAction: String?
    var documentation: String?
    var hideAfter: Double?
    var help = false
}

func usage() -> String {
    """
    Usage: nag --title TITLE [options]

    Options:
      --id ID                  Explicit identity for dedupe
      --title TITLE            Notification title (required)
      --body BODY              Notification body
      --level LEVEL            INFO | WARN | URGENT  (default: INFO)
      --perform-action CMD     Bash command run when user clicks "Perform"
      --check-action CMD       Bash command run to verify resolution
      --documentation URL      URL opened in browser on click
      --hide-after SECONDS     Auto-hide after N seconds
      -h, --help               This help
    """
}

func parseArgs(_ argv: [String]) -> Result<CLIArgs, String> {
    var args = CLIArgs()
    var it = argv.dropFirst().makeIterator()
    while let a = it.next() {
        func value(_ name: String) -> Result<String, String> {
            guard let v = it.next() else { return .failure("missing value for \(name)") }
            return .success(v)
        }
        switch a {
        case "-h", "--help": args.help = true
        case "--id": switch value(a) { case .success(let v): args.id = v; case .failure(let e): return .failure(e) }
        case "--title": switch value(a) { case .success(let v): args.title = v; case .failure(let e): return .failure(e) }
        case "--body": switch value(a) { case .success(let v): args.body = v; case .failure(let e): return .failure(e) }
        case "--level":
            switch value(a) {
            case .success(let v):
                guard let lvl = Level(rawValue: v.uppercased()) else {
                    return .failure("invalid --level: \(v) (expected INFO/WARN/URGENT)")
                }
                args.level = lvl
            case .failure(let e): return .failure(e)
            }
        case "--perform-action": switch value(a) { case .success(let v): args.performAction = v; case .failure(let e): return .failure(e) }
        case "--check-action": switch value(a) { case .success(let v): args.checkAction = v; case .failure(let e): return .failure(e) }
        case "--documentation": switch value(a) { case .success(let v): args.documentation = v; case .failure(let e): return .failure(e) }
        case "--hide-after":
            switch value(a) {
            case .success(let v):
                guard let n = Double(v) else { return .failure("invalid --hide-after: \(v)") }
                args.hideAfter = n
            case .failure(let e): return .failure(e)
            }
        default:
            return .failure("unknown argument: \(a)")
        }
    }
    return .success(args)
}

// MARK: - Daemon discovery / auto-launch

func findDaemon() -> String? {
    let cliPath = CommandLine.arguments[0]
    let cliDir = (cliPath as NSString).deletingLastPathComponent
    let candidates = [
        cliDir + "/nagbertd",
        "/usr/local/bin/nagbertd",
        "/opt/homebrew/bin/nagbertd",
    ]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
        return c
    }
    return nil
}

func launchDaemon() throws {
    guard let path = findDaemon() else {
        throw NSError(domain: "nag", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "nagbertd not found alongside `nag`, /usr/local/bin, or /opt/homebrew/bin",
        ])
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = []
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try task.run()
    // Disown — daemon stays alive after we exit.
}

func waitForSocket(timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: NagbertPaths.socketPath) {
            return true
        }
        usleep(100_000)
    }
    return false
}

// MARK: - Socket I/O

func sendPayload(_ payload: NotifyPayload) throws -> NotifyReply {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { throw POSIXError(.EIO) }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = NagbertPaths.socketPath
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
        throw NSError(domain: "nag", code: 2, userInfo: [NSLocalizedDescriptionKey: "socket path too long"])
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
        for (i, b) in pathBytes.enumerated() {
            ptr[i] = b
        }
    }

    let result = withUnsafePointer(to: &addr) { ap -> Int32 in
        ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if result < 0 {
        throw NSError(domain: "nag", code: Int(errno), userInfo: [
            NSLocalizedDescriptionKey: "connect failed: \(String(cString: strerror(errno)))",
        ])
    }

    var data = try JSONEncoder().encode(payload)
    data.append(0x0A) // newline
    try data.withUnsafeBytes { raw in
        var remaining = raw.count
        var p = raw.baseAddress!
        while remaining > 0 {
            let n = write(fd, p, remaining)
            if n <= 0 { throw POSIXError(.EIO) }
            p = p.advanced(by: n)
            remaining -= n
        }
    }

    var buf = Data()
    var tmp = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &tmp, tmp.count)
        if n <= 0 { break }
        buf.append(tmp, count: n)
        if buf.last == 0x0A { break }
    }
    if buf.last == 0x0A { buf.removeLast() }
    return try JSONDecoder().decode(NotifyReply.self, from: buf)
}

// MARK: - Main

let parsed = parseArgs(CommandLine.arguments)
switch parsed {
case .failure(let msg):
    FileHandle.standardError.write(Data("nag: \(msg)\n\n\(usage())\n".utf8))
    exit(2)
case .success(let args):
    if args.help {
        print(usage())
        exit(0)
    }
    guard let title = args.title else {
        FileHandle.standardError.write(Data("nag: --title is required\n\n\(usage())\n".utf8))
        exit(2)
    }
    let payload = NotifyPayload(
        id: args.id,
        title: title,
        body: args.body,
        level: args.level,
        performAction: args.performAction,
        checkAction: args.checkAction,
        documentation: args.documentation,
        hideAfter: args.hideAfter
    )

    if !FileManager.default.fileExists(atPath: NagbertPaths.socketPath) {
        do {
            try launchDaemon()
        } catch {
            FileHandle.standardError.write(Data("nag: failed to launch nagbertd: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        if !waitForSocket(timeout: 5.0) {
            FileHandle.standardError.write(Data("nag: nagbertd did not open its socket within 5s\n".utf8))
            exit(1)
        }
    }

    do {
        let reply = try sendPayload(payload)
        if !reply.ok {
            FileHandle.standardError.write(Data("nag: \(reply.message ?? "error")\n".utf8))
            exit(1)
        }
    } catch {
        FileHandle.standardError.write(Data("nag: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
