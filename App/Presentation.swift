import SwiftUI
import ShieldStatCore

// The glossary calls this a State; the type is `PostureState` because a type
// named `State` is ambiguous with SwiftUI's property wrapper in every view file.
extension PostureState {
    var title: String {
        switch self {
        case .offline: "Offline"
        case .noNetwork: "No Network"
        case .carrierNAT: "Carrier NAT"
        case .private: "Private"
        case .publiclyAddressable: "Publicly Addressable"
        case .directlyExposed: "Directly Exposed"
        case .listeningService: "Open Ports"
        case .exposedService: "Exposed Service"
        }
    }

    /// The compact form shown beside the glyph in the menu bar.
    var shortLabel: String {
        switch self {
        case .offline: "Offline"
        case .noNetwork: "No IP"
        case .carrierNAT: "CGNAT"
        case .private: "Private"
        case .publiclyAddressable: "Public v6"
        case .directlyExposed: "Exposed"
        case .listeningService: "Open Ports"
        // Strictly worse than Directly Exposed, so it must not read milder.
        // The headline fact is the exposure; which ports are open is panel
        // detail, and the two states already share a severity and a glyph.
        case .exposedService: "Exposed"
        }
    }

    var explanation: String {
        switch self {
        case .offline: "No interface holds a usable address."
        case .noNetwork: "An interface is up but has no address — DHCP has not completed."
        case .carrierNAT: "Addresses sit in carrier NAT space. Not reachable from the internet."
        case .private: "Every address is private. Something is NATing this Mac."
        case .publiclyAddressable:
            "This Mac holds a globally-routable IPv6 address. Whether anything filters inbound traffic cannot be determined locally."
        case .directlyExposed:
            "This Mac holds a globally-routable IPv4 address. Nothing is NATing it."
        case .listeningService:
            "Services are listening on every interface. Nothing outside can reach them while this Mac is behind NAT, but they would be reachable the moment it is not."
        case .exposedService:
            "This Mac is reachable from outside and something is listening on it. Either fact on its own would be milder."
        }
    }
}

extension Severity {
    var name: String {
        switch self {
        case .ok: "ok"
        case .notice: "notice"
        case .alert: "alert"
        }
    }

    /// Shape carries the meaning, not colour alone — the glyph has to survive
    /// colourblindness and monochrome menu bar rendering.
    var symbolName: String {
        switch self {
        case .ok: "shield"
        case .notice: "shield.lefthalf.filled"
        case .alert: "exclamationmark.shield.fill"
        }
    }

    /// Colour is carried in addition to the shape difference, never instead of
    /// it — the glyph still changes form, so severity survives for a colourblind
    /// reader and in a monochrome menu bar.
    var menuBarTint: NSColor {
        switch self {
        case .ok: .systemGreen
        case .notice: .systemYellow
        case .alert: .systemRed
        }
    }

    var tint: Color {
        switch self {
        case .ok: .green
        case .notice: .yellow
        case .alert: .red
        }
    }
}

extension ListenerKey {
    /// How a dismissal reads in a list. Also the sort key — dismissals live in
    /// a Set, so without an explicit order the rows shuffle between renders.
    var label: String {
        switch self {
        case .process(let name): name
        case .port(let port): "port \(port)"
        }
    }
}

extension ListeningSocket {
    /// What clicking dismiss will actually do. The plain action is deliberately
    /// narrow — this port and no other — so the control says "only" to
    /// distinguish it from the separate whole-process action beside it.
    var dismissDescription: String {
        process.map { "Dismiss port \(port) only (\($0))" } ?? "Dismiss port \(port)"
    }
}

extension ListeningSocket {
    /// The one thing about a listener that decides whether it matters, said in
    /// the detail window where there is room to say it in full.
    var reachabilityDescription: String {
        switch scope {
        case .loopback: "Bound to loopback — nothing outside this Mac can reach it."
        case .allInterfaces: "Bound to every interface — reachable from any network this Mac joins."
        case .specificAddress: "Bound to one interface address — reachable from that network."
        }
    }
}

extension ListenerProcess {
    /// Ownership is decided on uid, never on the user name. `ps` pads and
    /// truncates the name column; the uid is neither, and it is what the kernel
    /// actually checks when a signal is sent.
    var isOwnedByCurrentUser: Bool { uid == getuid() }

    /// Every address this process bound `port` on. Usually one entry, two when a
    /// dual-stack service listens on both families.
    func bindDescription(for port: UInt16) -> String {
        let addresses = sockets.filter { $0.port == port }.map(\.addressDescription)
        return addresses.isEmpty ? "port \(port)" : Set(addresses).sorted().joined(separator: ", ")
    }

    /// The rest of what this process is listening on — the context that turns
    /// "some port" into "this is the dev server". Nil when there is no rest.
    func otherPortsDescription(besides port: UInt16) -> String? {
        let others = otherPorts(besides: port)
        return others.isEmpty ? nil : others.map(String.init).joined(separator: ", ")
    }
}

extension AddressClass {
    var title: String {
        switch self {
        case .private: "Private"
        case .carrierNAT: "Carrier NAT"
        case .noAddress: "No address"
        case .globalV4: "Global IPv4"
        case .globalV6: "Global IPv6"
        }
    }
}
