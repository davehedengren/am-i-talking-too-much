import Foundation

/// Rolling estimate of the room's ambient noise level, used to gate "is anyone
/// speaking" adaptively instead of at a fixed RMS.
///
/// Why: the audio session runs in `.measurement` mode (no automatic gain
/// control), so absolute mic levels vary hugely with device, distance, and
/// venue — a fixed gate tuned on one setup reads a quiet room's speech as
/// silence and a loud venue's music as speech. The floor tracks the quietest
/// recent chunks: it drops immediately when a quieter chunk arrives and creeps
/// back up slowly (≈5% per 2 s chunk), so pauses in conversation keep it
/// anchored to the true ambient level.
///
/// Pure value type — no side effects — so it can be exercised standalone.
struct NoiseFloor {
    /// Speech must exceed the floor by this factor to count as speech.
    static let speechFactor = 2.5
    /// Gate never drops below this, so electrical noise can't read as speech.
    static let minimumGate = 0.0015
    /// Floor clamps, keeping the gate sane in dead silence and sustained noise.
    static let floorRange = 0.0002...0.02

    /// Start low: fail toward detecting speech, and climb only if the room is
    /// genuinely loud.
    private(set) var floor = 0.0005

    /// Current "someone is speaking" RMS gate.
    var speechGate: Double { max(Self.minimumGate, floor * Self.speechFactor) }

    /// Feed every chunk's RMS, speech or not.
    mutating func update(rms: Double) {
        if rms < floor {
            floor = max(rms, Self.floorRange.lowerBound)
        } else {
            floor = min(floor * 1.05, Self.floorRange.upperBound)
        }
    }
}
