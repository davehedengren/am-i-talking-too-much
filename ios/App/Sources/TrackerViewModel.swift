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

    // Per-chunk timeline for the saved-event chart, plus the run's start time.
    private var trackingStart: Date?
    private var chunkOutcomes: [ChunkOutcome] = []

    // Async analysis pipeline: the capture callback yields drained chunks into
    // this stream; a single consumer scores them in order with the selected
    // matcher (which may be async neural inference).
    private var matcher: (any SpeakerMatcher)?
    private var chunkContinuation: AsyncStream<[Double]>.Continuation?
    private var consumerTask: Task<Void, Never>?

    init(capture: AudioCapture) {
        self.capture = capture
    }

    /// Start the microphone; runs the level meter while idle and analyzes
    /// chunks with `matcher` whenever tracking is on.
    func startMonitoring(matcher: any SpeakerMatcher) async {
        guard await AudioCapture.requestPermission() else {
            errorMessage = AudioCaptureError.permissionDenied.errorDescription
            return
        }
        // The view may have been swapped away while awaiting the permission
        // callback; starting now would steal the capture from its successor.
        guard !Task.isCancelled else { return }

        self.matcher = matcher

        // Single-consumer pipeline: chunks are scored one at a time in arrival
        // order, so results apply in order even though matching is async. The
        // 2 s chunk cadence is far longer than inference, so nothing backs up.
        let (stream, continuation) = AsyncStream<[Double]>.makeStream()
        chunkContinuation = continuation
        consumerTask?.cancel()
        consumerTask = Task { [weak self] in
            for await chunk in stream {
                guard let self else { break }
                guard let matcher = self.matcher else { continue }
                let result = await Self.analyze(chunk, matcher: matcher)
                self.apply(result)
            }
        }

        do {
            try capture.start(owner: self, onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Microphone stopped: \(error.localizedDescription)"
                }
            }) { [weak self, continuation] samples in
                // We are on the capture queue. `sink` is thread-safe; drained
                // chunks go to the async consumer, and the idle level meter
                // hops to main to publish.
                guard let self else { return }
                let tracking = self.sink.isCollecting
                self.sink.ingest(samples)

                if tracking {
                    while let chunk = self.sink.drain(self.chunkSampleCount) {
                        continuation.yield(chunk)
                    }
                } else {
                    let level = VoiceMatcher.meterLevel(samples)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.level = level }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            continuation.finish()
        }
    }

    func stopMonitoring() {
        capture.stop(owner: self)
        sink.setCollecting(false)
        isTracking = false
        chunkContinuation?.finish()
        chunkContinuation = nil
        consumerTask?.cancel()
        consumerTask = nil
    }

    func startTracking() {
        reset()
        trackingStart = Date()
        errorMessage = nil
        sink.setCollecting(true)
        isTracking = true
    }

    /// Snapshot the just-finished run as a draft event, or nil if nothing worth
    /// saving was captured. Call after `stopTracking()`, before `reset()`.
    func makeDraft() -> SessionDraft? {
        guard let start = trackingStart, totalSeconds > 0 else { return nil }
        let buckets = Session.buildBuckets(
            chunkOutcomes: chunkOutcomes,
            chunkSeconds: VoiceMatcher.chunkSeconds
        )
        return SessionDraft(
            start: start,
            end: Date(),
            userSeconds: userSeconds,
            totalSpeechSeconds: totalSeconds,
            buckets: buckets
        )
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
        chunkOutcomes = []
        trackingStart = nil
    }

    struct ChunkResult {
        let rms: Double
        let peak: Double
        let isSpeech: Bool
        let isUser: Bool
        let confidence: Double
        let matchInfo: String
    }

    nonisolated private static func analyze(_ chunk: [Double], matcher: any SpeakerMatcher) async -> ChunkResult {
        let rms = VoiceMatcher.rms(chunk)
        let peak = chunk.reduce(0.0) { max($0, abs($1)) }
        guard rms > VoiceMatcher.speechGateRMS else {
            return ChunkResult(rms: rms, peak: peak, isSpeech: false, isUser: false, confidence: 0, matchInfo: "")
        }
        let match = await matcher.match(chunk)
        return ChunkResult(
            rms: rms, peak: peak, isSpeech: true,
            isUser: match.isMatch, confidence: match.confidence,
            matchInfo: match.debugInfo
        )
    }

    private func apply(_ result: ChunkResult) {
        guard isTracking else { return }

        // Record one timeline entry per chunk (including silence) so saved-event
        // buckets keep accurate time positions.
        chunkOutcomes.append(result.isSpeech ? (result.isUser ? .you : .others) : .silence)

        var entry = String(format: "RMS: %.4f | Max: %.4f", result.rms, result.peak)
        if result.isSpeech {
            totalSeconds += VoiceMatcher.chunkSeconds
            if result.isUser {
                userSeconds += VoiceMatcher.chunkSeconds
            }
            percentageHistory.append(percentage)
            entry += String(format: " | SPEECH | %@ | conf %.2f | IsYou: %@",
                            result.matchInfo, result.confidence, result.isUser ? "true" : "false")
        } else {
            entry += " | (silence)"
        }

        debugLog.append(entry)
        if debugLog.count > 20 {
            debugLog.removeFirst(debugLog.count - 20)
        }
    }
}
