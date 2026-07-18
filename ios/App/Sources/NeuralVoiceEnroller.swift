import Foundation

/// Builds a `NeuralVoiceProfile` from a calibration recording: the centroid of
/// the user's embeddings plus a cosine-similarity threshold with the same
/// `mean − 1.5·std` headroom idea as `VoiceMatcher.calibrationThreshold`, so
/// short 2 s tracking chunks (noisier than the calibration window) aren't
/// rejected.
enum NeuralVoiceEnroller {
    enum EnrollError: Error { case notEnoughAudio }

    /// Minimum cosine headroom below the calibration mean. Unlike GMM
    /// log-likelihoods, cosine self-similarities cluster very tightly, so
    /// `1.5·std` alone leaves almost no room and rejects noisier 2 s tracking
    /// chunks — floor the headroom so a genuine match still passes. Tunable
    /// from on-device A/B testing.
    static let marginFloor: Float = 0.08

    static func enroll(_ audio: [Double]) async throws -> NeuralVoiceProfile {
        let windows = try await NeuralVoiceEmbedder.windowEmbeddings(audio)
        guard windows.count >= 3,
              let centroid = NeuralVoiceEmbedder.pooledNormalized(windows) else {
            throw EnrollError.notEnoughAudio
        }

        let similarities = windows.compactMap { window in
            NeuralVoiceEmbedder.l2normalized(window).map { NeuralVoiceEmbedder.dot($0, centroid) }
        }
        let mean = similarities.reduce(0, +) / Float(similarities.count)
        let variance = similarities.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(similarities.count)
        let headroom = max(1.5 * variance.squareRoot(), marginFloor)
        let threshold = mean - headroom

        return NeuralVoiceProfile(centroid: centroid, threshold: threshold, dimension: centroid.count)
    }
}
