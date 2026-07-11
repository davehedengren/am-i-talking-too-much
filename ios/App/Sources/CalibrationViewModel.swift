import AVFoundation
import Foundation
import VoiceCore

@MainActor
final class CalibrationViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(progress: Double)
        case recorded
        case saving
    }

    static let calibrationSeconds = 10.0

    @Published var phase: Phase = .idle
    @Published var level: Double = 0
    @Published var errorMessage: String?

    private let capture: AudioCapture
    private let sink = SampleSink()
    private var recordedAudio: [Double] = []
    private var player: AVAudioPlayer?
    private let targetSampleCount = Int(calibrationSeconds * AudioCapture.sampleRate)

    init(capture: AudioCapture) {
        self.capture = capture
    }

    /// Start the microphone for the live level meter (and, once recording,
    /// sample collection). Called when the calibration screen appears.
    func startMonitoring() async {
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
                let level = VoiceMatcher.meterLevel(samples)
                let collectedCount = self.sink.ingest(samples)
                // Main queue rather than an unstructured Task: FIFO, so the
                // recording progress can never regress.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.handleAudioUpdate(level: level, collectedCount: collectedCount)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopMonitoring() {
        capture.stop(owner: self)
    }

    func startRecording() {
        guard capture.isRunning else { return }
        player?.stop()
        errorMessage = nil
        sink.setCollecting(true)
        phase = .recording(progress: 0)
    }

    func discardRecording() {
        recordedAudio = []
        player?.stop()
        player = nil
        phase = .idle
    }

    func playRecording() {
        guard !recordedAudio.isEmpty else { return }
        let data = WavCodec.encode(recordedAudio)
        player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        player?.play()
    }

    /// Train the GMM profile from the recording and hand it to the app
    /// model. Persistence failures come back to this screen instead of
    /// pretending the profile was saved.
    func saveProfile(into model: AppModel) {
        guard phase == .recorded, !recordedAudio.isEmpty else { return }
        phase = .saving
        let audio = recordedAudio
        Task.detached(priority: .userInitiated) {
            let profile = VoiceMatcher.createProfile(audio)
            await MainActor.run {
                do {
                    try model.save(profile)
                } catch {
                    self.errorMessage = "Could not save the profile: \(error.localizedDescription)"
                    self.phase = .recorded
                }
            }
        }
    }

    private func handleAudioUpdate(level: Double, collectedCount: Int) {
        self.level = level
        guard case .recording = phase else { return }

        if collectedCount >= targetSampleCount {
            sink.setCollecting(false)
            recordedAudio = Array(sink.takeAll().prefix(targetSampleCount))
            phase = .recorded
        } else {
            phase = .recording(progress: Double(collectedCount) / Double(targetSampleCount))
        }
    }
}
