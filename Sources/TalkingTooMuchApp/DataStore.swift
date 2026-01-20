import Foundation
import SwiftUI

class DataStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var targetPercentage: Double = 50.0
    @Published var showNotifications: Bool = true
    @Published var notificationThreshold: Double = 60.0
    @Published var hasCompletedVoiceSetup: Bool = false
    @Published var latestSession: Session?
    
    init() {
        // In a real app, we would load data from persistent storage here
        // For now, just populate with some sample data
        if sessions.isEmpty {
            populateSampleData()
        }
        // Mock setup for development
        hasCompletedVoiceSetup = true
    }
    
    func addSession(_ session: Session) {
        sessions.append(session)
        latestSession = session
        // In a real app, we would save to persistent storage here
    }
    
    func clearHistory() {
        sessions.removeAll()
        latestSession = nil
        // In a real app, we would clear persistent storage here
    }
    
    private func populateSampleData() {
        let calendar = Calendar.current
        
        // Add some sample sessions from the past week
        for i in 0..<10 {
            let daysAgo = Double(i)
            let date = calendar.date(byAdding: .day, value: -Int(daysAgo), to: Date()) ?? Date()
            
            let userDuration = Double.random(in: 30...600)
            let totalDuration = userDuration + Double.random(in: 30...600)
            
            let session = Session(
                id: UUID(),
                date: date,
                userDuration: userDuration,
                totalDuration: totalDuration
            )
            
            sessions.append(session)
        }
        
        // Sort sessions by date, most recent first
        sessions.sort { $0.date > $1.date }
        
        // Set latest session
        if let first = sessions.first {
            latestSession = first
        }
    }
    
    // Convenience static property for previews
    static var preview: DataStore {
        let store = DataStore()
        return store
    }
}

// Model representing a recorded session
struct Session: Identifiable, Hashable, Codable {
    var id: UUID
    var date: Date
    var userDuration: TimeInterval
    var totalDuration: TimeInterval
    
    var userPercentage: Double {
        if totalDuration > 0 {
            return (userDuration / totalDuration) * 100.0
        }
        return 0
    }
    
    // Convenience initializer
    init(id: UUID = UUID(), date: Date = Date(), userDuration: TimeInterval, totalDuration: TimeInterval) {
        self.id = id
        self.date = date
        self.userDuration = userDuration
        self.totalDuration = totalDuration
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
} 