import Foundation

/// A suppression of notifications about one address class. Never scoped to an
/// interface or a network — see ADR-0002.
public struct FactMute: Sendable, Equatable, Codable {
    public let addressClass: AddressClass
    /// Shown in settings so a mute can be reconsidered rather than forgotten.
    public let since: Date
    /// Nil means permanent, which is only permitted below alert severity.
    public let until: Date?

    func isActive(at now: Date) -> Bool {
        guard let until else { return true }
        return now < until
    }
}

public enum MuteError: Error, Equatable {
    /// Nothing that means "you are on the open internet right now" may be
    /// permanently silenced.
    case alertCannotBeMutedPermanently(AddressClass)
}

/// Suppresses notifications. Never suppresses the glyph — muting is not
/// blinding, and the glyph never lies.
public struct MuteBook: Sendable, Equatable, Codable {
    private var mutes: [FactMute] = []
    private var snoozedUntil: Date?

    public init() {}

    public mutating func mute(_ addressClass: AddressClass, since: Date, until: Date?) throws {
        if until == nil, severity(of: addressClass) == .alert {
            throw MuteError.alertCannotBeMutedPermanently(addressClass)
        }
        mutes.removeAll { $0.addressClass == addressClass }
        mutes.append(FactMute(addressClass: addressClass, since: since, until: until))
    }

    public mutating func unmute(_ addressClass: AddressClass) {
        mutes.removeAll { $0.addressClass == addressClass }
    }

    /// A blanket "not now" across every class, always time-bounded.
    public mutating func snooze(until: Date) {
        snoozedUntil = until
    }

    public func activeMutes(at now: Date) -> [FactMute] {
        mutes.filter { $0.isActive(at: now) }
    }

    /// A worsening transition notifies unless every fact that raised the
    /// severity is muted.
    public func shouldNotify(_ transition: Transition, at now: Date) -> Bool {
        guard transition.isWorsening else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }

        let muted = Set(activeMutes(at: now).map(\.addressClass))
        let raising = Set(transition.verdict.raisingFacts.map(\.addressClass))

        guard !raising.isEmpty else { return true }
        return !raising.isSubset(of: muted)
    }

    private func severity(of addressClass: AddressClass) -> Severity {
        Policy.evaluate([Fact(
            interface: "", addressClass: addressClass, count: 1, carriesDefaultRoute: false
        )]).severity
    }
}
