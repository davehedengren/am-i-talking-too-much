import Foundation
import VoiceCore

/// A per-chunk "is this the calibrated speaker?" decision. Async so a neural
/// implementation can run inference off the main actor; the GMM implementation
/// satisfies it synchronously.
protocol SpeakerMatcher: Sendable {
    func match(_ audio: [Double]) async -> (isMatch: Bool, confidence: Double)
}

/// The classic MFCC + GMM matcher (VoiceCore), kept for A/B comparison and as a
/// fallback when neural enrollment isn't available.
struct GMMSpeakerMatcher: SpeakerMatcher {
    let profile: VoiceProfile

    func match(_ audio: [Double]) async -> (isMatch: Bool, confidence: Double) {
        VoiceMatcher.match(audio, profile: profile)
    }
}
