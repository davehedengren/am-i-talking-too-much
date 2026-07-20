import Foundation
import UIKit
import VoiceCore

@MainActor
final class TrackerViewModel: ObservableObject {
    /// Live mic level, isolated in its own observable so its ~10 Hz updates
    /// re-render only the small meter view, never the chart-bearing screen.
    final class LiveLevel: ObservableObject {
        @Published var value: Double = 0
    }

    @Published var isTracking = false
    @Published var userSeconds = 0.0
    @Published var totalSeconds = 0.0
    @Published var percentageHistory: [Double] = []
    @Published var debugLog: [String] = []
    @Published var errorMessage: String?

    /// The last chunk's classification, for the live "is it working" chip.
    @Published var lastOutcome: ChunkOutcome?

    let liveLevel = LiveLevel()

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
            // The gate adapts to the room: every chunk (speech or not) feeds
            // the noise-floor estimate. Single consumer, so no races.
            var noiseFloor = NoiseFloor()
            for await chunk in stream {
                guard let self else { break }
                guard let matcher = self.matcher else { continue }
                // Anchor the floor on the chunk's quietest 100 ms frame, not
                // its overall RMS — inter-word gaps keep the estimate at the
                // ambient level even during a sustained monologue.
                noiseFloor.update(quietestFrameRMS: VoicedTrim.quietestFrameRMS(chunk))
                let result = await Self.analyze(chunk, matcher: matcher, gateRMS: noiseFloor.speechGate)
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
                // chunks go to the async consumer. The live level publishes on
                // every buffer — but only into `liveLevel`, whose updates
                // re-render just the meter subview.
                guard let self else { return }
                let tracking = self.sink.isCollecting
                self.sink.ingest(samples)

                if tracking {
                    while let chunk = self.sink.drain(self.chunkSampleCount) {
                        continuation.yield(chunk)
                    }
                }

                let level = VoiceMatcher.meterLevel(samples)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.liveLevel.value = level }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            continuation.finish()
        }
    }

    /// Idempotent entry point for the tracking screen: starts capture if it
    /// isn't running, swaps the matcher without ending the session when the
    /// user flips the neural toggle, and does nothing when returning from a
    /// pushed screen mid-session — navigation must not kill tracking.
    func ensureMonitoring(matcher: any SpeakerMatcher, isNeural: Bool) async {
        if capture.isRunning, self.matcher != nil, activeMatcherIsNeural == isNeural {
            return
        }
        let wasTracking = isTracking
        stopMonitoring()
        activeMatcherIsNeural = isNeural
        await startMonitoring(matcher: matcher)
        if wasTracking {
            // Matcher swap mid-session: keep counting, don't reset totals.
            sink.setCollecting(true)
            isTracking = true
        }
    }

    private var activeMatcherIsNeural: Bool?

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
        lastOutcome = nil
        lastNudge = nil
    }

    // MARK: - Haptic nudge

    /// Discreet "you're dominating" wrist-tap replacement: a warning haptic
    /// when your share stays over the red band, at most once per interval.
    /// Requires some accumulated speech so a hot first minute doesn't buzz.
    static let nudgePercentage = 55.0
    static let nudgeMinimumSpeechSeconds = 60.0
    static let nudgeInterval: TimeInterval = 120
    private var lastNudge: Date?

    private func nudgeIfDominating() {
        guard percentage > Self.nudgePercentage,
              totalSeconds >= Self.nudgeMinimumSpeechSeconds,
              Date().timeIntervalSince(lastNudge ?? .distantPast) > Self.nudgeInterval
        else { return }
        lastNudge = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    struct ChunkResult {
        let rms: Double
        let peak: Double
        let gate: Double
        let voicedFraction: Double
        let isSpeech: Bool
        let isUser: Bool
        let confidence: Double
        let matchInfo: String
    }

    nonisolated private static func analyze(_ chunk: [Double], matcher: any SpeakerMatcher, gateRMS: Double) async -> ChunkResult {
        let rms = VoiceMatcher.rms(chunk)
        let peak = chunk.reduce(0.0) { max($0, abs($1)) }
        // Voiced fraction is a logged diagnostic only. Scoring spliced
        // voiced-only audio regressed accuracy in the field (seam artifacts +
        // profiles trained on untrimmed audio) — whole-chunk scoring is the
        // measured-best baseline until the eval harness says otherwise.
        let voicedFraction = VoicedTrim.trim(chunk, gate: gateRMS).fraction
        guard rms > gateRMS else {
            return ChunkResult(rms: rms, peak: peak, gate: gateRMS, voicedFraction: voicedFraction,
                               isSpeech: false, isUser: false, confidence: 0, matchInfo: "")
        }
        let match = await matcher.match(chunk)
        return ChunkResult(
            rms: rms, peak: peak, gate: gateRMS, voicedFraction: voicedFraction, isSpeech: true,
            isUser: match.isMatch, confidence: match.confidence,
            matchInfo: match.debugInfo
        )
    }

    private func apply(_ result: ChunkResult) {
        guard isTracking else { return }

        // Record one timeline entry per chunk (including silence) so saved-event
        // buckets keep accurate time positions.
        let outcome: ChunkOutcome = result.isSpeech ? (result.isUser ? .you : .others) : .silence
        chunkOutcomes.append(outcome)
        lastOutcome = outcome

        var entry = String(format: "RMS: %.4f | Gate: %.4f | Voiced: %d%% | Max: %.4f",
                           result.rms, result.gate, Int((result.voicedFraction * 100).rounded()), result.peak)
        if result.isSpeech {
            totalSeconds += VoiceMatcher.chunkSeconds
            if result.isUser {
                userSeconds += VoiceMatcher.chunkSeconds
            }
            percentageHistory.append(percentage)
            nudgeIfDominating()
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
