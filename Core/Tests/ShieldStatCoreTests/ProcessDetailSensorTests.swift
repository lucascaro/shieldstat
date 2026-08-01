import Testing
@testable import ShieldStatCore

/// Real `netstat -anv -p tcp` output. The shapes that matter: a name with
/// spaces in it, which tears the process:pid column apart; one pid holding two
/// ports; a socket whose process column is missing entirely; and a row in a
/// state other than LISTEN.
private let realNetstat = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp6       0      0  *.916                  *.*                    LISTEN                 0            0  131072  131072        rpc.lockd:14920  00080 00000006 00000000018a0be0 00000000 00000800      1      0 000000
tcp4       0      0  *.921                  *.*                    LISTEN                 0            0  131072  131072        rpc.lockd:14920  00080 00000006 00000000018a0bc7 00000000 00000800      1      0 000000
tcp4       0      0  127.0.0.1.20599        *.*                    LISTEN                 0            0  131072  131072 Code Helper (Plu:1519   00100 00000106 000000000189c627 00000001 00000800      1      0 000000
tcp6       0      0  ::1.8021               *.*                    LISTEN                 0            0  131072  131072        rpc.statd:14919  00080 00000006 00000000018a0b82 00000000 00000800      1      0 000000
tcp4       0      0  192.168.50.119.52012   17.253.144.10.443      ESTABLISHED            0            0  131072  131072        Spotify:31090    00100 00000106 000000000189c111 00000001 00000800      1      0 000000
tcp4       0      0  *.7000                 *.*                    LISTEN                 0            0  131072  131072                         00080 00000006 00000000018a0aaa 00000000 00000800      1      0 000000
"""

/// Two processes sharing one port, as a pre-forking server or an SO_REUSEPORT
/// listener produces.
private let reusePortNetstat = """
tcp4       0      0  *.8080                 *.*                    LISTEN                 0            0  131072  131072        nginx:441        00080 00000006 00000000018a0be0 00000000 00000800      1      0 000000
tcp4       0      0  *.8080                 *.*                    LISTEN                 0            0  131072  131072        nginx:442        00080 00000006 00000000018a0bc7 00000000 00000800      1      0 000000
"""

/// Real `ps -o pid=,uid=,lstart=,etime=,args=` output, covering every `etime`
/// shape: minutes, hours, and days. Pid 7171 carries a single-digit day, which
/// `lstart` pads to a double space — the shape the positional read depends on
/// `omittingEmptySubsequences` to absorb, and which a third of every month has.
private let realPS = """
    1     0 Thu May 21 14:22:40 2026     70-08:09:25 /sbin/launchd
  318     0 Thu May 21 14:24:58 2026     10:01:23 /usr/sbin/systemstats --daemon
 7171   501 Tue Jun  2 09:44:13 2026     59-04:12:55 /Applications/Discord.app/Contents/MacOS/Discord
62102   501 Sun Jul 26 20:39:41 2026     01:23 node /Users/lucascaro/checkout/keto-copilot/node_modules/.bin/next dev
"""

@Suite("Process detail sensor")
struct ProcessDetailSensorTests {
    @Test("Sockets are paired with the pid holding them")
    func pairsSocketsWithPids() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.first { $0.port == 20599 }?.pid == 1519)
        #expect(owners.first { $0.port == 8021 }?.pid == 14919)
    }

    /// The regression this parser exists for: splitting on whitespace tears
    /// "Code Helper (Plu:1519" into three fields, so the pid is not at a fixed
    /// index. Every listener from a process with a space in its name depends on
    /// this — VS Code, Discord and Google Chrome all have one.
    @Test("A process name containing spaces still yields its pid")
    func pidSurvivesSpacesInProcessName() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.contains { $0.pid == 1519 && $0.port == 20599 })
    }

    @Test("One pid holding several ports is reported once per socket")
    func onePidManyPorts() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        let lockd = owners.filter { $0.pid == 14920 }
        #expect(Set(lockd.map(\.port)) == [916, 921])
    }

    @Test("One port held by several pids is reported once per pid")
    func onePortManyPids() {
        let owners = ProcessDetailSensor.owners(netstat: reusePortNetstat)
        let onPort = owners.filter { $0.port == 8080 }
        #expect(Set(onPort.map(\.pid)) == [441, 442])
    }

    @Test("Only sockets in LISTEN state are reported")
    func ignoresEstablished() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.contains { $0.port == 52012 } == false)
    }

    /// netstat leaves the process column blank for some sockets. Without a pid
    /// there is nothing to detail, so the socket is skipped rather than
    /// attributed to whatever hex column happened to parse.
    @Test("A socket with no process column is skipped, not misattributed")
    func skipsSocketsWithoutAPid() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.contains { $0.port == 7000 } == false)
    }

    @Test("The literal bind address is kept, not just its scope")
    func keepsLiteralAddress() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.first { $0.port == 20599 }?.address == "127.0.0.1")
        #expect(owners.first { $0.port == 8021 }?.address == "::1")
        #expect(owners.first { $0.port == 916 }?.address == "*")
        #expect(owners.first { $0.port == 20599 }?.addressDescription == "127.0.0.1:20599")
    }

    /// `::1:8021` reads as a run of colons, not an address and a port. This
    /// string is shown verbatim in the detail window, and IPv6 loopback is the
    /// ordinary case for a local dev server.
    @Test("An IPv6 literal is bracketed, an IPv4 one and the wildcard are not")
    func bracketsIPv6() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.first { $0.port == 8021 }?.addressDescription == "[::1]:8021")
        #expect(owners.first { $0.port == 916 }?.addressDescription == "*:916")
    }

    @Test("Scope still agrees with what ListeningSensor would decide")
    func scopeMatchesListeningSensor() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        #expect(owners.first { $0.port == 916 }?.scope == .allInterfaces)
        #expect(owners.first { $0.port == 20599 }?.scope == .loopback)
        #expect(owners.first { $0.port == 8021 }?.scope == .loopback)
    }

    @Test("A ps row is read positionally, so argv keeps its spaces")
    func parsesArgumentsWithSpaces() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[318]?.arguments == "/usr/sbin/systemstats --daemon")
        #expect(lines[62102]?.arguments.hasSuffix("next dev") == true)
    }

    /// lstart is five whitespace-separated fields with nothing marking its end.
    /// If it were split on rather than counted, etime and argv would both land
    /// in the wrong place.
    @Test("lstart is the absolute start instant, not the elapsed time")
    func startedAtIsAbsolute() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[1]?.startedAt == "Thu May 21 14:22:40 2026")
        #expect(lines[62102]?.startedAt == "Sun Jul 26 20:39:41 2026")
    }

    /// A single-digit day is padded to a double space, so the row has the same
    /// five lstart fields as any other only if empty subsequences are dropped.
    /// Read the wrong way, etime and argv both shift a column and the identity
    /// guard starts comparing an elapsed time it can never match.
    @Test("A single-digit day in lstart does not shift the columns after it")
    func startedAtSurvivesPaddedDay() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[7171]?.startedAt == "Tue Jun 2 09:44:13 2026")
        #expect(lines[7171]?.elapsed == "59-04:12:55")
        #expect(lines[7171]?.arguments == "/Applications/Discord.app/Contents/MacOS/Discord")
    }

    /// The identity guard keys on startedAt precisely because elapsed drifts.
    /// If these two ever hold the same value the guard is comparing the wrong
    /// field and would refuse every action a second after the window opened.
    @Test("elapsed is kept apart from startedAt, in all three etime shapes")
    func elapsedIsSeparate() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[1]?.elapsed == "70-08:09:25")
        #expect(lines[318]?.elapsed == "10:01:23")
        #expect(lines[62102]?.elapsed == "01:23")
        #expect(lines[1]?.elapsed != lines[1]?.startedAt)
    }

    @Test("uid is parsed for ownership decisions")
    func parsesUID() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[1]?.uid == 0)
        #expect(lines[62102]?.uid == 501)
    }

    /// ps prints nothing at all for a pid that has already exited, and netstat's
    /// process column goes stale — measured, 2 of 13 listening pids on a real
    /// machine no longer existed. A pid with no ps row has to come back absent
    /// rather than half-populated.
    @Test("A pid that has already exited yields no line")
    func exitedPidIsAbsent() {
        let lines = ProcessDetailSensor.processes(ps: realPS)
        #expect(lines[4371] == nil)
    }

    /// The empty answer is two different facts and they must not read alike.
    /// Port 7000 is in the fixture with a blank process column: it is listening,
    /// it reaches the panel, and it has no pid — so it is the one a user is
    /// likeliest to click, and the one "nothing is listening" would libel.
    @Test("A port with no pid in netstat is unattributed, not gone")
    func portWithoutAPidIsUnattributed() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        let detail = ProcessDetailSensor.detail(
            listeningOn: 7000, owners: owners, lines: [:], paths: [:], users: [:]
        )
        #expect(detail == .unattributed)
    }

    @Test("A port whose every pid has exited is gone, not unattributed")
    func portWhosePidsExitedIsGone() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        // netstat named 14920 for port 916; ps has no row for it any more.
        let detail = ProcessDetailSensor.detail(
            listeningOn: 916, owners: owners, lines: [:], paths: [:], users: [:]
        )
        #expect(detail == .gone)
    }

    @Test("Only the pids that still have a ps row are reported")
    func partialSurvivalReportsTheSurvivors() {
        let owners = ProcessDetailSensor.owners(netstat: reusePortNetstat)
        let line = ProcessLine(
            pid: 441, uid: 501, startedAt: "Thu May 21 14:22:40 2026",
            elapsed: "01:23", arguments: "nginx: master process"
        )
        let detail = ProcessDetailSensor.detail(
            listeningOn: 8080,
            owners: owners,
            lines: [441: line],
            paths: [441: "/opt/homebrew/bin/nginx"],
            users: [501: "lucascaro"]
        )
        guard case .processes(let found) = detail else {
            Issue.record("expected processes, got \(detail)")
            return
        }
        #expect(found.map(\.pid) == [441])
        #expect(found[0].name == "nginx")
        #expect(found[0].user == "lucascaro")
    }

    /// proc_pidpath answers for other users' processes but not for one that has
    /// exited between the two reads, and getpwuid can miss a uid from a
    /// directory service that is not answering. Neither may blank the window.
    @Test("A missing path or user name falls back to the pid and the uid")
    func missingLookupsFallBack() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        let line = ProcessLine(
            pid: 14919, uid: 0, startedAt: "Thu May 21 14:22:40 2026",
            elapsed: "01:23", arguments: "/usr/sbin/rpc.statd"
        )
        let detail = ProcessDetailSensor.detail(
            listeningOn: 8021, owners: owners, lines: [14919: line], paths: [:], users: [:]
        )
        guard case .processes(let found) = detail else {
            Issue.record("expected processes, got \(detail)")
            return
        }
        #expect(found[0].name == "pid 14919")
        #expect(found[0].user == "uid 0")
        #expect(found[0].executablePath == nil)
    }

    /// The sockets a process carries are all of its ports, not just the one
    /// asked about — otherPorts(besides:) is computed from them.
    @Test("A process carries every port it holds, not only the one asked for")
    func processCarriesAllItsPorts() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat)
        let line = ProcessLine(
            pid: 14920, uid: 0, startedAt: "Thu May 21 14:22:40 2026",
            elapsed: "01:23", arguments: "/usr/sbin/rpc.lockd"
        )
        let detail = ProcessDetailSensor.detail(
            listeningOn: 916, owners: owners, lines: [14920: line], paths: [:], users: [:]
        )
        guard case .processes(let found) = detail else {
            Issue.record("expected processes, got \(detail)")
            return
        }
        #expect(found[0].sockets.map(\.port) == [916, 921])
        #expect(found[0].otherPorts(besides: 916) == [921])
    }

    @Test("Other ports exclude the one being looked at")
    func otherPortsExcludesSelf() {
        let owners = ProcessDetailSensor.owners(netstat: realNetstat).filter { $0.pid == 14920 }
        let process = ListenerProcess(
            pid: 14920, uid: 0, name: "rpc.lockd", user: "root",
            startedAt: "Thu May 21 14:22:40 2026", elapsed: "01:23",
            arguments: "/usr/sbin/rpc.lockd", executablePath: nil, sockets: owners
        )
        #expect(process.otherPorts(besides: 916) == [921])
    }
}
