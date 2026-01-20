import Foundation
import AVFoundation
import SwiftUI

@available(macOS 14.0, *)
@MainActor
class AudioManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isRecording = false
    @Published var userSpeakingTime: TimeInterval = 0
    @Published var totalTime: TimeInterval = 0
    @Published var noiseLevel: Float = 0
    @Published var speakingPercentage: Double = 0
    @Published var currentAmplitude: CGFloat = 0
    
    // Simulation mode
    var isSimulationMode = true
    private var simulatedSpeakingPattern: [Bool] = []
    private var simulationIndex = 0
    
    // Private properties
    private var audioRecorder: AVAudioRecorder?
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var timerTask: Task<Void, Never>?
    
    // For speech detection
    private let silenceThreshold: Float = 0.03
    private var isSpeaking = false
    private var lastSpeakingTime = Date()
    private var recordingStartTime: Date?
    
    // Store a weak reference to self for use in deinit
    private(set) weak var weakSelf: AudioManager?
    
    override init() {
        super.init()
        weakSelf = self
        setupAudio()
        setupSimulation()
    }
    
    private func setupSimulation() {
        // Create a pattern of speaking/not speaking intervals
        // This simulates a conversation where the user speaks intermittently
        var pattern: [Bool] = []
        
        // Add some random speaking patterns - alternating between speaking and listening
        for _ in 0..<50 {
            // Speaking for 1-3 seconds (10-30 intervals of 0.1s)
            let speakingDuration = Int.random(in: 10...30)
            pattern.append(contentsOf: Array(repeating: true, count: speakingDuration))
            
            // Not speaking for 1-5 seconds
            let silentDuration = Int.random(in: 10...50)
            pattern.append(contentsOf: Array(repeating: false, count: silentDuration))
        }
        
        simulatedSpeakingPattern = pattern
    }
    
    func setupAudio() {
        if !isSimulationMode {
            // Initialize audio engine
            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode
        }
    }
    
    deinit {
        // Just cancel the task without trying to access actor-isolated properties
        timerTask?.cancel()
    }
    
    func configureAudio() {
        // In simulation mode, we don't need to configure real audio
        if isSimulationMode {
            return
        }
        
        // Get audio input node from engine
        inputNode = audioEngine.inputNode
        
        // Configure audio format - mono channel with 44.1kHz sample rate
        let recordingFormat = inputNode?.outputFormat(forBus: 0)
        
        // Install tap on audio input node
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Process audio buffer
            let samples = buffer.floatChannelData?[0]
            let frameLength = buffer.frameLength
            
            // Calculate RMS amplitude from audio samples
            var sum: Float = 0
            for i in 0..<Int(frameLength) {
                let sample = samples?[i] ?? 0
                sum += sample * sample
            }
            
            let rms = sqrt(sum / Float(frameLength))
            
            // Update speaking state based on amplitude
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                self.currentAmplitude = CGFloat(rms) * 5 // Scale for UI
                self.noiseLevel = rms
                
                if rms > self.silenceThreshold {
                    // User is speaking
                    if !self.isSpeaking {
                        self.isSpeaking = true
                    }
                    self.lastSpeakingTime = Date()
                } else {
                    // Check if user has been silent for more than 0.5 seconds
                    if self.isSpeaking && Date().timeIntervalSince(self.lastSpeakingTime) > 0.5 {
                        self.isSpeaking = false
                    }
                }
            }
        }
    }
    
    func startRecording() {
        // Reset timers and state
        userSpeakingTime = 0
        totalTime = 0
        speakingPercentage = 0
        recordingStartTime = Date()
        isSpeaking = false
        simulationIndex = 0
        
        if !isSimulationMode {
            // Configure real audio before starting
            configureAudio()
            
            do {
                // Start audio engine if not running
                if !audioEngine.isRunning {
                    try audioEngine.start()
                }
            } catch {
                print("Failed to start recording: \(error.localizedDescription)")
                isRecording = false
                return
            }
        }
        
        // Start timer for UI updates using a Task instead of Timer
        startTimerTask()
        
        isRecording = true
    }
    
    private func startTimerTask() {
        // Cancel existing task if any
        timerTask?.cancel()
        
        // Use a Task for UI updates
        timerTask = Task { [weak self] in
            guard let self = self else { return }
            
            while self.isRecording {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                if Task.isCancelled {
                    break
                }
                
                guard let startTime = self.recordingStartTime else { break }
                
                // Update total time
                self.totalTime = Date().timeIntervalSince(startTime)
                
                if self.isSimulationMode {
                    // Update simulated speaking state
                    if self.simulationIndex < self.simulatedSpeakingPattern.count {
                        self.isSpeaking = self.simulatedSpeakingPattern[self.simulationIndex]
                        self.simulationIndex += 1
                        
                        // Update amplitude for visual feedback
                        self.currentAmplitude = self.isSpeaking ? CGFloat.random(in: 2...5) : CGFloat.random(in: 0...0.5)
                        self.noiseLevel = self.isSpeaking ? Float.random(in: 0.05...0.2) : Float.random(in: 0...0.02)
                    } else {
                        // If we reach the end of the pattern, loop back or stop
                        self.simulationIndex = 0
                    }
                }
                
                // Update user speaking time if currently speaking
                if self.isSpeaking {
                    self.userSpeakingTime += 0.1
                }
                
                // Calculate speaking percentage
                if self.totalTime > 0 {
                    self.speakingPercentage = (self.userSpeakingTime / self.totalTime) * 100
                }
            }
        }
    }
    
    func stopRecording() {
        // Update isRecording to stop the timer task
        isRecording = false
        
        // Stop audio engine if not in simulation mode
        if !isSimulationMode && audioEngine.isRunning {
            audioEngine.stop()
            inputNode?.removeTap(onBus: 0)
        }
    }
    
    func reset() {
        userSpeakingTime = 0
        totalTime = 0
        speakingPercentage = 0
        currentAmplitude = 0
        noiseLevel = 0
        simulationIndex = 0
    }
} 