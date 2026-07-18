import AVFoundation
import CoreML
import CreateMLComponents
import Foundation
import VoiceCore

/// Turns audio into a pooled, L2-normalized neural embedding using Apple's
/// on-device `AudioFeaturePrint`. All CreateMLComponents usage is isolated to
/// this file, so if the framework API shifts, only this changes.
enum NeuralVoiceEmbedder {
    /// AudioFeaturePrint window settings — 1 s windows at 50% overlap give
    /// several vectors to pool from a 2 s chunk and ~19 from a 10 s calibration.
    static let windowDuration = 1.0
    static let overlapFactor = 0.5

    /// Reused across chunks so the underlying model isn't set up every 2 s.
    /// AudioFeaturePrint is a Sendable value type, so sharing is safe.
    private static let featurePrint = AudioFeaturePrint(
        windowDuration: windowDuration, overlapFactor: overlapFactor
    )

    /// One pooled, L2-normalized embedding for the whole clip, or nil if the
    /// audio was too short to produce any windows.
    static func embedding(_ audio: [Double]) async throws -> [Float]? {
        pooledNormalized(try await windowEmbeddings(audio))
    }

    /// Per-window embedding vectors straight from AudioFeaturePrint.
    static func windowEmbeddings(_ audio: [Double]) async throws -> [[Float]] {
        // AudioReader reads from a file URL; write the samples to a temp WAV
        // (16 kHz mono, via VoiceCore's WavCodec) and clean it up after.
        let data = WavCodec.encode(audio)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let buffers = try AudioReader.read(contentsOf: url)
        let features = try featurePrint.applied(to: buffers)

        var windows: [[Float]] = []
        for try await temporalFeature in features {
            windows.append(temporalFeature.feature.scalars)
        }
        return windows
    }

    /// Mean-pool the window vectors and L2-normalize the result.
    static func pooledNormalized(_ windows: [[Float]]) -> [Float]? {
        guard let dimension = windows.first?.count, dimension > 0 else { return nil }
        var sum = [Float](repeating: 0, count: dimension)
        var count = 0
        for window in windows where window.count == dimension {
            for i in 0..<dimension { sum[i] += window[i] }
            count += 1
        }
        guard count > 0 else { return nil }
        for i in 0..<dimension { sum[i] /= Float(count) }
        return l2normalized(sum)
    }

    static func l2normalized(_ vector: [Float]) -> [Float]? {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }

    /// Dot product — cosine similarity when both inputs are already normalized.
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1 }
        var result: Float = 0
        for i in 0..<a.count { result += a[i] * b[i] }
        return result
    }
}
