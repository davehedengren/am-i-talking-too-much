import SwiftUI

@available(macOS 14.0, *)
struct HistoryView: View {
    @State private var selectedTab = 0
    @State private var sessions: [SessionData] = [
        // Sample data - in a real app, this would come from persistent storage
        SessionData(date: Date().addingTimeInterval(-86400 * 2), userPercentage: 35, duration: 1800),
        SessionData(date: Date().addingTimeInterval(-86400), userPercentage: 62, duration: 3600),
        SessionData(date: Date(), userPercentage: 45, duration: 2700)
    ]
    
    // For weekly and monthly averages
    var weeklyAverage: Double {
        let weekSessions = sessions.filter { $0.date > Date().addingTimeInterval(-86400 * 7) }
        return weekSessions.isEmpty ? 0 : weekSessions.reduce(0) { $0 + $1.userPercentage } / Double(weekSessions.count)
    }
    
    var monthlyAverage: Double {
        let monthSessions = sessions.filter { $0.date > Date().addingTimeInterval(-86400 * 30) }
        return monthSessions.isEmpty ? 0 : monthSessions.reduce(0) { $0 + $1.userPercentage } / Double(monthSessions.count)
    }
    
    var body: some View {
        VStack {
            Text("Speaking History")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            Picker("Time Period", selection: $selectedTab) {
                Text("Sessions").tag(0)
                Text("Weekly").tag(1)
                Text("Monthly").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content changes based on the selected tab
            Group {
                switch selectedTab {
                case 0:
                    sessionsList
                case 1:
                    weeklyView
                case 2:
                    monthlyView
                default:
                    sessionsList
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - View Components
    
    private var sessionsList: some View {
        List {
            ForEach(sessions.sorted(by: { $0.date > $1.date })) { session in
                SessionRow(session: session)
            }
            .onDelete { indexSet in
                sessions.remove(atOffsets: indexSet)
            }
        }
    }
    
    private var weeklyView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Weekly Average:")
                    .font(.headline)
                Spacer()
                Text("\(Int(weeklyAverage))%")
                    .font(.headline)
                    .foregroundColor(colorForPercentage(weeklyAverage))
            }
            .padding(.horizontal)
            
            // Simple bar chart implementation
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(last7DaysSessions) { session in
                        VStack {
                            Text("\(Int(session.userPercentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorForPercentage(session.userPercentage))
                                .frame(width: 30, height: max(20, CGFloat(session.userPercentage) * 2))
                            
                            Text(formattedDay(from: session.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(height: 250)
            }
            
            Spacer()
        }
    }
    
    private var monthlyView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Monthly Average:")
                    .font(.headline)
                Spacer()
                Text("\(Int(monthlyAverage))%")
                    .font(.headline)
                    .foregroundColor(colorForPercentage(monthlyAverage))
            }
            .padding(.horizontal)
            
            // Simple line graph implementation
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(last30DaysSessions) { session in
                        VStack {
                            Text("\(Int(session.userPercentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorForPercentage(session.userPercentage))
                                .frame(width: 4, height: max(20, CGFloat(session.userPercentage) * 2))
                            
                            Text(formattedDate(from: session.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(height: 250)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private var last7DaysSessions: [SessionData] {
        let groupedByDay = Dictionary(grouping: sessions.filter { $0.date > Date().addingTimeInterval(-86400 * 7) }) { session in
            Calendar.current.startOfDay(for: session.date)
        }
        
        return groupedByDay.map { day, sessions in
            let avgPercentage = sessions.reduce(0) { $0 + $1.userPercentage } / Double(sessions.count)
            return SessionData(date: day, userPercentage: avgPercentage, duration: sessions.reduce(0) { $0 + $1.duration })
        }.sorted { $0.date < $1.date }
    }
    
    private var last30DaysSessions: [SessionData] {
        let groupedByDay = Dictionary(grouping: sessions.filter { $0.date > Date().addingTimeInterval(-86400 * 30) }) { session in
            Calendar.current.startOfDay(for: session.date)
        }
        
        return groupedByDay.map { day, sessions in
            let avgPercentage = sessions.reduce(0) { $0 + $1.userPercentage } / Double(sessions.count)
            return SessionData(date: day, userPercentage: avgPercentage, duration: sessions.reduce(0) { $0 + $1.duration })
        }.sorted { $0.date < $1.date }
    }
    
    private func formattedDay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        return formatter.string(from: date)
    }
    
    private func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    private func colorForPercentage(_ percentage: Double) -> Color {
        if percentage <= 33 {
            return .green
        } else if percentage <= 66 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Supporting Views

@available(macOS 14.0, *)
struct SessionRow: View {
    let session: SessionData
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formattedDate(from: session.date))
                    .font(.headline)
                Text("\(formattedDuration(session.duration))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(lineWidth: 4)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(session.userPercentage / 100, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .foregroundColor(colorForPercentage(session.userPercentage))
                    .rotationEffect(Angle(degrees: 270.0))
                
                Text("\(Int(session.userPercentage))%")
                    .font(.footnote)
                    .bold()
            }
            .frame(width: 50, height: 50)
        }
        .padding(.vertical, 8)
    }
    
    private func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes) min"
    }
    
    private func colorForPercentage(_ percentage: Double) -> Color {
        if percentage <= 33 {
            return .green
        } else if percentage <= 66 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Model

@available(macOS 14.0, *)
public struct SessionData: Identifiable, Codable {
    public var id: UUID
    public let date: Date
    public let userPercentage: Double
    public let duration: TimeInterval
    
    public init(id: UUID = UUID(), date: Date, userPercentage: Double, duration: TimeInterval) {
        self.id = id
        self.date = date
        self.userPercentage = userPercentage
        self.duration = duration
    }
}

// MARK: - Previews

@available(macOS 14.0, *)
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
} 
