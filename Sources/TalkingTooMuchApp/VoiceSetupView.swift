import SwiftUI

struct VoiceSetupView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var isPresented: Bool
    @State private var isRecording = false
    @State private var recordingPhase = 0
    @State private var progressValue: Float = 0.0
    @State private var isProcessing = false
    @State private var recordingTask: Task<Void, Never>? = nil
    
    // Sample phrases for calibration
    private let phrases = [
        "Hello, my name is...",
        "Today I'd like to talk about...",
        "The weather is lovely today"
    ]
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Voice Setup")
                .font(.largeTitle)
                .bold()
            
            Text("Let's calibrate to recognize your voice")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom)
            
            if recordingPhase < phrases.count {
                setupView
            } else {
                completionView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Cancel") {
                    cancelRecording()
                    isPresented = false
                }
            }
        }
        .onDisappear {
            cancelRecording()
        }
    }
    
    private var setupView: some View {
        VStack(spacing: 25) {
            Text("Please read aloud:")
                .font(.headline)
            
            Text(phrases[recordingPhase])
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 1)
            
            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 250)
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
            }
            
            Text(isRecording ? "Recording... Tap to stop" : "Tap to start recording")
                .font(.subheadline)
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 25) {
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                
                Text("Processing your voice...")
                    .font(.headline)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Setup Complete!")
                    .font(.title)
                    .bold()
                
                Text("Your voice profile has been created.")
                    .multilineTextAlignment(.center)
                
                Button("Continue") {
                    // Save that setup is complete
                    dataStore.hasCompletedVoiceSetup = true
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        progressValue = 0.0
        
        // Simulate recording progress
        recordingTask = Task {
            for i in 1...50 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    progressValue = Float(i) * 0.02
                }
                
                // If we've stopped recording, exit the task
                if !isRecording {
                    break
                }
            }
            
            // Auto-stop if we reach the end
            if isRecording && progressValue >= 1.0 {
                await MainActor.run {
                    stopRecording()
                }
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        cancelRecording()
        
        // If we've completed all phrases, show processing state
        if recordingPhase == phrases.count - 1 {
            isProcessing = true
            
            // Simulate processing time
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
        
        // Move to next phrase
        recordingPhase += 1
    }
    
    private func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
    }
}

@available(macOS 14.0, *)
struct VoiceSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            VoiceSetupView(isPresented: .constant(true))
                .environmentObject(DataStore.preview)
        }
    }
} 