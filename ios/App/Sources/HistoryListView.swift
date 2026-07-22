import SwiftUI

/// Browsable list of saved events, newest first. Every row carries a small
/// gold/teal share bar, so the list itself reads as a chart of your habits;
/// a header aggregates the practice ("your average across events").
struct HistoryListView: View {
    @EnvironmentObject private var history: HistoryStore

    private var averageShare: Double? {
        let withSpeech = history.sessions.filter { $0.totalSpeechSeconds > 0 }
        guard !withSpeech.isEmpty else { return nil }
        return withSpeech.reduce(0) { $0 + $1.userPercentage } / Double(withSpeech.count)
    }

    var body: some View {
        Group {
            if history.sessions.isEmpty {
                ContentUnavailableView(
                    "No conversations yet",
                    systemImage: "waveform",
                    description: Text("Your first saved conversation will appear here.")
                )
            } else {
                List {
                    if let average = averageShare {
                        Section {
                            HStack(spacing: 12) {
                                Text("\(Int(average.rounded()))%")
                                    .font(Theme.metric(30, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.band(for: average))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Your average airtime")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.text)
                                    Text("across \(history.sessions.count) saved conversation\(history.sessions.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Theme.elevated)
                        }
                    }

                    Section {
                        ForEach(history.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .listRowBackground(Theme.elevated)
                        }
                        .onDelete { history.delete(at: $0) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(session.userPercentage.rounded()))%")
                    .font(Theme.metric(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.band(for: session.userPercentage))
            }

            ShareBar(fraction: session.totalSpeechSeconds > 0
                     ? session.userSeconds / session.totalSpeechSeconds : 0)

            HStack(spacing: 6) {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(session.duration.durationLabel)
                if let place = session.placeName {
                    Text("·")
                    Text(place).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }
}

/// The row's miniature verdict: your gold share against everyone else's teal.
private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Capsule()
                    .fill(Theme.you)
                    .frame(width: max(geometry.size.width * fraction, 3))
                Capsule()
                    .fill(Theme.others.opacity(0.55))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
