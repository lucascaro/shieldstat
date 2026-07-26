import Foundation
import Observation
import ServiceManagement
import ShieldStatCore

/// When the short text label sits next to the glyph in the menu bar.
enum LabelDisplay: String, CaseIterable, Identifiable {
    case always, whenNotOK, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .whenNotOK: "Only when not OK"
        case .never: "Never"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var labelDisplay: LabelDisplay { didSet { defaults.set(labelDisplay.rawValue, forKey: Key.labelDisplay) } }
    var debounceSeconds: Double { didSet { defaults.set(debounceSeconds, forKey: Key.debounce) } }
    /// Which severities skip the debounce and notify immediately.
    var bypassAlert: Bool { didSet { defaults.set(bypassAlert, forKey: Key.bypassAlert) } }
    var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }

    var muteBook: MuteBook { didSet { persistMutes() } }

    /// Listeners the user has said are expected on this machine. Suppresses the
    /// standalone notice only — see Policy, a dismissal never survives the
    /// machine becoming reachable.
    var dismissedListeners: Set<ListenerKey> { didSet { persistDismissals() } }

    /// Auto-dismiss the listeners macOS starts on its own behalf. On by
    /// default, and deliberately a visible toggle: it is a blind spot, and a
    /// blind spot the user cannot see is one they cannot reconsider.
    var ignoreSystemServices: Bool {
        didSet { defaults.set(ignoreSystemServices, forKey: Key.ignoreSystem) }
    }

    /// What Policy is actually told, user choices plus the baseline.
    var effectiveDismissals: Set<ListenerKey> {
        ignoreSystemServices
            ? dismissedListeners.union(SystemServiceBaseline.keys)
            : dismissedListeners
    }

    private let defaults: UserDefaults

    private enum Key {
        static let labelDisplay = "labelDisplay"
        static let debounce = "debounceSeconds"
        static let bypassAlert = "bypassAlert"
        static let mutes = "muteBook"
        static let dismissals = "dismissedListeners"
        static let ignoreSystem = "ignoreSystemServices"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        labelDisplay = (defaults.string(forKey: Key.labelDisplay).flatMap(LabelDisplay.init)) ?? .whenNotOK
        debounceSeconds = defaults.object(forKey: Key.debounce) as? Double ?? 30
        bypassAlert = defaults.object(forKey: Key.bypassAlert) as? Bool ?? true
        muteBook = (defaults.data(forKey: Key.mutes)
            .flatMap { try? JSONDecoder().decode(MuteBook.self, from: $0) }) ?? MuteBook()
        dismissedListeners = (defaults.data(forKey: Key.dismissals)
            .flatMap { try? JSONDecoder().decode(Set<ListenerKey>.self, from: $0) }) ?? []
        ignoreSystemServices = defaults.object(forKey: Key.ignoreSystem) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var bypassing: Set<Severity> { bypassAlert ? [.alert] : [] }

    private func persistDismissals() {
        defaults.set(try? JSONEncoder().encode(dismissedListeners), forKey: Key.dismissals)
    }

    private func persistMutes() {
        defaults.set(try? JSONEncoder().encode(muteBook), forKey: Key.mutes)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The user can always flip this in System Settings > Login Items.
            NSLog("ShieldStat: login item change failed: \(error.localizedDescription)")
        }
    }
}
