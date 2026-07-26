import Foundation

/// A change from one settled severity to another.
public struct Transition: Sendable, Equatable {
    public let from: Severity
    public let to: Severity
    public let verdict: Verdict
    public let at: Date

    public var isWorsening: Bool { to > from }
}

/// Separates the severity the glyph shows from the severity notifications trust.
///
/// A laptop waking onto a network passes through several transient states in
/// seconds. Observed severity follows every one of them; settled severity only
/// moves once a reading has held still — except into a bypass severity, where
/// waiting 30 seconds to mention that you are on the open internet is absurd.
public struct SeverityTracker: Sendable {
    private var debounce: TimeInterval
    private var bypassing: Set<Severity>

    public private(set) var observedSeverity: Severity?
    public private(set) var settledSeverity: Severity?
    private var candidate: (verdict: Verdict, since: Date)?

    public init(debounce: TimeInterval = 30, bypassing: Set<Severity> = [.alert]) {
        self.debounce = debounce
        self.bypassing = bypassing
    }

    /// Changes the timing without discarding the settled baseline. Rebuilding
    /// the tracker instead would make the next evaluation settle silently, so
    /// nudging a slider could swallow a worsening that was already pending.
    public mutating func reconfigure(debounce: TimeInterval, bypassing: Set<Severity>) {
        self.debounce = debounce
        self.bypassing = bypassing
        candidate = nil
    }

    /// When the pending candidate would settle, so the app can schedule a wake.
    /// Nil when nothing is pending.
    public var settleDeadline: Date? {
        candidate.map { $0.since.addingTimeInterval(debounce) }
    }

    /// Feeds an evaluation. Returns a transition only when the settled severity
    /// actually moves — never on the first evaluation, which settles silently so
    /// that launching the app is not itself an event.
    @discardableResult
    public mutating func observe(_ verdict: Verdict, at now: Date) -> Transition? {
        observedSeverity = verdict.severity

        guard let settled = settledSeverity else {
            settle(verdict)
            return nil
        }

        guard verdict.severity != settled else {
            candidate = nil
            return nil
        }

        if bypassing.contains(verdict.severity) {
            settle(verdict)
            return Transition(from: settled, to: verdict.severity, verdict: verdict, at: now)
        }

        if candidate?.verdict.severity != verdict.severity {
            candidate = (verdict, now)
            return nil
        }

        guard let since = candidate?.since, now.timeIntervalSince(since) >= debounce else {
            return nil
        }

        settle(verdict)
        return Transition(from: settled, to: verdict.severity, verdict: verdict, at: now)
    }

    private mutating func settle(_ verdict: Verdict) {
        settledSeverity = verdict.severity
        candidate = nil
    }
}
