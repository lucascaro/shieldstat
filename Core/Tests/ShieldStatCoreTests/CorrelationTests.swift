import Testing
@testable import ShieldStatCore

private func fact(_ interface: String, _ addressClass: AddressClass) -> Fact {
    Fact(interface: interface, addressClass: addressClass, count: 1, carriesDefaultRoute: true)
}

private let wildcard = [ListeningSocket(port: 5433, scope: .allInterfaces)]
private let loopbackOnly = [ListeningSocket(port: 8000, scope: .loopback)]

@Suite("Exposure and listening services, correlated")
struct CorrelationTests {
    @Test("Services listening behind NAT are calm — this is the common case")
    func listeningWhilePrivateIsCalm() {
        let verdict = Policy.evaluate([fact("en0", .private)], listening: wildcard)
        #expect(verdict.severity == .ok)
        #expect(verdict.state == .private)
    }

    @Test("A machine with dozens of wildcard listeners behind NAT stays calm")
    func manyListenersStillCalm() {
        let many = (3000..<3030).map { ListeningSocket(port: UInt16($0), scope: .allInterfaces) }
        #expect(Policy.evaluate([fact("en0", .private)], listening: many).severity == .ok)
    }

    @Test("Publicly addressable plus a wildcard listener is worse than either alone")
    func correlationEscalates() {
        let alone = Policy.evaluate([fact("en0", .globalV6)], listening: [])
        let correlated = Policy.evaluate([fact("en0", .globalV6)], listening: wildcard)

        #expect(alone.severity == .notice)
        #expect(correlated.severity == .alert)
        #expect(correlated.state == .exposedService)
    }

    @Test("Loopback-only listeners never escalate anything")
    func loopbackNeverEscalates() {
        let verdict = Policy.evaluate([fact("en0", .globalV6)], listening: loopbackOnly)
        #expect(verdict.severity == .notice)
        #expect(verdict.state == .publiclyAddressable)
    }

    @Test("A listener bound to one specific address still counts when exposed")
    func specificAddressCounts() {
        let specific = [ListeningSocket(port: 7000, scope: .specificAddress)]
        let verdict = Policy.evaluate([fact("en0", .globalV4)], listening: specific)
        #expect(verdict.state == .exposedService)
    }

    @Test("Directly exposed with a listener is exposedService, not merely alert")
    func exposedWithListener() {
        let verdict = Policy.evaluate([fact("en0", .globalV4)], listening: wildcard)
        #expect(verdict.severity == .alert)
        #expect(verdict.state == .exposedService)
    }

    @Test("The verdict carries the reachable ports, and only those")
    func verdictCarriesPorts() {
        let mixed = wildcard + loopbackOnly
        let verdict = Policy.evaluate([fact("en0", .globalV4)], listening: mixed)
        #expect(verdict.reachablePorts == [5433])
    }

    @Test("Reachable ports are not reported when nothing is exposed")
    func noPortsWhenPrivate() {
        #expect(Policy.evaluate([fact("en0", .private)], listening: wildcard).reachablePorts.isEmpty)
    }

    @Test("Omitting the listening argument preserves the address-only verdict")
    func defaultsToAddressOnly() {
        #expect(Policy.evaluate([fact("en0", .globalV4)]).state == .directlyExposed)
    }

    @Test("Escalation still names the address facts, so mute rules are unchanged")
    func raisingFactsUnchanged() {
        let exposure = fact("en0", .globalV6)
        let verdict = Policy.evaluate([exposure], listening: wildcard)
        #expect(verdict.raisingFacts == [exposure])
    }
}
