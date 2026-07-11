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

        do {
            try capture.start(owner: self) { [weak self] samples in
                guard let self else { return }
                let level = min(max(VoiceMatcher.rms(samples) * 50, 0), 1)
                let collectedCount = self.sink.ingest(samples)
                Task { @MainActor in
                    self.handleAudioUpdate(level: level, collectedCount: collectedCount)
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
        let data = WavCodec.encode(recordedAudio, sampleRate: Int(AudioCapture.sampleRate))
        player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        player?.play()
    }

    /// Train the GMM profile from the recording and hand it to the app model.
    func saveProfile(into model: AppModel) {
        guard phase == .recorded, !recordedAudio.isEmpty else { return }
        phase = .saving
        let audio = recordedAudio
        Task.detached(priority: .userInitiated) {
            let profile = VoiceMatcher.createProfile(audio)
            await MainActor.run {
                model.save(profile)
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
