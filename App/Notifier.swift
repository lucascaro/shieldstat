import Foundation
import UserNotifications
import ShieldStatCore

/// Delivers worsening transitions. `.timeSensitive` is the ceiling — `.critical`
/// needs an Apple-approved entitlement. Whether the notification persists as an
/// alert or fades as a banner remains the user's System Settings choice.
@MainActor
final class Notifier {
    private var authorized = false

    func requestAuthorization() async {
        authorized = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notify(_ transition: Transition) {
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = transition.verdict.state.title
        content.body = transition.verdict.detail
        content.interruptionLevel = .timeSensitive
        if transition.to == .alert { content.sound = .default }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

extension Verdict {
    /// The state's own words, plus which interfaces are responsible. Keeping one
    /// source of prose means adding a state cannot leave the two out of step.
    var detail: String {
        let interfaces = raisingFacts.map(\.interface).sorted().joined(separator: ", ")
        guard !interfaces.isEmpty else { return state.explanation }
        return "\(state.explanation) (\(interfaces))"
    }
}
