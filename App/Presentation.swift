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

extension ListeningSocket {
    /// What clicking dismiss will actually do. A process-keyed dismissal covers
    /// every port that process holds now or later, which is the whole reason for
    /// keying on the name — but two rows vanishing after one click looks like a
    /// bug unless the control says so first.
    var dismissDescription: String {
        switch key {
        case .process(let name): "Dismiss all \(name) listeners"
        case .port(let port): "Dismiss port \(port)"
        }
    }

    var dismissScopeNote: String? {
        if case .process(let name) = key { "all \(name) ports" } else { nil }
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
