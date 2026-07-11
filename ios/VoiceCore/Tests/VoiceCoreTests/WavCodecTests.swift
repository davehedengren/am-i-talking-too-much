import XCTest
@testable import VoiceCore

final class WavCodecTests: XCTestCase {
    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
        }
    }

    private func readInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, at: offset))
    }

    func testHeaderLayout() {
        let data = WavCodec.encode([0.0, 1.0, -1.0], sampleRate: 16000)

        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(readUInt32(data, at: 4), UInt32(36 + 6))
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(readUInt32(data, at: 16), 16)      // fmt chunk size
        XCTAssertEqual(readUInt16(data, at: 20), 1)       // PCM
        XCTAssertEqual(readUInt16(data, at: 22), 1)       // mono
        XCTAssertEqual(readUInt32(data, at: 24), 16000)   // sample rate
        XCTAssertEqual(readUInt32(data, at: 28), 32000)   // byte rate
        XCTAssertEqual(readUInt16(data, at: 32), 2)       // block align
        XCTAssertEqual(readUInt16(data, at: 34), 16)      // bits per sample
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(readUInt32(data, at: 40), 6)       // data size
    }

    func testSampleEncoding() {
        let data = WavCodec.encode([0.0, 1.0, -1.0, 0.5])
        XCTAssertEqual(readInt16(data, at: 44), 0)
        XCTAssertEqual(readInt16(data, at: 46), 32767)
        XCTAssertEqual(readInt16(data, at: 48), -32767)
        XCTAssertEqual(readInt16(data, at: 50), 16384)    // 16383.5 rounds up
    }

    func testOutOfRangeSamplesAreClamped() {
        let data = WavCodec.encode([2.0, -3.5])
        XCTAssertEqual(readInt16(data, at: 44), 32767)
        XCTAssertEqual(readInt16(data, at: 46), -32767)
    }

    func testDefaultSampleRateMatchesPipeline() {
        let data = WavCodec.encode([0.0])
        XCTAssertEqual(readUInt32(data, at: 24), UInt32(VoiceMatcher.sampleRate))
    }
}
