import AppKit
import Darwin
import Foundation
import OSLog
import ShieldStatCore

/// What happened when the user asked for a process to quit.
enum QuitOutcome {
    /// The signal, or the Quit event, went out. The process may still take a
    /// moment to go; the next refresh is what confirms it.
    case sent
    /// The pid no longer belongs to the process shown. Nothing was sent.
    case stale
    case failed(String)
}

/// Reads who holds a listening socket, and acts on it when the user says so.
///
/// Everything here is fetched when a listener is clicked, never on the refresh
/// path. The posture check runs on a timer and must stay cheap; this runs once
/// per click and can afford two subprocesses. Fetching late also means the
/// detail cannot be stale on arrival — if the socket closed in between, that is
/// what the window says.
enum ProcessDetailSource {
    private static let log = Logger(subsystem: "dev.lucascaro.ShieldStat", category: "detail")

    /// Every process holding a listening socket on `port`.
    ///
    /// Usually one. A pre-forking server or an `SO_REUSEPORT` listener gives
    /// several, and they are all returned — picking a "main" one would be a
    /// guess, and the window has room to show what is actually there.
    static func processes(listeningOn port: UInt16) -> [ListenerProcess] {
        let owners = ProcessDetailSensor.owners(
            netstat: Subprocess.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"]) ?? ""
        )

        let pids = Array(Set(owners.filter { $0.port == port }.map(\.pid))).sorted()
        guard !pids.isEmpty else { return [] }

        let lines = processLines(for: pids)

        // A pid netstat still lists can already be gone — measured, 2 of 13 on a
        // real machine. No ps row means no process, so it is dropped rather than
        // shown half-populated.
        return pids.compactMap { pid in
            guard let line = lines[pid] else { return nil }
            let path = executablePath(of: pid)

            return ListenerProcess(
                pid: pid,
                uid: line.uid,
                name: path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)",
                user: userName(uid: line.uid),
                startedAt: line.startedAt,
                elapsed: line.elapsed,
                arguments: line.arguments,
                executablePath: path,
                sockets: owners.filter { $0.pid == pid }.sorted { $0.port < $1.port }
            )
        }
    }

    /// Sends the process a Quit, or a Force Quit when `force`.
    ///
    /// The identity check is the point of this function. A pid is reused once
    /// its process exits, and the detail window is a real window that can sit
    /// open for minutes — long enough for the pid on screen to have become
    /// somebody else's. So the start instant is read again here, at the moment
    /// of the press, and compared against the one captured when the window
    /// opened. `startedAt` and not `elapsed`: elapsed time advances every
    /// second, so comparing it would refuse every press.
    static func quit(_ process: ListenerProcess, force: Bool) -> QuitOutcome {
        // uid as well as the start instant: lstart has one-second granularity, so
        // a pid reused inside the same second would otherwise compare equal.
        guard let current = processLines(for: [process.pid])[process.pid],
              current.startedAt == process.startedAt,
              current.uid == process.uid
        else {
            log.notice("refusing to signal pid \(process.pid, privacy: .public): no longer the same process")
            return .stale
        }

        // Checked again rather than trusted from the disabled button: the button
        // state is a courtesy, this is the guarantee.
        guard process.uid == getuid() else {
            return .failed("ShieldStat cannot quit processes owned by \(process.user).")
        }

        // A GUI app gets a real Quit event, so it can save and close as it would
        // from its own menu. NSRunningApplication is nil for anything that is
        // not an app, which sorts daemons onto the signal path for free.
        if let app = NSRunningApplication(processIdentifier: process.pid) {
            let sent = force ? app.forceTerminate() : app.terminate()
            return sent ? .sent : .failed("\(process.name) refused the request.")
        }

        guard kill(process.pid, force ? SIGKILL : SIGTERM) == 0 else {
            return .failed(String(cString: strerror(errno)))
        }
        return .sent
    }

    /// `lstart` is the identity, `etime` is for reading, `uid` decides what the
    /// user is allowed to do, and `args` is what the process was launched with —
    /// readable here even for root-owned processes.
    private static func processLines(for pids: [Int32]) -> [Int32: ProcessLine] {
        let arguments = ["-o", "pid=,uid=,lstart=,etime=,args=", "-p", pids.map(String.init).joined(separator: ",")]
        return ProcessDetailSensor.processes(ps: Subprocess.run("/bin/ps", arguments) ?? "")
    }

    /// The kernel's answer for which binary is running, rather than `argv[0]`,
    /// which is whatever the process was told to call itself. They differ in
    /// practice — a Node process reports a bare `node` in argv while the kernel
    /// names the interpreter it actually runs from. For a tool whose whole job
    /// is "what is this process", the spoofable one is not good enough.
    ///
    /// Works for other users' processes, root-owned ones included; it returns 0
    /// only when the pid is gone.
    private static func executablePath(of pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a macro, so it does not reach Swift. It is
        // defined as MAXPATHLEN * 4, and proc_pidpath fails outright on a buffer
        // smaller than that rather than truncating.
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<Int(length)], as: UTF8.self)
    }

    private static func userName(uid: UInt32) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "uid \(uid)" }
        return String(cString: name)
    }
}
