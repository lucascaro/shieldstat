import Foundation
import Testing
@testable import ShieldStatSystem

/// The only tests in this package that run real processes, because running real
/// processes is the entire content of the thing under test. They use the tools
/// every macOS install has at fixed paths, and nothing they do touches a file.
@Suite("Subprocess")
struct SubprocessTests {
    /// Deliberately not `defaultTimeout`. Five seconds of real waiting is five
    /// seconds on every run forever; one is enough to prove the deadline fires.
    private static let deadline: TimeInterval = 1

    @Test("A tool that answers returns its output")
    func returnsOutput() async {
        let output = await Subprocess.run("/bin/echo", ["hello"], timeout: Self.deadline)
        #expect(output == "hello\n")
    }

    @Test("Arguments are passed as arguments, never through a shell")
    func argumentsAreNotInterpreted() async {
        // Were this going through a shell, the substitution would run and the
        // semicolon would separate a second command. It arrives verbatim.
        let output = await Subprocess.run("/bin/echo", ["$(id -u); rm", "-rf"], timeout: Self.deadline)
        #expect(output == "$(id -u); rm -rf\n")
    }

    /// The reason this module exists. `readToEnd` returns at EOF and never
    /// otherwise, so before the deadline a tool that does not answer held the
    /// caller — the main actor, in this app — for as long as it liked.
    @Test("A tool that never answers is killed at the deadline and yields nil")
    func hungToolIsKilled() async {
        let started = Date()
        let output = await Subprocess.run("/bin/sleep", ["30"], timeout: Self.deadline)
        let waited = -started.timeIntervalSinceNow

        #expect(output == nil)
        #expect(waited < Self.deadline + 1.5, "gave up after \(waited)s")
    }

    /// Not the partial output. Half a netstat is indistinguishable from a
    /// machine with fewer listeners on it, and quietly reporting fewer listeners
    /// is the one wrong answer this must never give.
    @Test("A timeout yields nil even when the tool had already written some output")
    func partialOutputIsNotReturned() async {
        let output = await Subprocess.run(
            "/bin/sh", ["-c", "echo first; sleep 30"], timeout: Self.deadline
        )
        #expect(output == nil)
    }

    @Test("A tool that is not there yields nil rather than throwing")
    func missingToolIsNil() async {
        let output = await Subprocess.run("/usr/sbin/definitely-not-here", [], timeout: Self.deadline)
        #expect(output == nil)
    }

    @Test("A directory is not mistaken for a tool")
    func directoryIsNil() async {
        let output = await Subprocess.run("/usr/bin", [], timeout: Self.deadline)
        #expect(output == nil)
    }

    /// Output past the pipe buffer is where the read-before-wait ordering earns
    /// its comment: waiting first would leave the child blocked on a full pipe
    /// that nobody is draining, and neither side would ever move again.
    @Test("Output larger than the pipe buffer comes back whole, without deadlocking")
    func largeOutputDoesNotDeadlock() async {
        let bytes = 200_000
        let output = await Subprocess.run(
            "/usr/bin/head", ["-c", String(bytes), "/dev/zero"], timeout: 5
        )
        #expect(output?.utf8.count == bytes)
    }

    /// The shape the posture poll issues on every tick.
    @Test("Concurrent calls do not starve each other, even when one is wedged")
    func concurrentCallsDoNotStarve() async {
        let started = Date()
        let results = await withTaskGroup(of: String?.self) { group in
            group.addTask { await Subprocess.run("/bin/sleep", ["30"], timeout: Self.deadline) }
            group.addTask { await Subprocess.run("/bin/echo", ["a"], timeout: Self.deadline) }
            group.addTask { await Subprocess.run("/bin/echo", ["b"], timeout: Self.deadline) }

            var collected: [String?] = []
            for await result in group { collected.append(result) }
            return collected
        }
        let waited = -started.timeIntervalSinceNow

        #expect(results.compactMap { $0 }.sorted() == ["a\n", "b\n"])
        #expect(waited < Self.deadline + 1.5, "the wedged call held the others for \(waited)s")
    }
}
