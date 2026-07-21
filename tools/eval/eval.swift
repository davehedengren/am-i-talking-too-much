import Foundation

// Ground-truth evaluation harness.
//
// Replays a labeled recording (from the app's Ground Truth Recorder) through
// the exact tracking pipeline — NoiseFloor gate + whole-chunk GMM and neural
// matching — and scores every variant against the labels. Enrollment is taken
// from the first long contiguous "me" segment and excluded from scoring.
//
// Build & run: tools/eval/run.sh <audio.wav> <labels.json>
// (compiled together with the VoiceCore + app sources; see run.sh)

@main
struct Eval {
    static let chunkSeconds = 2.0
    static let sampleRate = 16000
    static let chunkSamples = Int(chunkSeconds) * sampleRate
    /// A chunk counts toward metrics only if one label covers ≥ this fraction.
    static let purityFloor = 0.7
    static let enrollSeconds = 10.0

    // MARK: - Label handling

    struct LabelEvent: Codable { let time: Double; let label: String }
    struct Metadata: Codable {
        let durationSeconds: Double
        let events: [LabelEvent]
        let sampleRate: Int
    }

    struct Segment { let start: Double; let end: Double; let label: String }

    struct Chunk {
        let index: Int
        let start: Double
        let truth: String        // dominant label
        let purity: Double
        let excluded: Bool       // enrollment overlap / low purity / unsure
        let rms: Double
        let gate: Double
        var gmmScore: Double?    // avg log-likelihood (nil if gated quiet)
        var neuralSim: Double?   // cosine similarity  (nil if gated or embed fail)
    }

    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            print("usage: eval <audio.wav> <labels.json>")
            exit(1)
        }

        // ---- Load audio + labels ----
        let audio = loadWAV(args[1])
        let meta = loadLabels(args[2])
        let segments = makeSegments(meta)
        print("Audio: \(String(format: "%.1f", Double(audio.count) / Double(sampleRate))) s, \(audio.count) samples")
        printTruthSummary(segments)

        // ---- Enrollment from the first long contiguous "me" segment ----
        guard let enrollSegment = segments.first(where: { $0.label == "me" && $0.end - $0.start >= enrollSeconds + 1 }) else {
            print("ERROR: no contiguous 'me' segment of \(enrollSeconds + 1)+ s to enroll from")
            exit(1)
        }
        let enrollStart = enrollSegment.start + 0.5
        let enrollEnd = enrollStart + enrollSeconds
        let enrollAudio = Array(audio[Int(enrollStart * Double(sampleRate))..<Int(enrollEnd * Double(sampleRate))])
        print(String(format: "\nEnrollment: me segment %.1f–%.1f s (excluded from scoring)", enrollStart, enrollEnd))

        let gmmProfile = VoiceMatcher.createProfile(enrollAudio)
        print(String(format: "GMM profile: threshold %.2f", gmmProfile.thresholdScore))
        let neuralProfile = try? await NeuralVoiceEnroller.enroll(enrollAudio)
        if let neuralProfile {
            print(String(format: "Neural profile: threshold %.4f, dim %d", neuralProfile.threshold, neuralProfile.dimension))
        } else {
            print("Neural enrollment FAILED — neural columns will be empty")
        }

        // ---- Replay the pipeline over every chunk ----
        var noiseFloor = NoiseFloor()
        var chunks: [Chunk] = []
        var index = 0
        var offset = 0
        while offset + chunkSamples <= audio.count {
            let chunk = Array(audio[offset..<(offset + chunkSamples)])
            let start = Double(offset) / Double(sampleRate)
            noiseFloor.update(quietestFrameRMS: VoicedTrim.quietestFrameRMS(chunk))
            let gate = noiseFloor.speechGate
            let rms = VoiceMatcher.rms(chunk)

            let (truth, purity) = dominantLabel(segments, start: start, end: start + chunkSeconds)
            let overlapsEnroll = start < enrollEnd && start + chunkSeconds > enrollStart
            let excluded = overlapsEnroll || truth == "unsure" || purity < purityFloor

            var c = Chunk(index: index, start: start, truth: truth, purity: purity,
                          excluded: excluded, rms: rms, gate: gate, gmmScore: nil, neuralSim: nil)
            if rms > gate {
                c.gmmScore = VoiceMatcher.matchScore(chunk, profile: gmmProfile, gateRMS: 0)
                if let neuralProfile,
                   let embedding = try? await NeuralVoiceEmbedder.embedding(chunk),
                   embedding.count == neuralProfile.centroid.count {
                    c.neuralSim = Double(NeuralVoiceEmbedder.dot(embedding, neuralProfile.centroid))
                }
            }
            chunks.append(c)
            index += 1
            offset += chunkSamples
        }

        let included = chunks.filter { !$0.excluded }
        let boundary = chunks.filter { $0.purity < purityFloor && $0.truth != "unsure" }.count
        print("\nChunks: \(chunks.count) total, \(included.count) scored, \(chunks.count - included.count) excluded (\(boundary) boundary, rest enrollment/unsure)")

        // ---- Score distributions (the ground truth about separability) ----
        printDistributions(included)

        // ---- Variant evaluations ----
        print("\n================ VARIANTS ================")
        evaluate("GMM @ calibrated threshold", included,
                 decide: { $0.gmmScore.map { s in s > gmmProfile.thresholdScore } })
        if neuralProfile != nil {
            evaluate("Neural @ calibrated threshold", included,
                     decide: { $0.neuralSim.map { s in s > Double(neuralProfile!.threshold) } })
        }

        // Threshold sweeps: find the balanced-accuracy-optimal threshold.
        if let best = sweep(included, scores: { $0.gmmScore }) {
            print(String(format: "\nGMM sweep: best threshold %.2f (calibrated %.2f, offset %+.2f)",
                         best, gmmProfile.thresholdScore, best - gmmProfile.thresholdScore))
            evaluate("GMM @ swept threshold", included,
                     decide: { $0.gmmScore.map { s in s > best } })
            evaluateSmoothed("GMM @ swept + median-3", chunks, includedOnly: included,
                             decide: { $0.gmmScore.map { s in s > best } })
        }
        if neuralProfile != nil, let best = sweep(included, scores: { $0.neuralSim }) {
            print(String(format: "\nNeural sweep: best threshold %.4f (calibrated %.4f, offset %+.4f)",
                         best, Double(neuralProfile!.threshold), best - Double(neuralProfile!.threshold)))
            evaluate("Neural @ swept threshold", included,
                     decide: { $0.neuralSim.map { s in s > best } })
            evaluateSmoothed("Neural @ swept + median-3", chunks, includedOnly: included,
                             decide: { $0.neuralSim.map { s in s > best } })
        }

        // Smoothing on the calibrated thresholds too.
        evaluateSmoothed("GMM @ calibrated + median-3", chunks, includedOnly: included,
                         decide: { $0.gmmScore.map { s in s > gmmProfile.thresholdScore } })
        if neuralProfile != nil {
            evaluateSmoothed("Neural @ calibrated + median-3", chunks, includedOnly: included,
                             decide: { $0.neuralSim.map { s in s > Double(neuralProfile!.threshold) } })
        }

        // Share-honest thresholds: optimize the product metric directly.
        if let t = sweepForShare(included, scores: { $0.gmmScore }) {
            print(String(format: "\nGMM share-honest threshold %.2f (calibrated %.2f)", t, gmmProfile.thresholdScore))
            evaluate("GMM @ share-honest threshold", included,
                     decide: { $0.gmmScore.map { s in s > t } })
        }
        if neuralProfile != nil, let t = sweepForShare(included, scores: { $0.neuralSim }) {
            print(String(format: "\nNeural share-honest threshold %.4f (calibrated %.4f)", t, Double(neuralProfile!.threshold)))
            evaluate("Neural @ share-honest threshold", included,
                     decide: { $0.neuralSim.map { s in s > t } })
        }
    }

    // MARK: - Evaluation

    /// decide: nil = chunk was gated quiet (or unscoreable); true = "you".
    static func evaluate(_ name: String, _ included: [Chunk], decide: (Chunk) -> Bool?) {
        report(name, rows: included.map { ($0, decide($0)) })
    }

    /// Median-of-3 over the chronological speech-decision sequence (quiet
    /// chunks pass through), then metrics on the included subset.
    static func evaluateSmoothed(_ name: String, _ all: [Chunk], includedOnly: [Chunk], decide: (Chunk) -> Bool?) {
        let raw: [(Chunk, Bool?)] = all.map { ($0, decide($0)) }
        let speechIdx = raw.indices.filter { raw[$0].1 != nil }
        var smoothed = raw
        for (position, i) in speechIdx.enumerated() {
            let window = [position - 1, position, position + 1]
                .compactMap { $0 >= 0 && $0 < speechIdx.count ? raw[speechIdx[$0]].1 : nil }
            let votes = window.filter { $0 }.count
            smoothed[i].1 = votes * 2 > window.count
        }
        let includedSet = Set(includedOnly.map(\.index))
        report(name, rows: smoothed.filter { includedSet.contains($0.0.index) })
    }

    static func report(_ name: String, rows: [(Chunk, Bool?)]) {
        var counts: [String: (you: Int, others: Int, quiet: Int)] = [:]
        for (chunk, decision) in rows {
            var c = counts[chunk.truth] ?? (0, 0, 0)
            switch decision {
            case .some(true): c.you += 1
            case .some(false): c.others += 1
            case .none: c.quiet += 1
            }
            counts[chunk.truth] = c
        }
        func line(_ truth: String) -> String {
            let c = counts[truth] ?? (0, 0, 0)
            let total = c.you + c.others + c.quiet
            guard total > 0 else { return "  truth \(truth): (none)" }
            return String(format: "  truth %-7@ (%2d): you %2d  others %2d  quiet %2d",
                          truth as NSString, total, c.you, c.others, c.quiet)
        }
        let me = counts["me"] ?? (0, 0, 0)
        let others = counts["others"] ?? (0, 0, 0)
        let meTotal = me.you + me.others + me.quiet
        let othersTotal = others.you + others.others + others.quiet
        let recallMe = meTotal > 0 ? Double(me.you) / Double(meTotal) : 0
        let rejectOthers = othersTotal > 0 ? Double(others.others + others.quiet) / Double(othersTotal) : 0
        let predictedYou = me.you + others.you
        let predictedSpeech = me.you + me.others + others.you + others.others
        let trueShare = meTotal + othersTotal > 0 ? Double(meTotal) / Double(meTotal + othersTotal) * 100 : 0
        let predictedShare = predictedSpeech > 0 ? Double(predictedYou) / Double(predictedSpeech) * 100 : 0

        print("\n--- \(name) ---")
        print(line("me")); print(line("others")); print(line("quiet"))
        print(String(format: "  recall(me) %.0f%%   reject(others) %.0f%%   balanced %.0f%%",
                     recallMe * 100, rejectOthers * 100, (recallMe + rejectOthers) / 2 * 100))
        print(String(format: "  predicted your share: %.0f%%   (true: %.0f%%)", predictedShare, trueShare))
    }

    /// Best threshold by |predicted share − true share| — the product metric.
    /// Errors can cancel (missed "me" vs matched "others"), so the share-honest
    /// threshold can differ from the balanced-accuracy one.
    static func sweepForShare(_ included: [Chunk], scores: (Chunk) -> Double?) -> Double? {
        let labeled: [(Double, Bool)] = included.compactMap { chunk in
            guard chunk.truth == "me" || chunk.truth == "others", let s = scores(chunk) else { return nil }
            return (s, chunk.truth == "me")
        }
        guard labeled.count >= 8 else { return nil }
        let trueShare = Double(labeled.filter(\.1).count) / Double(labeled.count)
        let sorted = labeled.map(\.0).sorted()
        var best: (threshold: Double, error: Double)? = nil
        for i in 0..<(sorted.count - 1) {
            let t = (sorted[i] + sorted[i + 1]) / 2
            let predictedShare = Double(labeled.filter { $0.0 > t }.count) / Double(labeled.count)
            let error = abs(predictedShare - trueShare)
            if best == nil || error < best!.error {
                best = (t, error)
            }
        }
        return best?.threshold
    }

    /// Best threshold by balanced accuracy over included speech chunks.
    static func sweep(_ included: [Chunk], scores: (Chunk) -> Double?) -> Double? {
        let labeled: [(Double, Bool)] = included.compactMap { chunk in
            guard chunk.truth == "me" || chunk.truth == "others", let s = scores(chunk) else { return nil }
            return (s, chunk.truth == "me")
        }
        guard labeled.count >= 8 else { return nil }
        let sorted = labeled.map(\.0).sorted()
        var best: (threshold: Double, score: Double)? = nil
        for i in 0..<(sorted.count - 1) {
            let t = (sorted[i] + sorted[i + 1]) / 2
            let me = labeled.filter(\.1)
            let others = labeled.filter { !$0.1 }
            let recall = Double(me.filter { $0.0 > t }.count) / Double(max(me.count, 1))
            let reject = Double(others.filter { $0.0 <= t }.count) / Double(max(others.count, 1))
            let balanced = (recall + reject) / 2
            if best == nil || balanced > best!.score {
                best = (t, balanced)
            }
        }
        return best?.threshold
    }

    // MARK: - Distributions

    static func printDistributions(_ included: [Chunk]) {
        func stats(_ values: [Double]) -> String {
            guard !values.isEmpty else { return "(none)" }
            let s = values.sorted()
            func pct(_ p: Double) -> Double { s[min(s.count - 1, Int(p * Double(s.count)))] }
            return String(format: "n=%2d  min %.3f  p25 %.3f  med %.3f  p75 %.3f  max %.3f",
                          s.count, s[0], pct(0.25), pct(0.5), pct(0.75), s[s.count - 1])
        }
        print("\n================ SCORE DISTRIBUTIONS ================")
        for (label, name) in [("me", "me    "), ("others", "others")] {
            let subset = included.filter { $0.truth == label }
            print("GMM ll  [\(name)]: \(stats(subset.compactMap(\.gmmScore)))")
        }
        for (label, name) in [("me", "me    "), ("others", "others")] {
            let subset = included.filter { $0.truth == label }
            print("Neural  [\(name)]: \(stats(subset.compactMap(\.neuralSim)))")
        }
        let quiet = included.filter { $0.truth == "quiet" }
        let gatedAsSpeech = quiet.filter { $0.gmmScore != nil || $0.neuralSim != nil }.count
        print("Quiet chunks scored as speech by the gate: \(gatedAsSpeech)/\(quiet.count)")
    }

    // MARK: - IO helpers

    static func loadWAV(_ path: String) -> [Double] {
        guard let data = FileManager.default.contents(atPath: path), data.count > 44 else {
            print("ERROR: cannot read \(path)"); exit(1)
        }
        let payload = data.dropFirst(44)
        var samples = [Double]()
        samples.reserveCapacity(payload.count / 2)
        payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let int16s = raw.bindMemory(to: Int16.self)
            for v in int16s { samples.append(Double(Int16(littleEndian: v)) / 32767.0) }
        }
        return samples
    }

    static func loadLabels(_ path: String) -> Metadata {
        guard let data = FileManager.default.contents(atPath: path),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data) else {
            print("ERROR: cannot parse \(path)"); exit(1)
        }
        return meta
    }

    static func makeSegments(_ meta: Metadata) -> [Segment] {
        var segments: [Segment] = []
        for (i, event) in meta.events.enumerated() {
            let end = i + 1 < meta.events.count ? meta.events[i + 1].time : meta.durationSeconds
            segments.append(Segment(start: event.time, end: end, label: event.label))
        }
        return segments
    }

    static func dominantLabel(_ segments: [Segment], start: Double, end: Double) -> (String, Double) {
        var overlap: [String: Double] = [:]
        for seg in segments {
            let o = max(0, min(end, seg.end) - max(start, seg.start))
            if o > 0 { overlap[seg.label, default: 0] += o }
        }
        guard let best = overlap.max(by: { $0.value < $1.value }) else { return ("quiet", 1) }
        return (best.key, best.value / (end - start))
    }

    static func printTruthSummary(_ segments: [Segment]) {
        var totals: [String: Double] = [:]
        for seg in segments { totals[seg.label, default: 0] += seg.end - seg.start }
        let parts = totals.sorted { $0.value > $1.value }
            .map { String(format: "%@ %.1fs", $0.key, $0.value) }
            .joined(separator: ", ")
        print("Truth totals: \(parts)")
    }
}
