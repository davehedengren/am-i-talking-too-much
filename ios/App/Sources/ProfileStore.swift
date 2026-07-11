import Foundation
import VoiceCore
import os

/// Persists the voice profile as `voice_profile.json` in the app's
/// Documents directory. The file uses the same schema as the Python app,
/// so a profile calibrated on either platform works on the other.
struct ProfileStore {
    private static let logger = Logger(subsystem: "com.amitalkingtoomuch", category: "ProfileStore")

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice_profile.json")
    }

    func load() -> VoiceProfile? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(VoiceProfile.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            // Incompatible or corrupted profile: drop it and re-calibrate,
            // same recovery as the Python app.
            Self.logger.error("Failed to load voice profile: \(error.localizedDescription)")
            delete()
            return nil
        }
    }

    func save(_ profile: VoiceProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save voice profile: \(error.localizedDescription)")
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
