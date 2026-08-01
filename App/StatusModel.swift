import Foundation
import Observation
import OSLog
import ShieldStatCore

/// Drives evaluation: routing-socket events, a safety poll, and a wake timed
/// to the debounce deadline so a pending change settles even if nothing else
/// happens on the network.
@MainActor
@Observable
final class StatusModel {
    private(set) var verdict = Verdict(state: .offline, severity: .ok, raisingFacts: [])
    private(set) var facts: [Fact] = []
    private(set) var listeners: [ListeningSocket] = []
    /// The last attempt to enumerate listeners failed, so `listeners` and every
    /// verdict drawn from it describe the machine as it was, not as it is.
    ///
    /// Shown rather than swallowed. Keeping the previous list is the safe half
    /// of the answer — it errs toward leaving a warning up rather than dropping
    /// one — but a stale warning presented as a current one is still the app
    /// claiming to know something it does not.
    private(set) var listenersAreStale = false
    /// Most recent first, capped. In memory only — nothing about the user's
    /// network history is written to disk.
    private(set) var history: [Transition] = []

    var observedSeverity: Severity { verdict.severity }

    /// Bound to loopback only, so unreachable from any other machine. Shown for
    /// completeness and never warned about — the distinction between these and
    /// the reachable ones is the entire point of the check.
    var localOnlyListeners: [ListeningSocket] {
        listeners.filter { !$0.isReachable }.sorted { $0.port < $1.port }
    }

    /// Reachable listeners the user has already accepted. Not warned about, but
    /// still worth being able to see without opening settings.
    var dismissedListeners: [ListeningSocket] {
        listeners
            .filter { $0.isReachable && $0.isDismissed(by: settings.effectiveDismissals) }
            .sorted { $0.port < $1.port }
    }

    private var tracker: SeverityTracker
    private var started = false
    private let journal = TransitionLog()
    private let settings: AppSettings
    private let notifier: Notifier
    private let routeEvents = RouteEventSource()
    private var safetyPoll: Timer?
    private var settleTimer: Timer?
    private var evaluating = false
    private var reevaluationPending = false

    /// Called after every evaluation so the menu bar item can redraw. The
    /// status item is AppKit, so it does not observe the model automatically.
    var onUpdate: (() -> Void)?

    private static let historyLimit = 50
    // A genuine backstop again, now that the routing socket catches address
    // changes as they happen. It exists for anything the socket might miss —
    // a dropped message, a wake from sleep — not as the primary detector.
    private static let safetyPollInterval: TimeInterval = 60

    // Notifier is main-actor isolated, so it cannot be a default argument —
    // default arguments are evaluated in a nonisolated context.
    init(settings: AppSettings, notifier: Notifier? = nil) {
        self.settings = settings
        self.notifier = notifier ?? Notifier()
        tracker = SeverityTracker(debounce: settings.debounceSeconds, bypassing: settings.bypassing)
    }

    func notifierAuthorization() async {
        await notifier.requestAuthorization()
    }

