import Foundation

/// In-place iterative radix-2 Cooley-Tukey FFT.
///
/// Pure Swift so results are bit-stable across platforms and unit-testable
/// off-device. At the app's workload (512-point transforms over 16 kHz
/// audio) this is far from being a bottleneck.
enum FFT {
    /// Forward complex FFT. `real.count` must be a power of two and
    /// `imag.count` must equal `real.count`.
    static func forward(real: inout [Double], imag: inout [Double]) {
        let n = real.count
        precondition(n == imag.count, "real/imag length mismatch")
        precondition(n > 0 && (n & (n - 1)) == 0, "FFT size must be a power of two")

        // Bit-reversal permutation.
        var j = 0
        for i in 0..<(n - 1) {
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
            var mask = n >> 1
            while j & mask != 0 {
                j &= ~mask
                mask >>= 1
            }
            j |= mask
        }

        // Butterflies.
        var length = 2
        while length <= n {
            let half = length / 2
            let angleStep = -2.0 * Double.pi / Double(length)
            for start in stride(from: 0, to: n, by: length) {
                for k in 0..<half {
                    let angle = angleStep * Double(k)
                    let wr = cos(angle)
                    let wi = sin(angle)
                    let evenIndex = start + k
                    let oddIndex = start + k + half
                    let tr = wr * real[oddIndex] - wi * imag[oddIndex]
                    let ti = wr * imag[oddIndex] + wi * real[oddIndex]
                    real[oddIndex] = real[evenIndex] - tr
                    imag[oddIndex] = imag[evenIndex] - ti
                    real[evenIndex] += tr
                    imag[evenIndex] += ti
                }
            }
            length <<= 1
        }
    }
}
