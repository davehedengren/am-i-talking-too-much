import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var viewModel: CalibrationViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: CalibrationViewModel(capture: .shared))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Voice Calibration")
                        .font(.largeTitle.weight(.semibold))
                    Text("Record a sample of your voice so we can identify you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Level — speak to verify your mic is working")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LevelMeterView(level: viewModel.level)
                }

                if model.profileWasReset {
                    Label(
                        "Your saved voice profile couldn't be loaded and has been reset. Please re-calibrate.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                instructions

                controls
            }
            .padding()
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instructions").font(.headline)
            Text("1. Verify the level meter above responds when you speak")
            Text("2. Tap “Start Recording”")
            Text("3. Speak naturally for 10 seconds (read something aloud or just talk)")
            Text("4. Review and save your voice profile")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.phase {
        case .idle:
            Button {
                model.clearResetNotice()
                viewModel.startRecording()
            } label: {
                Label("Start Recording (10 seconds)", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .recording(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress) {
                    Text("Recording… speak now!")
                }
                Text("\(Int((CalibrationViewModel.calibrationSeconds * (1 - progress)).rounded())) s remaining")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .recorded:
            VStack(spacing: 12) {
                Label("Recording complete!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button {
                    viewModel.playRecording()
                } label: {
                    Label("Play Recording", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                HStack(spacing: 12) {
                    Button {
                        viewModel.discardRecording()
                    } label: {
                        Label("Re-record", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        viewModel.saveProfile(into: model)
                    } label: {
                        Label("Save Profile", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

        case .saving:
            ProgressView("Creating voice profile…")
        }
    }
}
