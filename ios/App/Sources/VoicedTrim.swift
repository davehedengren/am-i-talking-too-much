import Foundation

/// Frame-level (100 ms) energy analysis of a tracking chunk.
///
/// History: v1 spliced the voiced frames together and scored only those. In
/// the field that *regressed* solo accuracy (~80% → ~55%): splice seams
/// corrupt the MFCC frames that span them, the GMM is trained on untrimmed
/// calibration audio so trimmed input shifts the score distribution, and a
/// then-runaway noise gate shaved soft speech frames aggressively. Scoring
/// reverted to whole chunks; this type now provides
/// - the voiced *fraction*, logged per chunk as a diagnostic, and
/// - the quietest frame's RMS, which anchors `NoiseFloor` even mid-speech
///   (inter-word gaps approximate the ambient level).
/// Revisit trimming only with the annotated-recording eval harness measuring
/// it against ground truth.
enum VoicedTrim {
    /// Frame size: 100 ms at 16 kHz.
    static let frameSamples = 1600

    struct Result {
        /// Concatenated frames whose RMS clears the gate.
        let voiced: [Double]
        /// Fraction (0...1) of the chunk's frames that were voiced.
        let fraction: Double
    }

    /// Frames whose RMS clears `gate`, concatenated in order, plus the voiced
    /// fraction. Currently used for diagnostics/logging only — see the type
    /// comment before scoring trimmed audio again.
    static func trim(_ audio: [Double], gate: Double) -> Result {
        guard !audio.isEmpty else { return Result(voiced: [], fraction: 0) }

        var voiced: [Double] = []
        voiced.reserveCapacity(audio.count)
        var frameCount = 0
        var voicedFrames = 0

        forEachFrame(audio) { frame, rms in
            frameCount += 1
            if rms > gate {
                voicedFrames += 1
                voiced.append(contentsOf: frame)
            }
        }

        return Result(voiced: voiced, fraction: Double(voicedFrames) / Double(frameCount))
    }

    /// RMS of the quietest 100 ms frame — the chunk's best estimate of the
    /// ambient level even while someone is talking (inter-word gaps). Feeds
    /// `NoiseFloor`.
    static func quietestFrameRMS(_ audio: [Double]) -> Double {
        var quietest = Double.greatestFiniteMagnitude
        forEachFrame(audio) { _, rms in
            quietest = min(quietest, rms)
        }
        return quietest == .greatestFiniteMagnitude ? 0 : quietest
    }

    private static func forEachFrame(_ audio: [Double], _ body: (ArraySlice<Double>, Double) -> Void) {
        var start = 0
        while start < audio.count {
            let end = min(start + frameSamples, audio.count)
            let frame = audio[start..<end]
            let rms = frame.isEmpty ? 0 : (frame.reduce(0) { $0 + $1 * $1 } / Double(frame.count)).squareRoot()
            body(frame, rms)
            start = end
        }
    }
}
