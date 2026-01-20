import SwiftUI

@available(macOS 14.0, *)
struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var audioManager = AudioManager()
    @State private var showingRecalibration = false
    @State private var targetPercentage: Double
    @State private var showNotifications: Bool
    @State private var notificationThreshold: Double
    
    init() {
        // Initialize state variables with default values
        // These will be overridden by environmentObject when the view appears
        _targetPercentage = State(initialValue: 50.0)
        _showNotifications = State(initialValue: true)
        _notificationThreshold = State(initialValue: 60.0)
    }
    
    var body: some View {
        Form {
            Section("Voice Setup") {
                Button("Recalibrate Voice") {
                    showingRecalibration = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical)
            }
            
            Section("Speaking Goals") {
                VStack(alignment: .leading) {
                    Text("Target speaking percentage: \(Int(targetPercentage))%")
                    
                    Slider(value: $targetPercentage, in: 0...100, step: 5) {
                        Text("Target percentage")
                    }
                    .padding(.vertical, 8)
                    
                    Text("Try to keep your speaking time around this percentage of the total conversation time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section("Notifications") {
                Toggle("Show Notifications", isOn: $showNotifications)
                
                if showNotifications {
                    VStack(alignment: .leading) {
                        Text("Notification threshold: \(Int(notificationThreshold))%")
                        
                        Slider(value: $notificationThreshold, in: 0...100, step: 5) {
                            Text("Notification threshold")
                        }
                        
                        Text("You'll receive a notification when your speaking percentage exceeds this threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("About App") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Am I Talking Too Much?")
                        .font(.headline)
                    
                    Text("Version 1.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("This app helps you monitor your speaking time in conversations to ensure you're not dominating the discussion.")
                        .font(.body)
                        .padding(.vertical, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showingRecalibration) {
            RecalibrationView(isPresented: $showingRecalibration)
                .environmentObject(dataStore)
        }
        .onAppear {
            // Set state variables from environment object when the view appears
            targetPercentage = dataStore.targetPercentage
            showNotifications = dataStore.showNotifications
            notificationThreshold = dataStore.notificationThreshold
        }
        .onChange(of: targetPercentage) {
            dataStore.targetPercentage = targetPercentage
        }
        .onChange(of: showNotifications) {
            dataStore.showNotifications = showNotifications
        }
        .onChange(of: notificationThreshold) {
            dataStore.notificationThreshold = notificationThreshold
        }
    }
}

@available(macOS 14.0, *)
struct RecalibrationView: View {
    @Binding var isPresented: Bool
    @StateObject private var audioManager = AudioManager()
    @State private var progressValue = 0.0
    @State private var isProcessing = false
    @State private var recordingTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 20) {
            if isProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Processing voice data...")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if progressValue >= 1.0 {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Voice setup complete!")
                        .font(.headline)
                    
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Recalibrate Your Voice")
                    .font(.title2)
                    .padding(.top)
                
                Text("Please read the text below out loud for 10 seconds to help the app recognize your voice.")
                    .multilineTextAlignment(.center)
                    .padding()
                
                ScrollView {
                    Text("Becoming mindful of speaking time is a powerful skill that improves both personal and professional relationships. Research shows that balanced conversations create stronger connections and more productive meetings. Many of us don't realize when we're dominating a discussion, which can unintentionally silence other valuable perspectives. By monitoring your speaking patterns, you can ensure everyone has the opportunity to contribute, leading to more inclusive and effective communication.")
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(height: 200)
                .padding()
                
                ProgressView(value: progressValue, total: 1.0)
                    .padding(.horizontal)
                
                Button(action: {
                    if audioManager.isRecording {
                        cancelRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    Text(audioManager.isRecording ? "Stop Recording" : "Start Recording")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .padding()
        .frame(width: 500, height: 400)
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
    
    private func startRecording() {
        progressValue = 0.0
        audioManager.startRecording()
        
        recordingTask = Task {
            // Simulate 10 seconds of recording with progress updates
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                if Task.isCancelled {
                    break
                }
                
                await MainActor.run {
                    progressValue = Double(i) / 100.0
                }
            }
            
            await MainActor.run {
                audioManager.stopRecording()
                isProcessing = true
                
                // Simulate processing time
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await MainActor.run {
                        isProcessing = false
                    }
                }
            }
        }
    }
    
    private func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        audioManager.stopRecording()
        progressValue = 0.0
    }
}

@available(macOS 14.0, *)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DataStore.preview)
    }
} 