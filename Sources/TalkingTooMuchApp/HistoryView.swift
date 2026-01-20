import SwiftUI

@available(macOS 14.0, *)
struct HistoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedSession: Session?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack {
            List(selection: $selectedSession) {
                ForEach(dataStore.sessions) { session in
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSession = session
                        }
                }
            }
            .listStyle(.inset)
            
            if let selectedSession = selectedSession {
                SessionDetailView(session: selectedSession)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem {
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                }
                .disabled(dataStore.sessions.isEmpty)
            }
        }
        .alert("Clear History", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                dataStore.clearHistory()
                selectedSession = nil
            }
        } message: {
            Text("Are you sure you want to clear all history? This action cannot be undone.")
        }
    }
}

@available(macOS 14.0, *)
struct SessionRow: View {
    let session: Session
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dateFormatter.string(from: session.date))
                    .font(.headline)
                
                Text("\(Int(session.userPercentage))% speaking time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Circular percentage indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(session.userPercentage / 100, 1.0)))
                    .stroke(
                        percentageColor(for: session.userPercentage),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(session.userPercentage))%")
                    .font(.system(size: 10, weight: .bold))
            }
            .frame(width: 40, height: 40)
        }
        .padding(.vertical, 8)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func percentageColor(for percentage: Double) -> Color {
        if percentage < 30 {
            return .blue
        } else if percentage < 50 {
            return .green
        } else if percentage < 70 {
            return .orange
        } else {
            return .red
        }
    }
}

@available(macOS 14.0, *)
struct SessionDetailView: View {
    let session: Session
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Session Details")
                .font(.headline)
            
            HStack(spacing: 40) {
                VStack {
                    Text(formatTime(session.userDuration))
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Your time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(formatTime(session.totalDuration))
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Total time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(Int(session.userPercentage))%")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Speaking percentage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Date and time
            Text("Recorded on \(fullDateFormatter.string(from: session.date))")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
    }
}

@available(macOS 14.0, *)
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(DataStore.preview)
    }
} 