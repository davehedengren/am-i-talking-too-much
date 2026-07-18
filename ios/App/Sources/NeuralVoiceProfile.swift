import Foundation

/// A calibrated speaker profile for the neural matcher: the L2-normalized mean
/// (centroid) of the user's AudioFeaturePrint embeddings, plus a cosine-similarity
/// threshold below which a chunk is "not you". Persisted as `neural_profile.json`.
struct NeuralVoiceProfile: Codable, Equatable {
    var centroid: [Float]
    var threshold: Float
    var dimension: Int
    var version: Int

    init(centroid: [Float], threshold: Float, dimension: Int, version: Int = 1) {
        self.centroid = centroid
        self.threshold = threshold
        self.dimension = dimension
        self.version = version
    }
}
