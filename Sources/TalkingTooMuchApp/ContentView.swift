import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @EnvironmentObject var dataStore: DataStore
    @State private var isRecording = false
    @State private var showShareSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Simulation mode indicator
            if audioManager.isSimulationMode {
                Text("Simulation Mode")
                    .font(.caption)
                    .padding(6)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // Speaking percentage indicator
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 250, height: 250)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(min(audioManager.speakingPercentage / 100, 1.0)))
                    .stroke(
                        audioManager.speakingPercentage > dataStore.targetPercentage ? Color.red : Color.green,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: audioManager.speakingPercentage)
                
                // Percentage text
                VStack {
                    Text("\(Int(audioManager.speakingPercentage))%")
                        .font(.system(size: 50, weight: .bold))
                    
                    Text("You're speaking")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 20)
            
            // Time information
            VStack(spacing: 8) {
                HStack(spacing: 30) {
                    VStack {
                        Text(formatTime(audioManager.userSpeakingTime))
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Your time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack {
                        Text(formatTime(audioManager.totalTime))
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Total time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.bottom, 30)
            
            // Control buttons
            HStack(spacing: 40) {
                Button(action: {
                    toggleRecording()
                }) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    resetRecording()
                }) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .disabled(!isRecording && audioManager.totalTime == 0)
            }
        }
        .padding(30)
        .background(Color.gray.opacity(0.1))
        .toolbar {
            ToolbarItem {
                Button(action: {
                    shareSession()
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(audioManager.totalTime == 0)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            audioManager.startRecording()
        } else {
            audioManager.stopRecording()
            
            // Save session data
            let session = Session(
                id: UUID(),
                date: Date(),
                userDuration: audioManager.userSpeakingTime,
                totalDuration: audioManager.totalTime
            )
            dataStore.addSession(session)
        }
    }
    
    private func resetRecording() {
        if isRecording {
            toggleRecording()
        }
        
        audioManager.reset()
    }
    
    private func shareSession() {
        // In a real app, we would implement sharing functionality here
        showShareSheet = true
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@available(macOS 14.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataStore.preview)
    }
} 