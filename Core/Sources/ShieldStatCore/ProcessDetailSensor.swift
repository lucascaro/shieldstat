import Foundation

/// One listening socket together with the process that holds it.
///
/// Deliberately separate from `ListeningSocket`, which is a `Set` element used
/// to collapse the dual-stack duplicates a service produces — storing a literal
/// address or a pid on that type would split `127.0.0.1` and `::1` back into two
/// rows and quietly change the listener count, the verdict and dismissal.
/// Nothing here feeds the posture check; it exists only to answer "what is this".
public struct SocketOwner: Sendable, Equatable, Hashable, Codable {
    public let pid: Int32
    public let port: UInt16
    public let scope: BindScope
    /// The literal bind address as netstat printed it: `*`, `127.0.0.1`, `::1`,
    /// `192.168.50.119`. `ListeningSocket` keeps only the `scope` this maps to.
    public let address: String

    public init(pid: Int32, port: UInt16, scope: BindScope, address: String) {
        self.pid = pid
        self.port = port
        self.scope = scope
        self.address = address
    }

    /// How the bind reads in full: `*:3000`, `127.0.0.1:8000`, `[::1]:8021`.
    ///
    /// An IPv6 literal is bracketed, because `::1:8021` reads as a run of
    /// colons rather than an address and a port. That is the RFC 3986 form and
    /// what every other tool prints.
    public var addressDescription: String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}

/// One `ps` row. Split out from `ListenerProcess` because it is exactly what the
/// text parse can know — the executable path takes a syscall, which is the App's
/// job, not this module's.
public struct ProcessLine: Sendable, Equatable, Hashable, Codable {
    public let pid: Int32
    public let uid: UInt32
    /// `ps -o lstart=` — the absolute instant the process started, as printed.
    ///
    /// The stable half of the (pid, start-time) pair that identifies a process
    /// across time, and so the only thing a PID-reuse guard can compare. Never
    /// parsed into a `Date`: two reads of the same `ps` on the same machine
    /// compare as strings, which is exactly what the guard needs and leaves no
    /// locale to get wrong.
    public let startedAt: String
    /// `ps -o etime=` — how long the process has run, as printed.
    ///
    /// Display only. It increments every second, so comparing it against an
    /// earlier read always mismatches; a guard keyed on it would look
    /// implemented and refuse every time.
    public let elapsed: String
    public let arguments: String

    public init(pid: Int32, uid: UInt32, startedAt: String, elapsed: String, arguments: String) {
        self.pid = pid
        self.uid = uid
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.arguments = arguments
    }
}

/// Everything the detail window shows about one process holding a listening
/// socket. Assembled by the App from a `ProcessLine`, the sockets that share its
/// pid, and `proc_pidpath`.
public struct ListenerProcess: Sendable, Equatable, Hashable, Codable {
    public let pid: Int32
    public let uid: UInt32
    /// Display name. From `proc_pidpath`'s last component where the kernel will
    /// give one, which is untruncated and covers root-owned processes — unlike
    /// netstat, which cuts at 16 characters, and unlike lsof, which without
    /// privilege sees only the current user's processes.
    public let name: String
    /// For display beside the name. Ownership decisions use `uid`.
    public let user: String
    public let startedAt: String
    public let elapsed: String
    public let arguments: String
    /// `proc_pidpath` — the kernel's vnode answer, not `argv[0]`. The two differ
    /// in practice: a Node process reports a bare `node` in argv while the
    /// kernel names the actual interpreter it is running from.
    public let executablePath: String?
    /// Every listening socket this pid holds, the one that was clicked included.
    public let sockets: [SocketOwner]

    public init(
        pid: Int32,
        uid: UInt32,
        name: String,
        user: String,
        startedAt: String,
        elapsed: String,
        arguments: String,
        executablePath: String?,
        sockets: [SocketOwner]
    ) {
        self.pid = pid
        self.uid = uid
        self.name = name
        self.user = user
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.arguments = arguments
        self.executablePath = executablePath
        self.sockets = sockets
    }

    /// Ports this process listens on other than `port`.
    public func otherPorts(besides port: UInt16) -> [UInt16] {
        Array(Set(sockets.map(\.port)).subtracting([port])).sorted()
    }
}

/// Reads who owns a listening socket, and what that process is.
/// Pure: parsing only, the caller supplies the text.
public enum ProcessDetailSensor {
    /// Pairs every listening socket in `netstat -anv -p tcp` with its pid.
    ///
    /// netstat rather than lsof because an unprivileged lsof cannot see other
    /// users' sockets at all — measured, it reported 26 of 39 listening sockets
    /// on a real machine, every one of them the current user's. netstat's
    /// verbose columns name all of them, and its local-address column is already
    /// the exact bind address, so lsof adds nothing here.
    public static func owners(netstat text: String) -> [SocketOwner] {
        var owners: [SocketOwner] = []

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 6,
                  columns[0].hasPrefix("tcp"),
                  columns[5] == "LISTEN",
                  let socket = ListeningSensor.parseLocalAddress(String(columns[3])),
                  let pid = pid(inTailFrom: columns)
            else { continue }

            let field = String(columns[3])
            let address = field.lastIndex(of: ".").map { String(field[..<$0]) } ?? field

            owners.append(SocketOwner(
                pid: pid,
                port: socket.port,
                scope: socket.scope,
                address: address
            ))
        }

        return owners
    }

    /// The pid out of netstat's `process:pid` column.
    ///
    /// Scanned for rather than indexed, because the column holds a name that can
    /// contain spaces and splitting on whitespace tears it apart: `Code Helper
    /// (Plu:1519` arrives as three separate fields, so a fixed index lands on
    /// `Code`. Everything after it is hex with no colon in it, so the first
    /// `…:<digits>` in the tail is the pid, wherever the name pushed it to.
    static func pid(inTailFrom columns: [Substring]) -> Int32? {
        for column in columns.dropFirst(6) {
            guard let separator = column.lastIndex(of: ":"),
                  let pid = Int32(column[column.index(after: separator)...])
            else { continue }
            return pid
        }
        return nil
    }

    /// Parses `ps -o pid=,uid=,lstart=,etime=,args=`, keyed by pid.
    ///
    /// ```
    ///     1     0 Thu May 21 14:22:40 2026     70-08:09:25 /sbin/launchd
    /// ```
    ///
    /// Read positionally, not by splitting on a delimiter: `lstart` prints five
    /// whitespace-separated fields with nothing marking where it ends, and
    /// `args` runs to the end of the line and contains spaces of its own. That
    /// puts `etime` at a fixed offset and `args` as the remainder, which is the
    /// only way to read this without guessing.
    public static func processes(ps text: String) -> [Int32: ProcessLine] {
        var lines: [Int32: ProcessLine] = [:]

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            // pid, uid, five for lstart, etime, and at least one for args.
            guard columns.count >= 9,
                  let pid = Int32(columns[0]),
                  let uid = UInt32(columns[1])
            else { continue }

            lines[pid] = ProcessLine(
                pid: pid,
                uid: uid,
                startedAt: columns[2...6].joined(separator: " "),
                elapsed: String(columns[7]),
                arguments: columns[8...].joined(separator: " ")
            )
        }

        return lines
    }
}
