import Foundation
import VoiceCore

/// Records raw pipeline audio together with live who-is-speaking labels, to
/// build a ground-truth set for offline matcher/gate evaluation.
///
/// This deliberately saves conversation audio — the one exception to the app's
/// "no audio stored" rule, opt-in from the Diagnostics screen and clearly
/// labeled there. Audio uses the exact capture path the tracker uses
/// (`AudioCapture`, 16 kHz mono, `.measurement` mode), so offline replays see
/// what the live pipeline sees. Everything stays in Documents/GroundTruth
/// until the user shares or deletes it.
@MainActor
final class GroundTruthRecorder: ObservableObject {
    enum SpeakerLabel: String, Codable, CaseIterable, Identifiable {
        case me, others, quiet, unsure
        var id: String { rawValue }

        var title: String {
            switch self {
            case .me: return "Me"
            case .others: return "Others"
            case .quiet: return "Quiet"
            case .unsure: return "Unsure"
            }
        }
    }

    struct LabelEvent: Codable {
        /// Seconds from recording start, on the audio clock (sample count),
        /// so labels align with the WAV regardless of UI timing.
        let time: Double
        let label: SpeakerLabel
    }

    struct SessionMetadata: Codable {
        let version: Int
        let sampleRate: Int
        let recordedAt: Date
        let durationSeconds: Double
        let events: [LabelEvent]
    }

    struct SessionFiles: Identifiable {
        let id: String
        let directory: URL
        var audioURL: URL { directory.appendingPathComponent("audio.wav") }
        var labelsURL: URL { directory.appendingPathComponent("labels.json") }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var currentLabel: SpeakerLabel = .quiet
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var sessions: [SessionFiles] = []
    @Published var errorMessage: String?

    private let capture = AudioCapture.shared
    private let store = PCMStore()
    private var events: [LabelEvent] = []
    private var recordingStarted: Date?
    private var timer: Timer?

    init() {
        reloadSessions()
    }

    // MARK: - Recording

    func startRecording() async {
        guard !isRecording else { return }
        guard await AudioCapture.requestPermission() else {
            errorMessage = AudioCaptureError.permissionDenied.errorDescription
            return
        }

        store.reset()
        events = [LabelEvent(time: 0, label: .quiet)]
        currentLabel = .quiet
        recordingStarted = Date()
        errorMessage = nil

        do {
            try capture.start(owner: self, onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Microphone stopped: \(error.localizedDescription)"
                }
            }) { [store] samples in
                store.append(samples)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.store.seconds
            }
        }
    }

    /// Tap whenever the speaker changes; the timestamp comes from the audio
    /// clock so it lines up with the saved WAV exactly.
    func setLabel(_ label: SpeakerLabel) {
        guard isRecording, label != currentLabel else { return }
        currentLabel = label
        events.append(LabelEvent(time: store.seconds, label: label))
    }

    func stopAndSave() {
        guard isRecording else { return }
        capture.stop(owner: self)
        timer?.invalidate()
        timer = nil
        isRecording = false

        let samples = store.snapshot()
        let duration = Double(samples.count) / Double(VoiceMatcher.sampleRate)
        guard duration > 1 else {
            errorMessage = "Recording too short to save."
            return
        }

        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let directory = Self.rootDirectory
                .appendingPathComponent(formatter.string(from: recordingStarted ?? Date()))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            try WavCodec.encode(pcm16: samples)
                .write(to: directory.appendingPathComponent("audio.wav"), options: .atomic)

            let metadata = SessionMetadata(
                version: 1,
                sampleRate: VoiceMatcher.sampleRate,
                recordedAt: recordingStarted ?? Date(),
                durationSeconds: duration,
                events: events
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(metadata)
                .write(to: directory.appendingPathComponent("labels.json"), options: .atomic)

            reloadSessions()
        } catch {
            errorMessage = "Could not save the session: \(error.localizedDescription)"
        }
        store.reset()
        elapsed = 0
    }

    // MARK: - Saved sessions

    func delete(_ session: SessionFiles) {
        try? FileManager.default.removeItem(at: session.directory)
        reloadSessions()
    }

    private static var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GroundTruth")
    }

    private func reloadSessions() {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: Self.rootDirectory, includingPropertiesForKeys: nil
        )) ?? []
        sessions = directories
            .filter { $0.hasDirectoryPath }
            .map { SessionFiles(id: $0.lastPathComponent, directory: $0) }
            .sorted { $0.id > $1.id }
    }
}

/// Thread-safe PCM accumulator: the capture queue appends, the main actor
/// reads. Stores Int16 so an hour of audio is ~115 MB and 10 minutes ~19 MB.
private final class PCMStore: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []

    func append(_ newSamples: [Double]) {
        let converted = newSamples.map(WavCodec.quantize)
        lock.lock()
        samples.append(contentsOf: converted)
        lock.unlock()
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Double(VoiceMatcher.sampleRate)
    }

    func snapshot() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        samples = []
        lock.unlock()
    }
}
