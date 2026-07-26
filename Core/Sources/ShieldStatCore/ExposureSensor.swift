import Foundation

/// One address held by one interface, as captured from the system.
public struct InterfaceAddress: Sendable, Equatable {
    public let interface: String
    public let address: String
    public let isUp: Bool
    public let isRunning: Bool
    public let isLoopback: Bool

    public init(interface: String, address: String, isUp: Bool, isRunning: Bool, isLoopback: Bool) {
        self.interface = interface
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
    }
}

/// Something observed, stated without evaluation. One per (interface, class).
public struct Fact: Sendable, Hashable {
    public let interface: String
    public let addressClass: AddressClass
    /// How many addresses of this class the interface holds. SLAAC privacy
    /// extensions routinely make this 2–4 for `globalV6`.
    public let count: Int
    /// Display metadata only. Never modifies severity — see ADR-0003.
    public let carriesDefaultRoute: Bool

    public init(interface: String, addressClass: AddressClass, count: Int, carriesDefaultRoute: Bool) {
        self.interface = interface
        self.addressClass = addressClass
        self.count = count
        self.carriesDefaultRoute = carriesDefaultRoute
    }
}

/// Reads address exposure. Pure: no network, no system calls, no judgment.
public enum ExposureSensor {
    public static func facts(
        from addresses: [InterfaceAddress],
        defaultRouteInterfaces: Set<String>
    ) -> [Fact] {
        let classified = addresses.lazy
            .filter { $0.isUp && $0.isRunning && !$0.isLoopback }
            .compactMap { entry -> (String, AddressClass)? in
                AddressClass.of(entry.address).map { (entry.interface, $0) }
            }

        let counts = classified.reduce(into: [Pair: Int]()) { tally, item in
            tally[Pair(interface: item.0, addressClass: item.1), default: 0] += 1
        }

        return counts
            .map { pair, count in
                Fact(
                    interface: pair.interface,
                    addressClass: pair.addressClass,
                    count: count,
                    carriesDefaultRoute: defaultRouteInterfaces.contains(pair.interface)
                )
            }
            .sorted { ($0.interface, $0.addressClass.rawValue) < ($1.interface, $1.addressClass.rawValue) }
    }

    private struct Pair: Hashable {
        let interface: String
        let addressClass: AddressClass
    }
}
