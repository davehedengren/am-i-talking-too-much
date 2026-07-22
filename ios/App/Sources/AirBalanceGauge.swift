import SwiftUI

/// The app's signature element: a circular dial where your share of the
/// conversation fills in candlelight gold against everyone else's tide teal.
/// Tick marks sit at the 40% and 55% band boundaries. While listening, a halo
/// behind the dial breathes with the live microphone level — the app visibly
/// paying attention, calmly.
struct AirBalanceGauge: View {
    let percentage: Double            // 0–100, your share of speaking time
    let hasSpeech: Bool               // false until anyone has spoken
    /// Present only while listening; drives the breathing halo in an isolated
    /// subview so ~10 Hz level updates never re-render the dial.
    var liveLevel: TrackerViewModel.LiveLevel?

    private var fraction: Double { min(max(percentage / 100, 0), 1) }
    private var bandColor: Color { Theme.band(for: percentage) }

    var body: some View {
        ZStack {
            if let liveLevel {
                BreathingHalo(level: liveLevel)
            }

            // Track + the two shares.
            Circle()
                .stroke(Theme.elevated, lineWidth: 14)
            Circle()
                .trim(from: fraction, to: 1)
                .stroke(Theme.others.opacity(hasSpeech ? 0.85 : 0.25),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.you,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: fraction)

            tick(at: 0.40)
            tick(at: 0.55)

            VStack(spacing: 2) {
                if hasSpeech {
                    Text("\(Int(percentage.rounded()))%")
                        .font(Theme.metric(52, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(bandColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: Int(percentage.rounded()))
                } else {
                    Text("—")
                        .font(Theme.metric(52, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                Text("your airtime")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 230, height: 230)
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your share of speaking time")
        .accessibilityValue(hasSpeech ? "\(Int(percentage.rounded())) percent" : "No speech yet")
    }

    /// A thin radial tick at a band boundary.
    private func tick(at fraction: Double) -> some View {
        Capsule()
            .fill(Theme.bg)
            .frame(width: 3, height: 18)
            .offset(y: -115)
            .rotationEffect(.degrees(fraction * 360))
    }
}

/// Observes only the live level so the ~10 Hz mic updates re-render just this
/// glow, never the dial or the screen. Breathes unless Reduce Motion is on.
private struct BreathingHalo: View {
    @ObservedObject var level: TrackerViewModel.LiveLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.you.opacity(0.28), Theme.you.opacity(0)],
                    center: .center, startRadius: 60, endRadius: 160
                )
            )
            .scaleEffect(reduceMotion ? 1.08 : 1 + level.value * 0.18)
            .opacity(0.5 + level.value * 0.5)
            .animation(.easeOut(duration: 0.12), value: level.value)
    }
}
