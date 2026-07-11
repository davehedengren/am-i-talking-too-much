import XCTest
@testable import VoiceCore

struct MFCCFixture: Decodable {
    let sampleRate: Int
    let audio: [Double]
    let expectedMFCC: [[Double]]

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case audio
        case expectedMFCC = "expected_mfcc"
    }
}

final class MFCCParityTests: XCTestCase {
    func testMatchesPythonImplementation() throws {
        let fixture = try loadFixture("mfcc_parity", as: MFCCFixture.self)

        let mfcc = MFCC.extract(fixture.audio, sampleRate: fixture.sampleRate, numMFCC: 20)

        XCTAssertEqual(mfcc.count, fixture.expectedMFCC.count, "frame count")
        for (frame, expectedFrame) in zip(mfcc, fixture.expectedMFCC) {
            assertClose(frame, expectedFrame, absoluteTolerance: 1e-4, "MFCC frame")
        }
    }

    func testShortAudioIsPaddedToOneFrame() {
        let mfcc = MFCC.extract([Double](repeating: 0.1, count: 100), sampleRate: 16000, numMFCC: 20)
        XCTAssertEqual(mfcc.count, 1)
        XCTAssertEqual(mfcc[0].count, 20)
    }

    func testHammingWindowMatchesNumPy() {
        let window = MFCC.hammingWindow(512)
        XCTAssertEqual(window[0], 0.08, accuracy: 1e-12)
        XCTAssertEqual(window[511], 0.08, accuracy: 1e-12)
        // np.hamming(512)[256]
        XCTAssertEqual(window[256], 0.54 - 0.46 * cos(2 * .pi * 256 / 511), accuracy: 1e-12)
    }

    func testFFTAgainstDirectDFT() {
        var rng = SplitMix64(seed: 7)
        let n = 64
        let signal = (0..<n).map { _ in rng.nextDouble() * 2 - 1 }

        var real = signal
        var imag = [Double](repeating: 0, count: n)
        FFT.forward(real: &real, imag: &imag)

        for k in 0..<n {
            var sumReal = 0.0
            var sumImag = 0.0
            for t in 0..<n {
                let angle = -2 * Double.pi * Double(k) * Double(t) / Double(n)
                sumReal += signal[t] * cos(angle)
                sumImag += signal[t] * sin(angle)
            }
            XCTAssertEqual(real[k], sumReal, accuracy: 1e-9, "real bin \(k)")
            XCTAssertEqual(imag[k], sumImag, accuracy: 1e-9, "imag bin \(k)")
        }
    }
}
