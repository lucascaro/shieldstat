import Foundation

/// How much a state should worry you.
public enum Severity: Int, Sendable, Comparable, CaseIterable {
    case ok, notice, alert

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The user-facing name for a situation. Produced by Policy, never by a Sensor.
public enum PostureState: String, Sendable, CaseIterable {
    case offline
    case noNetwork
    case carrierNAT
    case `private`
    case publiclyAddressable
    case directlyExposed
}

public struct Verdict: Sendable, Equatable {
    public let state: PostureState
    public let severity: Severity
    /// The facts that produced this severity. A worsening transition notifies
    /// unless *every* one of these is muted — see ADR-0002.
    public let raisingFacts: [Fact]

    public init(state: PostureState, severity: Severity, raisingFacts: [Fact]) {
        self.state = state
        self.severity = severity
        self.raisingFacts = raisingFacts
    }
}

/// The single place judgment lives. Everything else in this module observes.
public enum Policy {
    public static func evaluate(_ facts: [Fact]) -> Verdict {
        guard !facts.isEmpty else {
            return Verdict(state: .offline, severity: .ok, raisingFacts: [])
        }

        // Each link is classified independently; the worst one names the state.
        // No match ordering, no quantifiers over the whole set.
        let worst = facts.map { state(for: $0.addressClass) }.max { rank($0) < rank($1) }!
        let raising = facts.filter { state(for: $0.addressClass) == worst }

        return Verdict(state: worst, severity: severity(of: worst), raisingFacts: raising)
    }

    private static func state(for addressClass: AddressClass) -> PostureState {
        switch addressClass {
        case .private: .private
        case .carrierNAT: .carrierNAT
        case .noAddress: .noNetwork
        case .globalV6: .publiclyAddressable
        case .globalV4: .directlyExposed
        }
    }

    public static func severity(of state: PostureState) -> Severity {
        switch state {
        case .offline, .noNetwork, .carrierNAT, .private: .ok
        case .publiclyAddressable: .notice
        case .directlyExposed: .alert
        }
    }

    /// Severity first; ties broken so the most informative calm state wins the
    /// label. Affects only the words shown, never the glyph.
    private static func rank(_ state: PostureState) -> (Severity, Int) {
        let tieBreak: Int = switch state {
        case .private: 3
        case .carrierNAT: 2
        case .noNetwork: 1
        case .offline: 0
        case .publiclyAddressable, .directlyExposed: 0
        }
        return (severity(of: state), tieBreak)
    }
}
