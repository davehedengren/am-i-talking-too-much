import Foundation

/// Thread-safe sample buffer bridging the audio capture queue and the
/// main-actor view models.
final class SampleSink {
    private let lock = NSLock()
    private var buffer: [Double] = []
    private var isCollecting = false

    /// Start or stop accumulating. Starting clears any previous samples.
    func setCollecting(_ collecting: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if collecting {
            buffer.removeAll()
        }
        isCollecting = collecting
    }

    /// Append samples if collecting; returns the current buffered count.
    func ingest(_ samples: [Double]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if isCollecting {
            buffer.append(contentsOf: samples)
        }
        return buffer.count
    }

    /// Remove and return up to `count` samples from the front.
    func drain(_ count: Int) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.count >= count else { return nil }
        let chunk = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return chunk
    }

    /// Remove and return everything buffered.
    func takeAll() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let all = buffer
        buffer = []
        return all
    }
}
