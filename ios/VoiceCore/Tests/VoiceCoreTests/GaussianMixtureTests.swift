import XCTest
@testable import VoiceCore

final class GaussianMixtureTests: XCTestCase {
    /// With one component, EM has a closed form: the sample mean and the
    /// population variance (plus the regularization term).
    func testSingleComponentMatchesClosedForm() {
        let data: [[Double]] = [[1, 2], [3, 4], [5, 9]]
        let gmm = GaussianMixture.fit(data, numComponents: 1)

        XCTAssertEqual(gmm.weights, [1.0])
        XCTAssertEqual(gmm.means[0][0], 3.0, accuracy: 1e-12)
        XCTAssertEqual(gmm.means[0][1], 5.0, accuracy: 1e-12)
        XCTAssertEqual(gmm.covariances[0][0], 8.0 / 3.0 + 1e-6, accuracy: 1e-9)
        XCTAssertEqual(gmm.covariances[0][1], 26.0 / 3.0 + 1e-6, accuracy: 1e-9)
        XCTAssertEqual(gmm.precisionsCholesky[0][0], 1 / (8.0 / 3.0 + 1e-6).squareRoot(), accuracy: 1e-9)
    }

    /// Hand-computed log-density of a single Gaussian, matching sklearn's
    /// score_samples formula.
    func testScoreSamplesMatchesHandComputedGaussian() {
        let gmm = GaussianMixture(weights: [1.0], means: [[1.0, -2.0]], covariances: [[4.0, 0.25]])
        let x = [2.0, -1.0]

        // log N(x|mu,Sigma) = -0.5*(d*log(2pi) + sum((x-mu)^2/sigma^2) + sum(log sigma^2))
        let mahalanobis = pow(2.0 - 1.0, 2) / 4.0 + pow(-1.0 + 2.0, 2) / 0.25
        let logDetTerm = log(4.0) + log(0.25)
        let expected = -0.5 * (2 * log(2 * Double.pi) + mahalanobis + logDetTerm)

        let score = gmm.scoreSamples([x])[0]
        XCTAssertEqual(score, expected, accuracy: 1e-12)
    }

    func testRequestingMoreComponentsThanSamplesIsClamped() {
        let data: [[Double]] = [[0.0], [10.0]]
        let gmm = GaussianMixture.fit(data, numComponents: 8)
        XCTAssertEqual(gmm.weights.count, 2)
        XCTAssertEqual(gmm.weights.reduce(0, +), 1.0, accuracy: 1e-12)
    }

    func testLogSumExpHandlesExtremes() {
        XCTAssertEqual(logSumExp([-Double.infinity, 0]), 0, accuracy: 1e-12)
        XCTAssertEqual(logSumExp([-Double.infinity, -Double.infinity]), -Double.infinity)
        // Values that would overflow exp() directly.
        XCTAssertEqual(logSumExp([1000, 1000]), 1000 + log(2), accuracy: 1e-9)
    }
}
