import Foundation
import VoiceCore

@MainActor
final class TrackerViewModel: ObservableObject {
    /// Audio is analyzed in 2-second chunks, matching the Python app.
    static let chunkSeconds = 2.0
    /// RMS above this counts as speech (yours or someone else's);
    /// quieter chunks are silence and not counted at all.
    static let speechRMSThreshold = 0.005

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
    private let chunkSampleCount = Int(chunkSeconds * AudioCapture.sampleRate)

    init(capture: AudioCapture) {
        self.capture = capture
    }

    /// Start the microphone; runs the level meter continuously and analyzes
    /// chunks whenever tracking is on.
    func startMonitoring(profile: VoiceProfile) async {
        guard await AudioCapture.requestPermission() else {
            errorMessage = AudioCaptureError.permissionDenied.errorDescription
            return
        }

        do {
            try capture.start(owner: self) { [weak self] samples in
                guard let self else { return }
                let level = min(max(VoiceMatcher.rms(samples) * 50, 0), 1)
                _ = self.sink.ingest(samples)

                // Analyze full chunks off the main thread (we are on the
                // capture queue here); only publishing hops to the main actor.
                var results: [ChunkResult] = []
                while let chunk = self.sink.drain(self.chunkSampleCount) {
                    results.append(Self.analyze(chunk, profile: profile))
                }

                Task { @MainActor in
                    self.level = level
                    for result in results {
                        self.apply(result)
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
        guard rms > speechRMSThreshold else {
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
            totalSeconds += Self.chunkSeconds
            if result.isUser {
                userSeconds += Self.chunkSeconds
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
