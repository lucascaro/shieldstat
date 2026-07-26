import Foundation
import UserNotifications
import ShieldStatCore

/// Delivers worsening transitions. `.timeSensitive` is the ceiling — `.critical`
/// needs an Apple-approved entitlement. Whether the notification persists as an
/// alert or fades as a banner remains the user's System Settings choice.
@MainActor
final class Notifier {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notify(_ transition: Transition) {
        Task { await deliver(transition) }
    }

    /// Authorization is re-read every time rather than cached at launch: the
    /// first-run prompt may still be unanswered when the first transition
    /// lands, and a user who grants permission later should not have to
    /// relaunch to be heard from again.
    private func deliver(_ transition: Transition) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = transition.verdict.state.title
        content.body = transition.verdict.detail
        content.interruptionLevel = .timeSensitive
        if transition.to == .alert { content.sound = .default }

        try? await center.add(
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
