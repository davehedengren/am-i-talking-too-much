import Charts
import MapKit
import SwiftUI

/// Detail for one saved event: header, a map pin if a location was captured,
/// the "speaking share over time" chart, and summary tiles.
struct SessionDetailView: View {
    let session: Session

    private struct SharePoint: Identifiable {
        let id: TimeInterval
        let x: Double
        let share: Double
    }

    /// Show elapsed time in minutes for longer events, seconds for short ones.
    private var useMinutes: Bool { session.duration >= 120 }
    private var xAxisLabel: String { useMinutes ? "Elapsed (min)" : "Elapsed (s)" }

    private var points: [SharePoint] {
        session.buckets.compactMap { bucket in
            bucket.userShare.map {
                SharePoint(
                    id: bucket.startOffset,
                    x: useMinutes ? bucket.startOffset / 60 : bucket.startOffset,
                    share: $0 * 100
                )
            }
        }
    }

    private var percentageColor: Color {
        switch session.userPercentage {
        case ...40: return .green
        case ...55: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let coordinate = session.coordinate {
                    map(coordinate)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your speaking share over time")
                        .font(.headline)
                    Text("How much of the speaking was yours as the event went on. 50% is an even split.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    chart
                }

                stats
            }
            .padding()
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                Text(session.date.formatted(date: .complete, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let place = session.placeName {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            Text("No speech was recorded during this event.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 120)
        } else {
            Chart {
                RuleMark(y: .value("Even split", 50))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                ForEach(points) { point in
                    AreaMark(
                        x: .value(xAxisLabel, point.x),
                        y: .value("Your share %", point.share)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value(xAxisLabel, point.x),
                        y: .value("Your share %", point.share)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                    .symbol(.circle)
                    .symbolSize(points.count <= 30 ? 24 : 0)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("Your share (%)")
            .chartXAxisLabel(xAxisLabel)
            .frame(height: 220)
        }
    }

    private var stats: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatTile(title: "You spoke", value: String(format: "%.0fs", session.userSeconds))
                StatTile(title: "Others spoke", value: String(format: "%.0fs", session.totalSpeechSeconds - session.userSeconds))
                StatTile(title: "Your share", value: "\(Int(session.userPercentage.rounded()))%")
            }
            Text("You spoke \(Int(session.userPercentage.rounded()))% of the speaking time.")
                .font(.caption)
                .foregroundStyle(percentageColor)
        }
    }

    private func map(_ coordinate: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        ))) {
            Marker(session.placeName ?? session.title, coordinate: coordinate)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}

private extension Session {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
