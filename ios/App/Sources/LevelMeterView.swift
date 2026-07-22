import SwiftUI

/// Live microphone level bar (0–1), like the Streamlit level meter.
struct LevelMeterView: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.elevated)
                Capsule()
                    .fill(level > 0.85 ? Theme.coral : Theme.you)
                    .frame(width: max(geometry.size.width * level, 6))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
