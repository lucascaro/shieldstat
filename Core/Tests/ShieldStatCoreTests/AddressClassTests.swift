import Testing
@testable import ShieldStatCore

@Suite("Address classification")
struct AddressClassTests {
    @Test("RFC1918 addresses are private", arguments: [
        "10.0.0.1", "10.255.255.254", "172.16.0.1", "172.31.255.254",
        "192.168.50.119", "192.168.1.1",
    ])
    func rfc1918(text: String) {
        #expect(AddressClass.of(text) == .private)
    }

    @Test("Addresses adjacent to RFC1918 blocks are global, not private", arguments: [
        "172.15.0.1", "172.32.0.1", "192.167.1.1", "192.169.1.1", "11.0.0.1", "9.255.255.255",
    ])
    func rfc1918Boundaries(text: String) {
        #expect(AddressClass.of(text) == .globalV4)
    }

    @Test("IPv6 unique local addresses are private", arguments: [
        "fd9e:6186:fccd:74f:10ac:e769:35ce:ee55", "fc00::1", "fdff::1",
    ])
    func uniqueLocal(text: String) {
        #expect(AddressClass.of(text) == .private)
    }

    @Test("100.64/10 is carrier NAT", arguments: [
        "100.64.0.1", "100.100.100.100", "100.127.255.254",
    ])
    func carrierNAT(text: String) {
        #expect(AddressClass.of(text) == .carrierNAT)
    }

    @Test("Addresses adjacent to the CGNAT block are global", arguments: [
        "100.63.255.255", "100.128.0.1",
    ])
    func carrierNATBoundaries(text: String) {
        #expect(AddressClass.of(text) == .globalV4)
    }

    @Test("IPv4 link-local means DHCP failed, not private")
    func linkLocalV4() {
        #expect(AddressClass.of("169.254.10.20") == .noAddress)
    }

    @Test("Ordinary public IPv4 is globalV4", arguments: [
        "1.1.1.1", "8.8.8.8", "203.0.113.7", "198.51.100.1",
    ])
    func globalV4(text: String) {
        #expect(AddressClass.of(text) == .globalV4)
    }

    @Test("IPv6 global unicast is globalV6", arguments: [
        "2001:4860:4860::8888", "2600:1700:1::1", "3fff::1",
    ])
    func globalV6(text: String) {
        #expect(AddressClass.of(text) == .globalV6)
    }

    @Test("Loopback and IPv6 link-local carry no exposure meaning", arguments: [
        "127.0.0.1", "127.255.255.254", "::1",
        "fe80::8806:c5ff:fe0c:e98d", "fe80::1%lo0", "febf::1",
    ])
    func excluded(text: String) {
        #expect(AddressClass.of(text) == nil)
    }

    @Test("Unparseable text is not classified")
    func garbage() {
        #expect(AddressClass.of("not-an-address") == nil)
        #expect(AddressClass.of("") == nil)
    }
}
