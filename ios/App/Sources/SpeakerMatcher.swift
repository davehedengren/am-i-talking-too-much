import Foundation
import VoiceCore

/// Outcome of scoring one chunk, including a short raw score-vs-threshold
/// string for the debug log so mismatches can be diagnosed in the field.
struct MatchResult: Sendable {
    let isMatch: Bool
    let confidence: Double
    let debugInfo: String
}

/// A per-chunk "is this the calibrated speaker?" decision. Async so a neural
/// implementation can run inference off the main actor; the GMM implementation
/// satisfies it synchronously.
protocol SpeakerMatcher: Sendable {
    func match(_ audio: [Double]) async -> MatchResult
}

/// The classic MFCC + GMM matcher (VoiceCore), kept for A/B comparison and as a
/// fallback when neural enrollment isn't available.
struct GMMSpeakerMatcher: SpeakerMatcher {
    let profile: VoiceProfile

    func match(_ audio: [Double]) async -> MatchResult {
        guard let score = VoiceMatcher.matchScore(audio, profile: profile) else {
            return MatchResult(isMatch: false, confidence: 0, debugInfo: "gmm gated (quiet/short)")
        }
        // Keep in lockstep with VoiceMatcher.match: sigmoid(0.5 * margin).
        let margin = score - profile.thresholdScore
        let confidence = 1 / (1 + exp(-0.5 * margin))
        return MatchResult(
            isMatch: margin > 0,
            confidence: confidence,
            debugInfo: String(format: "ll %.1f thr %.1f", score, profile.thresholdScore)
        )
    }
}
