import Charts
import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var viewModel: TrackerViewModel
    @State private var showSettings = false
    @State private var pendingDraft: SessionDraft?
    @AppStorage("showDiagnosticsOnTracker") private var showDiagnostics = false

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TrackerViewModel(capture: .shared))
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    AirBalanceGauge(
                        percentage: viewModel.percentage,
                        hasSpeech: viewModel.totalSeconds > 0,
                        liveLevel: viewModel.isTracking ? viewModel.liveLevel : nil
                    )
                    .padding(.top, 6)

                    if viewModel.isTracking {
                        listeningStatus
                    } else if viewModel.totalSeconds > 0 {
                        totalsLine
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.coral)
                            .multilineTextAlignment(.leading)
                    }

                    controls

                    if !viewModel.isTracking {
                        micCheck
                    } else if !viewModel.percentageHistory.isEmpty {
                        liveChart
                    }

                    if showDiagnostics {
                        diagnostics
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
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
        .sheet(isPresented: $showSettings, onDismiss: {
            // The ground-truth recorder (reached via Settings) takes over the
            // shared capture; re-arm the tracker's monitoring when the sheet
            // closes. No-op if capture is still ours.
            Task {
                if let matcher = model.activeMatcher() {
                    let isNeural = model.useNeuralMatching && model.neuralProfile != nil
                    await viewModel.ensureMonitoring(matcher: matcher, isNeural: isNeural)
                }
            }
        }) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(item: $pendingDraft) { draft in
            SaveSessionView(draft: draft) {
                viewModel.reset()
            }
            .environmentObject(history)
        }
        // Idempotent: re-runs on appear and when the neural/GMM toggle flips.
        // Returning from a pushed screen mid-session is a no-op; a toggle flip
        // swaps the matcher without ending the session.
        .task(id: model.useNeuralMatching) {
            if let matcher = model.activeMatcher() {
                let isNeural = model.useNeuralMatching && model.neuralProfile != nil
                await viewModel.ensureMonitoring(matcher: matcher, isNeural: isNeural)
            }
        }
        .onDisappear {
            // Keep the mic alive while tracking (History push, backgrounding —
            // the audio background mode covers it); stop only an idle meter.
            if !viewModel.isTracking {
                viewModel.stopMonitoring()
            }
        }
    }

    // MARK: - Listening state

    private var listeningStatus: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                let matcherName = (model.useNeuralMatching && model.neuralProfile != nil) ? "Neural" : "Classic"
                Label("Listening · \(matcherName)", systemImage: "mic.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                outcomeChip
            }
            totalsLine
            if viewModel.percentage > 55, viewModel.totalSeconds >= 60 {
                Text("Lots of airtime — try a question?")
                    .font(.footnote)
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private var totalsLine: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.you).frame(width: 7, height: 7)
                    Text("You \(mmss(viewModel.userSeconds))")
                }
                HStack(spacing: 6) {
                    Circle().fill(Theme.others).frame(width: 7, height: 7)
                    Text("Others \(mmss(viewModel.totalSeconds - viewModel.userSeconds))")
                }
            }
            .font(Theme.metric(15, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            Text("Silence isn't counted.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var outcomeChip: some View {
        let (text, color): (String, Color) = switch viewModel.lastOutcome {
        case .you: ("You", Theme.you)
        case .others: ("Others", Theme.others)
        case .silence: ("quiet", Theme.muted)
        case nil: ("…", Theme.muted)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(Theme.metric(12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
        .animation(.easeInOut(duration: 0.25), value: viewModel.lastOutcome)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            if viewModel.isTracking {
                Button {
                    viewModel.stopTracking()
                    // Offer to save the finished run; nil means nothing worth
                    // saving was captured (no speech), so just stop.
                    pendingDraft = viewModel.makeDraft()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(QuietButtonStyle())
            } else {
                Button {
                    viewModel.startTracking()
                } label: {
                    Label("Start listening", systemImage: "mic.fill")
                }
                .buttonStyle(GoldButtonStyle())

                if viewModel.totalSeconds > 0 {
                    Button("Clear this session") {
                        viewModel.reset()
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var micCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mic check — speak and watch the bar")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            LiveLevelMeter(level: viewModel.liveLevel)
        }
    }

    private var liveChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This conversation")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Chart(Array(viewModel.percentageHistory.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Chunk", index),
                    y: .value("Your share", value)
                )
                .foregroundStyle(Theme.you)
                .interpolationMethod(.monotone)
                RuleMark(y: .value("Even", 50))
                    .foregroundStyle(Theme.muted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 110)
        }
    }

    // MARK: - Diagnostics (opt-in from Settings)

    private var diagnostics: some View {
        DisclosureGroup("Diagnostics") {
            if viewModel.debugLog.isEmpty {
                Text("No chunks yet. Start listening.")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.debugLog.reversed().enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.text)
    }

    /// Observes only the live level, so ~10 Hz meter updates re-render this
    /// tiny view instead of the whole chart-bearing screen.
    private struct LiveLevelMeter: View {
        @ObservedObject var level: TrackerViewModel.LiveLevel

        var body: some View {
            LevelMeterView(level: level.value)
        }
    }

    private func mmss(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
