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

@Suite("lsof name escaping")
struct ProcessNameEscapingTests {
    @Test("Spaces arrive as \\x20 and are decoded")
    func decodesSpaces() {
        #expect(ListeningSensor.unescape("Discord\\x20Helper\\x20(Renderer)") == "Discord Helper (Renderer)")
    }

    @Test("Names without escapes are untouched")
    func passesThrough() {
        #expect(ListeningSensor.unescape("com.docker.backend") == "com.docker.backend")
        #expect(ListeningSensor.unescape("") == "")
    }

    @Test("A malformed escape is left alone rather than dropped")
    func malformedEscape() {
        #expect(ListeningSensor.unescape("weird\\xZZname") == "weird\\xZZname")
    }

    @Test("Decoded names are what a dismissal keys on")
    func keysUseDecodedName() {
        let lsof = "Code\\x20Helper 1 u 1u IPv4 0x1 0t0 TCP *:19738 (LISTEN)"
        let netstat = "tcp4       0      0  *.19738                *.*                    LISTEN"
        let socket = ListeningSensor.parse(netstat: netstat, lsof: lsof).first
        #expect(socket?.process == "Code Helper")
        #expect(socket?.processKey == .process("Code Helper"))
    }
}

@Suite("Process names from netstat -anv")
struct NetstatProcessTests {
    /// Real `netstat -anv -p tcp` rows, including root-owned sockets that an
    /// unprivileged lsof cannot see at all.
    static let real = """
    tcp6       0      0  *.111                  *.*                    LISTEN                 0            0  131072  131072          rpcbind:578    00080 00000006 000000000000133f 00000000 00000800      1      0 000000
    tcp4       0      0  *.981                  *.*                    LISTEN                 0            0  131072  131072      rpc.statd:94374    00080 00000006 00000000014f81ca 00000000 00000800      1      0 000000
    tcp4       0      0  *.5432                 *.*                    LISTEN                 0            0  131072  131072 com.docker.backe:39886 00080 00000006 0000000000e57b0a 00000000 00000800      1      0 000000
    """

    @Test("Root-owned sockets get a name lsof could not provide")
    func namesRootOwnedSockets() {
        let sockets = ListeningSensor.parse(netstat: Self.real)
        #expect(sockets.first { $0.port == 111 }?.process == "rpcbind")
        #expect(sockets.first { $0.port == 981 }?.process == "rpc.statd")
    }

    @Test("The pid is dropped — it changes on every restart and is a poor key")
    func stripsPid() {
        #expect(ListeningSensor.processName(column: "rpcbind:578") == "rpcbind")
        #expect(ListeningSensor.processName(column: "no-colon") == nil)
    }

    @Test("lsof wins over netstat, which truncates at sixteen characters")
    func lsofNameWins() {
        let lsof = "com.docker.backend 1 u 1u IPv4 0x1 0t0 TCP *:5432 (LISTEN)"
        let sockets = ListeningSensor.parse(netstat: Self.real, lsof: lsof)
        #expect(sockets.first { $0.port == 5432 }?.process == "com.docker.backend")
    }

    @Test("Without lsof the truncated netstat name is still better than nothing")
    func netstatFallback() {
        let sockets = ListeningSensor.parse(netstat: Self.real)
        #expect(sockets.first { $0.port == 5432 }?.process == "com.docker.backe")
    }
}
