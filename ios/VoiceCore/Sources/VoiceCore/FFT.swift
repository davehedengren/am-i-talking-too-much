import Foundation

/// In-place iterative radix-2 Cooley-Tukey FFT.
///
/// Pure Swift so results are bit-stable across platforms and unit-testable
/// off-device. Twiddle factors are precomputed once per transform size and
/// reused across frames — during tracking the app runs ~124 transforms per
/// 2-second chunk, so recomputing sines per butterfly would be the largest
/// avoidable cost in the audio hot path.
enum FFT {
    /// Precomputed twiddle factors w^k = exp(-2πik/n) for k in 0..<n/2.
    struct Twiddles {
        let size: Int
        let real: [Double]
        let imag: [Double]

        init(size: Int) {
            precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two")
            self.size = size
            var real = [Double]()
            var imag = [Double]()
            real.reserveCapacity(size / 2)
            imag.reserveCapacity(size / 2)
            for k in 0..<(size / 2) {
                let angle = -2.0 * Double.pi * Double(k) / Double(size)
                real.append(cos(angle))
                imag.append(sin(angle))
            }
            self.real = real
            self.imag = imag
        }
    }

    /// Forward complex FFT using precomputed twiddles.
    /// `real.count` must equal `imag.count` and `twiddles.size`.
    static func forward(real: inout [Double], imag: inout [Double], twiddles: Twiddles) {
        let n = real.count
        precondition(n == imag.count, "real/imag length mismatch")
        precondition(n == twiddles.size, "twiddle table size mismatch")

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

        // Butterflies. A stage of length L uses every (n/L)-th twiddle.
        var length = 2
        while length <= n {
            let half = length / 2
            let twiddleStride = n / length
            for start in stride(from: 0, to: n, by: length) {
                for k in 0..<half {
                    let w = k * twiddleStride
                    let wr = twiddles.real[w]
                    let wi = twiddles.imag[w]
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

    /// Convenience overload for one-off transforms.
    static func forward(real: inout [Double], imag: inout [Double]) {
        forward(real: &real, imag: &imag, twiddles: Twiddles(size: real.count))
    }
}
