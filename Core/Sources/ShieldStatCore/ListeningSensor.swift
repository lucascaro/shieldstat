import Foundation

/// Where a listening socket is bound, which is what decides whether anything
/// outside this machine could ever reach it.
public enum BindScope: String, Sendable, Codable, CaseIterable {
    /// `127.0.0.1` or `::1` — unreachable from anywhere else, always.
    case loopback
    /// `*` / `0.0.0.0` / `::` — every interface this Mac has or will have.
    case allInterfaces
    /// One specific non-loopback address.
    case specificAddress
}

/// What a Dismissal is keyed to.
///
/// Process name where it is known, because ports are not stable: Spotify holds
/// 57621 permanently but also an ephemeral port that rotates, and a port-keyed
/// dismissal would decay every time it moved. Falls back to the port for the
/// root-owned daemons an unprivileged `lsof` cannot name.
public enum ListenerKey: Hashable, Sendable, Codable {
    case process(String)
    case port(UInt16)
}

/// A TCP socket in LISTEN state.
///
/// `process` is best-effort: an unprivileged `lsof` names sockets owned by the
/// current user — measured, 8 of 21 wildcard listeners on a real machine — and
/// those are exactly the user-facing apps worth dismissing. The rest are system
/// daemons, nameable only by a root helper this project declines to install.
public struct ListeningSocket: Sendable, Equatable, Hashable, Codable {
    public let port: UInt16
    public let scope: BindScope
    public let process: String?

    public init(port: UInt16, scope: BindScope, process: String? = nil) {
        self.port = port
        self.scope = scope
        self.process = process
    }

    /// What a plain dismissal keys on: this port and nothing else.
    ///
    /// Deliberately *not* the process. Keying on the process would make one
    /// click cover every port that process opens later, which is convenient for
    /// Spotify's rotating peer-discovery port and dangerous for Docker, whose
    /// whole job is publishing arbitrary ports. Broad dismissal exists, but it
    /// has to be chosen explicitly.
    public var key: ListenerKey { .port(port) }

    /// The broader key, offered as a separate and deliberate action.
    public var processKey: ListenerKey? {
        process.map(ListenerKey.process)
    }

    /// A socket is dismissed if its port was dismissed, or if its process was
    /// dismissed wholesale.
    public func isDismissed(by dismissals: Set<ListenerKey>) -> Bool {
        if dismissals.contains(.port(port)) { return true }
        if let processKey, dismissals.contains(processKey) { return true }
        return false
    }

    /// Loopback sockets are unreachable from anywhere else, so they never count.
    public var isReachable: Bool { scope != .loopback }

    public var label: String {
        process.map { "\($0) · \(port)" } ?? "port \(port)"
    }

    /// A short note on what the port conventionally carries. Most useful for
    /// sockets with no process name, where the number alone says nothing and a
    /// dismissal would otherwise be a guess.
    public var portDescription: String? {
        WellKnownPorts.description(of: port)
    }
}

/// Reads listening TCP sockets. Pure: parsing only, the caller supplies the text.
public enum ListeningSensor {
    /// Parses `netstat -an -p tcp`, optionally enriched with the output of
    /// `lsof -iTCP -sTCP:LISTEN -P -n` for process names.
    ///
    /// ponytail: parses text rather than reading the TCP PCB list via
    /// `net.inet.tcp.pcblist_n`. The sysctl avoids two subprocesses but means
    /// decoding kernel structs that shift between releases. Upgrade if it ever
    /// shows up in a profile.
    public static func parse(netstat text: String, lsof: String = "") -> [ListeningSocket] {
        let names = processNames(lsof: lsof)
        var found = Set<ListeningSocket>()

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 6,
                  columns[0].hasPrefix("tcp"),
                  columns[5] == "LISTEN",
                  let socket = parseLocalAddress(String(columns[3]))
            else { continue }

            // `netstat -anv` carries "process:pid" in column 11 for *every*
            // socket, including root-owned ones an unprivileged lsof cannot see.
            // It truncates at 16 characters and breaks on spaces, so lsof's name
            // wins when there is one.
            let fromNetstat = columns.count >= 11 ? processName(column: String(columns[10])) : nil

            // A dual-stack service appears once per family; it is one service.
            found.insert(ListeningSocket(
                port: socket.port,
                scope: socket.scope,
                process: names[socket.port] ?? fromNetstat
            ))
        }

        return found.sorted { ($0.port, $0.scope.rawValue) < ($1.port, $1.scope.rawValue) }
    }

    /// `Spotify 31090 lucascaro 295u IPv4 0x… 0t0 TCP *:57621 (LISTEN)`
    static func processNames(lsof text: String) -> [UInt16: String] {
        var names: [UInt16: String] = [:]

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 9, columns.last == "(LISTEN)" else { continue }

            let address = String(columns[columns.count - 2])
            guard let separator = address.lastIndex(of: ":"),
                  let port = UInt16(address[address.index(after: separator)...])
            else { continue }

            // The caller passes +c 0 so commands arrive untruncated. First
            // writer wins, so the mapping is stable across dual-stack rows.
            names[port] = names[port] ?? unescape(String(columns[0]))
        }
        return names
    }

    /// "rpcbind:578" -> "rpcbind". A pid is not useful to show and changes on
    /// every restart, so it would make a poor dismissal key.
    static func processName(column: String) -> String? {
        guard let separator = column.lastIndex(of: ":") else { return nil }
        let name = String(column[..<separator])
        return name.isEmpty ? nil : name
    }

    /// lsof renders non-printable and space characters as \xNN, so
    /// "Discord Helper (Renderer)" arrives as "Discord\x20Helper\x20(Renderer)".
    /// Left escaped it is unreadable, and it is also the key a dismissal is
    /// stored under.
    static func unescape(_ name: String) -> String {
        guard name.contains("\\x") else { return name }
        var result = ""
        var rest = Substring(name)
        while let marker = rest.range(of: "\\x") {
            result += rest[..<marker.lowerBound]
            let hex = rest[marker.upperBound...].prefix(2)
            if hex.count == 2, let value = UInt8(hex, radix: 16), let scalar = Unicode.Scalar(UInt32(value)) {
                result.append(Character(scalar))
                rest = rest[rest.index(marker.upperBound, offsetBy: 2)...]
            } else {
                result += rest[marker.lowerBound..<marker.upperBound]
                rest = rest[marker.upperBound...]
            }
        }
        return result + rest
    }

    /// `*.3000`, `127.0.0.1.8000`, `::1.8021`, `192.168.50.119.7000` — the port
    /// is always after the final dot, whatever the address family.
    private static func parseLocalAddress(_ field: String) -> ListeningSocket? {
        guard let separator = field.lastIndex(of: "."),
              let port = UInt16(field[field.index(after: separator)...])
        else { return nil }

        let address = String(field[..<separator])
        return ListeningSocket(port: port, scope: scope(of: address))
    }

    private static func scope(of address: String) -> BindScope {
        switch address {
        case "*", "0.0.0.0", "::": .allInterfaces
        case "127.0.0.1", "::1": .loopback
        default: address.hasPrefix("127.") ? .loopback : .specificAddress
        }
    }
}
