import Foundation

/// MFCC feature extraction.
///
/// Numerical port of `voice_matcher.extract_mfcc` from the Python app:
/// 512-sample frames with a 256-sample hop, Hamming window, power spectrum,
/// 26-filter mel bank, then a cosine transform down to `numMFCC`
/// coefficients. Voice profiles are shared between the two implementations,
/// so any change here must stay in lockstep with the Python code.
public enum MFCC {
    public static let defaultFrameSize = 512
    public static let defaultHopSize = 256
    static let numMelFilters = 26

    /// Extract MFCC features. Returns `numFrames x numMFCC`.
    public static func extract(
        _ audio: [Double],
        sampleRate: Int = 16000,
        numMFCC: Int = 13,
        frameSize: Int = defaultFrameSize,
        hopSize: Int = defaultHopSize
    ) -> [[Double]] {
        var samples = audio

        var numFrames: Int
        if samples.count >= frameSize {
            numFrames = 1 + (samples.count - frameSize) / hopSize
        } else {
            // Pad short audio to a single frame, matching the Python code.
            samples.append(contentsOf: [Double](repeating: 0, count: frameSize - samples.count))
            numFrames = 1
        }

        let window = hammingWindow(frameSize)
        let filterbank = melFilterbank(numFilters: numMelFilters, fftSize: frameSize, sampleRate: sampleRate)
        let dct = dctMatrix(numMFCC: numMFCC, numFilters: numMelFilters)
        let numBins = frameSize / 2 + 1

        var mfcc = [[Double]](repeating: [Double](repeating: 0, count: numMFCC), count: numFrames)
        var real = [Double](repeating: 0, count: frameSize)
        var imag = [Double](repeating: 0, count: frameSize)
        var power = [Double](repeating: 0, count: numBins)
        var melLog = [Double](repeating: 0, count: numMelFilters)

        for frame in 0..<numFrames {
            let start = frame * hopSize
            for i in 0..<frameSize {
                real[i] = samples[start + i] * window[i]
                imag[i] = 0
            }
            FFT.forward(real: &real, imag: &imag)
            for k in 0..<numBins {
                power[k] = real[k] * real[k] + imag[k] * imag[k]
            }

            for f in 0..<numMelFilters {
                var sum = 0.0
                for k in 0..<numBins {
                    sum += power[k] * filterbank[f][k]
                }
                // Same zero guard as the Python implementation.
                melLog[f] = log(sum == 0 ? 1e-10 : sum)
            }

            for i in 0..<numMFCC {
                var sum = 0.0
                for f in 0..<numMelFilters {
                    sum += melLog[f] * dct[i][f]
                }
                mfcc[frame][i] = sum
            }
        }

        return mfcc
    }

    static func hzToMel(_ hz: Double) -> Double {
        2595 * log10(1 + hz / 700)
    }

    static func melToHz(_ mel: Double) -> Double {
        700 * (pow(10, mel / 2595) - 1)
    }

    /// `numpy.hamming`: symmetric window with denominator N-1.
    static func hammingWindow(_ size: Int) -> [Double] {
        guard size > 1 else { return [Double](repeating: 1, count: size) }
        return (0..<size).map { n in
            0.54 - 0.46 * cos(2 * Double.pi * Double(n) / Double(size - 1))
        }
    }

    /// Triangular mel filterbank, `numFilters x (fftSize/2 + 1)`.
    static func melFilterbank(numFilters: Int, fftSize: Int, sampleRate: Int) -> [[Double]] {
        let highMel = hzToMel(Double(sampleRate) / 2)
        let melPoints = (0..<(numFilters + 2)).map { i in
            highMel * Double(i) / Double(numFilters + 1)
        }
        let binPoints = melPoints.map { mel in
            Int(floor(Double(fftSize + 1) * melToHz(mel) / Double(sampleRate)))
        }

        var filterbank = [[Double]](
            repeating: [Double](repeating: 0, count: fftSize / 2 + 1),
            count: numFilters
        )
        for i in 0..<numFilters {
            let left = binPoints[i]
            let center = binPoints[i + 1]
            let right = binPoints[i + 2]
            for j in left..<center {
                filterbank[i][j] = Double(j - left) / Double(center - left)
            }
            for j in center..<right {
                filterbank[i][j] = Double(right - j) / Double(right - center)
            }
        }
        return filterbank
    }

    /// Non-orthonormal DCT-II matrix as used by the Python implementation:
    /// `dct[i][j] = cos(pi * i * (j + 0.5) / numFilters)`.
    static func dctMatrix(numMFCC: Int, numFilters: Int) -> [[Double]] {
        (0..<numMFCC).map { i in
            (0..<numFilters).map { j in
                cos(Double.pi * Double(i) * (Double(j) + 0.5) / Double(numFilters))
            }
        }
    }
}
