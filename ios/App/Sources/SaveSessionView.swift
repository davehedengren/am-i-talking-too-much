import SwiftUI

/// Sheet shown after a tracking run stops: confirm the event's title and
/// (auto-detected) location, then save it to history or discard it. Location
/// resolves asynchronously and never blocks saving.
struct SaveSessionView: View {
    let draft: SessionDraft
    /// Called after the sheet finishes (save or discard) so the tracker can reset.
    let onFinish: () -> Void

    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss

    // Retained for the whole sheet lifetime so the one-shot request isn't
    // torn down mid-flight.
    @State private var locationProvider = LocationProvider()
    @State private var title = ""
    @State private var place: LocationProvider.Place?
    @State private var isResolvingLocation = true

    private var fallbackTitle: String {
        "Event · " + draft.start.formatted(date: .abbreviated, time: .shortened)
    }

    private var userPercentage: Int {
        Int((draft.totalSpeechSeconds > 0
             ? draft.userSeconds / draft.totalSpeechSeconds * 100 : 0).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                }

                Section("Details") {
                    LabeledContent("Date", value: draft.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Duration", value: draft.duration.durationLabel)
                    HStack {
                        Text("Location")
                        Spacer()
                        if isResolvingLocation {
                            ProgressView()
                        } else {
                            Text(place?.name ?? "Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Summary") {
                    HStack(spacing: 12) {
                        StatTile(title: "You", value: String(format: "%.0fs", draft.userSeconds))
                        StatTile(title: "Others", value: String(format: "%.0fs", draft.totalSpeechSeconds - draft.userSeconds))
                        StatTile(title: "Your share", value: "\(userPercentage)%")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Save Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if title.isEmpty { title = fallbackTitle }
                await resolveLocation()
            }
            .interactiveDismissDisabled()
        }
    }

    private func resolveLocation() async {
        let resolved = await locationProvider.currentPlace()
        place = resolved
        isResolvingLocation = false
        // Prefill the title with the place name only if the user hasn't typed
        // their own yet.
        if let name = resolved.name, title == fallbackTitle {
            title = name
        }
    }

    private func save() {
        let session = Session(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: draft.start,
            duration: draft.duration,
            userSeconds: draft.userSeconds,
            totalSpeechSeconds: draft.totalSpeechSeconds,
            placeName: place?.name,
            latitude: place?.latitude,
            longitude: place?.longitude,
            buckets: draft.buckets
        )
        history.add(session)
        finish()
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}
