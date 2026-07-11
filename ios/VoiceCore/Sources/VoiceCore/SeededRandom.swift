import Foundation

/// SplitMix64 PRNG. Used instead of `SystemRandomNumberGenerator` so GMM
/// training is deterministic for a given seed (mirrors the Python app's
/// `random_state=42`).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform integer in 0..<upperBound.
    mutating func nextInt(_ upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }
}
