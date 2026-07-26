import Testing
@testable import ShieldStatCore

private func fact(
    _ interface: String,
    _ addressClass: AddressClass,
    count: Int = 1,
    defaultRoute: Bool = false
) -> Fact {
    Fact(interface: interface, addressClass: addressClass, count: count, carriesDefaultRoute: defaultRoute)
}

@Suite("Policy")
struct PolicyTests {
    @Test("No facts at all means offline")
    func offline() {
        let verdict = Policy.evaluate([])
        #expect(verdict.state == .offline)
        #expect(verdict.severity == .ok)
    }

    @Test("Only private addresses is Private and calm")
    func privateOnly() {
        let verdict = Policy.evaluate([fact("en0", .private, defaultRoute: true), fact("bridge100", .private)])
        #expect(verdict.state == .private)
        #expect(verdict.severity == .ok)
    }

    @Test("Carrier NAT is calm — unreachable, even though Tailscale looks identical")
    func carrierNAT() {
        let verdict = Policy.evaluate([fact("en0", .carrierNAT, defaultRoute: true)])
        #expect(verdict.state == .carrierNAT)
        #expect(verdict.severity == .ok)
    }

    @Test("A global IPv6 address is Publicly Addressable, a notice")
    func globalV6() {
        let verdict = Policy.evaluate([fact("en0", .private, defaultRoute: true), fact("en0", .globalV6, count: 3)])
        #expect(verdict.state == .publiclyAddressable)
        #expect(verdict.severity == .notice)
    }

    @Test("A global IPv4 address is Directly Exposed, an alert")
    func globalV4() {
        let verdict = Policy.evaluate([fact("en0", .globalV4, defaultRoute: true)])
        #expect(verdict.state == .directlyExposed)
        #expect(verdict.severity == .alert)
    }

    @Test("Exposure on a secondary interface carries full severity — ADR-0003")
    func secondaryInterfaceIsNotDiscounted() {
        let onDefaultRoute = Policy.evaluate([fact("en0", .globalV4, defaultRoute: true)])
        let onSecondary = Policy.evaluate([
            fact("en0", .private, defaultRoute: true),
            fact("en5", .globalV4, defaultRoute: false),
        ])
        #expect(onSecondary.severity == onDefaultRoute.severity)
        #expect(onSecondary.state == .directlyExposed)
    }

    @Test("The worst link names the state when several disagree")
    func maxSeverityWins() {
        let verdict = Policy.evaluate([
            fact("en0", .private, defaultRoute: true),
            fact("en0", .globalV6, count: 2),
            fact("en5", .globalV4),
        ])
        #expect(verdict.state == .directlyExposed)
        #expect(verdict.severity == .alert)
    }

    @Test("A failed DHCP lease alongside working private wifi is still Private")
    func mixedOkClassesDoNotFallThrough() {
        let verdict = Policy.evaluate([
            fact("en0", .private, defaultRoute: true),
            fact("en6", .noAddress),
        ])
        #expect(verdict.state == .private)
        #expect(verdict.severity == .ok)
    }

    @Test("Link-local only means No Network")
    func noAddressOnly() {
        let verdict = Policy.evaluate([fact("en6", .noAddress)])
        #expect(verdict.state == .noNetwork)
        #expect(verdict.severity == .ok)
    }

    @Test("The verdict names which facts raised the severity")
    func raisingFactsIdentified() {
        let exposed = fact("en5", .globalV4)
        let verdict = Policy.evaluate([
            fact("en0", .private, defaultRoute: true),
            fact("en0", .globalV6),
            exposed,
        ])
        #expect(verdict.raisingFacts == [exposed])
    }

    @Test("Every fact at the top severity is named, not just the first")
    func allRaisingFactsIdentified() {
        let a = fact("en5", .globalV4)
        let b = fact("en6", .globalV4)
        let verdict = Policy.evaluate([fact("en0", .private), a, b])
        #expect(Set(verdict.raisingFacts) == [a, b])
    }

    @Test("Severity orders ok < notice < alert")
    func severityOrdering() {
        #expect(Severity.ok < Severity.notice)
        #expect(Severity.notice < Severity.alert)
    }
}
