import Foundation
import AVFoundation
import Speech
import Combine

@available(macOS 14.0, *)
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
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Timer for updating UI
    private var timer: Timer?
    
    // Audio analysis parameters
    private let silenceThreshold: Float = 0.05
    private let minimumSpeakingSegment: TimeInterval = 0.5
    private var audioBuffers: [AudioBuffer] = []
    
    override init() {
        super.init()
        configureAudio()
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
        isRecording = true
        
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
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        isRecording = false
    }
    
    func getUserSpeakingPercentage() -> Double {
        guard totalActiveTime > 0 else { return 0 }
        return (userSpeakingTime / totalActiveTime) * 100
    }
    
    // MARK: - Private Methods
    
    private func configureAudio() {
        // Initialize the audio engine
        audioEngine = AVAudioEngine()
    }
    
    private func setupAudioEngine() {
        guard let audioEngine = audioEngine else { return }
        
        // Set up audio engine and input node
        inputNode = audioEngine.inputNode
        
        let recordingFormat = inputNode?.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Process audio buffer
            self.processAudioBuffer(buffer)
            
            // For speech recognition
            self.recognitionRequest?.append(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Could not start audio engine: \(error.localizedDescription)")
        }
        
        // Set up speech recognition
        setupSpeechRecognition()
    }
    
    private func setupSpeechRecognition() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create speech recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let result = result {
                // Process speech recognition result
                print("Speech recognized: \(result.bestTranscription.formattedString)")
            }
            
            if error != nil {
                // Handle error
                print("Recognition error: \(String(describing: error))")
            }
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Analyze audio buffer to determine if user is speaking
        let isSpeaking = detectSpeech(in: buffer)
        
        // Update speaking state
        updateSpeakingState(isSpeaking: isSpeaking)
        
        // Store buffer for later analysis
        let timestamp = Date()
        let audioBuffer = AudioBuffer(buffer: buffer, timestamp: timestamp, isSpeaking: isSpeaking)
        audioBuffers.append(audioBuffer)
    }
    
    private func detectSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        // Simple speech detection based on amplitude
        let channelData = buffer.floatChannelData?[0]
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData?[i] ?? 0)
        }
        
        let average = sum / Float(frameLength)
        return average > silenceThreshold
    }
    
    private func updateSpeakingState(isSpeaking: Bool) {
        let now = Date()
        
        if isSpeaking && !isUserSpeaking {
            // User started speaking
            isUserSpeaking = true
            lastUserSpeakStartTime = now
        } else if !isSpeaking && isUserSpeaking {
            // User stopped speaking
            isUserSpeaking = false
            
            // Only count it if they spoke for at least the minimum segment duration
            if let startTime = lastUserSpeakStartTime,
               now.timeIntervalSince(startTime) >= minimumSpeakingSegment {
                totalUserSpeakingTime += now.timeIntervalSince(startTime)
            }
        }
    }
    
    private func updateSpeakingTimes() {
        guard let startTime = recordingStartTime else { return }
        
        let now = Date()
        totalActiveTime = now.timeIntervalSince(startTime)
        
        // If user is currently speaking, add the current segment
        if isUserSpeaking, let speakStartTime = lastUserSpeakStartTime {
            userSpeakingTime = totalUserSpeakingTime + now.timeIntervalSince(speakStartTime)
        } else {
            userSpeakingTime = totalUserSpeakingTime
        }
    }
}

// MARK: - Supporting Types

struct AudioBuffer {
    let buffer: AVAudioPCMBuffer
    let timestamp: Date
    let isSpeaking: Bool
} 
