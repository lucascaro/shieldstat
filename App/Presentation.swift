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

    var tint: Color {
        switch self {
        case .ok: .primary
        case .notice: .orange
        case .alert: .red
        }
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
