import SwiftUI
import ShieldStatCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: StatusModel

    var body: some View {
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

            Section("Muted") {
                if settings.muteBook.activeMutes(at: Date()).isEmpty {
                    Text("Nothing is muted.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.muteBook.activeMutes(at: Date()), id: \.addressClass) { mute in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mute.addressClass.title)
                                Text(muteSubtitle(mute)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unmute") {
                                settings.muteBook.unmute(mute.addressClass)
                            }
                        }
                    }
                }
                Text("Mutes suppress notifications only. The menu bar always shows the true severity, and nothing that means direct exposure can be silenced permanently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dismissed listeners") {
                Toggle("Ignore services macOS starts itself", isOn: $settings.ignoreSystemServices)
                Text("Covers AirPlay, Continuity and Handoff. Deliberately excludes SSH, file sharing, NFS and screen sharing — those are listening because somebody switched them on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.dismissedListeners.isEmpty {
                    Text("Nothing dismissed.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.dismissedListeners), id: \.self) { key in
                        HStack {
                            Text(label(for: key))
                            Spacer()
                            Button("Restore") { model.restore(key) }
                        }
                    }
                }
                Text("Dismissed listeners are still reported whenever this Mac becomes reachable from outside — a dismissal means the service is expected, not that it is safe to expose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.debounceSeconds) { model.settingsChanged() }
        .onChange(of: settings.bypassAlert) { model.settingsChanged() }
        .onChange(of: settings.labelDisplay) { model.redraw() }
        .onChange(of: settings.ignoreSystemServices) { model.refresh() }
    }

    private func label(for key: ListenerKey) -> String {
        switch key {
        case .process(let name): name
        case .port(let port): "port \(port)"
        }
    }

    private func muteSubtitle(_ mute: FactMute) -> String {
        let since = mute.since.formatted(date: .abbreviated, time: .omitted)
        guard let until = mute.until else { return "Muted since \(since)" }
        return "Muted since \(since) · expires \(until.formatted(date: .abbreviated, time: .shortened))"
    }
}
