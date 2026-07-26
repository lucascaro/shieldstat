import Foundation
import Network
import Observation
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
    var settledSeverity: Severity { tracker.settledSeverity ?? verdict.severity }

    private var tracker: SeverityTracker
    private let settings: AppSettings
    private let notifier: Notifier
    private let monitor = NWPathMonitor()
    private var safetyPoll: Timer?
    private var settleTimer: Timer?

    private static let historyLimit = 50
    private static let safetyPollInterval: TimeInterval = 300

    init(settings: AppSettings, notifier: Notifier = Notifier()) {
        self.settings = settings
        self.notifier = notifier
        tracker = SeverityTracker(debounce: settings.debounceSeconds, bypassing: settings.bypassing)
    }

    func notifierAuthorization() async {
        await notifier.requestAuthorization()
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        monitor.start(queue: .global(qos: .utility))

        safetyPoll = Timer.scheduledTimer(withTimeInterval: Self.safetyPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        evaluate()
    }

    /// Rebuilds the tracker when debounce settings change. The current settled
    /// severity is deliberately discarded — the next evaluation settles silently,
    /// so changing a setting is not itself an event.
    func settingsChanged() {
        tracker = SeverityTracker(debounce: settings.debounceSeconds, bypassing: settings.bypassing)
        evaluate()
    }

    func evaluate(now: Date = Date()) {
        let snapshot = SystemNetworkSource.snapshot()
        facts = ExposureSensor.facts(
            from: snapshot.addresses,
            defaultRouteInterfaces: snapshot.defaultRouteInterfaces
        )
        verdict = Policy.evaluate(facts)

        if let transition = tracker.observe(verdict, at: now) {
            record(transition)
            if settings.muteBook.shouldNotify(transition, at: now) {
                notifier.notify(transition)
            }
        }
        scheduleSettleWake()
    }

    private func record(_ transition: Transition) {
        history.insert(transition, at: 0)
        if history.count > Self.historyLimit { history.removeLast() }
    }

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
