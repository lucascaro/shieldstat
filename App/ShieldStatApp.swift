import SwiftUI
import AppKit
import ShieldStatCore

@main
struct ShieldStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item is an NSStatusItem owned by AppDelegate, not a
        // MenuBarExtra — see the note there.
        //
        // This is not a `Settings` scene: `openSettings` does not front a
        // window from an `.accessory` app on macOS 26. `openWindow` +
        // `NSApp.activate()` does, and is entirely public API. Both required.
        Window("ShieldStat Settings", id: SettingsWindow.id) {
            SettingsView(settings: delegate.settings, model: delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // One window whose content swaps, not a WindowGroup keyed on the
        // listener: several detail windows at once is not something anyone asked
        // for, and the presentation-value plumbing it needs is not free.
        Window("Listening Socket", id: ListenerDetailWindow.id) {
            ListenerDetailView(detail: delegate.detail, model: delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}
