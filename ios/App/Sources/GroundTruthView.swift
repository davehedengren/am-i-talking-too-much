import SwiftUI

/// Diagnostics screen: record a conversation with live who-is-speaking labels
/// to build a ground-truth set for tuning the matchers offline.
struct GroundTruthView: View {
    @StateObject private var recorder = GroundTruthRecorder()

    var body: some View {
        List {
            Section {
                Text("Tap the buttons while recording to mark who is speaking. "
                     + "This saves raw conversation audio on this phone — the only "
                     + "place it goes unless you share it. Delete sessions anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = recorder.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if recorder.isRecording {
                    recordingControls
                } else {
                    Button {
                        Task { await recorder.startRecording() }
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Saved sessions") {
                if recorder.sessions.isEmpty {
                    Text("No sessions yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recorder.sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.id)
                                    .font(.subheadline.monospacedDigit())
                                Text("audio.wav + labels.json")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(items: [session.audioURL, session.labelsURL]) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            recorder.delete(recorder.sessions[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Ground Truth")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Never lose data: leaving mid-recording saves what we have.
            recorder.stopAndSave()
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(timeString(recorder.elapsed))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Spacer()
                Text("Who is speaking?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(GroundTruthRecorder.SpeakerLabel.allCases) { label in
                    Button {
                        recorder.setLabel(label)
                    } label: {
                        Text(label.title)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.currentLabel == label ? color(for: label) : Color(.systemGray4))
                }
            }

            Button(role: .destructive) {
                recorder.stopAndSave()
            } label: {
                Label("Stop & Save", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private func color(for label: GroundTruthRecorder.SpeakerLabel) -> Color {
        switch label {
        case .me: return .green
        case .others: return .blue
        case .quiet: return .gray
        case .unsure: return .orange
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
