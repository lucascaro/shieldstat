import Testing
@testable import ShieldStatCore

private func fact(_ interface: String, _ addressClass: AddressClass) -> Fact {
    Fact(interface: interface, addressClass: addressClass, count: 1, carriesDefaultRoute: true)
}

private let wildcard = [ListeningSocket(port: 5433, scope: .allInterfaces)]
private let loopbackOnly = [ListeningSocket(port: 8000, scope: .loopback)]

@Suite("Exposure and listening services, correlated")
struct CorrelationTests {
    @Test("A wildcard listener behind NAT is a notice — dismissible, not silent")
    func listeningWhilePrivateIsNoticed() {
        let verdict = Policy.evaluate([fact("en0", .private)], listening: wildcard)
        #expect(verdict.severity == .notice)
        #expect(verdict.state == .listeningService)
    }

    @Test("Dismissing every listener behind NAT returns the machine to calm")
    func dismissingAllListenersIsCalm() {
        let many = (3000..<3030).map { ListeningSocket(port: UInt16($0), scope: .allInterfaces) }
        let dismissed = Set(many.map(\.key))
        #expect(Policy.evaluate([fact("en0", .private)], listening: many, dismissed: dismissed).severity == .ok)
        // Undismissed, the same set is a notice — never worse, since nothing
        // outside can reach them.
        #expect(Policy.evaluate([fact("en0", .private)], listening: many).severity == .notice)
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

    @Test("Ports are reported behind NAT too, so a dismissal can be made deliberately")
    func portsListedWhenPrivate() {
        #expect(Policy.evaluate([fact("en0", .private)], listening: wildcard).reachablePorts == [5433])
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
