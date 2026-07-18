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

    func match(_ audio: [Double]) async -> (isMatch: Bool, confidence: Double) {
        guard VoiceMatcher.rms(audio) >= VoiceMatcher.minimumRMS else { return (false, 0) }
        guard let embedding = try? await NeuralVoiceEmbedder.embedding(audio),
              embedding.count == profile.centroid.count else {
            return (false, 0)
        }

        let similarity = NeuralVoiceEmbedder.dot(embedding, profile.centroid)
        let margin = Double(similarity - profile.threshold)
        // Cosine margins are small, so scale before the sigmoid for a usable
        // 0-1 confidence.
        let confidence = 1 / (1 + exp(-8 * margin))
        return (margin > 0, confidence)
    }
}
