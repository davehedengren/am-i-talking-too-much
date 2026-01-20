import SwiftUI
import Charts

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
                // Delete sessions from the list
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
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(last7DaysSessions) { session in
                        BarMark(
                            x: .value("Day", formattedDay(from: session.date)),
                            y: .value("Percentage", session.userPercentage)
                        )
                        .foregroundStyle(colorForPercentage(session.userPercentage).gradient)
                    }
                }
                .frame(height: 250)
                .padding()
            } else {
                // Fallback for iOS 15 and earlier - a simple chart alternative
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(last7DaysSessions) { session in
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 5)
                                .fill(colorForPercentage(session.userPercentage))
                                .frame(width: 30, height: CGFloat(session.userPercentage) * 2)
                            Text(formattedDay(from: session.date, short: true))
                                .font(.caption)
                                .frame(width: 30)
                        }
                        .frame(height: 250)
                    }
                }
                .padding()
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
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(last30DaysSessions) { session in
                        LineMark(
                            x: .value("Date", formattedDate(from: session.date)),
                            y: .value("Percentage", session.userPercentage)
                        )
                        .foregroundStyle(colorForPercentage(monthlyAverage).gradient)
                    }
                    AreaMark(
                        x: .value("Date", formattedDate(from: last30DaysSessions.first?.date ?? Date())),
                        y: .value("Percentage", 50)
                    )
                    .foregroundStyle(.gray.opacity(0.2))
                }
                .frame(height: 250)
                .padding()
            } else {
                // Fallback for iOS 15 and earlier - simple text list
                List {
                    ForEach(last30DaysSessions) { session in
                        HStack {
                            Text(formattedDate(from: session.date))
                            Spacer()
                            Text("\(Int(session.userPercentage))%")
                                .foregroundColor(colorForPercentage(session.userPercentage))
                        }
                    }
                }
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
    
    private func formattedDay(from date: Date, short: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = short ? "EE" : "EEEE"
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

struct SessionData: Identifiable {
    let id = UUID()
    let date: Date
    let userPercentage: Double
    let duration: TimeInterval
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
} 