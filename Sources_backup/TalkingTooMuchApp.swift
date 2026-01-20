import SwiftUI

@available(macOS 14.0, *)
@main
struct TalkingTooMuchApp: App {
    @StateObject private var dataStore = DataStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
        }
    }
}

@available(macOS 14.0, *)
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
