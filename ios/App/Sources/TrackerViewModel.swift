import Foundation
import VoiceCore

@MainActor
final class TrackerViewModel: ObservableObject {
    @Published var isTracking = false
    @Published var userSeconds = 0.0
    @Published var totalSeconds = 0.0
    @Published var percentageHistory: [Double] = []
    @Published var level: Double = 0
    @Published var debugLog: [String] = []
    @Published var errorMessage: String?

    var percentage: Double {
        totalSeconds > 0 ? userSeconds / totalSeconds * 100 : 0
    }

    private let capture: AudioCapture
    private let sink = SampleSink()
    private let chunkSampleCount = Int(VoiceMatcher.chunkSeconds * AudioCapture.sampleRate)

    init(capture: AudioCapture) {
        self.capture = capture
    }

    /// Start the microphone; runs the level meter while idle and analyzes
    /// chunks whenever tracking is on.
    func startMonitoring(profile: VoiceProfile) async {
        guard await AudioCapture.requestPermission() else {
            errorMessage = AudioCaptureError.permissionDenied.errorDescription
            return
        }
        // The view may have been swapped away while awaiting the permission
        // callback; starting now would steal the capture from its successor.
        guard !Task.isCancelled else { return }

        do {
            try capture.start(owner: self, onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Microphone stopped: \(error.localizedDescription)"
                }
            }) { [weak self] samples in
                guard let self else { return }
                // We are on the capture queue: do the analysis here and hop
                // to the main queue (FIFO, unlike unstructured Tasks) only
                // to publish.
                let tracking = self.sink.isCollecting
                let level = tracking ? 0 : VoiceMatcher.meterLevel(samples)
                self.sink.ingest(samples)

                var results: [ChunkResult] = []
                while let chunk = self.sink.drain(self.chunkSampleCount) {
                    results.append(Self.analyze(chunk, profile: profile))
                }

                // While tracking, the level meter is not rendered — publish
                // only when a chunk finished, so the chart-bearing view body
                // is invalidated once per chunk, not per audio buffer.
                guard !tracking || !results.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if !tracking {
                            self.level = level
                        }
                        for result in results {
                            self.apply(result)
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopMonitoring() {
        capture.stop(owner: self)
        sink.setCollecting(false)
        isTracking = false
    }

    func startTracking() {
        reset()
        errorMessage = nil
        sink.setCollecting(true)
        isTracking = true
    }

    func stopTracking() {
        sink.setCollecting(false)
        isTracking = false
    }

    func reset() {
        userSeconds = 0
        totalSeconds = 0
        percentageHistory = []
        debugLog = []
    }

    struct ChunkResult {
        let rms: Double
        let peak: Double
        let isSpeech: Bool
        let isUser: Bool
        let confidence: Double
    }

    nonisolated private static func analyze(_ chunk: [Double], profile: VoiceProfile) -> ChunkResult {
        let rms = VoiceMatcher.rms(chunk)
        let peak = chunk.reduce(0.0) { max($0, abs($1)) }
        guard rms > VoiceMatcher.speechGateRMS else {
            return ChunkResult(rms: rms, peak: peak, isSpeech: false, isUser: false, confidence: 0)
        }
        let match = VoiceMatcher.match(chunk, profile: profile)
        return ChunkResult(
            rms: rms, peak: peak, isSpeech: true,
            isUser: match.isMatch, confidence: match.confidence
        )
    }

    private func apply(_ result: ChunkResult) {
        guard isTracking else { return }

        var entry = String(format: "RMS: %.4f | Max: %.4f", result.rms, result.peak)
        if result.isSpeech {
            totalSeconds += VoiceMatcher.chunkSeconds
            if result.isUser {
                userSeconds += VoiceMatcher.chunkSeconds
            }
            percentageHistory.append(percentage)
            entry += String(format: " | SPEECH | gmm: %.2f | IsYou: %@",
                            result.confidence, result.isUser ? "true" : "false")
        } else {
            entry += " | (silence)"
        }

        debugLog.append(entry)
        if debugLog.count > 20 {
            debugLog.removeFirst(debugLog.count - 20)
        }
    }
}
