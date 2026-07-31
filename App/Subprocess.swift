import Foundation

/// Runs a system tool and returns its stdout.
///
/// Extracted from `ListeningSocketSource` once the detail window became a second
/// caller. The care here is not incidental: reading before waiting avoids the
/// deadlock a full pipe buffer causes, and every failure has to come back as
/// `nil` rather than throwing, because a missing or failing tool degrades the
/// display and must never take the app down with it.
enum Subprocess {
    static func run(_ path: String, _ arguments: [String]) -> String? {
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

        // Read before waiting: a full pipe buffer would deadlock the child.
        let data = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        guard let data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
