import Foundation
import Testing
@testable import ShieldStatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func record(at: Date, to: Severity = .alert) -> TransitionRecord {
    TransitionRecord(
        Transition(
            from: .ok, to: to,
            verdict: Verdict(
                state: .directlyExposed, severity: to,
                raisingFacts: [Fact(interface: "en0", addressClass: .globalV4, count: 1, carriesDefaultRoute: true)]
            ),
            at: at
        )
    )
}

@Suite("Transition journal")
struct TransitionJournalTests {
    @Test("A record captures severities and interfaces but never an address")
    func recordsNoAddresses() throws {
        let line = try #require(TransitionJournal.encode(record(at: t0)))

        #expect(line.contains("en0"))
        #expect(line.contains("globalV4"))
        #expect(line.contains("directlyExposed"))
        // The whole point of logging classes rather than addresses.
        #expect(line.contains("192.168") == false)
        #expect(line.contains(".") == false || line.contains("addresses") == false)
    }

    @Test("A record survives a round trip")
    func roundTrip() throws {
        let original = record(at: t0)
        let line = try #require(TransitionJournal.encode(original))
        #expect(TransitionJournal.decode(line) == original)
    }

    @Test("Encoded records are one line each, so the file stays appendable")
    func singleLine() throws {
        let line = try #require(TransitionJournal.encode(record(at: t0)))
        #expect(line.contains("\n") == false)
    }

    @Test("Unparseable lines are skipped rather than discarding the whole file")
    func toleratesGarbage() throws {
        let good = try #require(TransitionJournal.encode(record(at: t0)))
        let parsed = TransitionJournal.parse("\(good)\nnot json\n\n\(good)")
        #expect(parsed.count == 2)
    }

    @Test("Records older than the retention window are pruned")
    func prunesByAge() {
        let now = t0.addingTimeInterval(86_400 * 20)
        let kept = TransitionJournal.prune(
            [record(at: t0),                                    // 20 days old
             record(at: now.addingTimeInterval(-86_400 * 13)),  // 13 days old
             record(at: now)],
            now: now, retention: 86_400 * 14
        )
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { $0.at > now.addingTimeInterval(-86_400 * 14) })
    }

    @Test("A record exactly at the retention boundary is dropped")
    func boundaryIsExclusive() {
        let now = t0.addingTimeInterval(86_400 * 20)
        let kept = TransitionJournal.prune(
            [record(at: now.addingTimeInterval(-86_400 * 14))],
            now: now, retention: 86_400 * 14
        )
        #expect(kept.isEmpty)
    }

    @Test("A runaway flap cannot grow the file without bound")
    func hardCapOnCount() {
        let flood = (0..<(TransitionJournal.maximumRecords + 500)).map {
            record(at: t0.addingTimeInterval(Double($0)))
        }
        let kept = TransitionJournal.prune(flood, now: t0.addingTimeInterval(1000), retention: 86_400 * 14)

        #expect(kept.count == TransitionJournal.maximumRecords)
        // The cap drops the oldest, not the newest.
        #expect(kept.last?.at == flood.last?.at)
    }

    @Test("Pruning an empty journal is not an error")
    func empty() {
        #expect(TransitionJournal.prune([], now: t0, retention: 86_400).isEmpty)
    }
}
