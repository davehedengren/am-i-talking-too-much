import SwiftUI

@main
struct AmITalkingTooMuchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
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
