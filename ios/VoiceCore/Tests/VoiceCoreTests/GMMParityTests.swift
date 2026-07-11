import XCTest
@testable import VoiceCore

struct GMMFixture: Decodable {
    let profile: VoiceProfile
    let otherAudio: [Double]
    let expectedScoresUser: [Double]
    let expectedScoresOther: [Double]
    let matchUser: MatchResult
    let matchOther: MatchResult

    struct MatchResult: Decodable {
        let isMatch: Bool
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case isMatch = "is_match"
            case confidence
        }
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case otherAudio = "other_audio"
        case expectedScoresUser = "expected_scores_user"
        case expectedScoresOther = "expected_scores_other"
        case matchUser = "match_user"
        case matchOther = "match_other"
    }
}

final class GMMParityTests: XCTestCase {
    func testScoreSamplesMatchesSklearn() throws {
        let gmmFixture = try loadFixture("gmm_parity", as: GMMFixture.self)
        let mfccFixture = try loadFixture("mfcc_parity", as: MFCCFixture.self)
        let gmm = gmmFixture.profile.gmm

        let userFeatures = MFCC.extract(mfccFixture.audio, sampleRate: 16000, numMFCC: 20)
        let otherFeatures = MFCC.extract(gmmFixture.otherAudio, sampleRate: 16000, numMFCC: 20)

        assertClose(
            gmm.scoreSamples(userFeatures), gmmFixture.expectedScoresUser,
            absoluteTolerance: 1e-3, "user scores"
        )
        assertClose(
            gmm.scoreSamples(otherFeatures), gmmFixture.expectedScoresOther,
            absoluteTolerance: 1e-3, relativeTolerance: 1e-5, "other scores"
        )
    }

    func testMatchDecisionsMatchPython() throws {
        let gmmFixture = try loadFixture("gmm_parity", as: GMMFixture.self)
        let mfccFixture = try loadFixture("mfcc_parity", as: MFCCFixture.self)

        let user = VoiceMatcher.match(mfccFixture.audio, profile: gmmFixture.profile)
        XCTAssertEqual(user.isMatch, gmmFixture.matchUser.isMatch)
        XCTAssertEqual(user.confidence, gmmFixture.matchUser.confidence, accuracy: 1e-4)

        let other = VoiceMatcher.match(gmmFixture.otherAudio, profile: gmmFixture.profile)
        XCTAssertEqual(other.isMatch, gmmFixture.matchOther.isMatch)
        XCTAssertEqual(other.confidence, gmmFixture.matchOther.confidence, accuracy: 1e-4)
    }

    func testQuietAudioIsRejectedWithoutScoring() throws {
        let fixture = try loadFixture("gmm_parity", as: GMMFixture.self)
        let quiet = [Double](repeating: 0.001, count: 16000)
        let result = VoiceMatcher.match(quiet, profile: fixture.profile)
        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, 0)
    }

    func testProfileJSONRoundTripKeepsPythonSchema() throws {
        let fixture = try loadFixture("gmm_parity", as: GMMFixture.self)

        let data = try JSONEncoder().encode(fixture.profile)
        let decoded = try JSONDecoder().decode(VoiceProfile.self, from: data)
        XCTAssertEqual(decoded, fixture.profile)

        // The Python loader requires these exact keys.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["weights", "means", "covariances", "precisions_cholesky", "threshold_score"] {
            XCTAssertNotNil(object[key], "missing key \(key)")
        }
    }

    func testMissingThresholdDefaultsLikePython() throws {
        let json = """
        {"weights": [1.0], "means": [[0.0]], "covariances": [[1.0]], "precisions_cholesky": [[1.0]]}
        """
        let profile = try JSONDecoder().decode(VoiceProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.thresholdScore, -20.0)
    }
}
