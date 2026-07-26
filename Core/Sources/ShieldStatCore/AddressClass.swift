import Foundation
import Network

/// The category a network address falls into, derived purely from the address bits.
public enum AddressClass: String, Sendable, CaseIterable, Codable {
    /// RFC1918 or IPv6 unique local. Not routable on the public internet.
    case `private`
    /// Carrier-grade NAT space (100.64/10). Also where overlay networks like
    /// Tailscale live — indistinguishable from these bits alone.
    case carrierNAT
    /// IPv4 link-local (169.254/16): DHCP failed. Not "safe", just unknown.
    case noAddress
    /// A globally-routable IPv4 address: nothing NATs this machine.
    case globalV4
    /// A globally-routable IPv6 address (2000::/3).
    case globalV6
}

extension AddressClass {
    /// Classifies a textual address. Returns nil for addresses that carry no
    /// exposure meaning at all — loopback and link-local IPv6.
    public static func of(_ text: String) -> AddressClass? {
        if let v4 = IPv4Address(text) { return of(v4) }
        if let v6 = IPv6Address(stripZone(text)) { return of(v6) }
        return nil
    }

    static func of(_ address: IPv4Address) -> AddressClass? {
        let b = Array(address.rawValue)
        switch (b[0], b[1]) {
        case (127, _): return nil                                // loopback
        case (10, _): return .private
        case (172, 16...31): return .private
        case (192, 168): return .private
        case (100, 64...127): return .carrierNAT
        case (169, 254): return .noAddress
        default: return .globalV4
        }
    }

    static func of(_ address: IPv6Address) -> AddressClass? {
        let b = Array(address.rawValue)
        if b == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] { return nil }  // ::1
        if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return nil }                      // fe80::/10
        if b[0] & 0xfe == 0xfc { return .private }                               // fc00::/7 ULA
        if b[0] & 0xe0 == 0x20 { return .globalV6 }                              // 2000::/3
        return nil
    }

    /// `getnameinfo` renders scoped IPv6 addresses as `fe80::1%en0`.
    private static func stripZone(_ text: String) -> String {
        String(text.prefix(while: { $0 != "%" }))
    }
}
