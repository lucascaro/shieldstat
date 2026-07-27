import Foundation
import ShieldStatCore

/// Enumerates listening TCP sockets, with process names where they can be had
/// without privilege.
///
/// `netstat -anv` names every socket including root-owned ones, but truncates
/// at 16 characters and breaks on spaces. `lsof` gives untruncated names but,
/// without root, only for the current user's sockets. Using both names nearly
/// everything — measured, 22 of 22 wildcard listeners on a real machine.
enum ListeningSocketSource {
    static func sockets() -> [ListeningSocket] {
        ListeningSensor.parse(
            // -v adds the process:pid column, which covers root-owned sockets
            // that an unprivileged lsof cannot see at all.
            netstat: run("/usr/sbin/netstat", ["-anv", "-p", "tcp"]) ?? "",
            // +c 0 lifts the 9-character cap on the COMMAND column, which
            // otherwise reports "com.docke" for com.docker.backend. The name is
            // what a dismissal keys on, so a truncated one is not cosmetic.
            lsof: run("/usr/sbin/lsof", ["+c", "0", "-iTCP", "-sTCP:LISTEN", "-P", "-n"]) ?? ""
        )
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

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
