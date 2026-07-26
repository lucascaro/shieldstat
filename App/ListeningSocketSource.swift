import Foundation
import ShieldStatCore

/// Enumerates listening TCP sockets, with process names where they can be had
/// without privilege.
///
/// `netstat` sees every socket but names none. `lsof` names them but, without
/// root, only the current user's — measured, 8 of 21 wildcard listeners on a
/// real machine. Those 8 are the user-facing apps worth dismissing (Spotify,
/// Docker, Control Center); the remainder are system daemons, nameable only by
/// a root helper this project declines to install. Using both gives every
/// socket with a name attached wherever one is obtainable.
enum ListeningSocketSource {
    static func sockets() -> [ListeningSocket] {
        ListeningSensor.parse(
            netstat: run("/usr/sbin/netstat", ["-an", "-p", "tcp"]) ?? "",
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
