import SwiftUI

@main
struct AmITalkingTooMuchApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(history)
                // The "quiet instrument" identity: dark-first (discreet on a
                // dinner table), candlelight-gold accent throughout.
                .preferredColorScheme(.dark)
                .tint(Theme.you)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            if model.profile == nil {
                CalibrationView()
            } else {
                TrackingView()
            }
        }
    }
}
