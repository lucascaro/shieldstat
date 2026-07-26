import SwiftUI
import AppKit
import ShieldStatCore

@main
struct ShieldStatApp: App {
    @State private var settings: AppSettings
    @State private var model: StatusModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: StatusModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: model, settings: settings)
        } label: {
            MenuBarLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)

        // Not a `Settings` scene: `openSettings` does not front a window from an
        // `.accessory` app on macOS 26. `openWindow` + `NSApp.activate()` does,
        // and is entirely public API. Both calls are required.
        Window("ShieldStat Settings", id: SettingsWindow.id) {
            SettingsView(settings: settings, model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}

private struct MenuBarLabel: View {
    let model: StatusModel
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.observedSeverity.symbolName)
            if showLabel { Text(model.verdict.state.shortLabel) }
        }
        .task {
            await model.notifierAuthorization()
            model.start()
        }
    }

    private var showLabel: Bool {
        switch settings.labelDisplay {
        case .always: true
        case .never: false
        case .whenNotOK: model.observedSeverity != .ok
        }
    }
}
