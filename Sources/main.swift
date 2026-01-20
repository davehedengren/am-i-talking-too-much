import SwiftUI
import AppKit

// Create and run the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

// App delegate to manage the application lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var dataStore = DataStore()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Am I Talking Too Much?"
        window.center()
        
        // Create the SwiftUI view
        let contentView = ContentView()
            .environmentObject(dataStore)
        
        // Set the SwiftUI view as the window content
        window.contentView = NSHostingView(rootView: contentView)
        
        // Show the window
        window.makeKeyAndOrderFront(nil)
        
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
        
        print("App started with direct window creation")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
} 