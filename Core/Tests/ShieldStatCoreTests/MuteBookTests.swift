import Foundation
import Testing
@testable import ShieldStatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func fact(_ interface: String, _ addressClass: AddressClass) -> Fact {
    Fact(interface: interface, addressClass: addressClass, count: 1, carriesDefaultRoute: true)
}

private func transition(from: Severity, to: Severity, raising: [Fact]) -> Transition {
    Transition(
        from: from, to: to,
        verdict: Verdict(state: to == .alert ? .directlyExposed : .publiclyAddressable,
                         severity: to, raisingFacts: raising),
        at: t0
    )
}

@Suite("Mute book")
struct MuteBookTests {
    @Test("An unmuted worsening transition notifies")
    func plainWorsening() {
        let book = MuteBook()
        let t = transition(from: .ok, to: .notice, raising: [fact("en0", .globalV6)])
        #expect(book.shouldNotify(t, at: t0) == true)
    }

    @Test("Recovery never notifies")
    func recoveryIsSilent() {
        let book = MuteBook()
        let t = transition(from: .alert, to: .ok, raising: [])
        #expect(book.shouldNotify(t, at: t0) == false)
    }

    @Test("A permanent mute on a notice-level fact silences it")
    func permanentNoticeMute() throws {
        var book = MuteBook()
        try book.mute(.globalV6, since: t0, until: nil)

        let t = transition(from: .ok, to: .notice, raising: [fact("en0", .globalV6)])
        #expect(book.shouldNotify(t, at: t0.addingTimeInterval(86_400 * 365)) == false)
    }

    @Test("An alert-level fact cannot be muted permanently — ADR-0002")
    func alertCannotBeMutedForever() {
        var book = MuteBook()
        #expect(throws: MuteError.self) {
            try book.mute(.globalV4, since: t0, until: nil)
        }
    }

    @Test("An alert-level fact can be snoozed, and the snooze expires")
    func alertSnoozeExpires() throws {
        var book = MuteBook()
        try book.mute(.globalV4, since: t0, until: t0.addingTimeInterval(3600))

        let t = transition(from: .ok, to: .alert, raising: [fact("en0", .globalV4)])
        #expect(book.shouldNotify(t, at: t0.addingTimeInterval(60)) == false)
        #expect(book.shouldNotify(t, at: t0.addingTimeInterval(7200)) == true)
    }

    @Test("A muted fact does not silence an alert raised by a different fact")
    func mutedFactDoesNotSwallowUnrelatedAlert() throws {
        var book = MuteBook()
        try book.mute(.globalV6, since: t0, until: nil)

        // Joined a network handing out both a GUA and a public IPv4.
        let t = transition(from: .ok, to: .alert, raising: [fact("en0", .globalV4)])
        #expect(book.shouldNotify(t, at: t0) == true)
    }

    @Test("Notification is suppressed only when every raising fact is muted")
    func allRaisingFactsMustBeMuted() throws {
        var book = MuteBook()
        try book.mute(.globalV4, since: t0, until: t0.addingTimeInterval(3600))

        let both = transition(from: .ok, to: .alert, raising: [fact("en0", .globalV4), fact("en5", .globalV4)])
        #expect(book.shouldNotify(both, at: t0) == false)

        let mixed = transition(from: .ok, to: .alert, raising: [fact("en0", .globalV4), fact("en5", .globalV6)])
        #expect(book.shouldNotify(mixed, at: t0) == true)
    }

    @Test("A snooze suppresses everything for its duration")
    func blanketSnooze() {
        var book = MuteBook()
        book.snooze(until: t0.addingTimeInterval(3600))

        let t = transition(from: .ok, to: .alert, raising: [fact("en0", .globalV4)])
        #expect(book.shouldNotify(t, at: t0.addingTimeInterval(60)) == false)
        #expect(book.shouldNotify(t, at: t0.addingTimeInterval(7200)) == true)
    }

    @Test("Mutes are keyed to the address class, never to an interface — ADR-0002")
    func mutesAreNotInterfaceScoped() throws {
        var book = MuteBook()
        try book.mute(.globalV6, since: t0, until: nil)

        let home = transition(from: .ok, to: .notice, raising: [fact("en0", .globalV6)])
        let hotel = transition(from: .ok, to: .notice, raising: [fact("en5", .globalV6)])
        #expect(book.shouldNotify(home, at: t0) == book.shouldNotify(hotel, at: t0))
    }

    @Test("Active mutes are listed with their creation date so they can be reconsidered")
    func activeMutesAreVisible() throws {
        var book = MuteBook()
        try book.mute(.globalV6, since: t0, until: nil)
        try book.mute(.globalV4, since: t0, until: t0.addingTimeInterval(3600))

        #expect(book.activeMutes(at: t0).count == 2)
        #expect(book.activeMutes(at: t0).first { $0.addressClass == .globalV6 }?.since == t0)

        // The alert snooze has lapsed; the permanent notice mute has not.
        #expect(book.activeMutes(at: t0.addingTimeInterval(7200)).map(\.addressClass) == [.globalV6])
    }

    @Test("A mute can be revoked")
    func unmute() throws {
        var book = MuteBook()
        try book.mute(.globalV6, since: t0, until: nil)
        book.unmute(.globalV6)

        let t = transition(from: .ok, to: .notice, raising: [fact("en0", .globalV6)])
        #expect(book.shouldNotify(t, at: t0) == true)
        #expect(book.activeMutes(at: t0).isEmpty)
    }

    @Test("Re-muting the same class replaces rather than duplicates")
    func remuteReplaces() throws {
        var book = MuteBook()
        try book.mute(.globalV4, since: t0, until: t0.addingTimeInterval(60))
        try book.mute(.globalV4, since: t0, until: t0.addingTimeInterval(3600))

        #expect(book.activeMutes(at: t0).count == 1)
        #expect(book.activeMutes(at: t0.addingTimeInterval(120)).count == 1)
    }

    @Test("Muting a calm class is pointless but harmless")
    func mutingCalmClasses() throws {
        var book = MuteBook()
        try book.mute(.private, since: t0, until: nil)
        #expect(book.activeMutes(at: t0).count == 1)
    }
}
