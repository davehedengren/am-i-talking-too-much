import SwiftUI

/// The "quiet instrument" design system — dark-first, seeded from the app
/// icon (teal → indigo field, warm cream speech bubble). The app lives on
/// dinner tables: surfaces stay deep and discreet, and the two speakers get
/// the identity duotone — your voice is candlelight gold, everyone else is
/// tide teal. Feedback bands are coach-calm, not traffic-light loud.
enum Theme {
    // MARK: Surfaces
    static let bg = Color(hex: 0x0E1220)
    static let elevated = Color(hex: 0x171C2E)
    static let line = Color.white.opacity(0.08)

    // MARK: Ink
    static let text = Color(hex: 0xECEFF7)
    static let muted = Color(hex: 0x8B93A8)

    // MARK: The duotone
    /// You — candlelight gold (the icon's speech bubble, warmed).
    static let you = Color(hex: 0xE9C46A)
    /// Everyone else — tide teal (the icon's field).
    static let others = Color(hex: 0x4E9F9B)

    // MARK: Feedback bands (coach, not smoke detector)
    static let tranquil = Color(hex: 0x58B896)   // under 40% — great listening
    static let sand = Color(hex: 0xD9B36A)       // 40–55% — balanced
    static let coral = Color(hex: 0xE0685C)      // over 55% — lots of airtime

    static func band(for percentage: Double) -> Color {
        switch percentage {
        case ...40: return tranquil
        case ...55: return sand
        default: return coral
        }
    }

    // MARK: Type
    /// Metrics speak SF Rounded; everything else is quiet SF Pro.
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Primary action: a candlelight capsule with dark ink.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.bg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.you, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Secondary action: quiet elevated capsule.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
