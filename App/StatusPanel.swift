import SwiftUI
import AppKit
import ShieldStatCore

struct StatusPanel: View {
    let model: StatusModel
    let settings: AppSettings

    /// Collapsed by default: these are the listeners the check judged harmless,
    /// so they are reassurance rather than information, and the panel should
    /// lead with what needs a decision.
    @State private var showingQuiet = false

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
            if !model.localOnlyListeners.isEmpty || !model.dismissedListeners.isEmpty {
                Divider()
                quietList
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
                Text(model.verdict.state == .exposedService ? "Reachable now" : "Reachable from other machines")
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
                    lookupButton(listener)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(listener.label).font(.system(.caption, design: .monospaced))
                        if let note = listener.portDescription {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // Broad dismissal is a separate, explicit action. One click
                    // covering every port a process opens later is convenient
                    // for Spotify and a standing blind spot for Docker, whose
                    // job is publishing arbitrary ports.
                    if model.verdict.state != .exposedService, let name = listener.process {
                        Button("all \(name)") { model.dismissProcess(listener) }
                            .buttonStyle(.link)
                            .font(.caption2)
                            .help("Dismiss every port \(name) opens, now and in future")
                    }
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

    /// Opens a web search for what this listener is and whether it should be
    /// reachable. Deliberately a search rather than a built-in verdict: for most
    /// ports the honest answer depends on what the user installed, and a tool
    /// that guessed would be trusted more than it deserves.
    ///
    /// Note this is the one control in the app that leaves the machine — it
    /// sends a process name to Google, so it only ever fires on a click.
    private func lookupButton(_ listener: ListeningSocket) -> some View {
        Button {
            if let url = ListenerLookup.searchURL(for: listener) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help("Search the web for what \(listener.process ?? "port \(listener.port)") is, and whether it should be listening")
        .accessibilityLabel("Look up \(listener.label)")
    }

    /// Listeners that cannot be reached, or that the user has accepted. Listed
    /// without any control, because there is nothing to decide about them — the
    /// point is to show that the check saw them and judged them harmless, rather
    /// than to leave the user wondering whether it looked.
    private var quietList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingQuiet.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingQuiet ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(quietSummary).font(.caption)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(showingQuiet ? "Hide" : "Show") \(quietSummary)")

            if showingQuiet {
                if !model.localOnlyListeners.isEmpty {
                    Text("Local only — unreachable from other machines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(model.localOnlyListeners, id: \.self) { listener in
                        HStack(spacing: 6) {
                            lookupButton(listener)
                            Text(listener.label).font(.system(.caption2, design: .monospaced))
                            Spacer()
                            if let note = listener.portDescription {
                                Text(note).font(.caption2)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                if !model.dismissedListeners.isEmpty {
                    Text("Dismissed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, model.localOnlyListeners.isEmpty ? 0 : 4)
                    ForEach(model.dismissedListeners, id: \.self) { listener in
                        Text(listener.label)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var quietSummary: String {
        var parts: [String] = []
        if !model.localOnlyListeners.isEmpty {
            parts.append("\(model.localOnlyListeners.count) local only")
        }
        if !model.dismissedListeners.isEmpty {
            parts.append("\(model.dismissedListeners.count) dismissed")
        }
        return parts.joined(separator: " · ")
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
