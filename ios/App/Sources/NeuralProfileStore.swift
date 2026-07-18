import Foundation
import os

/// Persists the neural voice profile as `neural_profile.json` in Documents,
/// mirroring `ProfileStore`. A missing or corrupt file is treated as "no neural
/// profile" (the app falls back to the GMM matcher).
struct NeuralProfileStore {
    private static let logger = Logger(subsystem: "com.amitalkingtoomuch", category: "NeuralProfileStore")

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("neural_profile.json")
    }

    func load() -> NeuralVoiceProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(NeuralVoiceProfile.self, from: data)
        } catch {
            Self.logger.error("Failed to load neural profile: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ profile: NeuralVoiceProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
