import Foundation

/// Observable list of saved events, kept sorted newest-first. Wraps
/// `SessionStore` for persistence and is injected into the view tree via
/// `.environmentObject`, exactly like `AppModel`. Writes are persisted
/// immediately; a failed write is logged but leaves the in-memory list intact
/// so the UI stays responsive.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let store = SessionStore()

    init() {
        sessions = store.load().sorted { $0.date > $1.date }
    }

    func add(_ session: Session) {
        sessions.append(session)
        sessions.sort { $0.date > $1.date }
        persist()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        try? store.save(sessions)
    }
}
