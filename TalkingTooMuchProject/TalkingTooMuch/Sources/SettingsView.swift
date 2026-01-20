import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @AppStorage("silenceThreshold") private var silenceThreshold = 0.05
    @AppStorage("minimumSpeakingSegment") private var minimumSpeakingSegment = 0.5
    @AppStorage("useAdvancedAnalysis") private var useAdvancedAnalysis = false
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = true
    
    @State private var showingDeleteConfirmation = false
    @State private var showingRecalibrateSheet = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Voice Recognition")) {
                    Toggle("Use Advanced Analysis", isOn: $useAdvancedAnalysis)
                    
                    Button("Recalibrate Voice") {
                        showingRecalibrateSheet = true
                    }
                    .foregroundColor(.blue)
                }
                
                Section(header: Text("Advanced Settings")) {
                    Stepper(
                        "Silence Threshold: \(silenceThreshold, specifier: "%.2f")",
                        value: $silenceThreshold,
                        in: 0.01...0.20,
                        step: 0.01
                    )
                    .padding(.vertical, 4)
                    
                    Stepper(
                        "Min Speaking Segment: \(minimumSpeakingSegment, specifier: "%.1f")s",
                        value: $minimumSpeakingSegment,
                        in: 0.1...2.0,
                        step: 0.1
                    )
                    .padding(.vertical, 4)
                    
                    Text("These settings affect voice detection sensitivity.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Data Management")) {
                    Button("Clear Session History") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
            .navigationTitle("Settings")
            .alert("Clear History", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    dataStore.clearAllSessions()
                }
            } message: {
                Text("Are you sure you want to delete all your recording history? This action cannot be undone.")
            }
            .sheet(isPresented: $showingRecalibrateSheet) {
                RecalibrationView(isPresented: $showingRecalibrateSheet)
            }
        }
    }
}

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
                    .fontWeight(.bold)
                
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
                        .fontWeight(.semibold)
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
                    .fontWeight(.semibold)
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
            .navigationBarItems(leading: Button("Cancel") {
                isPresented = false
            })
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
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if recordingProgress < 1.0 {
                recordingProgress += 0.1 / recordingDuration
            } else {
                stopRecording()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            setupStep = .complete
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(DataStore.shared)
    }
} 