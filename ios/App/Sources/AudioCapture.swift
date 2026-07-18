import AVFoundation
import Foundation
import VoiceCore

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is denied. Enable it in Settings to use the app."
        case .formatUnavailable:
            return "No microphone input is available. On the Simulator, "
                + "enable Device \u{203A} I/O \u{203A} Audio Input (or run on a "
                + "real device), then reopen this screen."
        }
    }
}

/// Streams microphone audio as 16 kHz mono Double samples — the format
/// VoiceCore expects (and the same rate the Python app records at).
///
/// AVAudioEngine delivers hardware-rate buffers; an AVAudioConverter
/// resamples them. Capture recovers from route changes (AirPods connecting),
/// interruptions (phone calls, Siri), and media-services resets. Failures
/// that happen outside a `start` call — a recovery that can't re-acquire the
/// microphone — are reported through the client's failure handler so the UI
/// never silently shows a live tracker over a dead microphone.
final class AudioCapture {
    /// One engine for the whole app — only one screen records at a time.
    static let shared = AudioCapture()

    static let sampleRate = Double(VoiceMatcher.sampleRate)

    // Recreated after a media-services reset, which invalidates audio objects.
    private var engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "audio-capture.processing")
    private(set) var isRunning = false

    /// Current client. `owner` decides who may stop the capture — screen
    /// transitions overlap (the next view's task can run before the previous
    /// view's onDisappear), so stops from a stale owner are ignored. The
    /// callbacks are retained across engine restarts so recovery can
    /// re-establish delivery.
    private weak var owner: AnyObject?
    private var onSamples: (([Double]) -> Void)?
    private var onFailure: ((Error) -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        // Route changed (headset/Bluetooth): the input format is different,
        // so the tap and converter must be rebuilt.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartEngine()
        })
        // Phone call, Siri, alarm: the system pauses the engine; resume when
        // the interruption ends.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })
        // mediaserverd restarted: all audio objects are invalid and must be
        // recreated from scratch.
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartEngine(recreateEngine: true)
        })
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

    /// Start capturing for `owner`, replacing any current client.
    /// `onSamples` fires on a private queue with each converted batch;
    /// `onFailure` fires on the main queue if capture dies later and cannot
    /// be recovered automatically.
    func start(
        owner: AnyObject,
        onFailure: ((Error) -> Void)? = nil,
        onSamples: @escaping ([Double]) -> Void
    ) throws {
        tearDownEngine()
        self.owner = owner
        self.onSamples = onSamples
        self.onFailure = onFailure

        do {
            try startEngine()
        } catch {
            clearClient()
            deactivateSession()
            throw error
        }
    }

    /// Stop if `owner` started the capture. A nil stored owner (the starting
    /// object was deallocated) matches any caller — the microphone must
    /// never be left running with no one able to stop it.
    func stop(owner: AnyObject) {
        guard self.owner === owner || self.owner == nil else { return }
        tearDownEngine()
        clearClient()
        deactivateSession()
    }

    // MARK: - Engine lifecycle

    private func startEngine() throws {
        guard let deliver = onSamples else { return }

        let session = AVAudioSession.sharedInstance()
        // .measurement minimizes system input processing; .playAndRecord so
        // calibration playback works without reconfiguring the session.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)

        let input = engine.inputNode
        // Prepare so the input node configures itself against the active
        // session before we read its format.
        engine.prepare()
        // Use the hardware *input* format for the tap and converter, not the
        // node's output format. On the Simulator `outputFormat(forBus:0)`
        // reports 0 Hz even when a mic is routed, whereas `inputFormat` reports
        // the real format (e.g. 44.1 kHz mono). A 0 Hz / 0-channel format means
        // no mic input is available — fail gracefully rather than crashing in
        // installTap/start (IsFormatSampleRateAndChannelCountValid).
        let recordingFormat = input.inputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: recordingFormat, to: targetFormat)
        else {
            throw AudioCaptureError.formatUnavailable
        }

        // The tap captures the converter and callback directly so the
        // processing queue never reads mutable instance state. Remove any
        // previous tap first — installing twice on the same bus raises an
        // uncatchable NSException.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [processingQueue] buffer, _ in
            processingQueue.async {
                Self.convertAndDeliver(buffer, converter: converter, targetFormat: targetFormat, to: deliver)
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    private func tearDownEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func clearClient() {
        owner = nil
        onSamples = nil
        onFailure = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recovery

    /// Re-establish capture for the current client after a route change,
    /// interruption end, or media reset. The client is kept on failure so a
    /// later event can retry, and the failure is reported so the UI can
    /// tell the user instead of pretending to listen.
    private func restartEngine(recreateEngine: Bool = false) {
        guard owner != nil, onSamples != nil else { return }
        tearDownEngine()
        if recreateEngine {
            engine = AVAudioEngine()
        }
        do {
            try startEngine()
        } catch {
            onFailure?(error)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            // The system already paused the engine; tear down so isRunning
            // reflects reality and the .ended restart begins clean.
            if owner != nil {
                tearDownEngine()
            }
        case .ended:
            restartEngine()
        @unknown default:
            break
        }
    }

    // MARK: - Conversion

    private static func convertAndDeliver(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        to deliver: @escaping ([Double]) -> Void
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
        deliver(samples)
    }
}
