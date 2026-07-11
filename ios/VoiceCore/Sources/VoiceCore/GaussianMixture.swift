import Foundation

/// Gaussian mixture model with diagonal covariance.
///
/// Scoring is an exact port of scikit-learn's `GaussianMixture.score_samples`
/// for `covariance_type='diag'`, so a profile trained by the Python app
/// scores identically here (see `GMMParityTests`). Training uses k-means++
/// initialization followed by EM, matching sklearn's algorithm (trained
/// parameters are equivalent in quality, not bit-identical).
public struct GaussianMixture {
    public let weights: [Double]            // K
    public let means: [[Double]]            // K x D
    public let covariances: [[Double]]      // K x D (diagonal)
    public let precisionsCholesky: [[Double]] // K x D, 1/sqrt(cov)

    static let regCovar = 1e-6
    static let convergenceTol = 1e-3
    static let maxIterations = 100

    public init(weights: [Double], means: [[Double]], covariances: [[Double]], precisionsCholesky: [[Double]]) {
        self.weights = weights
        self.means = means
        self.covariances = covariances
        self.precisionsCholesky = precisionsCholesky
    }

    public init(weights: [Double], means: [[Double]], covariances: [[Double]]) {
        self.init(
            weights: weights,
            means: means,
            covariances: covariances,
            precisionsCholesky: covariances.map { row in row.map { 1 / sqrt(max($0, 1e-300)) } }
        )
    }

    /// Log-likelihood of each sample under the mixture
    /// (`sklearn.GaussianMixture.score_samples`).
    public func scoreSamples(_ samples: [[Double]]) -> [Double] {
        let k = weights.count
        let logWeights = weights.map { $0 > 0 ? log($0) : -Double.infinity }
        // Per-component log-determinant term: sum_d log(precision_cholesky).
        let logDet = (0..<k).map { c in
            precisionsCholesky[c].reduce(0.0) { $0 + log($1) }
        }

        return samples.map { x in
            let d = x.count
            var weighted = [Double](repeating: 0, count: k)
            for c in 0..<k {
                var mahalanobis = 0.0
                for j in 0..<d {
                    let z = (x[j] - means[c][j]) * precisionsCholesky[c][j]
                    mahalanobis += z * z
                }
                let logProb = -0.5 * (Double(d) * log(2 * Double.pi) + mahalanobis) + logDet[c]
                weighted[c] = logProb + logWeights[c]
            }
            return logSumExp(weighted)
        }
    }

    /// Fit a diagonal-covariance GMM with EM, best of `numInits` runs
    /// (mirrors sklearn's `n_init=3, random_state=42` used by the Python app).
    public static func fit(
        _ samples: [[Double]],
        numComponents: Int,
        numInits: Int = 3,
        seed: UInt64 = 42
    ) -> GaussianMixture {
        precondition(!samples.isEmpty, "cannot fit GMM on empty data")
        let k = min(numComponents, samples.count)
        var rng = SplitMix64(seed: seed)

        var best: GaussianMixture?
        var bestLowerBound = -Double.infinity
        for _ in 0..<max(1, numInits) {
            let (model, lowerBound) = fitSingle(samples, numComponents: k, rng: &rng)
            if best == nil || lowerBound > bestLowerBound {
                bestLowerBound = lowerBound
                best = model
            }
        }
        return best!
    }

    private static func fitSingle(
        _ x: [[Double]],
        numComponents k: Int,
        rng: inout SplitMix64
    ) -> (GaussianMixture, Double) {
        let n = x.count
        let d = x[0].count

        // Initialize responsibilities from hard k-means labels.
        let labels = kMeans(x, k: k, rng: &rng)
        var resp = [[Double]](repeating: [Double](repeating: 0, count: k), count: n)
        for i in 0..<n {
            resp[i][labels[i]] = 1
        }

        var (weights, means, covariances) = estimateParameters(x, resp: resp)
        var lowerBound = -Double.infinity

        for _ in 0..<maxIterations {
            // E-step: responsibilities and per-sample log-likelihood.
            let model = GaussianMixture(weights: weights, means: means, covariances: covariances)
            let logWeights = weights.map { $0 > 0 ? log($0) : -Double.infinity }
            let logDet = (0..<k).map { c in
                model.precisionsCholesky[c].reduce(0.0) { $0 + log($1) }
            }
            var totalLogProb = 0.0
            for i in 0..<n {
                var weighted = [Double](repeating: 0, count: k)
                for c in 0..<k {
                    var mahalanobis = 0.0
                    for j in 0..<d {
                        let z = (x[i][j] - means[c][j]) * model.precisionsCholesky[c][j]
                        mahalanobis += z * z
                    }
                    weighted[c] = -0.5 * (Double(d) * log(2 * Double.pi) + mahalanobis)
                        + logDet[c] + logWeights[c]
                }
                let norm = logSumExp(weighted)
                totalLogProb += norm
                for c in 0..<k {
                    resp[i][c] = exp(weighted[c] - norm)
                }
            }
            let newLowerBound = totalLogProb / Double(n)

            // M-step.
            (weights, means, covariances) = estimateParameters(x, resp: resp)

            if abs(newLowerBound - lowerBound) < convergenceTol {
                lowerBound = newLowerBound
                break
            }
            lowerBound = newLowerBound
        }

        let model = GaussianMixture(weights: weights, means: means, covariances: covariances)
        return (model, lowerBound)
    }

