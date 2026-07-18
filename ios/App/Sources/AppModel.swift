import Foundation
import VoiceCore

/// Root app state: the calibrated voice profile decides whether the app
/// shows calibration or tracking, mirroring the Streamlit app's flow.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: VoiceProfile?

    /// Neural (AudioFeaturePrint) profile, when calibration produced one.
    @Published var neuralProfile: NeuralVoiceProfile?

    /// True when a saved profile existed but couldn't be loaded and was
    /// discarded; the calibration screen explains the reset to the user.
    @Published var profileWasReset: Bool

    /// Prefer the neural matcher when a neural profile exists. Persisted so the
    /// A/B choice survives launches.
    @Published var useNeuralMatching: Bool {
        didSet { UserDefaults.standard.set(useNeuralMatching, forKey: Self.neuralPrefKey) }
    }

    private static let neuralPrefKey = "useNeuralMatching"

    private let store = ProfileStore()
    private let neuralStore = NeuralProfileStore()

    init() {
        let result = store.load()
        profile = result.profile
        profileWasReset = result.wasReset
        neuralProfile = neuralStore.load()
        useNeuralMatching = (UserDefaults.standard.object(forKey: Self.neuralPrefKey) as? Bool) ?? true
    }

    /// Persist and publish the calibration result. The GMM profile is required;
    /// the neural profile is optional (enrollment may have failed). Only
    /// published on a successful write, so "saved" in the UI is always true.
    func save(_ newProfile: VoiceProfile, neural: NeuralVoiceProfile?) throws {
        try store.save(newProfile)
        profile = newProfile

        if let neural {
            try? neuralStore.save(neural)
            neuralProfile = neural
        } else {
            neuralStore.delete()
            neuralProfile = nil
        }
    }

    func recalibrate() {
        profile = nil
        neuralProfile = nil
        store.delete()
        neuralStore.delete()
    }

    func clearResetNotice() {
        profileWasReset = false
    }

    /// The matcher tracking should use: neural when enrolled and enabled,
    /// otherwise the classic GMM. Nil only when there's no profile at all.
    func activeMatcher() -> (any SpeakerMatcher)? {
        if useNeuralMatching, let neuralProfile {
            return NeuralSpeakerMatcher(profile: neuralProfile)
        }
        if let profile {
            return GMMSpeakerMatcher(profile: profile)
        }
        return nil
    }
}
