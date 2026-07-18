import SwiftUI

/// Browsable list of saved events, newest first. Rows push a detail view;
/// swipe to delete. Pushed onto the tracker's existing navigation stack.
struct HistoryListView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        Group {
            if history.sessions.isEmpty {
                ContentUnavailableView(
                    "No events yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Track a conversation and save it to see it here.")
                )
            } else {
                List {
                    ForEach(history.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete { history.delete(at: $0) }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(session.duration.durationLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let place = session.placeName {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(Int(session.userPercentage.rounded()))%")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("you")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
