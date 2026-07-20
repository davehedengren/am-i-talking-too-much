import Foundation

/// Extracts the voiced portion of a fixed 2 s tracking chunk before speaker
/// matching.
///
/// Why: chunks are cut on a clock, not on speech boundaries, so a chunk at a
/// pause or sentence end is part speech, part silence. Both matchers score the
/// whole chunk — averaging in a second of silence drags the GMM log-likelihood
/// (silent frames score terribly) and muddies the pooled neural embedding, so
/// partial chunks of the *calibrated speaker* routinely fall below threshold
/// and count as "others". Solo testing showed ~20% of own-speech chunks lost
/// this way, identically on both matchers — the shared upstream cause.
///
/// Pure value-level code — no side effects — so it can be exercised standalone.
enum VoicedTrim {
    /// Frame size used to find voiced regions: 100 ms at 16 kHz.
    static let frameSamples = 1600
    /// A chunk needs at least this much voiced audio to be attributed at all.
    /// Just above the neural embedder's 1 s analysis window; below it, the
    /// chunk is mostly silence and carries too little signal to score fairly —
    /// for a share metric, dropping an ambiguous chunk is more honest than
    /// misattributing it, and the cost is symmetric across speakers.
    static let minimumVoicedSeconds = 1.05

    struct Result {
        /// Concatenated frames whose RMS clears the gate.
        let voiced: [Double]
        /// Fraction (0...1) of the chunk's frames that were voiced.
        let fraction: Double
    }

    /// Keep the frames whose RMS clears `gate` (the tracker's adaptive speech
    /// gate), concatenated in order. Mid-chunk pauses are removed along with
    /// the edges; at 100 ms frames the concatenation seams are negligible next
    /// to the silence dilution they replace.
    static func trim(_ audio: [Double], gate: Double) -> Result {
        guard !audio.isEmpty else { return Result(voiced: [], fraction: 0) }

        var voiced: [Double] = []
        voiced.reserveCapacity(audio.count)
        var frameCount = 0
        var voicedFrames = 0

        var start = 0
        while start < audio.count {
            let end = min(start + frameSamples, audio.count)
            let frame = Array(audio[start..<end])
            frameCount += 1

            let rms = frame.isEmpty ? 0 : (frame.reduce(0) { $0 + $1 * $1 } / Double(frame.count)).squareRoot()
            if rms > gate {
                voicedFrames += 1
                voiced.append(contentsOf: frame)
            }
            start = end
        }

        return Result(voiced: voiced, fraction: Double(voicedFrames) / Double(frameCount))
    }

    /// The audio a matcher should score for this chunk — `audio` is nil when
    /// the chunk has too little voice to attribute. `sampleRate` converts the
    /// minimum-duration policy into samples.
    static func audioForMatching(_ audio: [Double], gate: Double, sampleRate: Double) -> (audio: [Double]?, fraction: Double) {
        let result = trim(audio, gate: gate)
        guard Double(result.voiced.count) >= minimumVoicedSeconds * sampleRate else {
            return (nil, result.fraction)
        }
        return (result.voiced, result.fraction)
    }
}
