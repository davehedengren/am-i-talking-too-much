import Foundation
import os

/// Persists saved events as `sessions.json` in the app's Documents directory,
/// following the same Codable-to-JSON approach as `ProfileStore`. A corrupt or
/// unreadable file is logged and treated as "no history" rather than crashing.
struct SessionStore {
    private static let logger = Logger(subsystem: "com.amitalkingtoomuch", category: "SessionStore")

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions.json")
    }

    func load() -> [Session] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // No file yet is the normal first-run case.
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Session].self, from: data)
        } catch {
            Self.logger.error("Failed to load sessions: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ sessions: [Session]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
}
