import SwiftUI
import StoreKit

@available(macOS 14.0, *)
struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var silenceThreshold: Double = UserDefaults.standard.double(forKey: "silenceThreshold")
    @State private var minimumSpeakingSegment: Double = UserDefaults.standard.double(forKey: "minimumSpeakingSegment")
    @State private var useAdvancedAnalysis: Bool = UserDefaults.standard.bool(forKey: "useAdvancedAnalysis")
    @State private var hasCompletedSetup: Bool = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
    @State private var showingDeleteConfirmation = false
    @State private var showingRecalibrateSheet = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Voice Recognition") {
                    Toggle("Use Advanced Analysis", isOn: Binding(
                        get: { useAdvancedAnalysis },
                        set: {
                            useAdvancedAnalysis = $0
                            UserDefaults.standard.set($0, forKey: "useAdvancedAnalysis")
                        }
                    ))
                    
                    Button("Recalibrate Voice") {
                        showingRecalibrateSheet = true
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Voice Detection Settings") {
                    VStack(alignment: .leading) {
                        Text("Silence Threshold: \(Int(silenceThreshold * 100))%")
                        Slider(value: Binding(
                            get: { silenceThreshold },
                            set: {
                                silenceThreshold = $0
                                UserDefaults.standard.set($0, forKey: "silenceThreshold")
                            }
                        ), in: 0.01...0.2)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Minimum Speaking Duration: \(String(format: "%.1f", minimumSpeakingSegment))s")
                        Slider(value: Binding(
                            get: { minimumSpeakingSegment },
                            set: {
                                minimumSpeakingSegment = $0
                                UserDefaults.standard.set($0, forKey: "minimumSpeakingSegment")
                            }
                        ), in: 0.1...2.0)
                    }
                }
                
                Section {
                    Button("Reset All Settings") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Settings?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("This will reset all settings to their default values. This cannot be undone.")
            }
            .sheet(isPresented: $showingRecalibrateSheet) {
                VoiceSetupView()
            }
        }
    }
    
    private func resetSettings() {
        silenceThreshold = 0.05
        minimumSpeakingSegment = 0.5
        useAdvancedAnalysis = false
        hasCompletedSetup = false
        
        UserDefaults.standard.set(0.05, forKey: "silenceThreshold")
        UserDefaults.standard.set(0.5, forKey: "minimumSpeakingSegment")
        UserDefaults.standard.set(false, forKey: "useAdvancedAnalysis")
        UserDefaults.standard.set(false, forKey: "hasCompletedSetup")
    }
}

@available(macOS 14.0, *)
struct RecalibrationView: View {
    @Binding var isPresented: Bool
    
    // Reuse the voice setup logic but with a different flow
    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var setupStep = SetupStep.welcome
    
    private let recordingDuration: TimeInterval = 10.0
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Voice Recalibration")
                    .font(.largeTitle)
                    .font(.system(size: 34, weight: .bold))
                
                ProgressView(value: recordingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 10)
                
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
                .padding()
                .frame(height: 200)
                
                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 17, weight: .semibold))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isRecording ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                
                if setupStep == .complete {
                    Button("Finish") {
                        isPresented = false
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        recordingProgress = 0
        
        // In a real app, we would start real recording here
        // using the AudioManager
        
        // Use Task for better actor isolation
        Task { @MainActor in
            let startDate = Date()
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startDate)
                    let progress = elapsed / recordingDuration
                    
                    if progress < 1.0 {
                        recordingProgress = progress
                    } else {
                        stopRecording()
                    }
                }
            }
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        // In a real app, we would stop recording and 
        // process the voice calibration data
        
        // Simulate processing time
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            setupStep = .complete
        }
    }
}

@available(macOS 14.0, *)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DataStore())
    }
} 
