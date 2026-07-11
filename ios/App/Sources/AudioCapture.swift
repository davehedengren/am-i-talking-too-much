import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is denied. Enable it in Settings to use the app."
        case .formatUnavailable:
            return "The microphone format could not be configured."
        }
    }
}

/// Streams microphone audio as 16 kHz mono Double samples — the format
/// VoiceCore expects (and the same rate the Python app records at).
///
/// AVAudioEngine delivers hardware-rate buffers; an AVAudioConverter
/// resamples them. `onSamples` fires on a private queue.
final class AudioCapture {
    /// One engine for the whole app — only one screen records at a time.
    static let shared = AudioCapture()

    static let sampleRate = 16000.0

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "audio-capture.processing")
    private(set) var isRunning = false

    /// The object that started the current capture. Screen transitions can
    /// overlap (the next view's task may run before the previous view's
    /// onDisappear), so stop requests from a stale owner are ignored.
    private weak var owner: AnyObject?

    /// Kept so capture can be re-established when the audio route changes
    /// (e.g. AirPods connect mid-conversation).
    private var onSamples: (([Double]) -> Void)?
    private var configurationChangeObserver: NSObjectProtocol?

    private init() {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func start(owner: AnyObject, onSamples: @escaping ([Double]) -> Void) throws {
        if isRunning {
            stopEngine()
        }
        self.owner = owner
        self.onSamples = onSamples

        let session = AVAudioSession.sharedInstance()
        // .measurement minimizes system input processing; .playAndRecord so
        // calibration playback works without reconfiguring the session.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw AudioCaptureError.formatUnavailable
        }

        // The tap captures the converter and callback directly so the
        // processing queue never reads mutable instance state. Remove any
        // tap left behind by a previously failed start — installing twice
        // on the same bus raises an uncatchable NSException.
        let deliver = onSamples
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [processingQueue] buffer, _ in
            processingQueue.async {
                Self.convertAndDeliver(buffer, converter: converter, targetFormat: targetFormat, to: deliver)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.onSamples = nil
            self.owner = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        isRunning = true
    }

    func stop(owner: AnyObject) {
        guard self.owner === owner else { return }
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopEngine() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onSamples = nil
        owner = nil
        isRunning = false
    }

    /// The input format changes when the audio route changes; reinstall the
    /// tap and converter for the new format and keep going.
    private func handleConfigurationChange() {
        guard isRunning, let owner, let onSamples else { return }
        try? start(owner: owner, onSamples: onSamples)
    }

    private static func convertAndDeliver(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        to deliver: (([Double]) -> Void)?
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if suppliedInput {
                status.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              converted.frameLength > 0,
              let channel = converted.floatChannelData?[0]
        else {
            return
        }

        let count = Int(converted.frameLength)
        var samples = [Double](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Double(channel[i])
        }
        deliver?(samples)
    }
}
