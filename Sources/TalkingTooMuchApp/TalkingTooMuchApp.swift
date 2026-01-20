import SwiftUI

// Navigation structure for the app
struct NavigationStructure: View {
    @StateObject private var dataStore = DataStore()
    
    var body: some View {
        NavigationSplitView {
            Sidebar()
                .environmentObject(dataStore)
                .frame(minWidth: 200)
        } detail: {
            ContentView()
                .environmentObject(dataStore)
                .frame(minWidth: 500, minHeight: 600)
        }
        .navigationTitle("Am I Talking Too Much?")
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct Sidebar: View {
    @State private var selection: NavigationItem? = .recording
    @EnvironmentObject var dataStore: DataStore
    
    enum NavigationItem: Hashable {
        case recording, history, settings
    }
    
    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: NavigationItem.recording) {
                Label("Recording", systemImage: "mic.fill")
            }
            
            NavigationLink(value: NavigationItem.history) {
                Label("History", systemImage: "chart.bar.fill")
            }
            
            NavigationLink(value: NavigationItem.settings) {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationDestination(for: NavigationItem.self) { item in
            switch item {
            case .recording:
                ContentView()
                    .environmentObject(dataStore)
            case .history:
                HistoryView()
                    .environmentObject(dataStore)
            case .settings:
                SettingsView()
                    .environmentObject(dataStore)
            }
        }
    }
} 