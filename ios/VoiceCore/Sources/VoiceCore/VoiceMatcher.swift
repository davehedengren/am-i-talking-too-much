import Foundation

/// Voice calibration and matching — port of the profile-level functions in
/// the Python app's `voice_matcher.py`.
public enum VoiceMatcher {
    public static let sampleRate = 16000
    public static let numCoefficients = 20

    /// Minimum RMS for a segment to be considered at all (quieter segments
    /// are treated as "not you" without scoring).
    public static let minimumRMS = 0.01

    /// RMS above which a chunk counts as speech at all (yours or someone
    /// else's); quieter chunks are silence and excluded from the totals.
    /// Parity: app.py SPEECH_THRESHOLD.
    public static let speechGateRMS = 0.005

    /// Tracking analyzes audio in chunks of this length, like the Python app.
    public static let chunkSeconds = 2.0

    /// Build a voice profile from a calibration recording (~10 s of speech).
    public static func createProfile(_ audio: [Double], sampleRate: Int = sampleRate) -> VoiceProfile {
        let features = MFCC.extract(audio, sampleRate: sampleRate, numMFCC: numCoefficients)

        // At least 20 frames per component so means/variances are estimable;
        // cap at 16 components.
        let numComponents = max(1, min(16, features.count / 20))
        let gmm = GaussianMixture.fit(features, numComponents: numComponents, numInits: 3, seed: 42)

        let scores = gmm.scoreSamples(features)
        return VoiceProfile(gmm: gmm, thresholdScore: calibrationThreshold(forScores: scores))
    }

    /// Threshold below which a chunk's average log-likelihood is "not you".
    /// Short tracking chunks (2 s) score with higher variance than the
    /// calibration window, so the threshold leaves 1.5 sigma of headroom.
    static func calibrationThreshold(forScores scores: [Double]) -> Double {
        let average = mean(scores)
        let standardDeviation = sqrt(mean(scores.map { ($0 - average) * ($0 - average) }))
        return average - 1.5 * standardDeviation
    }

    /// Decide whether an audio segment is the calibrated speaker.
    /// Returns the decision and a 0-1 confidence (sigmoid of the
    /// log-likelihood margin over the profile threshold).
    public static func match(
        _ audio: [Double],
        profile: VoiceProfile,
        sampleRate: Int = sampleRate
    ) -> (isMatch: Bool, confidence: Double) {
        guard let averageScore = matchScore(audio, profile: profile, sampleRate: sampleRate) else {
            return (false, 0)
        }
        let margin = averageScore - profile.thresholdScore
        let confidence = 1 / (1 + exp(-0.5 * margin))
        return (margin > 0, confidence)
    }

    /// The raw average log-likelihood of a segment under the profile, or nil
    /// when the segment is gated (too quiet, too short, or a dimension
    /// mismatch). Exposed so the app can log score-vs-threshold diagnostics.
    public static func matchScore(
        _ audio: [Double],
        profile: VoiceProfile,
        sampleRate: Int = sampleRate
    ) -> Double? {
        guard rms(audio) >= minimumRMS else {
            return nil
        }

        let features = MFCC.extract(audio, sampleRate: sampleRate, numMFCC: numCoefficients)
        // Too few frames to judge, or a profile trained with a different
        // feature dimension (scoring it would index out of range).
        guard features.count >= 5, features[0].count == profile.dimension else {
            return nil
        }

        return mean(profile.gmm.scoreSamples(features))
    }

    /// Root-mean-square amplitude.
    public static func rms(_ audio: [Double]) -> Double {
        guard !audio.isEmpty else { return 0 }
        return sqrt(audio.reduce(0) { $0 + $1 * $1 } / Double(audio.count))
    }

    /// Level-meter value in 0...1. Typical speech RMS is 0.01-0.05, so the
    /// 50x scaling shows normal speech around 50-100% (parity:
    /// audio_recorder.get_audio_level).
    public static func meterLevel(_ audio: [Double]) -> Double {
        min(max(rms(audio) * 50, 0), 1)
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
