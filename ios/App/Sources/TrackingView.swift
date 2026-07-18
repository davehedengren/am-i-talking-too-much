import Charts
import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var viewModel: TrackerViewModel
    @State private var showSettings = false
    @State private var pendingDraft: SessionDraft?

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TrackerViewModel(capture: .shared))
    }

    /// Same feedback bands as the Python app.
    private var percentageColor: Color {
        switch viewModel.percentage {
        case ...40: return .green
        case ...55: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                percentageHeader

                ProgressView(value: min(viewModel.percentage / 100, 1))
                    .tint(percentageColor)

                if !viewModel.percentageHistory.isEmpty {
                    historyChart
                }

                stats

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                controls

                if !viewModel.isTracking {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Audio Level")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LevelMeterView(level: viewModel.level)
                    }
                } else {
                    Label("Listening… speak naturally!", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                debugSection
            }
            .padding()
        }
        .navigationTitle("Conversation Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HistoryListView()
                        .environmentObject(history)
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(item: $pendingDraft) { draft in
            SaveSessionView(draft: draft) {
                viewModel.reset()
            }
            .environmentObject(history)
        }
        .task {
            if let profile = model.profile {
                await viewModel.startMonitoring(profile: profile)
            }
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var percentageHeader: some View {
        VStack(spacing: 4) {
            Text("\(Int(viewModel.percentage.rounded()))%")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(percentageColor)
                .contentTransition(.numericText())
                .animation(.default, value: Int(viewModel.percentage.rounded()))
            Text("Your speaking time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var historyChart: some View {
        Chart(Array(viewModel.percentageHistory.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Chunk", index),
                y: .value("Your Speaking %", value)
            )
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 160)
    }

    private var stats: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatTile(title: "You spoke", value: String(format: "%.1fs", viewModel.userSeconds))
                StatTile(title: "Others spoke", value: String(format: "%.1fs", viewModel.totalSeconds - viewModel.userSeconds))
                StatTile(title: "Total speech", value: String(format: "%.1fs", viewModel.totalSeconds))
            }
            Text("Silence is not counted — only time when someone is speaking")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if viewModel.isTracking {
                Button {
                    viewModel.stopTracking()
                    // Offer to save the finished run; nil means nothing worth
                    // saving was captured (no speech), so just stop.
                    pendingDraft = viewModel.makeDraft()
                } label: {
                    Label("Stop Tracking", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    viewModel.startTracking()
                } label: {
                    Label("Start Tracking", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                viewModel.stopTracking()
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var debugSection: some View {
        DisclosureGroup("Debug Log") {
            if viewModel.debugLog.isEmpty {
                Text("No logs yet. Start tracking.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.debugLog.reversed().enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
    }
}
