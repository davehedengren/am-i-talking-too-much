import Foundation
import VoiceCore

/// Root app state: the calibrated voice profile decides whether the app
/// shows calibration or tracking, mirroring the Streamlit app's flow.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: VoiceProfile?

    private let store = ProfileStore()

    init() {
        profile = store.load()
    }

    func save(_ newProfile: VoiceProfile) {
        profile = newProfile
        store.save(newProfile)
    }

    func recalibrate() {
        profile = nil
        store.delete()
    }
}
