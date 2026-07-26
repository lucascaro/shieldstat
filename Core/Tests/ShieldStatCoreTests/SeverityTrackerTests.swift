import Foundation
import Testing
@testable import ShieldStatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func verdict(_ severity: Severity) -> Verdict {
    switch severity {
    case .ok:
        Verdict(state: .private, severity: .ok, raisingFacts: [])
    case .notice:
        Verdict(
            state: .publiclyAddressable, severity: .notice,
            raisingFacts: [Fact(interface: "en0", addressClass: .globalV6, count: 1, carriesDefaultRoute: true)]
        )
    case .alert:
        Verdict(
            state: .directlyExposed, severity: .alert,
            raisingFacts: [Fact(interface: "en0", addressClass: .globalV4, count: 1, carriesDefaultRoute: true)]
        )
    }
}

@Suite("Severity tracker")
struct SeverityTrackerTests {
    @Test("The first evaluation settles silently — no notification at launch")
    func firstEvaluationIsSilent() {
        var tracker = SeverityTracker()
        let transition = tracker.observe(verdict(.alert), at: t0)

        #expect(transition == nil)
        #expect(tracker.settledSeverity == .alert)
        #expect(tracker.observedSeverity == .alert)
    }

    @Test("Observed severity updates instantly; settled severity waits")
    func observedLeadsSettled() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)
        _ = tracker.observe(verdict(.notice), at: t0.addingTimeInterval(1))

        #expect(tracker.observedSeverity == .notice)
        #expect(tracker.settledSeverity == .ok)
    }

    @Test("A notice that holds for the debounce window settles and transitions")
    func noticeSettlesAfterDebounce() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)

        #expect(tracker.observe(verdict(.notice), at: t0.addingTimeInterval(1)) == nil)
        #expect(tracker.observe(verdict(.notice), at: t0.addingTimeInterval(20)) == nil)

        let settled = tracker.observe(verdict(.notice), at: t0.addingTimeInterval(31))
        #expect(settled?.to == .notice)
        #expect(settled?.isWorsening == true)
        #expect(tracker.settledSeverity == .notice)
    }

    @Test("A transient blip during wake never settles and never notifies")
    func transientBlipIsSwallowed() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)

        #expect(tracker.observe(verdict(.notice), at: t0.addingTimeInterval(1)) == nil)
        #expect(tracker.observe(verdict(.ok), at: t0.addingTimeInterval(3)) == nil)
        #expect(tracker.observe(verdict(.ok), at: t0.addingTimeInterval(60)) == nil)
        #expect(tracker.settledSeverity == .ok)
    }

    @Test("Entering alert bypasses the debounce entirely")
    func alertIsImmediate() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)

        let transition = tracker.observe(verdict(.alert), at: t0.addingTimeInterval(1))
        #expect(transition?.to == .alert)
        #expect(transition?.isWorsening == true)
        #expect(tracker.settledSeverity == .alert)
    }

    @Test("Bypass severities are configurable")
    func bypassIsConfigurable() {
        var tracker = SeverityTracker(debounce: 30, bypassing: [])
        _ = tracker.observe(verdict(.ok), at: t0)

        #expect(tracker.observe(verdict(.alert), at: t0.addingTimeInterval(1)) == nil)
        #expect(tracker.settledSeverity == .ok)
    }

    @Test("Debounce duration is configurable")
    func debounceIsConfigurable() {
        var tracker = SeverityTracker(debounce: 5, bypassing: [])
        _ = tracker.observe(verdict(.ok), at: t0)
        _ = tracker.observe(verdict(.notice), at: t0.addingTimeInterval(1))

        #expect(tracker.observe(verdict(.notice), at: t0.addingTimeInterval(7))?.to == .notice)
    }

    @Test("Recovery settles too, and is marked as not worsening")
    func recoveryIsNotWorsening() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.alert), at: t0)
        _ = tracker.observe(verdict(.ok), at: t0.addingTimeInterval(1))

        let recovered = tracker.observe(verdict(.ok), at: t0.addingTimeInterval(40))
        #expect(recovered?.to == .ok)
        #expect(recovered?.from == .alert)
        #expect(recovered?.isWorsening == false)
    }

    @Test("Recovery from alert does not bypass the debounce")
    func leavingAlertStillDebounces() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.alert), at: t0)

        #expect(tracker.observe(verdict(.ok), at: t0.addingTimeInterval(1)) == nil)
        #expect(tracker.settledSeverity == .alert)
    }

    @Test("A pending change exposes its deadline so the app can schedule a wake")
    func pendingDeadlineIsVisible() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)
        #expect(tracker.settleDeadline == nil)

        _ = tracker.observe(verdict(.notice), at: t0.addingTimeInterval(10))
        #expect(tracker.settleDeadline == t0.addingTimeInterval(40))
    }

    @Test("The candidate window restarts when the observed severity changes again")
    func candidateRestartsOnChange() {
        var tracker = SeverityTracker(debounce: 30, bypassing: [])
        _ = tracker.observe(verdict(.ok), at: t0)
        _ = tracker.observe(verdict(.notice), at: t0.addingTimeInterval(1))
        _ = tracker.observe(verdict(.alert), at: t0.addingTimeInterval(20))

        // 25s after the alert appeared: not yet 30s, nothing settles.
        #expect(tracker.observe(verdict(.alert), at: t0.addingTimeInterval(45)) == nil)
        #expect(tracker.observe(verdict(.alert), at: t0.addingTimeInterval(51))?.to == .alert)
    }

    @Test("The settled verdict carries the facts that raised it")
    func settledVerdictCarriesFacts() {
        var tracker = SeverityTracker()
        _ = tracker.observe(verdict(.ok), at: t0)
        let transition = tracker.observe(verdict(.alert), at: t0.addingTimeInterval(1))

        #expect(transition?.verdict.raisingFacts.first?.addressClass == .globalV4)
    }
}
