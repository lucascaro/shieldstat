import SwiftUI
import ShieldStatCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: StatusModel

    /// One size for every tab. A preferences window that resizes as you switch
    /// tabs reads as broken, and the lists inside are unbounded in principle, so
    /// they scroll rather than dictating the window's height.
    private static let size = CGSize(width: 460, height: 440)

    /// Long lists scroll inside their own section instead of pushing the
    /// explanatory text off the bottom. That text carries the caveats — what a
    /// dismissal does not cover, what a mute cannot silence — so it has to stay
    /// on screen next to the thing it qualifies.
    private static let listHeight: CGFloat = 220

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            dismissed.tabItem { Label("Dismissed", systemImage: "xmark.circle") }
            muted.tabItem { Label("Muted", systemImage: "bell.slash") }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Attached to the TabView, not to an individual tab: a modifier on a
        // tab that is not currently showing does nothing at all.
        .onChange(of: settings.debounceSeconds) { model.settingsChanged() }
        .onChange(of: settings.bypassAlert) { model.settingsChanged() }
        .onChange(of: settings.labelDisplay) { model.redraw() }
        .onChange(of: settings.ignoreSystemServices) { model.refresh() }
    }

    private var general: some View {
        Form {
            Section("Menu bar") {
                Picker("Show text label", selection: $settings.labelDisplay) {
                    ForEach(LabelDisplay.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Notifications") {
                LabeledContent("Debounce") {
                    HStack {
                        Slider(value: $settings.debounceSeconds, in: 5...120, step: 5)
                        Text("\(Int(settings.debounceSeconds))s").monospacedDigit().frame(width: 40)
                    }
                }
                Toggle("Notify immediately when directly exposed", isOn: $settings.bypassAlert)
                Text("A change must hold for the debounce window before it notifies, so waking onto a network does not produce a burst. Direct exposure can skip that wait.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private var dismissed: some View {
        Form {
            Section("Automatic") {
                Toggle("Ignore services macOS starts itself", isOn: $settings.ignoreSystemServices)
                Text("Covers AirPlay, Continuity and Handoff. Deliberately excludes SSH, file sharing, NFS and screen sharing — those are listening because somebody switched them on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dismissed listeners") {
                if sortedDismissals.isEmpty {
                    Text("Nothing dismissed.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(sortedDismissals, id: \.self) { key in
                                HStack {
                                    Text(key.label)
                                    Spacer()
                                    Button("Restore") { model.restore(key) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: Self.listHeight)
                }
                Text("Dismissed listeners are still reported whenever this Mac becomes reachable from outside — a dismissal means the service is expected, not that it is safe to expose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var muted: some View {
        Form {
            Section("Muted") {
                if activeMutes.isEmpty {
                    Text("Nothing is muted.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(activeMutes, id: \.addressClass) { mute in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mute.addressClass.title)
                                        Text(muteSubtitle(mute)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Unmute") { settings.muteBook.unmute(mute.addressClass) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: Self.listHeight)
                }
                Text("Mutes suppress notifications only. The menu bar always shows the true severity, and nothing that means direct exposure can be silenced permanently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Dismissals are stored in a Set, so an explicit order is the difference
    /// between a stable list and one that reshuffles on every render.
    private var sortedDismissals: [ListenerKey] {
        settings.dismissedListeners.sorted { $0.label < $1.label }
    }

    private var activeMutes: [FactMute] {
        settings.muteBook.activeMutes(at: Date())
    }

    private func muteSubtitle(_ mute: FactMute) -> String {
        let since = mute.since.formatted(date: .abbreviated, time: .omitted)
        guard let until = mute.until else { return "Muted since \(since)" }
        return "Muted since \(since) · expires \(until.formatted(date: .abbreviated, time: .shortened))"
    }
}
