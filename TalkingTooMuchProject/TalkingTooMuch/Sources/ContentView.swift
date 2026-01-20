import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @EnvironmentObject private var dataStore: DataStore
    @State private var isRecording = false
    @State private var userSpeakingPercentage: Double = 0
    @State private var totalRecordingTime: TimeInterval = 0
    @State private var userSpeakingTime: TimeInterval = 0
    @State private var showingResults = false
    @AppStorage("useAdvancedAnalysis") private var useAdvancedAnalysis = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Am I Talking Too Much?")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Speaking percentage display
            ZStack {
                Circle()
                    .stroke(lineWidth: 20)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(userSpeakingPercentage / 100, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                    .foregroundColor(speakingPercentageColor)
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.linear, value: userSpeakingPercentage)
                
                VStack {
                    Text("\(Int(userSpeakingPercentage))%")
                        .font(.system(size: 50))
                        .fontWeight(.bold)
                    
                    Text("Your speaking time")
                        .font(.headline)
                }
            }
            .frame(width: 250, height: 250)
            .padding()
            
            // Time information
            VStack(spacing: 10) {
                HStack {
                    Text("Total Time:")
                    Spacer()
                    Text(formatTime(totalRecordingTime))
                }
                
                HStack {
                    Text("Your Speaking Time:")
                    Spacer()
                    Text(formatTime(userSpeakingTime))
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Controls
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            if isRecording {
                Text("Recording in progress...")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingResults) {
            ResultsView(
                userSpeakingPercentage: userSpeakingPercentage,
                totalRecordingTime: totalRecordingTime,
                userSpeakingTime: userSpeakingTime,
                onDismiss: resetValues
            )
        }
    }
    
    private func startRecording() {
        resetValues()
        // Apply settings from user preferences
        if let silenceThreshold = UserDefaults.standard.object(forKey: "silenceThreshold") as? Float {
            audioManager.configureSilenceThreshold(silenceThreshold)
        }
        
        if let minSpeakingSegment = UserDefaults.standard.object(forKey: "minimumSpeakingSegment") as? TimeInterval {
            audioManager.configureMinimumSpeakingSegment(minSpeakingSegment)
        }
        
        audioManager.startRecording()
        isRecording = true
    }
    
    private func stopRecording() {
        audioManager.stopRecording()
        isRecording = false
        
        // Get results from audioManager
        userSpeakingTime = audioManager.userSpeakingTime
        totalRecordingTime = audioManager.totalActiveTime
        userSpeakingPercentage = audioManager.getUserSpeakingPercentage()
        
        // Save session to data store
        dataStore.saveSession(
            userPercentage: userSpeakingPercentage,
            userSpeakingTime: userSpeakingTime,
            totalTime: totalRecordingTime
        )
        
        // Show results
        showingResults = true
    }
    
    private func resetValues() {
        userSpeakingTime = 0
        totalRecordingTime = 0
        userSpeakingPercentage = 0
    }
    
    private var speakingPercentageColor: Color {
        if userSpeakingPercentage <= 33 {
            return .green
        } else if userSpeakingPercentage <= 66 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Results view shown after a recording session
struct ResultsView: View {
    let userSpeakingPercentage: Double
    let totalRecordingTime: TimeInterval
    let userSpeakingTime: TimeInterval
    let onDismiss: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Recording Results")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                ZStack {
                    Circle()
                        .stroke(lineWidth: 25)
                        .opacity(0.3)
                        .foregroundColor(.gray)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(userSpeakingPercentage / 100, 1.0)))
                        .stroke(style: StrokeStyle(lineWidth: 25, lineCap: .round, lineJoin: .round))
                        .foregroundColor(speakingPercentageColor)
                        .rotationEffect(Angle(degrees: 270.0))
                    
                    VStack {
                        Text("\(Int(userSpeakingPercentage))%")
                            .font(.system(size: 60))
                            .fontWeight(.bold)
                        
                        Text("Speaking Time")
                            .font(.headline)
                    }
                }
                .frame(width: 280, height: 280)
                .padding()
                
                VStack(spacing: 16) {
                    Text(feedbackMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text(detailedFeedback)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Session Duration:")
                        Spacer()
                        Text(formatTime(totalRecordingTime))
                            .bold()
                    }
                    
                    HStack {
                        Text("Your Speaking Time:")
                        Spacer()
                        Text(formatTime(userSpeakingTime))
                            .bold()
                    }
                    
                    HStack {
                        Text("Others Speaking Time:")
                        Spacer()
                        Text(formatTime(totalRecordingTime - userSpeakingTime))
                            .bold()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
                
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .fontWeight(.semibold)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarItems(trailing: Button("Share") {
                // Share functionality
            })
        }
    }
    
    private var speakingPercentageColor: Color {
        if userSpeakingPercentage <= 33 {
            return .green
        } else if userSpeakingPercentage <= 66 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private var feedbackMessage: String {
        if userSpeakingPercentage <= 33 {
            return "You're a good listener!"
        } else if userSpeakingPercentage <= 55 {
            return "You have a balanced conversation style."
        } else if userSpeakingPercentage <= 70 {
            return "You're speaking more than others."
        } else {
            return "You're dominating the conversation."
        }
    }
    
    private var detailedFeedback: String {
        if userSpeakingPercentage <= 33 {
            return "You're giving others plenty of space to express themselves. Consider if you want to contribute more to the discussion."
        } else if userSpeakingPercentage <= 55 {
            return "You have a good balance of speaking and listening. This is ideal for most conversations."
        } else if userSpeakingPercentage <= 70 {
            return "You're speaking quite a bit more than others. Consider giving others more opportunity to contribute."
        } else {
            return "You're taking up most of the conversation. Try to ask more questions and listen more to create balance."
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Extension for AudioManager to apply user settings
extension AudioManager {
    func configureSilenceThreshold(_ threshold: Float) {
        // In a real implementation, this would modify the silenceThreshold property
    }
    
    func configureMinimumSpeakingSegment(_ duration: TimeInterval) {
        // In a real implementation, this would modify the minimumSpeakingSegment property
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataStore.shared)
    }
} 