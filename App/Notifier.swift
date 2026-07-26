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
    var detail: String {
        let interfaces = raisingFacts.map(\.interface).joined(separator: ", ")
        return switch state {
        case .directlyExposed:
            "A globally-routable IPv4 address is assigned to \(interfaces). Nothing is NATing this Mac."
        case .publiclyAddressable:
            "A globally-routable IPv6 address is assigned to \(interfaces)."
        case .private: "All addresses are private."
        case .carrierNAT: "Addresses are in carrier NAT space."
        case .noNetwork: "No address assigned — DHCP has not completed."
        case .offline: "No active network interfaces."
        }
    }
}
