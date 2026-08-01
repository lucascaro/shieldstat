import AppKit
import Observation
import SwiftUI
import ShieldStatCore

/// Which listener the detail window is showing, and what was found out about it.
///
/// A separate observable object rather than a property read off the delegate:
/// the window's content is built once, so it has to observe something that
/// changes, or clicking a second listener would leave the first one on screen.
@MainActor
@Observable
final class ListenerDetailModel {
    private(set) var socket: ListeningSocket?
    private(set) var detail: ListenerDetail?

    func show(_ socket: ListeningSocket) {
        self.socket = socket
        // Nil, not the last listener's answer: the read takes a beat now that it
        // is off the main actor, and showing the previous socket's processes
        // under the new socket's header would be worse than showing nothing.
        detail = nil
        Task { await reload() }
    }

    func reload() async {
        guard let socket else { return }
        let found = await ProcessDetailSource.detail(listeningOn: socket.port)
        // A second click while this read was in flight wins. Without this the
        // slower of two overlapping reads lands last and the window ends up
        // describing whichever listener happened to answer later.
        guard self.socket == socket else { return }
        detail = found
    }
}

/// What is listening, who owns it, and what can be done about it.
///
/// A window rather than more of the status popover. The popover is transient and
/// 340pt wide: a confirmation shown from inside it would dismiss its own parent,
/// and none of this fits. It follows the settings window, which is opened the
/// same way and for the same reason.
struct ListenerDetailView: View {
    let detail: ListenerDetailModel
    let model: StatusModel

    /// The app has no other user-facing error surface — everything else degrades
    /// silently into the log. Quitting a process is the first action that can
    /// fail in a way the user needs told about, so it gets one line and no more.
    @State private var failure: String?
    @State private var confirming: ListenerProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let socket = detail.socket {
                header(socket)
                Divider()

                switch detail.detail {
                case nil:
                    Text("Reading…").font(.callout).foregroundStyle(.secondary)
                case .processes(let processes):
                    ForEach(processes, id: \.pid) { process in
                        processSection(process, port: socket.port)
                    }
                case .gone:
                    // Ordinary rather than an error: the socket closed between
                    // the click and the read, or netstat named a pid that had
                    // already exited. Either way there is nothing left to name.
                    Text("Nothing is listening on port \(String(socket.port)) any more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .unreadable:
                    // Not a claim about the port at all. Every other branch here
                    // says something about the machine; this one says the
                    // question went unanswered, and must not be mistaken for an
                    // answer of "nothing".
                    Text("Could not read the process table. Nothing is known about port \(String(socket.port)) right now.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Text("Refresh to try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unattributed:
                    // The socket is real and still listening — it is on screen
                    // behind this window. Saying "nothing is listening" here
                    // would be flatly untrue, and untrue about the listener the
                    // panel raises loudest.
                    Text("Port \(String(socket.port)) is listening, but netstat names no process holding it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("This is what an unprivileged read can see. `sudo lsof -iTCP:\(String(socket.port)) -sTCP:LISTEN` will name it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let failure {
                    Text(failure).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("Select a listening socket.").foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Refresh") {
                    failure = nil
                    Task { await detail.reload() }
                }
                Spacer()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // The window outlives the selection, so a failure about the last
        // listener would otherwise sit under the details of the next one.
        .onChange(of: detail.socket) {
            failure = nil
            confirming = nil
        }
    }

    private func header(_ socket: ListeningSocket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(socket.label).font(.title3.monospaced())
            if let note = socket.portDescription {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Text(socket.scopeDescription)
                .font(.caption)
                .foregroundStyle(socket.isReachable ? .red : .secondary)
        }
    }

    /// One section per process, because a port can be held by more than one —
    /// a pre-forking server or an SO_REUSEPORT listener. Each gets its own
    /// actions rather than the window guessing which is the real one.
    private func processSection(_ process: ListenerProcess, port: UInt16) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(process.name).font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
                field("PID", String(process.pid))
                field("User", "\(process.user) (uid \(process.uid))")
                field("Started", process.startedAt)
                field("Running for", process.elapsed)
                field("Bound to", process.bindDescription(for: port))
                if let path = process.executablePath {
                    field("Executable", path)
                }
                field("Command", process.arguments)
                if let others = process.otherPortsDescription(besides: port) {
                    field("Also listening on", others)
                }
            }

            actions(process)
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ShieldStat does not stop anything by itself; these fire only when the
    /// user presses them. What it will not do is offer an action that cannot
    /// work — signalling another user's process fails with EPERM and there is no
    /// way around that without a privileged helper, so the buttons say so
    /// instead of failing on press.
    private func actions(_ process: ListenerProcess) -> some View {
        HStack(spacing: 8) {
            Group {
                Button("Quit") { perform(process, force: false) }
                Button("Force Quit…") { confirming = process }
            }
            .disabled(!process.isOwnedByCurrentUser)
            .help(process.isOwnedByCurrentUser
                  ? "Ask \(process.name) to quit"
                  : "ShieldStat cannot quit processes owned by \(process.user).")

            // Not gated on ownership: looking at where a binary lives is reading,
            // and it is most worth doing for the processes you did not start.
            if let path = process.executablePath {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Spacer()
        }
        .font(.caption)
        .confirmationDialog(
            "Force quit \(process.name)?",
            isPresented: .init(get: { confirming?.pid == process.pid }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                confirming = nil
                perform(process, force: true)
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("It is killed outright, with no chance to save. Quit asks it to close instead.")
        }
    }

    private func perform(_ process: ListenerProcess, force: Bool) {
        Task {
            switch await ProcessDetailSource.quit(process, force: force) {
            case .sent:
                failure = nil
                // Neither a signal nor a Quit event is synchronous: the process
                // is still alive when this returns. Re-reading straight away
                // would redraw the same section and read as the button having
                // done nothing. A beat first, then both surfaces, so the panel
                // behind the window agrees with it.
                //
                // ponytail: a fixed delay rather than watching for the process
                // to go. An app that puts up a save dialog outlives it and
                // needs the Refresh button; waiting properly means polling, and
                // polling for something the user can see for themselves is not
                // worth the code.
                try? await Task.sleep(for: .milliseconds(600))
                await detail.reload()
                model.refresh()
            case .stale:
                failure = "That process has already exited — pid \(process.pid) now belongs to something else. Nothing was sent."
                await detail.reload()
            case .failed(let reason):
                failure = reason
            }
        }
    }
}

enum ListenerDetailWindow {
    static let id = "listener-detail"
}
