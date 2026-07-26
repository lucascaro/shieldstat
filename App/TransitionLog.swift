import Foundation
import ShieldStatCore

/// Persists transitions so a multi-day trial survives the restarts that launch
/// at login guarantees. The in-memory ring buffer dies on quit and unified
/// logging persists nothing for this bundle, so neither answers "did it flap
/// last Tuesday".
///
/// Thin by design: all the retention and encoding logic is in
/// `TransitionJournal`, which is pure and tested. This only touches the disk.
@MainActor
final class TransitionLog {
    static let retention: TimeInterval = 14 * 86_400

    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    static var defaultURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShieldStat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("transitions.jsonl")
    }

    func append(_ transition: Transition, now: Date = Date()) {
        guard let line = TransitionJournal.encode(TransitionRecord(transition)) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func records() -> [TransitionRecord] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return TransitionJournal.parse(contents)
    }

    /// Called once at launch. Rewriting on every append would turn a cheap
    /// append into a full read-modify-write on every network blip.
    func pruneOnLaunch(now: Date = Date()) {
        let existing = records()
        guard !existing.isEmpty else { return }

        let kept = TransitionJournal.prune(existing, now: now, retention: Self.retention)
        guard kept.count != existing.count else { return }
        try? TransitionJournal.render(kept).write(to: url, atomically: true, encoding: .utf8)
    }
}
