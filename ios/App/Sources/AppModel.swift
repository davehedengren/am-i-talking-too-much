import Foundation
import VoiceCore

/// Root app state: the calibrated voice profile decides whether the app
/// shows calibration or tracking, mirroring the Streamlit app's flow.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: VoiceProfile?

    /// True when a saved profile existed but couldn't be loaded and was
    /// discarded; the calibration screen explains the reset to the user.
    @Published var profileWasReset: Bool

    private let store = ProfileStore()

    init() {
        let result = store.load()
        profile = result.profile
        profileWasReset = result.wasReset
    }

    /// Persist and publish a new profile. The profile is only published
    /// when the write succeeded, so "saved" in the UI is always true.
    func save(_ newProfile: VoiceProfile) throws {
        try store.save(newProfile)
        profile = newProfile
    }

    func recalibrate() {
        profile = nil
        store.delete()
    }

    func clearResetNotice() {
        profileWasReset = false
    }
}
