import Testing
@testable import ShieldStatCore

@Suite("Well-known ports and the system baseline")
struct WellKnownPortsTests {
    @Test("Common ports get a human description", arguments: [
        (UInt16(22), "SSH"), (53, "DNS"), (2049, "NFS"), (7000, "AirPlay"), (5432, "PostgreSQL"),
    ])
    func describesCommonPorts(port: UInt16, fragment: String) {
        #expect(WellKnownPorts.description(of: port)?.contains(fragment) == true)
    }

    @Test("An unlisted privileged port still says something useful")
    func privilegedFallback() {
        #expect(WellKnownPorts.description(of: 1017) == "System service (privileged port)")
    }

    @Test("An unlisted high port says nothing rather than guessing")
    func highPortsUndescribed() {
        #expect(WellKnownPorts.description(of: 59724) == nil)
    }

    @Test("The baseline covers services macOS starts itself")
    func baselineCoversSystemServices() {
        let controlCenter = ListeningSocket(port: 7000, scope: .allInterfaces, process: "ControlCenter")
        #expect(SystemServiceBaseline.covers(controlCenter))
        #expect(SystemServiceBaseline.keys.contains(.process("ControlCenter")))
    }

    @Test("The baseline does not cover services somebody switched on")
    func baselineExcludesOptedInServices() {
        // Listening because a human enabled Remote Login or File Sharing, not
        // because macOS decided to. Auto-dismissing these would hide a choice.
        let sshd = ListeningSocket(port: 22, scope: .allInterfaces, process: "sshd")
        let nfsd = ListeningSocket(port: 2049, scope: .allInterfaces, process: "nfsd")
        let smbd = ListeningSocket(port: 445, scope: .allInterfaces, process: "smbd")

        #expect(SystemServiceBaseline.covers(sshd) == false)
        #expect(SystemServiceBaseline.covers(nfsd) == false)
        #expect(SystemServiceBaseline.covers(smbd) == false)
    }

    @Test("An unnamed socket is never covered by the baseline")
    func unnamedNeverCovered() {
        #expect(SystemServiceBaseline.covers(ListeningSocket(port: 7000, scope: .allInterfaces)) == false)
    }

    @Test("The baseline still yields to exposure")
    func baselineDoesNotSurviveExposure() {
        let controlCenter = ListeningSocket(port: 7000, scope: .allInterfaces, process: "ControlCenter")
        let exposed = Policy.evaluate(
            [Fact(interface: "en0", addressClass: .globalV4, count: 1, carriesDefaultRoute: true)],
            listening: [controlCenter],
            dismissed: SystemServiceBaseline.keys
        )
        #expect(exposed.state == .exposedService)
    }
}
