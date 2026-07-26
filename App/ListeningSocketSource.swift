import Foundation
import ShieldStatCore

/// Enumerates listening TCP sockets by running `netstat`.
///
/// Unprivileged on purpose. `lsof` would name the process but only sees the
/// current user's sockets without root — measured: 27 of 45 on a real machine —
/// and closing that gap needs a permanently installed root helper. A passive
/// monitor should not require more privilege than the thing it monitors.
enum ListeningSocketSource {
    private static let netstat = "/usr/sbin/netstat"

    static func sockets() -> [ListeningSocket] {
        guard let output = run() else { return [] }
        return ListeningSensor.parse(netstat: output)
    }

    private static func run() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: netstat)
        process.arguments = ["-an", "-p", "tcp"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        guard let data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
