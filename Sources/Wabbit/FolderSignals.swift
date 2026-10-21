import Darwin
import Foundation
import WabbitCore

/// Local entry point for folder signals (docs/developer-tools.md): a Unix socket, owner-only (0600), that
/// exists only while the setting is on. A client writes one line, an absolute folder path, then closes.
/// The core validates the path. Accepting is DispatchSource-driven, nothing runs while nobody connects.
@MainActor
final class FolderSignalSocket {
    static let path = URL.applicationSupportDirectory.appending(path: "Wabbit/signal.sock").path
    private let source: DispatchSourceRead

    /// Nil when the socket can't be created (then signals only come from herdr).
    init?(onSignal: @escaping @MainActor (String) -> Void) {
        let path = Self.path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = path.withCString { p in
            withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                guard strlen(p) < buf.count else { return false }
                memcpy(buf.baseAddress!, p, strlen(p) + 1)
                return true
            }
        }
        unlink(path)  // a socket left by a crash
        let bound = ok && withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
        guard bound, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); unlink(path); return nil }
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "wabbit.signal-socket"))
        source.setEventHandler { @Sendable in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var timeout = timeval(tv_sec: 1, tv_usec: 0)  // a client that never closes can't hold the queue
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var data = [UInt8](), buf = [UInt8](repeating: 0, count: 512)
            while data.count <= Tracker.folderSignalMaxBytes + 1 {
                let n = read(client, &buf, buf.count)
                if n <= 0 { break }
                data += buf[0..<n]
                if buf[0..<n].contains(10) { break }  // one line is enough; closing lets `nc -U` exit at once
            }
            guard data.count <= Tracker.folderSignalMaxBytes + 1 else { return }
            let line = String(decoding: data.prefix { $0 != 10 }, as: UTF8.self)
            Task { @MainActor in onSignal(line) }
        }
        source.setCancelHandler { @Sendable in close(fd) }
        source.resume()
    }

    /// Closes and removes the socket file.
    func stop() { unlink(Self.path); source.cancel() }  // unlink here: a new socket may be bound right after
}

/// herdr (terminal multiplexer) reports the focused pane's folder; the terminal itself only sees herdr's
/// start folder. Read-only: runs `herdr api snapshot`, never a command that changes the session.
/// Called on events only (front app, window title), never on a timer.
enum Herdr {
    static let binary = [NSHomeDirectory() + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// The focused pane's folder when a herdr client runs inside the terminal `pid`; nil otherwise or on any failure.
    // ponytail: "a herdr client runs in this terminal", not "in its front tab": a plain tab next to a herdr tab
    // gets herdr's folder. Named sessions (`herdr --session`) aren't read, only the default one.
    nonisolated static func focusedFolder(terminalPid: pid_t) -> String? {
        guard let binary, runsHerdr(under: terminalPid) else { return nil }
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["api", "snapshot"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }  // a hung CLI
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? HerdrSnapshot.focusedFolder(data) : nil
    }

    /// A process named `herdr` among the descendants of `root` (Terminal → login → shell → herdr).
    nonisolated static func runsHerdr(under root: pid_t) -> Bool {
        var queue = [root], seen = Set<pid_t>()
        while let pid = queue.popLast(), seen.insert(pid).inserted, seen.count < 2000 {
            var kids = [pid_t](repeating: 0, count: 256)
            let n = proc_listchildpids(pid, &kids, Int32(kids.count * MemoryLayout<pid_t>.size))
            for kid in kids.prefix(max(0, Int(n))) where kid > 0 {
                var name = [CChar](repeating: 0, count: 64)
                if proc_name(kid, &name, UInt32(name.count)) > 0, strcmp(name, "herdr") == 0 { return true }
                queue.append(kid)
            }
        }
        return false
    }
}
