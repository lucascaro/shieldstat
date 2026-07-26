import Testing
@testable import ShieldStatCore

/// Real `netstat -an -p tcp` output, including the shapes that matter:
/// tcp4/tcp6/tcp46, wildcard binds, both loopback forms, and a bind to a
/// specific non-loopback address.
private let realNetstat = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  *.60579                *.*                    LISTEN
tcp46      0      0  *.3000                 *.*                    LISTEN
tcp46      0      0  *.5433                 *.*                    LISTEN
tcp6       0      0  *.53                   *.*                    LISTEN
tcp6       0      0  ::1.8021               *.*                    LISTEN
tcp4       0      0  127.0.0.1.8000         *.*                    LISTEN
tcp4       0      0  192.168.50.119.7000    *.*                    LISTEN
tcp4       0      0  192.168.50.119.52012   17.253.144.10.443      ESTABLISHED
tcp4       0      0  127.0.0.1.4000         *.*                    LISTEN
"""

@Suite("Listening sensor")
struct ListeningSensorTests {
    @Test("Only sockets in LISTEN state are reported")
    func ignoresEstablished() {
        let sockets = ListeningSensor.parse(netstat: realNetstat)
        #expect(sockets.contains { $0.port == 52012 } == false)
    }

    @Test("Wildcard binds are recognised across tcp4, tcp6 and tcp46")
    func wildcardBinds() {
        let sockets = ListeningSensor.parse(netstat: realNetstat)
        let wildcard = Set(sockets.filter { $0.scope == .allInterfaces }.map(\.port))
        #expect(wildcard == [60579, 3000, 5433, 53])
    }

    @Test("Both loopback forms are recognised and are never all-interfaces")
    func loopbackBinds() {
        let sockets = ListeningSensor.parse(netstat: realNetstat)
        let loopback = Set(sockets.filter { $0.scope == .loopback }.map(\.port))
        #expect(loopback == [8021, 8000, 4000])
    }

    @Test("A bind to one specific non-loopback address is its own scope")
    func specificAddressBind() {
        let sockets = ListeningSensor.parse(netstat: realNetstat)
        let specific = sockets.filter { $0.scope == .specificAddress }
        #expect(specific.map(\.port) == [7000])
    }

    @Test("The same port on tcp4 and tcp6 collapses to one socket")
    func dualStackCollapses() {
        let dual = """
        tcp6       0      0  *.55781                *.*                    LISTEN
        tcp4       0      0  *.55781                *.*                    LISTEN
        """
        #expect(ListeningSensor.parse(netstat: dual).count == 1)
    }

    @Test("Garbage and headers are skipped without losing valid rows")
    func toleratesNoise() {
        let noisy = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
        nonsense line
        tcp4       0      0  *.22                   *.*                    LISTEN
        tcp4       0      0  malformed              *.*                    LISTEN
        """
        #expect(ListeningSensor.parse(netstat: noisy).map(\.port) == [22])
    }

    @Test("Empty input yields nothing")
    func empty() {
        #expect(ListeningSensor.parse(netstat: "").isEmpty)
    }

    @Test("Results are ordered deterministically by port")
    func stableOrder() {
        let sockets = ListeningSensor.parse(netstat: realNetstat)
        #expect(sockets.map(\.port) == sockets.map(\.port).sorted())
    }
}
