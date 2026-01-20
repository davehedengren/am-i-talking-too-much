import Foundation
import AVFoundation
import Speech
import Combine

class AudioManager: NSObject, ObservableObject {
    // Published properties
    @Published var isRecording = false
    @Published var userSpeakingTime: TimeInterval = 0
    @Published var totalActiveTime: TimeInterval = 0
    
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer = AVAudioPCMBuffer()
    
    // Audio analysis
    private var voicePrintData: Data?
    private var recordingStartTime: Date?
    private var isUserSpeaking = false
    private var lastUserSpeakStartTime: Date?
    private var totalUserSpeakingTime: TimeInterval = 0
    
    // Audio settings
    private let audioSession = AVAudioSession.sharedInstance()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Voice identification
    private var userVoiceCharacteristics: VoiceCharacteristics?
    private var otherSpeakers: [VoiceCharacteristics] = []
    
    // Analysis parameters
    private let silenceThreshold: Float = 0.05
    private let minimumSpeakingSegment: TimeInterval = 0.5
    private var timer: Timer?
    private var audioBuffers: [AudioBuffer] = []
    
    override init() {
        super.init()
        configureAudioSession()
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Reset counters
        totalUserSpeakingTime = 0
        userSpeakingTime = 0
        totalActiveTime = 0
        audioBuffers = []
        recordingStartTime = Date()
        
        setupAudioEngine()
        isRecording = true
        
        // Start timer for updating speaking times
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateSpeakingTimes()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        timer?.invalidate()
        timer = nil
        
        audioEngine?.stop()
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        
        // Calculate final speaking times
        if let startTime = recordingStartTime {
            totalActiveTime = Date().timeIntervalSince(startTime)
        }
        
        userSpeakingTime = totalUserSpeakingTime
        
        // Once we've analyzed the full recording, we could improve user voice print here
        analyzeRecording()
    }
    
    func getUserSpeakingPercentage() -> Double {
        guard totalActiveTime > 0 else { return 0 }
        return (userSpeakingTime / totalActiveTime) * 100.0
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine,
              let inputNode = audioEngine.inputNode else {
            return
        }
        
        self.inputNode = inputNode
        
        // Set up the audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create speech recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start the speech recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                // Process speech results
                self?.processSpeechResult(result)
            }
            
            if error != nil {
                // Handle errors
                self?.audioEngine?.stop()
                self?.inputNode?.removeTap(onBus: 0)
            }
        }
        
        // Install a tap on the audio engine
        let bufferSize: UInt32 = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, time in
            self?.recognitionRequest?.append(buffer)
            self?.processAudioBuffer(buffer, time: time)
        }
        
        // Start the audio engine
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error.localizedDescription)")
        }
    }
    
    private func updateSpeakingTimes() {
        if let startTime = recordingStartTime {
            totalActiveTime = Date().timeIntervalSince(startTime)
            userSpeakingTime = totalUserSpeakingTime
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Extract audio features for voice analysis
        guard let channelData = buffer.floatChannelData else { return }
        
        let frames = buffer.frameLength
        var rms: Float = 0.0
        
        // Calculate RMS (Root Mean Square) power
        for frame in 0..<Int(frames) {
            let sample = channelData[0][frame]
            rms += sample * sample
        }
        
        rms = sqrt(rms / Float(frames))
        
        // Detect if someone is speaking based on audio level
        let isSpeaking = rms > silenceThreshold
        
        // Store buffer for later analysis
        let audioBuffer = AudioBuffer(
            buffer: buffer,
            timestamp: Date(),
            isSpeaking: isSpeaking,
            rms: rms
        )
        
        audioBuffers.append(audioBuffer)
        
        // Perform simple voice detection
        if isUserCurrentlySpeaking(rms: rms) {
            if !isUserSpeaking {
                isUserSpeaking = true
                lastUserSpeakStartTime = Date()
            }
        } else {
            if isUserSpeaking, let speakStartTime = lastUserSpeakStartTime {
                isUserSpeaking = false
                // Only count segments longer than minimum threshold
                let speakingTime = Date().timeIntervalSince(speakStartTime)
                if speakingTime >= minimumSpeakingSegment {
                    totalUserSpeakingTime += speakingTime
                }
            }
        }
    }
    
    private func isUserCurrentlySpeaking(rms: Float) -> Bool {
        // This is a placeholder for more sophisticated voice recognition
        // In a real implementation, we would:
        // 1. Train on the user's voice at setup
        // 2. Use ML to distinguish between the user and other speakers
        // 3. Consider acoustic fingerprinting
        
        // For now, we'll use a simple heuristic based on audio level
        // This assumes the user is typically closer to the mic than others
        return rms > silenceThreshold * 2.0
    }
    
    private func processSpeechResult(_ result: SFSpeechRecognitionResult) {
        // This could be used to analyze speech content
        // For the current app, we're more concerned with who is speaking
        // rather than what they're saying
    }
    
    private func analyzeRecording() {
        // This would implement more sophisticated analysis of the full recording
        // including speaker diarization to improve accuracy
        
        // For a more advanced implementation, we might:
        // 1. Use ML models for speaker identification
        // 2. Apply diarization to separate speakers
        // 3. Refine our user speaking time calculation
    }
}

// MARK: - Supporting Types

struct VoiceCharacteristics {
    let fundamentalFrequency: Float  // Average pitch
    let formants: [Float]           // Vocal tract resonances
    let spectralEnvelope: [Float]   // Overall spectral shape
    let speechRate: Float           // Rate of speech
    // Other parameters that could distinguish voices
}

struct AudioBuffer {
    let buffer: AVAudioPCMBuffer
    let timestamp: Date
    let isSpeaking: Bool
    let rms: Float
} 