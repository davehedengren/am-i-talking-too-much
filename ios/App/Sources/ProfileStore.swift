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

    /// Load the saved profile. `wasReset` is true when a file existed but
    /// was corrupted or incompatible and had to be discarded — the UI tells
    /// the user to re-calibrate (same recovery as the Python app).
    func load() -> (profile: VoiceProfile?, wasReset: Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return (nil, false)
        }

        do {
            let profile = try JSONDecoder().decode(VoiceProfile.self, from: data)
            guard profile.dimension == VoiceMatcher.numCoefficients else {
                // Trained with a different feature dimension — unusable here.
                Self.logger.error("Voice profile has dimension \(profile.dimension), expected \(VoiceMatcher.numCoefficients); resetting")
                delete()
                return (nil, true)
            }
            return (profile, false)
        } catch {
            Self.logger.error("Failed to load voice profile: \(error.localizedDescription)")
            delete()
            return (nil, true)
        }
    }

    func save(_ profile: VoiceProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
