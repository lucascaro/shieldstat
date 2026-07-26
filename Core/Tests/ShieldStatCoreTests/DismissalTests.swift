import Testing
@testable import ShieldStatCore

private func fact(_ interface: String, _ addressClass: AddressClass) -> Fact {
    Fact(interface: interface, addressClass: addressClass, count: 1, carriesDefaultRoute: true)
}

private let spotify = ListeningSocket(port: 57621, scope: .allInterfaces, process: "Spotify")
private let spotifyEphemeral = ListeningSocket(port: 49221, scope: .allInterfaces, process: "Spotify")
private let unnamedDaemon = ListeningSocket(port: 111, scope: .allInterfaces)
private let localOnly = ListeningSocket(port: 8000, scope: .loopback, process: "Python")

@Suite("Listening warnings and dismissals")
struct DismissalTests {
    @Test("A wildcard listener behind NAT is a notice, not silence")
    func listeningIsWarned() {
        let verdict = Policy.evaluate([fact("en0", .private)], listening: [spotify])
        #expect(verdict.state == .listeningService)
        #expect(verdict.severity == .notice)
        #expect(verdict.raisingListeners == [spotify])
    }

    @Test("Loopback listeners are never warned about")
    func loopbackIsSilent() {
        let verdict = Policy.evaluate([fact("en0", .private)], listening: [localOnly])
        #expect(verdict.state == .private)
        #expect(verdict.severity == .ok)
    }

    @Test("Dismissing by process name silences it behind NAT")
    func dismissByProcess() {
        let verdict = Policy.evaluate(
            [fact("en0", .private)], listening: [spotify], dismissed: [.process("Spotify")]
        )
        #expect(verdict.state == .private)
        #expect(verdict.severity == .ok)
    }

    @Test("A process dismissal covers that process's ephemeral ports too")
    func dismissalSurvivesPortRotation() {
        let verdict = Policy.evaluate(
            [fact("en0", .private)],
            listening: [spotify, spotifyEphemeral],
            dismissed: [.process("Spotify")]
        )
        #expect(verdict.severity == .ok)
    }

    @Test("An unnameable daemon is dismissed by port")
    func dismissByPort() {
        #expect(unnamedDaemon.key == .port(111))
        let verdict = Policy.evaluate(
            [fact("en0", .private)], listening: [unnamedDaemon], dismissed: [.port(111)]
        )
        #expect(verdict.severity == .ok)
    }

    @Test("Dismissing one listener leaves the others warned")
    func partialDismissal() {
        let verdict = Policy.evaluate(
            [fact("en0", .private)],
            listening: [spotify, unnamedDaemon],
            dismissed: [.process("Spotify")]
        )
        #expect(verdict.state == .listeningService)
        #expect(verdict.raisingListeners == [unnamedDaemon])
    }

    @Test("A dismissal does not survive becoming exposed — the point of the tool")
    func dismissalDoesNotSurviveExposure() {
        let athome = Policy.evaluate(
            [fact("en0", .private)], listening: [spotify], dismissed: [.process("Spotify")]
        )
        let atHotel = Policy.evaluate(
            [fact("en0", .globalV4)], listening: [spotify], dismissed: [.process("Spotify")]
        )

        #expect(athome.severity == .ok)
        #expect(atHotel.state == .exposedService)
        #expect(atHotel.severity == .alert)
        #expect(atHotel.raisingListeners == [spotify])
    }

    @Test("Exposure with every listener dismissed still alerts")
    func exposureIgnoresAllDismissals() {
        let verdict = Policy.evaluate(
            [fact("en0", .globalV6)],
            listening: [spotify, unnamedDaemon],
            dismissed: [.process("Spotify"), .port(111)]
        )
        #expect(verdict.severity == .alert)
        #expect(verdict.raisingListeners.count == 2)
    }

