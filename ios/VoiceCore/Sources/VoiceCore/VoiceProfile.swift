import Foundation

/// A calibrated voice profile: GMM parameters plus the log-likelihood
/// threshold that separates "you" from "someone else".
///
/// The JSON encoding matches the Python app's `voice_profile.json` exactly
/// (same keys, same shapes), so profiles are interchangeable between the
/// Streamlit and iOS apps.
public struct VoiceProfile: Codable, Equatable {
    public var weights: [Double]
    public var means: [[Double]]
    public var covariances: [[Double]]
    public var precisionsCholesky: [[Double]]
    public var thresholdScore: Double

    enum CodingKeys: String, CodingKey {
        case weights
        case means
        case covariances
        case precisionsCholesky = "precisions_cholesky"
        case thresholdScore = "threshold_score"
    }

    public init(gmm: GaussianMixture, thresholdScore: Double) {
        weights = gmm.weights
        means = gmm.means
        covariances = gmm.covariances
        precisionsCholesky = gmm.precisionsCholesky
        self.thresholdScore = thresholdScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weights = try container.decode([Double].self, forKey: .weights)
        means = try container.decode([[Double]].self, forKey: .means)
        covariances = try container.decode([[Double]].self, forKey: .covariances)
        precisionsCholesky = try container.decode([[Double]].self, forKey: .precisionsCholesky)
        // Same fallback as the Python loader for profiles saved before the
        // threshold field existed.
        thresholdScore = try container.decodeIfPresent(Double.self, forKey: .thresholdScore) ?? -20.0

        guard !weights.isEmpty,
              means.count == weights.count,
              covariances.count == weights.count,
              precisionsCholesky.count == weights.count
        else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Inconsistent GMM parameter shapes in voice profile"
            ))
        }
    }

    public var gmm: GaussianMixture {
        GaussianMixture(
            weights: weights,
            means: means,
            covariances: covariances,
            precisionsCholesky: precisionsCholesky
        )
    }
}
