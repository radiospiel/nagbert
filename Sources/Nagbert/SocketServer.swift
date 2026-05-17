import Foundation
import Darwin
import NagbertCore

final class SocketServer {
    typealias Handler = (NotifyPayload) -> NotifyReply

    private let socketPath: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "nagbert.socket", qos: .userInitiated)

    init(socketPath: String, handler: @escaping Handler) {
        self.socketPath = socketPath
        self.handler = handler
    }

    func start() throws {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw POSIXError(.EIO) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw NSError(domain: "Nagbert", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket path too long"])
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in bytes.enumerated() { ptr[i] = b }
        }

        let bindResult = withUnsafePointer(to: &addr) { ap -> Int32 in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult < 0 {
            let e = errno
            close(fd)
            throw NSError(domain: "Nagbert", code: Int(e), userInfo: [
                NSLocalizedDescriptionKey: "bind: \(String(cString: strerror(e)))",
            ])
        }

        chmod(socketPath, 0o600)

        if listen(fd, 16) < 0 {
            let e = errno
            close(fd)
            throw NSError(domain: "Nagbert", code: Int(e), userInfo: [
                NSLocalizedDescriptionKey: "listen: \(String(cString: strerror(e)))",
            ])
        }

        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    private func acceptOne() {
        var addr = sockaddr()
        var len = socklen_t(MemoryLayout<sockaddr>.size)
        let client = accept(listenFD, &addr, &len)
        if client < 0 { return }
        queue.async { self.serve(client) }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var buf = Data()
        var tmp = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &tmp, tmp.count)
            if n <= 0 { break }
            buf.append(tmp, count: n)
            if buf.last == 0x0A {
                buf.removeLast()
                break
            }
            if buf.count > 1_000_000 { break }
        }
        let reply: NotifyReply
        do {
            let payload = try JSONDecoder().decode(NotifyPayload.self, from: buf)
            reply = handler(payload)
        } catch {
            reply = NotifyReply(ok: false, action: .error, message: "bad payload: \(error.localizedDescription)")
        }
        if var data = try? JSONEncoder().encode(reply) {
            data.append(0x0A)
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
    }
}
