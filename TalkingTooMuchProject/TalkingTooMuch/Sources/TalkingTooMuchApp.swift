import SwiftUI

@main
struct TalkingTooMuchApp: App {
    @StateObject private var dataStore = DataStore.shared
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedSetup {
                MainTabView()
                    .environmentObject(dataStore)
            } else {
                VoiceSetupView()
                    .onDisappear {
                        // When the setup view disappears, mark setup as complete
                        hasCompletedSetup = true
                    }
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var dataStore: DataStore
    
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.bar.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
} 