    private static func estimateParameters(
        _ x: [[Double]],
        resp: [[Double]]
    ) -> ([Double], [[Double]], [[Double]]) {
        let n = x.count
        let d = x[0].count
        let k = resp[0].count

        var counts = [Double](repeating: 0, count: k)
        for i in 0..<n {
            for c in 0..<k {
                counts[c] += resp[i][c]
            }
        }
        // Guard against empty components so the math stays finite; a
        // degenerate component keeps near-zero weight and drops out of the
        // mixture naturally.
        let safeCounts = counts.map { max($0, 10 * .ulpOfOne) }

        var means = [[Double]](repeating: [Double](repeating: 0, count: d), count: k)
        for i in 0..<n {
            for c in 0..<k where resp[i][c] > 0 {
                let r = resp[i][c]
                for j in 0..<d {
                    means[c][j] += r * x[i][j]
                }
            }
        }
        for c in 0..<k {
            for j in 0..<d {
                means[c][j] /= safeCounts[c]
            }
        }

        var covariances = [[Double]](repeating: [Double](repeating: 0, count: d), count: k)
        for i in 0..<n {
            for c in 0..<k where resp[i][c] > 0 {
                let r = resp[i][c]
                for j in 0..<d {
                    let diff = x[i][j] - means[c][j]
                    covariances[c][j] += r * diff * diff
                }
            }
        }
        for c in 0..<k {
            for j in 0..<d {
                covariances[c][j] = covariances[c][j] / safeCounts[c] + regCovar
            }
        }

        let weights = counts.map { $0 / Double(n) }
        return (weights, means, covariances)
    }

    /// k-means++ seeding followed by Lloyd's algorithm; returns hard labels.
    private static func kMeans(_ x: [[Double]], k: Int, rng: inout SplitMix64) -> [Int] {
        let n = x.count
        let d = x[0].count

        // k-means++ seeding.
        var centers: [[Double]] = [x[rng.nextInt(n)]]
        var minDistSq = x.map { squaredDistance($0, centers[0]) }
        while centers.count < k {
            let total = minDistSq.reduce(0, +)
            var nextIndex = 0
            if total > 0 {
                let target = rng.nextDouble() * total
                var cumulative = 0.0
                for i in 0..<n {
                    cumulative += minDistSq[i]
                    if cumulative >= target {
                        nextIndex = i
                        break
                    }
                }
            } else {
                nextIndex = rng.nextInt(n)
            }
            let center = x[nextIndex]
            centers.append(center)
            for i in 0..<n {
                minDistSq[i] = min(minDistSq[i], squaredDistance(x[i], center))
            }
        }

        // Lloyd iterations.
        var labels = [Int](repeating: 0, count: n)
        for _ in 0..<30 {
            var changed = false
            for i in 0..<n {
                var bestLabel = 0
                var bestDist = Double.infinity
                for c in 0..<k {
                    let dist = squaredDistance(x[i], centers[c])
                    if dist < bestDist {
                        bestDist = dist
                        bestLabel = c
                    }
                }
                if labels[i] != bestLabel {
                    labels[i] = bestLabel
                    changed = true
                }
            }
            if !changed {
                break
            }
            var sums = [[Double]](repeating: [Double](repeating: 0, count: d), count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in 0..<n {
                counts[labels[i]] += 1
                for j in 0..<d {
                    sums[labels[i]][j] += x[i][j]
                }
            }
            for c in 0..<k where counts[c] > 0 {
                for j in 0..<d {
                    centers[c][j] = sums[c][j] / Double(counts[c])
                }
            }
        }
        return labels
    }

    private static func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sum
    }
}

func logSumExp(_ values: [Double]) -> Double {
    guard let maxValue = values.max(), maxValue > -Double.infinity else {
        return -Double.infinity
    }
    var sum = 0.0
    for v in values {
        sum += exp(v - maxValue)
    }
    return maxValue + log(sum)
}
