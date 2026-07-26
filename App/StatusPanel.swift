import SwiftUI
import AppKit
import ShieldStatCore

struct StatusPanel: View {
    let model: StatusModel
    let settings: AppSettings

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            factList
            if !model.verdict.raisingListeners.isEmpty {
                Divider()
                portList
            }
            if model.observedSeverity != .ok {
                Divider()
                muteControls
            }
            if !model.history.isEmpty {
                Divider()
                historyList
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.observedSeverity.symbolName)
                .font(.title2)
                .foregroundStyle(model.observedSeverity.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.verdict.state.title).font(.headline)
                Text(model.verdict.state.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var factList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.facts, id: \.self) { fact in
                HStack(spacing: 6) {
                    Text(fact.interface).font(.system(.caption, design: .monospaced))
                    if fact.carriesDefaultRoute {
                        Text("default route")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text(fact.count > 1 ? "\(fact.addressClass.title) ×\(fact.count)" : fact.addressClass.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if model.facts.isEmpty {
                Text("No active interfaces").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent changes").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(model.history.prefix(5).enumerated()), id: \.offset) { _, transition in
                HStack {
                    Image(systemName: transition.isWorsening ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(transition.to.tint)
                    Text(transition.verdict.state.title).font(.caption)
                    Spacer()
                    Text(transition.at, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Each listener is dismissible individually, because most of what a Mac
    /// listens on is expected and the warning is only useful once the expected
    /// things are out of the way.
    private var portList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.verdict.state == .exposedService ? "Reachable now" : "Listening on all interfaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // A fresh machine has ~20 of these. Accepting the current set as
                // a baseline is the only way the warning becomes about *new*
                // listeners rather than about macOS.
                if model.verdict.state != .exposedService, model.verdict.raisingListeners.count > 1 {
                    Button("Dismiss all \(model.verdict.raisingListeners.count)") { model.dismissAllListeners() }
                        .buttonStyle(.link)
                        .font(.caption2)
                }
            }

            ForEach(model.verdict.raisingListeners, id: \.self) { listener in
                HStack(spacing: 6) {
                    if model.verdict.state != .exposedService {
                        Button { model.dismiss(listener) } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(listener.dismissDescription)
                        .accessibilityLabel(listener.dismissDescription)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(listener.label).font(.system(.caption, design: .monospaced))
                        if let note = listener.portDescription {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let scope = listener.dismissScopeNote {
                        Text(scope)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if model.verdict.state == .exposedService {
                        Text("reachable").font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            if model.verdict.state == .exposedService {
                Text("Dismissals do not apply while this Mac is reachable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Direct exposure can be snoozed but never permanently silenced — the
    /// permanent option only appears for classes below alert severity.
    private var muteControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Quiet notifications").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("1 hour") { model.snoozeCurrent(for: 3600) }
                Button("Until tomorrow") { model.snoozeCurrent(for: 86_400) }
            }
            ForEach(permanentlyMutableClasses, id: \.self) { addressClass in
                Button("Always ignore \(addressClass.title)") { model.mutePermanently(addressClass) }
                    .font(.caption)
            }
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private var permanentlyMutableClasses: [AddressClass] {
        let raising = Set(model.verdict.raisingFacts.map(\.addressClass))
        let alreadyMuted = Set(settings.muteBook.activeMutes(at: Date()).map(\.addressClass))
        return raising
            .filter { Policy.severity(raisedBy: $0) != .alert && !alreadyMuted.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { model.refresh() }
            Button("Settings…") {
                openWindow(id: SettingsWindow.id)
                // Required: openWindow alone leaves the window visible but not
                // key from an .accessory app. Verified on macOS 26.4.
                NSApp.activate()
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}
