import Foundation

/// One Transition, reduced to what a trial needs to answer questions about
/// flapping and frequency.
///
/// Deliberately records Address Classes and interface names, never addresses:
/// DESIGN.md defers a persisted history precisely because a file of the user's
/// network history is a privacy artifact worth protecting. "globalV4 on en0" is
/// enough to answer "how often, and did it flap"; the address itself is not.
public struct TransitionRecord: Codable, Equatable, Sendable {
    public let at: Date
    public let from: Severity
    public let to: Severity
    public let state: PostureState
    public let interfaces: [String]
    public let classes: [AddressClass]

    public init(_ transition: Transition) {
        at = transition.at
        from = transition.from
        to = transition.to
        state = transition.verdict.state
        interfaces = transition.verdict.raisingFacts.map(\.interface).sorted()
        classes = Array(Set(transition.verdict.raisingFacts.map(\.addressClass)))
            .sorted { $0.rawValue < $1.rawValue }
    }
}

/// JSONL encoding and retention for the transition history.
///
/// Pure: turning records into lines and deciding what to keep. Reading and
/// writing the file is the caller's problem.
public enum TransitionJournal {
    /// A backstop against a pathological flap filling the disk. Retention by
    /// age is the real policy; this only bounds the worst case.
    public static let maximumRecords = 5_000

    public static func encode(_ record: TransitionRecord) -> String? {
        guard let data = try? encoder.encode(record) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ line: String) -> TransitionRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? decoder.decode(TransitionRecord.self, from: data)
    }

    /// A corrupt line loses one record, never the file.
    public static func parse(_ contents: String) -> [TransitionRecord] {
        contents.split(separator: "\n").compactMap { decode(String($0)) }
    }

    public static func prune(
        _ records: [TransitionRecord],
        now: Date,
        retention: TimeInterval
    ) -> [TransitionRecord] {
        let cutoff = now.addingTimeInterval(-retention)
        let fresh = records.filter { $0.at > cutoff }
        return fresh.count > maximumRecords ? Array(fresh.suffix(maximumRecords)) : fresh
    }

    public static func render(_ records: [TransitionRecord]) -> String {
        records.compactMap(encode).joined(separator: "\n").appending("\n")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]  // never .prettyPrinted: one line per record
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
