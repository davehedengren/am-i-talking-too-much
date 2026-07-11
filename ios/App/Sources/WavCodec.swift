import Foundation

/// Minimal 16-bit PCM mono WAV encoder, used to play back the calibration
/// recording with AVAudioPlayer.
enum WavCodec {
    static func encode(_ samples: [Double], sampleRate: Int = 16000) -> Data {
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)

        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(&data, UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(&data, UInt32(16))                 // fmt chunk size
        appendLittleEndian(&data, UInt16(1))                  // PCM
        appendLittleEndian(&data, UInt16(1))                  // mono
        appendLittleEndian(&data, UInt32(sampleRate))
        appendLittleEndian(&data, UInt32(sampleRate * 2))     // byte rate
        appendLittleEndian(&data, UInt16(2))                  // block align
        appendLittleEndian(&data, UInt16(16))                 // bits per sample

        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(&data, UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            appendLittleEndian(&data, UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
