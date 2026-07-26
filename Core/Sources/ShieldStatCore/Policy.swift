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
    /// Something is listening on a non-loopback socket, but the machine is not
    /// reachable from outside. A door that is open onto a courtyard.
    case listeningService
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
    /// The listening sockets responsible for this verdict. Dismissed ones are
    /// excluded while the machine is unreachable, and included once it is not.
    public let raisingListeners: [ListeningSocket]

    public init(
        state: PostureState,
        severity: Severity,
        raisingFacts: [Fact],
        raisingListeners: [ListeningSocket] = []
    ) {
        self.state = state
        self.severity = severity
        self.raisingFacts = raisingFacts
        self.raisingListeners = raisingListeners
    }

    public var reachablePorts: [UInt16] { raisingListeners.map(\.port).sorted() }
}

/// The single place judgment lives. Everything else in this module observes.
public enum Policy {
    public static func evaluate(
        _ facts: [Fact],
        listening: [ListeningSocket] = [],
        dismissed: Set<ListenerKey> = []
    ) -> Verdict {
        guard !facts.isEmpty else {
            return Verdict(state: .offline, severity: .ok, raisingFacts: [])
        }

        // Each link is classified independently; the worst one names the state.
        // No match ordering, no quantifiers over the whole set.
        let worst = facts.map { state(for: $0.addressClass) }.max { rank($0) < rank($1) }!
        let raising = facts.filter { state(for: $0.addressClass) == worst }
        let addressSeverity = severity(of: worst)
        let reachable = listening.filter(\.isReachable)

        // Reachable from outside: every non-loopback listener counts, dismissed
        // or not. A dismissal says "this service is expected on my machine", not
        // "this service is safe to expose" — and Spotify listening while you sit
        // on a hotel network is the situation this whole tool exists for.
        if addressSeverity >= .notice {
            guard !reachable.isEmpty else {
                return Verdict(state: worst, severity: addressSeverity, raisingFacts: raising)
            }
            return Verdict(
                state: .exposedService,
                severity: .alert,
                raisingFacts: raising,
                raisingListeners: reachable.sorted { $0.port < $1.port }
            )
        }

        // Not reachable: listeners are worth flagging but dismissible, because
        // the machine is full of them and most are expected.
        let undismissed = reachable.filter { !$0.isDismissed(by: dismissed) }
        guard !undismissed.isEmpty else {
            return Verdict(state: worst, severity: addressSeverity, raisingFacts: raising)
        }

        return Verdict(
            state: .listeningService,
            severity: .notice,
            raisingFacts: raising,
            raisingListeners: undismissed.sorted { $0.port < $1.port }
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
        case .publiclyAddressable, .listeningService: .notice
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
        case .publiclyAddressable, .directlyExposed, .exposedService, .listeningService: 0
        }
        return (severity(of: state), tieBreak)
    }
}
