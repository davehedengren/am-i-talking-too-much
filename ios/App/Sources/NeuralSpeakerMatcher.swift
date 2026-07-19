import Foundation
import VoiceCore

/// Neural "is this you?" matcher: embeds a chunk with AudioFeaturePrint and
/// compares it to the enrolled centroid by cosine similarity. An `actor` so the
/// embedding inference runs off the main actor; failures degrade to "not you"
/// rather than throwing into the tracking loop.
actor NeuralSpeakerMatcher: SpeakerMatcher {
    private let profile: NeuralVoiceProfile

    init(profile: NeuralVoiceProfile) {
        self.profile = profile
    }

    func match(_ audio: [Double]) async -> MatchResult {
        guard VoiceMatcher.rms(audio) >= VoiceMatcher.minimumRMS else {
            return MatchResult(isMatch: false, confidence: 0, debugInfo: "neural gated (quiet)")
        }
        guard let embedding = try? await NeuralVoiceEmbedder.embedding(audio) else {
            return MatchResult(isMatch: false, confidence: 0, debugInfo: "neural: EMBED FAILED")
        }
        guard embedding.count == profile.centroid.count else {
            return MatchResult(
                isMatch: false, confidence: 0,
                debugInfo: "neural: dim \(embedding.count) != \(profile.centroid.count)"
            )
        }

        let similarity = NeuralVoiceEmbedder.dot(embedding, profile.centroid)
        let margin = Double(similarity - profile.threshold)
        // Cosine margins are small, so scale before the sigmoid for a usable
        // 0-1 confidence.
        let confidence = 1 / (1 + exp(-8 * margin))
        return MatchResult(
            isMatch: margin > 0,
            confidence: confidence,
            debugInfo: String(format: "sim %.3f thr %.3f", similarity, profile.threshold)
        )
    }
}
