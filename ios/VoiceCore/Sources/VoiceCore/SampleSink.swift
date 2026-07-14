import Foundation

/// Thread-safe sample buffer bridging an audio capture queue and
/// main-actor consumers (level meters, chunked analysis).
public final class SampleSink {
    private let lock = NSLock()
    private var buffer: [Double] = []
    private var collecting = false

    public init() {}

    /// Whether samples are currently being accumulated.
    public var isCollecting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return collecting
    }

    /// Start or stop accumulating. Starting clears any previous samples.
    public func setCollecting(_ collecting: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if collecting {
            buffer.removeAll()
        }
        self.collecting = collecting
    }

    /// Append samples if collecting; returns the current buffered count.
    @discardableResult
    public func ingest(_ samples: [Double]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if collecting {
            buffer.append(contentsOf: samples)
        }
        return buffer.count
    }

    /// Remove and return exactly `count` samples from the front, or nil if
    /// fewer are buffered.
    public func drain(_ count: Int) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0, buffer.count >= count else { return nil }
        let chunk = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return chunk
    }

    /// Remove and return everything buffered.
    public func takeAll() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let all = buffer
        buffer = []
        return all
    }
}
