import Foundation
import OSLog

/// Runs a system tool and returns its stdout.
///
/// A module of its own, and the only one in this package that touches anything
/// outside its own arguments. `ShieldStatCore` is pure — no file, no process, no
/// clock — which is what lets its tests run without fixtures, and that property
/// is worth more than the convenience of one more file in it. Living here rather
/// than in the App means the care below can be tested; in the App it could not.
///
/// The care is not incidental. Reading before waiting avoids the
/// deadlock a full pipe buffer causes. Every failure comes back as `nil` rather
/// than throwing, because a missing or failing tool must degrade the display and
/// never take the app down with it. And the read is bounded, because a tool that
/// answers slowly and a tool that never answers look identical from here —
/// `lsof` on a wedged network mount is the stock example, and without a deadline
/// it takes the whole app with it.
public enum Subprocess {
    private static let log = Logger(subsystem: "dev.lucascaro.ShieldStat", category: "subprocess")

    /// Well past what a healthy `netstat`, `lsof` or `ps` takes — tens of
    /// milliseconds each — and short enough that a wedged one costs a missing
    /// section rather than a beachball.
    public static let defaultTimeout: TimeInterval = 5

    /// Threads that are allowed to block, which no shared pool's are.
    ///
    /// `Task.detached` would block the cooperative pool, which has about one
    /// thread per core and is shared with everything else. `DispatchQueue.global`
    /// would block the system's shared worker pool, which tolerates it better
    /// but is not ours to spend either. Both blocked threads per call live here
    /// instead, where the only thing they can starve is another subprocess read.
    ///
    /// Two queues and not one, because each call has a thread that waits and a
    /// thread that signals it. On a single queue that is a waiter depending on
    /// the queue it is itself occupying — true deadlock only if the queue runs
    /// out of width, which at two concurrent callers it never does, but the
    /// safety of it would then rest on a call count nobody is watching.
    private static let waiting = DispatchQueue(
        label: "dev.lucascaro.ShieldStat.subprocess",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let reading = DispatchQueue(
        label: "dev.lucascaro.ShieldStat.subprocess.read",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Runs the tool off the caller's actor and suspends until it answers.
    public static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async -> String? {
        await withCheckedContinuation { continuation in
            waiting.async {
                continuation.resume(returning: capture(path, arguments, timeout: timeout))
            }
        }
    }

    /// Handoff from the reading thread to the waiting one. Ordered by the
    /// semaphore, which is what makes the unchecked conformance true: the writer
    /// signals, and only after that does the reader look.
    private final class Output: @unchecked Sendable {
        var data: Data?
    }

    /// Blocks the calling thread. Only `run` calls it, and only on a GCD queue.
    private static func capture(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read before waiting: a full pipe buffer would deadlock the child. On a
        // second thread, because `readToEnd` returns only at EOF and there is
        // nothing in it that can be told to give up — the deadline needs a
        // thread of its own to fire from.
        let output = Output()
        let finished = DispatchSemaphore(value: 0)
        reading.async {
            output.data = try? pipe.fileHandleForReading.readToEnd()
            finished.signal()
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            log.notice("\(path, privacy: .public) did not answer in \(timeout, privacy: .public)s; terminated")
            // Killing the child closes its end of the pipe, which is what gets
            // the reading thread its EOF and lets it go.
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            // Deliberately not the partial output: half a netstat is
            // indistinguishable from a machine with fewer listeners on it, and
            // quietly reporting fewer listeners is the one wrong answer this
            // must never give.
            return nil
        }

        process.waitUntilExit()
        guard let data = output.data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
