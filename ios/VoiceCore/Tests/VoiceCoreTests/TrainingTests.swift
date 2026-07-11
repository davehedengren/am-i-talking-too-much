import XCTest
@testable import VoiceCore

struct TrainingFixture: Decodable {
    let trainFeatures: [[Double]]
    let evalUserFeatures: [[Double]]
    let evalOtherFeatures: [[Double]]
    let pythonThreshold: Double

    enum CodingKeys: String, CodingKey {
        case trainFeatures = "train_features"
        case evalUserFeatures = "eval_user_features"
        case evalOtherFeatures = "eval_other_features"
        case pythonThreshold = "python_threshold"
    }
}

/// Swift-side GMM *training* cannot be bit-identical to sklearn (different
/// RNG and k-means implementations), so these tests assert behavioral
/// equivalence: a model trained on the calibration voice must accept that
/// voice and reject the other one, just like the Python-trained model does.
final class TrainingTests: XCTestCase {
    func testTrainedModelDiscriminatesSpeakers() throws {
        let fixture = try loadFixture("training_features", as: TrainingFixture.self)

        let numComponents = max(1, min(16, fixture.trainFeatures.count / 20))
        let gmm = GaussianMixture.fit(fixture.trainFeatures, numComponents: numComponents)

        let trainScores = gmm.scoreSamples(fixture.trainFeatures)
        let average = trainScores.reduce(0, +) / Double(trainScores.count)
        let variance = trainScores.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(trainScores.count)
        let threshold = average - 1.5 * sqrt(variance)

        let userScores = gmm.scoreSamples(fixture.evalUserFeatures)
        let otherScores = gmm.scoreSamples(fixture.evalOtherFeatures)
        let userAverage = userScores.reduce(0, +) / Double(userScores.count)
        let otherAverage = otherScores.reduce(0, +) / Double(otherScores.count)

        XCTAssertGreaterThan(userAverage, threshold, "calibration voice should match its own profile")
        XCTAssertLessThan(otherAverage, threshold, "a different voice should be rejected")
        XCTAssertGreaterThan(
            userAverage, otherAverage + 50,
            "the margin between speakers should be decisive, not borderline"
        )
    }

    func testTrainingIsDeterministicForFixedSeed() throws {
        let fixture = try loadFixture("training_features", as: TrainingFixture.self)
        let subset = Array(fixture.trainFeatures.prefix(200))

        let first = GaussianMixture.fit(subset, numComponents: 4, seed: 42)
        let second = GaussianMixture.fit(subset, numComponents: 4, seed: 42)
        XCTAssertEqual(first.weights, second.weights)
        XCTAssertEqual(first.means, second.means)
    }

    func testWeightsSumToOne() throws {
        let fixture = try loadFixture("training_features", as: TrainingFixture.self)
        let gmm = GaussianMixture.fit(fixture.trainFeatures, numComponents: 8)
        XCTAssertEqual(gmm.weights.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertTrue(gmm.covariances.allSatisfy { $0.allSatisfy { $0 > 0 } })
    }
}
