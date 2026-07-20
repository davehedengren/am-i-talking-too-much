import Foundation

/// One point on the "speaking share over time" chart: how the speaking time in
/// a slice of the event split between you and everyone else. Silence is not
/// counted (matching the live tracker), so an all-silent bucket has no share.
struct SpeakingBucket: Codable, Identifiable {
    let startOffset: TimeInterval
    let userSeconds: Double
    let othersSeconds: Double

    var id: TimeInterval { startOffset }
    var speechSeconds: Double { userSeconds + othersSeconds }
    /// Your fraction of the speech in this bucket (0...1), or nil if nobody
    /// spoke — the chart renders those as gaps rather than a misleading zero.
    var userShare: Double? { speechSeconds > 0 ? userSeconds / speechSeconds : nil }
}

/// Per-chunk classification recorded while tracking. Each chunk covers
/// `VoiceMatcher.chunkSeconds` of audio.
enum ChunkOutcome: Codable, Equatable {
    case you
    case others
    case silence
}

/// A finished, saved event: date, location, summary metrics, and the
/// time-bucketed speaking share used for its chart. Persisted as JSON in the
/// Documents directory (see `SessionStore`), mirroring how `VoiceProfile` is
/// stored.
struct Session: Codable, Identifiable {
    let id: UUID
    var title: String
    let date: Date
    let duration: TimeInterval
    let userSeconds: Double
    let totalSpeechSeconds: Double
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    let buckets: [SpeakingBucket]

    /// Your share of all speech across the whole event (0...100).
    var userPercentage: Double {
        totalSpeechSeconds > 0 ? userSeconds / totalSpeechSeconds * 100 : 0
    }
}

/// The metrics collected during a tracking run, before a location or title is
/// attached. The save sheet turns this into a `Session`. `Identifiable` so it
/// can drive a `.sheet(item:)` presentation.
struct SessionDraft: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let userSeconds: Double
    let totalSpeechSeconds: Double
    let buckets: [SpeakingBucket]

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

extension TimeInterval {
    /// Compact human duration like "2h 14m", "3m 20s", or "45s".
    var durationLabel: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 60 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: self) ?? "0s"
    }
}

extension Session {
    /// Group per-chunk outcomes into ~24–40 evenly sized buckets for charting.
    /// Bucket duration adapts to the event length (min 15 s) so a short test
    /// and a multi-hour party both produce a readable number of points. Each
    /// speech chunk contributes `chunkSeconds` to its bucket; silence chunks
    /// contribute to neither total. Pure — no side effects, easy to verify.
    static func buildBuckets(chunkOutcomes: [ChunkOutcome], chunkSeconds: Double) -> [SpeakingBucket] {
        guard !chunkOutcomes.isEmpty else { return [] }

        let totalDuration = Double(chunkOutcomes.count) * chunkSeconds
        // Aim for ~32 buckets, but never finer than 15 s and never finer than a
        // single chunk.
        let targetBucketSeconds = max(15.0, (totalDuration / 32).rounded())
        let bucketSeconds = max(chunkSeconds, targetBucketSeconds)
        let chunksPerBucket = max(1, Int((bucketSeconds / chunkSeconds).rounded()))

        var buckets: [SpeakingBucket] = []
        var index = 0
        while index < chunkOutcomes.count {
            let slice = chunkOutcomes[index..<min(index + chunksPerBucket, chunkOutcomes.count)]
            var user = 0.0
            var others = 0.0
            for outcome in slice {
                switch outcome {
                case .you: user += chunkSeconds
                case .others: others += chunkSeconds
                case .silence: break
                }
            }
            buckets.append(SpeakingBucket(
                startOffset: Double(index) * chunkSeconds,
                userSeconds: user,
                othersSeconds: others
            ))
            index += chunksPerBucket
        }
        return buckets
    }
}
