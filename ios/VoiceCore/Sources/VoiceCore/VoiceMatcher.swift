import Foundation

/// Voice calibration and matching — port of the profile-level functions in
/// the Python app's `voice_matcher.py`.
public enum VoiceMatcher {
    public static let sampleRate = 16000
    public static let numCoefficients = 20

    /// Minimum RMS for a segment to be considered at all (quieter segments
    /// are treated as "not you" without scoring).
    public static let minimumRMS = 0.01

    /// Build a voice profile from a calibration recording (~10 s of speech).
    public static func createProfile(_ audio: [Double], sampleRate: Int = sampleRate) -> VoiceProfile {
        let features = MFCC.extract(audio, sampleRate: sampleRate, numMFCC: numCoefficients)

        // At least 20 frames per component so means/variances are estimable;
        // cap at 16 components.
        let numComponents = max(1, min(16, features.count / 20))
        let gmm = GaussianMixture.fit(features, numComponents: numComponents, numInits: 3, seed: 42)

        let scores = gmm.scoreSamples(features)
        let average = mean(scores)
        let standardDeviation = sqrt(mean(scores.map { ($0 - average) * ($0 - average) }))

        // Short tracking chunks (2 s) score with higher variance than the
        // calibration window, so the threshold leaves 1.5 sigma of headroom.
        return VoiceProfile(gmm: gmm, thresholdScore: average - 1.5 * standardDeviation)
    }

    /// Decide whether an audio segment is the calibrated speaker.
    /// Returns the decision and a 0-1 confidence (sigmoid of the
    /// log-likelihood margin over the profile threshold).
    public static func match(
        _ audio: [Double],
        profile: VoiceProfile,
        sampleRate: Int = sampleRate
    ) -> (isMatch: Bool, confidence: Double) {
        guard rms(audio) >= minimumRMS else {
            return (false, 0)
        }

        let features = MFCC.extract(audio, sampleRate: sampleRate, numMFCC: numCoefficients)
        guard features.count >= 5 else {
            return (false, 0)
        }

        let averageScore = mean(profile.gmm.scoreSamples(features))
        let margin = averageScore - profile.thresholdScore
        let confidence = 1 / (1 + exp(-0.5 * margin))
        return (margin > 0, confidence)
    }

    /// Root-mean-square amplitude.
    public static func rms(_ audio: [Double]) -> Double {
        guard !audio.isEmpty else { return 0 }
        return sqrt(audio.reduce(0) { $0 + $1 * $1 } / Double(audio.count))
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
