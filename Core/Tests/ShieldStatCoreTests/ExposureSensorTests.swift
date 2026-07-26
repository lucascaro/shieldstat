import Testing
@testable import ShieldStatCore

private func addr(
    _ interface: String,
    _ address: String,
    up: Bool = true,
    running: Bool = true,
    loopback: Bool = false
) -> InterfaceAddress {
    InterfaceAddress(
        interface: interface, address: address,
        isUp: up, isRunning: running, isLoopback: loopback
    )
}

@Suite("Exposure sensor")
struct ExposureSensorTests {
    /// The machine this project was designed on: private wifi, a VM bridge, and
    /// a pile of link-local tunnel interfaces.
    static let realSnapshot: [InterfaceAddress] = [
        addr("lo0", "127.0.0.1", loopback: true),
        addr("lo0", "::1", loopback: true),
        addr("lo0", "fe80::1%lo0", loopback: true),
        addr("utun0", "fe80::77cf:be47:bc7f:4664%utun0"),
        addr("utun1", "fe80::a6ea:11a7:3ae8:5add%utun1"),
        addr("bridge100", "192.168.64.1"),
        addr("bridge100", "fd9e:6186:fccd:74f:10ac:e769:35ce:ee55"),
        addr("en0", "192.168.50.119"),
        addr("awdl0", "fe80::8806:c5ff:fe0c:e98d%awdl0"),
    ]

    @Test("A private-only machine yields only private facts")
    func realWorldSnapshot() {
        let facts = ExposureSensor.facts(from: Self.realSnapshot, defaultRouteInterfaces: ["en0"])

        #expect(facts.allSatisfy { $0.addressClass == .private })
        #expect(Set(facts.map(\.interface)) == ["en0", "bridge100"])
    }

    @Test("Loopback interfaces are never facts")
    func loopbackExcluded() {
        let facts = ExposureSensor.facts(from: Self.realSnapshot, defaultRouteInterfaces: ["en0"])
        #expect(facts.contains { $0.interface == "lo0" } == false)
    }

    @Test("Interfaces that are down or not running are ignored")
    func downInterfacesIgnored() {
        let snapshot = [
            addr("en0", "192.168.1.5"),
            addr("en5", "203.0.113.9", up: false),
            addr("en6", "203.0.113.10", running: false),
        ]
        let facts = ExposureSensor.facts(from: snapshot, defaultRouteInterfaces: ["en0"])
        #expect(facts.count == 1)
        #expect(facts[0].interface == "en0")
    }

    @Test("Rotating SLAAC addresses collapse into one fact with a count")
    func slaacPrivacyExtensions() {
        let snapshot = [
            addr("en0", "192.168.1.5"),
            addr("en0", "2600:1700:1::1"),
            addr("en0", "2600:1700:1::a1b2"),
            addr("en0", "2600:1700:1::c3d4"),
            addr("en0", "fe80::1%en0"),
        ]
        let facts = ExposureSensor.facts(from: snapshot, defaultRouteInterfaces: ["en0"])

        let v6 = try! #require(facts.first { $0.addressClass == .globalV6 })
        #expect(v6.count == 3)
        #expect(facts.filter { $0.addressClass == .globalV6 }.count == 1)
    }

    @Test("A public address on a secondary interface is still a fact")
    func secondaryInterfaceExposure() {
        let snapshot = [
            addr("en0", "192.168.1.5"),
            addr("en5", "203.0.113.9"),
        ]
        let facts = ExposureSensor.facts(from: snapshot, defaultRouteInterfaces: ["en0"])

        let exposed = try! #require(facts.first { $0.addressClass == .globalV4 })
        #expect(exposed.interface == "en5")
        #expect(exposed.carriesDefaultRoute == false)
    }

    @Test("Default route membership is recorded as display metadata")
    func defaultRouteTagging() {
        let snapshot = [addr("en0", "192.168.1.5"), addr("en5", "10.0.0.1")]
        let facts = ExposureSensor.facts(from: snapshot, defaultRouteInterfaces: ["en0"])

        #expect(facts.first { $0.interface == "en0" }?.carriesDefaultRoute == true)
        #expect(facts.first { $0.interface == "en5" }?.carriesDefaultRoute == false)
    }

    @Test("No interfaces yields no facts")
    func empty() {
        #expect(ExposureSensor.facts(from: [], defaultRouteInterfaces: []).isEmpty)
    }

    @Test("Facts are ordered deterministically")
    func stableOrdering() {
        let snapshot = [
            addr("en5", "203.0.113.9"),
            addr("en0", "192.168.1.5"),
            addr("en0", "2600:1700:1::1"),
        ]
        let a = ExposureSensor.facts(from: snapshot, defaultRouteInterfaces: ["en0"])
        let b = ExposureSensor.facts(from: snapshot.reversed(), defaultRouteInterfaces: ["en0"])
        #expect(a == b)
    }
}
