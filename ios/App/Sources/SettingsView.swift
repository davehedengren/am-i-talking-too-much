import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Voice Profile") {
                    Label("Saved profile loaded", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                    Button(role: .destructive) {
                        dismiss()
                        model.recalibrate()
                    } label: {
                        Label("Re-calibrate Voice", systemImage: "waveform.badge.mic")
                    }
                }

                Section("Guide") {
                    Label { Text("Under 40% — great listening!") } icon: {
                        Circle().fill(.green).frame(width: 12, height: 12)
                    }
                    Label { Text("40–55% — balanced") } icon: {
                        Circle().fill(.yellow).frame(width: 12, height: 12)
                    }
                    Label { Text("Over 55% — talking a lot") } icon: {
                        Circle().fill(.red).frame(width: 12, height: 12)
                    }
                }

                Section {
                    Text("All analysis runs on this device. No audio is stored or sent anywhere — only speaking-time totals are kept, and only for the current session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
