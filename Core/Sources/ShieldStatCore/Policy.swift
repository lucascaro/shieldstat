import Foundation

/// How much a state should worry you.
public enum Severity: Int, Sendable, Comparable, CaseIterable, Codable {
    case ok, notice, alert

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The user-facing name for a situation. Produced by Policy, never by a Sensor.
public enum PostureState: String, Sendable, CaseIterable, Codable {
    case offline
    case noNetwork
    case carrierNAT
    case `private`
    case publiclyAddressable
    case directlyExposed
    /// Reachable from outside *and* something is listening. Neither fact alone
    /// justifies this; the correlation is the whole point of the policy layer.
    case exposedService
}

public struct Verdict: Sendable, Equatable {
    public let state: PostureState
    public let severity: Severity
    /// The facts that produced this severity. A worsening transition notifies
    /// unless *every* one of these is muted — see ADR-0002.
    public let raisingFacts: [Fact]
    /// Listening ports that something outside this Mac could plausibly reach.
    /// Empty unless the machine is also exposed — a listener behind NAT is not
    /// reachable, so reporting it would be noise.
    public let reachablePorts: [UInt16]

    public init(
        state: PostureState,
        severity: Severity,
        raisingFacts: [Fact],
        reachablePorts: [UInt16] = []
    ) {
        self.state = state
        self.severity = severity
        self.raisingFacts = raisingFacts
        self.reachablePorts = reachablePorts
    }
}

/// The single place judgment lives. Everything else in this module observes.
public enum Policy {
    public static func evaluate(
        _ facts: [Fact],
        listening: [ListeningSocket] = []
    ) -> Verdict {
        guard !facts.isEmpty else {
            return Verdict(state: .offline, severity: .ok, raisingFacts: [])
        }

        // Each link is classified independently; the worst one names the state.
        // No match ordering, no quantifiers over the whole set.
        let worst = facts.map { state(for: $0.addressClass) }.max { rank($0) < rank($1) }!
        let raising = facts.filter { state(for: $0.addressClass) == worst }

        // The correlation. A listening service is unremarkable on its own — a
        // typical Mac has dozens — and only means something once the machine is
        // reachable. Conversely, being reachable with nothing listening is
        // milder than being reachable with an open door.
        guard severity(of: worst) >= .notice else {
            return Verdict(state: worst, severity: severity(of: worst), raisingFacts: raising)
        }

        let reachable = listening.filter { $0.scope != .loopback }.map(\.port).sorted()
        guard !reachable.isEmpty else {
            return Verdict(state: worst, severity: severity(of: worst), raisingFacts: raising)
        }

        return Verdict(
            state: .exposedService,
            severity: .alert,
            raisingFacts: raising,
            reachablePorts: reachable
        )
    }

    /// The severity a single address class carries on its own.
    public static func severity(raisedBy addressClass: AddressClass) -> Severity {
        severity(of: state(for: addressClass))
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
        case .directlyExposed, .exposedService: .alert
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
        case .publiclyAddressable, .directlyExposed, .exposedService: 0
        }
        return (severity(of: state), tieBreak)
    }
}
