import Foundation
import Network
import Observation
import OSLog
import ShieldStatCore

/// Drives evaluation: network path events, a safety poll, and a wake timed to
/// the debounce deadline so a pending change settles even if nothing else
/// happens on the network.
@MainActor
@Observable
final class StatusModel {
    private(set) var verdict = Verdict(state: .offline, severity: .ok, raisingFacts: [])
    private(set) var facts: [Fact] = []
    /// Most recent first, capped. In memory only — nothing about the user's
    /// network history is written to disk.
    private(set) var history: [Transition] = []

    var observedSeverity: Severity { verdict.severity }

    private var tracker: SeverityTracker
    private var started = false
    private let journal = TransitionLog()
    private let settings: AppSettings
    private let notifier: Notifier
    private let monitor = NWPathMonitor()
    private var safetyPoll: Timer?
    private var settleTimer: Timer?

    /// Called after every evaluation so the menu bar item can redraw. The
    /// status item is AppKit, so it does not observe the model automatically.
    var onUpdate: (() -> Void)?

    private static let historyLimit = 50
    // A path event does not always follow an address change — a secondary
    // interface gaining an address can be silent — so the poll is the floor on
    // how stale the verdict can get. getifaddrs costs microseconds.
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

    /// Idempotent: the menu bar label's `.task` can run more than once, and
    /// restarting an already-started NWPathMonitor is not harmless.
    func start() {
        guard !started else { return }
        started = true
        journal.pruneOnLaunch()

        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        monitor.start(queue: .global(qos: .utility))

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

    func evaluate(now: Date = Date()) {
        let snapshot = SystemNetworkSource.snapshot()
        facts = ExposureSensor.facts(
            from: snapshot.addresses,
            defaultRouteInterfaces: snapshot.defaultRouteInterfaces
        )
        // Listening sockets are only consulted when the machine is actually
        // reachable. Behind NAT they cannot change the verdict, so the common
        // case spawns no subprocess at all.
        let addressOnly = Policy.evaluate(facts)
        verdict = addressOnly.severity >= .notice
            ? Policy.evaluate(facts, listening: ListeningSocketSource.sockets())
            : addressOnly

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
