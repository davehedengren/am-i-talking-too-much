import Foundation

/// Rolling estimate of the room's ambient noise level, used to gate "is anyone
/// speaking" adaptively instead of at a fixed RMS.
///
/// Why adaptive: the audio session runs in `.measurement` mode (no automatic
/// gain control), so absolute mic levels vary hugely with device, distance,
/// and venue — a fixed gate tuned on one setup reads a quiet room's speech as
/// silence and a loud venue's music as speech.
///
/// Why a windowed minimum (and not upward creep): the first version raised the
/// floor 5% per chunk whenever audio was louder than it, assuming pauses would
/// pull it back down. During sustained speech there are no quiet chunks, so it
/// ratcheted without bound — after ~2 min of talking, gate ≈ 0.023, above much
/// of normal speech, and the speaker's own voice started reading as silence
/// (field regression, 2026-07-20). The floor is now the minimum of the
/// quietest 100 ms frame per chunk over the last ~2 minutes: inter-word gaps
/// anchor it even mid-monologue, it cannot ratchet upward while anyone is
/// pausing for breath, and it still rises (by window expiry) when a venue is
/// genuinely loud for minutes on end.
///
/// Pure value type — no side effects — so it can be exercised standalone.
struct NoiseFloor {
    /// Speech must exceed the floor by this factor to count as speech.
    static let speechFactor = 2.5
    /// Gate never drops below this, so electrical noise can't read as speech.
    static let minimumGate = 0.0015
    /// Floor never drops below this (guards against digital-zero frames).
    static let minimumFloor = 0.0002
    /// Sliding window: ~2 minutes of 2 s chunks.
    static let windowChunks = 60

    private var recentMinima: [Double] = []
    private(set) var floor = 0.0005

    /// Current "someone is speaking" RMS gate.
    var speechGate: Double { max(Self.minimumGate, floor * Self.speechFactor) }

    /// Feed the quietest 100 ms frame RMS of every chunk, speech or not —
    /// that frame is the chunk's best view of the ambient level.
    mutating func update(quietestFrameRMS rms: Double) {
        recentMinima.append(max(rms, Self.minimumFloor))
        if recentMinima.count > Self.windowChunks {
            recentMinima.removeFirst()
        }
        floor = recentMinima.min() ?? Self.minimumFloor
    }
}
