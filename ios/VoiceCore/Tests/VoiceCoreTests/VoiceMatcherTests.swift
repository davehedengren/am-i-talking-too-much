import XCTest
@testable import VoiceCore

final class VoiceMatcherTests: XCTestCase {
    /// These constants are the cross-platform contract with the Python app
    /// (CLAUDE.md, "Cross-Platform Parity") — changing one side without the
    /// other breaks profile interchangeability or decision parity.
    func testParityConstants() {
        XCTAssertEqual(VoiceMatcher.sampleRate, 16000)
        XCTAssertEqual(VoiceMatcher.numCoefficients, 20)
        XCTAssertEqual(VoiceMatcher.minimumRMS, 0.01)
        XCTAssertEqual(VoiceMatcher.speechGateRMS, 0.005)
        XCTAssertEqual(VoiceMatcher.chunkSeconds, 2.0)
        XCTAssertEqual(MFCC.defaultFrameSize, 512)
        XCTAssertEqual(MFCC.defaultHopSize, 256)
        XCTAssertEqual(MFCC.numMelFilters, 26)
    }

    func testCalibrationThresholdIsMeanMinusOnePointFiveSigma() {
        // scores [0, 2, 4]: mean 2, population std sqrt(8/3)
        let threshold = VoiceMatcher.calibrationThreshold(forScores: [0, 2, 4])
        XCTAssertEqual(threshold, 2 - 1.5 * (8.0 / 3.0).squareRoot(), accuracy: 1e-12)
    }

    func testMeterLevelScalesAndClamps() {
        XCTAssertEqual(VoiceMatcher.meterLevel([Double](repeating: 0, count: 100)), 0)
        // Constant 0.001 → rms 0.001 → 0.05 after 50x scaling.
        XCTAssertEqual(VoiceMatcher.meterLevel([Double](repeating: 0.001, count: 100)), 0.05, accuracy: 1e-12)
        // Constant 0.1 → rms 0.1 → 5.0 → clamped to 1.
        XCTAssertEqual(VoiceMatcher.meterLevel([Double](repeating: 0.1, count: 100)), 1)
    }

    func testTooFewFramesIsRejected() throws {
        let fixture = try loadFixture("gmm_parity", as: GMMFixture.self)
        // 800 loud samples → 2 frames, below the 5-frame minimum.
        let audio = [Double](repeating: 0.5, count: 800)
        let result = VoiceMatcher.match(audio, profile: fixture.profile)
        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, 0)
    }

    func testDimensionMismatchedProfileIsRejectedNotCrashed() throws {
        // A self-consistent 2-dimensional profile (e.g. from a modified
        // Python build): matching must refuse it, not index out of range.
        let json = """
        {"weights": [1.0], "means": [[0.0, 0.0]], "covariances": [[1.0, 1.0]],
         "precisions_cholesky": [[1.0, 1.0]], "threshold_score": -5.0}
        """
        let profile = try JSONDecoder().decode(VoiceProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.dimension, 2)

        let audio = (0..<16000).map { 0.2 * sin(2 * Double.pi * 220 * Double($0) / 16000) }
        let result = VoiceMatcher.match(audio, profile: profile)
        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.confidence, 0)
    }

    func testEmptyAudioHasZeroRMS() {
        XCTAssertEqual(VoiceMatcher.rms([]), 0)
        XCTAssertEqual(VoiceMatcher.meterLevel([]), 0)
    }
}