    /// Idempotent: start may be called more than once, and reopening the
    /// routing socket would leak the previous one.
    func start() {
        guard !started else { return }
        started = true
        journal.pruneOnLaunch()

        routeEvents.start { [weak self] in self?.evaluate() }

        safetyPoll = Timer.scheduledTimer(withTimeInterval: Self.safetyPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        evaluate()
    }

    /// Retimes the tracker when debounce settings change, keeping the settled
    /// baseline — otherwise nudging the slider would re-baseline a pending
    /// worsening and swallow the notification it was about to produce.
    func settingsChanged() {
        tracker.reconfigure(debounce: settings.debounceSeconds, bypassing: settings.bypassing)
        evaluate()
    }

    /// Suppresses notifications about whatever is currently raising the
    /// severity. Visible and revocable in settings like any other mute.
    func snoozeCurrent(for duration: TimeInterval, now: Date = Date()) {
        try? settings.muteBook.snooze(verdict, until: now.addingTimeInterval(duration), now: now)
    }

    func mutePermanently(_ addressClass: AddressClass, now: Date = Date()) {
        try? settings.muteBook.mute(addressClass, since: now, until: nil)
    }

    /// Marks one port as expected. Narrow on purpose — see ListeningSocket.key.
    func dismiss(_ listener: ListeningSocket) {
        settings.dismissedListeners.insert(listener.key)
        evaluate()
    }

    /// Marks every port a process holds, now and in future, as expected. Only
    /// ever reached by an explicit second action, because for something like
    /// Docker this is a standing blind spot rather than a convenience.
    func dismissProcess(_ listener: ListeningSocket) {
        guard let key = listener.processKey else { return }
        settings.dismissedListeners.insert(key)
        evaluate()
    }

    /// Accepts everything currently listening as the expected baseline, so the
    /// warning becomes about listeners that appear later rather than about the
    /// twenty a Mac starts with.
    func dismissAllListeners() {
        // Port keys, never process keys: accepting a baseline should accept
        // what is listening now, not authorise whatever appears later.
        for listener in verdict.raisingListeners {
            settings.dismissedListeners.insert(listener.key)
        }
        evaluate()
    }

    func restore(_ key: ListenerKey) {
        settings.dismissedListeners.remove(key)
        evaluate()
    }

    /// Forces an immediate re-evaluation, for when the user does not believe us.
    func refresh() {
        evaluate()
    }

    /// Redraws the menu bar item without re-evaluating. Display settings change
    /// how the item is drawn, not what is true, and the item is AppKit so it
    /// does not observe the settings object.
    func redraw() {
        onUpdate?()
    }

    /// Kicks off an evaluation and returns; enumerating listeners means two
    /// subprocesses, and a route event or a button press must not wait on them.
    ///
    /// Overlapping requests coalesce rather than run in parallel. A route event
    /// arriving mid-read would otherwise start a second evaluation that could
    /// finish first, so the older verdict would land last and the tracker would
    /// see the two out of order. One at a time, with at most one more queued —
    /// a third request during the same read is already covered by the second.
    func evaluate(now: Date = Date()) {
        guard !evaluating else {
            reevaluationPending = true
            return
        }
        evaluating = true
        Task {
            await evaluateNow(now: now)
            evaluating = false
            if reevaluationPending {
                reevaluationPending = false
                // A fresh `now`: the queued request is about the machine as it
                // is when it runs, not as it was when it was asked for.
                evaluate()
            }
        }
    }

    private func evaluateNow(now: Date) async {
        let snapshot = SystemNetworkSource.snapshot()
        facts = ExposureSensor.facts(
            from: snapshot.addresses,
            defaultRouteInterfaces: snapshot.defaultRouteInterfaces
        )
        // Listeners are always enumerated now: a wildcard listener is a notice
        // even behind NAT, so the verdict depends on them in every case.
        //
        // A failed read keeps the previous list rather than clearing it. netstat
        // returning nothing and netstat not answering are different facts, and
        // only one of them means the machine stopped listening; treating the
        // second as the first is a false all-clear that would clear itself off
        // the menu bar for up to a minute.
        if let read = await ListeningSocketSource.sockets() {
            listeners = read
            listenersAreStale = false
        } else {
            listenersAreStale = true
            Self.log.notice("listener enumeration failed; keeping \(self.listeners.count, privacy: .public) from the last successful read")
        }
        verdict = Policy.evaluate(
            facts,
            listening: listeners,
            dismissed: settings.effectiveDismissals
        )

        if let transition = tracker.observe(verdict, at: now) {
            record(transition)
            if settings.muteBook.shouldNotify(transition, at: now) {
                notifier.notify(transition)
            }
        }
        scheduleSettleWake()
        onUpdate?()
    }

    private func record(_ transition: Transition) {
        history.insert(transition, at: 0)
        if history.count > Self.historyLimit { history.removeLast() }

        // The in-memory ring buffer dies on quit, and with launch at login that
        // means every reboot. The journal is what makes a multi-day trial
        // answerable; it records address classes, never addresses.
        journal.append(transition)

        Self.log.notice("""
            transition \(transition.from.name, privacy: .public) -> \
            \(transition.to.name, privacy: .public) \
            state=\(transition.verdict.state.rawValue, privacy: .public) \
            raisedBy=\(transition.verdict.raisingFacts.map(\.interface).sorted().joined(separator: ","), privacy: .public)
            """)
    }

    private static let log = Logger(subsystem: "dev.lucascaro.ShieldStat", category: "transitions")

    /// A pending candidate settles on a clock, not on network activity, so it
    /// needs its own wake-up.
    private func scheduleSettleWake() {
        settleTimer?.invalidate()
        guard let deadline = tracker.settleDeadline else { return }
        let delay = max(0.5, deadline.timeIntervalSinceNow + 0.1)
        settleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }
}
