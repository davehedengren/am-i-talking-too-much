import Foundation

/// Minimal 16-bit PCM mono WAV encoder, used to play back the calibration
/// recording and to export ground-truth recordings.
public enum WavCodec {
    public static func encode(_ samples: [Double], sampleRate: Int = VoiceMatcher.sampleRate) -> Data {
        encode(pcm16: samples.map(quantize), sampleRate: sampleRate)
    }

    /// Same container for already-quantized samples (the ground-truth recorder
    /// stores Int16 so long recordings stay small in memory).
    public static func encode(pcm16 samples: [Int16], sampleRate: Int = VoiceMatcher.sampleRate) -> Data {
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
            appendLittleEndian(&data, UInt16(bitPattern: sample))
        }
        return data
    }

    /// Clamp and quantize one sample to 16-bit PCM.
    public static func quantize(_ sample: Double) -> Int16 {
        Int16((max(-1.0, min(1.0, sample)) * 32767).rounded())
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
