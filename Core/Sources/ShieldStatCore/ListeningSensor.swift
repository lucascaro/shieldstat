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

/// A TCP socket in LISTEN state. No process attribution: naming the process
/// requires a root helper, and a passive monitor should not need more privilege
/// than the thing it monitors.
public struct ListeningSocket: Sendable, Equatable, Hashable, Codable {
    public let port: UInt16
    public let scope: BindScope

    public init(port: UInt16, scope: BindScope) {
        self.port = port
        self.scope = scope
    }
}

/// Reads listening TCP sockets. Pure: parsing only, the caller supplies the text.
public enum ListeningSensor {
    /// Parses `netstat -an -p tcp`.
    ///
    /// ponytail: parses netstat's text rather than reading the TCP PCB list via
    /// `net.inet.tcp.pcblist_n`. The sysctl avoids a subprocess but means
    /// decoding kernel structs that shift between releases. Upgrade if the
    /// subprocess ever shows up in a profile.
    public static func parse(netstat text: String) -> [ListeningSocket] {
        var found = Set<ListeningSocket>()

        for line in text.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 4,
                  columns.last == "LISTEN",
                  columns[0].hasPrefix("tcp"),
                  let socket = parseLocalAddress(String(columns[3]))
            else { continue }

            // A dual-stack service appears once per family; it is one service.
            found.insert(socket)
        }

        return found.sorted { $0.port < $1.port }
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
