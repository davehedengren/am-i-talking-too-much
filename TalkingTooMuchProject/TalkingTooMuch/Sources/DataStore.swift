import Foundation
import Combine

class DataStore: ObservableObject {
    // Published properties for SwiftUI binding
    @Published var sessions: [SessionData] = []
    @Published var userVoiceProfile: Data?
    
    // Singleton instance
    static let shared = DataStore()
    
    // UserDefaults keys
    private enum Keys {
        static let sessions = "sessions"
        static let voiceProfile = "voiceProfile"
    }
    
    private init() {
        loadData()
    }
    
    // MARK: - Public Methods
    
    /// Save a new recording session
    func saveSession(userPercentage: Double, userSpeakingTime: TimeInterval, totalTime: TimeInterval) {
        let newSession = SessionData(
            date: Date(),
            userPercentage: userPercentage,
            duration: totalTime
        )
        
        sessions.append(newSession)
        saveSessions()
    }
    
    /// Delete a session by ID
    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        saveSessions()
    }
    
    /// Clear all session history
    func clearAllSessions() {
        sessions.removeAll()
        saveSessions()
    }
    
    /// Save user voice profile
    func saveVoiceProfile(_ profileData: Data) {
        userVoiceProfile = profileData
        UserDefaults.standard.set(profileData, forKey: Keys.voiceProfile)
    }
    
    // MARK: - Analytics
    
    /// Get the user's average speaking percentage
    func getAverageSpeakingPercentage(for timeFrame: TimeFrame = .allTime) -> Double {
        let filteredSessions: [SessionData]
        
        switch timeFrame {
        case .day:
            filteredSessions = sessions.filter {
                Calendar.current.isDateInToday($0.date)
            }
        case .week:
            filteredSessions = sessions.filter {
                $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            }
        case .month:
            filteredSessions = sessions.filter {
                $0.date >= Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            }
        case .allTime:
            filteredSessions = sessions
        }
        
        guard !filteredSessions.isEmpty else { return 0 }
        
        let total = filteredSessions.reduce(0) { $0 + $1.userPercentage }
        return total / Double(filteredSessions.count)
    }
    
    /// Get the total recording time for a given time frame
    func getTotalRecordingTime(for timeFrame: TimeFrame = .allTime) -> TimeInterval {
        let filteredSessions: [SessionData]
        
        switch timeFrame {
        case .day:
            filteredSessions = sessions.filter {
                Calendar.current.isDateInToday($0.date)
            }
        case .week:
            filteredSessions = sessions.filter {
                $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            }
        case .month:
            filteredSessions = sessions.filter {
                $0.date >= Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            }
        case .allTime:
            filteredSessions = sessions
        }
        
        return filteredSessions.reduce(0) { $0 + $1.duration }
    }
    
    // MARK: - Private Methods
    
    private func loadData() {
        loadSessions()
        loadVoiceProfile()
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: Keys.sessions) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                sessions = try decoder.decode([SessionData].self, from: data)
            } catch {
                print("Failed to decode sessions: \(error.localizedDescription)")
                sessions = []
            }
        }
    }
    
    private func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: Keys.sessions)
        } catch {
            print("Failed to encode sessions: \(error.localizedDescription)")
        }
    }
    
    private func loadVoiceProfile() {
        userVoiceProfile = UserDefaults.standard.data(forKey: Keys.voiceProfile)
    }
}

// MARK: - Supporting Types

/// Time frame for data analysis
enum TimeFrame {
    case day
    case week
    case month
    case allTime
}

/// Make SessionData Codable for persistence
extension SessionData: Codable {} 