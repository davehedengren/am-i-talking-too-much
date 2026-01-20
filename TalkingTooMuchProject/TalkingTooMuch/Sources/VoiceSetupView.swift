import SwiftUI
import AVFoundation

struct VoiceSetupView: View {
    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var setupStep = SetupStep.welcome
    @State private var setupComplete = false
    
    // For progress animation
    @State private var timer: Timer?
    private let recordingDuration: TimeInterval = 10.0
    
    // Audio components
    private let audioManager = AudioManager()
    private let voiceAnalyzer = VoiceAnalyzer()
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            Text("Voice Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Progress indicator
            ProgressView(value: recordingProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 10)
            
            // Instructions based on current step
            instructionView
                .padding()
                .frame(height: 200)
            
            // Recording button
            Button(action: {
                handleRecordingButton()
            }) {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(buttonColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .disabled(setupStep == .processing)
            
            if setupComplete {
                Button(action: {
                    // Navigate to the main app
                }) {
                    Text("Continue to App")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding()
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var instructionView: some View {
        switch setupStep {
        case .welcome:
            VStack {
                Text("Welcome to 'Am I Talking Too Much?'")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("To get started, we need to calibrate the app to recognize your voice.")
                    .multilineTextAlignment(.center)
            }
            
        case .calibration:
            VStack {
                Text("Please speak continuously for 10 seconds")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Read the following text aloud clearly:")
                    .padding(.bottom, 5)
                
                Text("\"The quick brown fox jumps over the lazy dog. Voice recognition systems need diverse speech samples to accurately identify unique vocal characteristics.\"")
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
        case .processing:
            VStack {
                Text("Processing your voice")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Please wait while we analyze your voice pattern...")
                    .multilineTextAlignment(.center)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            }
            
        case .complete:
            VStack {
                Text("Setup Complete!")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Your voice has been calibrated. The app will now be able to distinguish your voice from others in the room.")
                    .multilineTextAlignment(.center)
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 50))
                    .padding()
            }
        }
    }
    
    // MARK: - Button Properties
    
    private var buttonTitle: String {
        switch setupStep {
        case .welcome:
            return "Begin Setup"
        case .calibration:
            return isRecording ? "Stop Recording" : "Start Recording"
        case .processing:
            return "Processing..."
        case .complete:
            return "Setup Complete"
        }
    }
    
    private var buttonColor: Color {
        switch setupStep {
        case .welcome:
            return .blue
        case .calibration:
            return isRecording ? .red : .blue
        case .processing:
            return .gray
        case .complete:
            return .green
        }
    }
    
    // MARK: - Actions
    
    private func handleRecordingButton() {
        switch setupStep {
        case .welcome:
            setupStep = .calibration
            
        case .calibration:
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
            
        case .processing:
            // Button disabled during processing
            break
            
        case .complete:
            setupComplete = true
        }
    }
    
    private func startRecording() {
        // Request microphone permissions if needed
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.recordingProgress = 0
                    
                    // Start audio recording for calibration
                    // In a real implementation, we would use the AudioManager to record
                    
                    // Start progress timer
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        if self.recordingProgress < 1.0 {
                            self.recordingProgress += 0.1 / self.recordingDuration
                        } else {
                            self.stopRecording()
                        }
                    }
                }
            }
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        // Stop the recording
        // In a real implementation, we would use AudioManager to stop recording
        
        // Move to processing step
        setupStep = .processing
        
        // Simulate processing time
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Processing complete
            self.setupStep = .complete
        }
    }
}

// MARK: - Supporting Types

enum SetupStep {
    case welcome
    case calibration
    case processing
    case complete
}

struct VoiceSetupView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceSetupView()
    }
} 