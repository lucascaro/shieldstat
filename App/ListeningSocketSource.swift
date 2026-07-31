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
    /// Concurrently, because neither tool needs the other's answer and this runs
    /// on a 60-second timer: two sequential reads cost twice the latency for
    /// nothing.
    static func sockets() async -> [ListeningSocket] {
        // -v adds the process:pid column, which covers root-owned sockets that
        // an unprivileged lsof cannot see at all.
        async let netstat = Subprocess.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"])
        // +c 0 lifts the 9-character cap on the COMMAND column, which otherwise
        // reports "com.docke" for com.docker.backend. The name is what the user
        // reads and what a broad dismissal keys on, so a truncated one is not
        // cosmetic.
        async let lsof = Subprocess.run("/usr/sbin/lsof", ["+c", "0", "-iTCP", "-sTCP:LISTEN", "-P", "-n"])

        return ListeningSensor.parse(netstat: await netstat ?? "", lsof: await lsof ?? "")
    }
}