    @Test("Exposure with nothing listening is not an exposed service")
    func exposedButQuiet() {
        let verdict = Policy.evaluate([fact("en0", .globalV4)], listening: [localOnly])
        #expect(verdict.state == .directlyExposed)
    }

    @Test("A plain dismissal keys on the port, even when the process is known")
    func plainDismissalIsNarrow() {
        // Keying on the process would make one click cover every port that
        // process opens later — convenient for Spotify, a standing blind spot
        // for Docker, whose job is publishing arbitrary ports.
        #expect(spotify.key == .port(57621))
        #expect(unnamedDaemon.key == .port(111))
        #expect(spotify.processKey == .process("Spotify"))
        #expect(unnamedDaemon.processKey == nil)
    }

    @Test("Dismissing one Docker port does not dismiss the next one it publishes")
    func dockerPortsAreIndependent() {
        let published = ListeningSocket(port: 5432, scope: .allInterfaces, process: "com.docker.backend")
        let newContainer = ListeningSocket(port: 8443, scope: .allInterfaces, process: "com.docker.backend")

        let verdict = Policy.evaluate(
            [fact("en0", .private)],
            listening: [published, newContainer],
            dismissed: [published.key]
        )
        #expect(verdict.raisingListeners == [newContainer])
    }

    @Test("Listeners are labelled for a human where possible")
    func labels() {
        #expect(spotify.label == "Spotify · 57621")
        #expect(unnamedDaemon.label == "port 111")
    }
}

@Suite("Process names from lsof")
struct ProcessNameTests {
    /// Real `lsof -iTCP -sTCP:LISTEN -P -n` output.
    static let real = """
    COMMAND     PID      USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    ControlCe  4573 lucascaro    9u  IPv4 0x4bd2cac8f12c5bd5      0t0  TCP *:7000 (LISTEN)
    rapportd   4594 lucascaro   15u  IPv4 0x30a0c592eb39e7a7      0t0  TCP *:55781 (LISTEN)
    Spotify   31090 lucascaro  295u  IPv4 0xc01ac6d5590dc605      0t0  TCP *:57621 (LISTEN)
    com.docke 39886 lucascaro  128u  IPv6  0xf5df0c287a0f1c8      0t0  TCP *:5432 (LISTEN)
    Python    68441 lucascaro    4u  IPv6 0x90628d3945da2da7      0t0  TCP *:8000 (LISTEN)
    Python    68441 lucascaro    5u  IPv4 0x90628d3945da2da8      0t0  TCP 127.0.0.1:9000 (LISTEN)
    """

    @Test("Ports are mapped to the owning command")
    func mapsPorts() {
        let names = ListeningSensor.processNames(lsof: Self.real)
        #expect(names[57621] == "Spotify")
        #expect(names[7000] == "ControlCe")
        #expect(names[5432] == "com.docke")
        #expect(names[9000] == "Python")
    }

    @Test("Headers and noise are skipped")
    func skipsHeader() {
        #expect(ListeningSensor.processNames(lsof: Self.real)[0] == nil)
        #expect(ListeningSensor.processNames(lsof: "").isEmpty)
    }

    @Test("Names are attached to the sockets netstat found")
    func enrichesSockets() {
        let netstat = """
        tcp46      0      0  *.57621                *.*                    LISTEN
        tcp46      0      0  *.99999                *.*                    LISTEN
        """
        let sockets = ListeningSensor.parse(netstat: netstat, lsof: Self.real)
        #expect(sockets.first { $0.port == 57621 }?.process == "Spotify")
    }

    @Test("A socket lsof cannot see keeps a nil process rather than a wrong one")
    func unnamedStaysUnnamed() {
        let netstat = "tcp4       0      0  *.111                  *.*                    LISTEN"
        let sockets = ListeningSensor.parse(netstat: netstat, lsof: Self.real)
        #expect(sockets.first?.process == nil)
        #expect(sockets.first?.key == .port(111))
    }
}
