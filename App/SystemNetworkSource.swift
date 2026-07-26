import Foundation
import SystemConfiguration
import ShieldStatCore

/// Captures the live interface table. The only thing here that touches the
/// system; everything downstream is a pure function over what it returns.
enum SystemNetworkSource {
    static func snapshot() -> (addresses: [InterfaceAddress], defaultRouteInterfaces: Set<String>) {
        (addresses(), primaryInterfaces())
    }

    static func addresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [InterfaceAddress] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = ptr.pointee
            guard let sockaddr = entry.ifa_addr else { continue }
            let family = sockaddr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            guard let text = numericHost(sockaddr, length: socklen_t(sockaddr.pointee.sa_len)) else { continue }

            let flags = Int32(entry.ifa_flags)
            result.append(InterfaceAddress(
                interface: String(cString: entry.ifa_name),
                address: text,
                isUp: flags & IFF_UP != 0,
                isRunning: flags & IFF_RUNNING != 0,
                isLoopback: flags & IFF_LOOPBACK != 0
            ))
        }
        return result
    }

    private static func numericHost(_ sockaddr: UnsafeMutablePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sockaddr, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Which interfaces carry a default route. Display metadata only — it never
    /// modifies severity (ADR-0003).
    private static func primaryInterfaces() -> Set<String> {
        guard let store = SCDynamicStoreCreate(nil, "ShieldStat" as CFString, nil, nil) else { return [] }
        let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
        return Set(keys.compactMap { key in
            (SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        })
    }
}
