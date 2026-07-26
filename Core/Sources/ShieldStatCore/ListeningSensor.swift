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

    public var key: ListenerKey {
        if let process { .process(process) } else { .port(port) }
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
            guard columns.count >= 4,
                  columns.last == "LISTEN",
                  columns[0].hasPrefix("tcp"),
                  let socket = parseLocalAddress(String(columns[3]))
            else { continue }

            // A dual-stack service appears once per family; it is one service.
            found.insert(ListeningSocket(
                port: socket.port,
                scope: socket.scope,
                process: names[socket.port]
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
            names[port] = names[port] ?? String(columns[0])
        }
        return names
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
