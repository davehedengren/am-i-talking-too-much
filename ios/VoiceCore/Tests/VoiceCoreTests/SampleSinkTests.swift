import XCTest
@testable import VoiceCore

final class SampleSinkTests: XCTestCase {
    func testNotCollectingBuffersNothing() {
        let sink = SampleSink()
        XCTAssertFalse(sink.isCollecting)
        XCTAssertEqual(sink.ingest([1, 2, 3]), 0)
        XCTAssertNil(sink.drain(1))
        XCTAssertTrue(sink.takeAll().isEmpty)
    }

    func testCollectingAccumulatesAndDrainsInOrder() {
        let sink = SampleSink()
        sink.setCollecting(true)
        XCTAssertTrue(sink.isCollecting)
        XCTAssertEqual(sink.ingest([1, 2, 3]), 3)
        XCTAssertEqual(sink.ingest([4]), 4)

        XCTAssertEqual(sink.drain(2), [1, 2])
        XCTAssertNil(sink.drain(3), "only 2 samples left")
        XCTAssertEqual(sink.takeAll(), [3, 4])
        XCTAssertTrue(sink.takeAll().isEmpty)
    }

    func testStartCollectingClearsPreviousSamples() {
        let sink = SampleSink()
        sink.setCollecting(true)
        sink.ingest([1, 2, 3])
        sink.setCollecting(true)
        XCTAssertEqual(sink.ingest([]), 0)
    }

    func testStopCollectingKeepsBufferedSamples() {
        let sink = SampleSink()
        sink.setCollecting(true)
        sink.ingest([1, 2])
        sink.setCollecting(false)
        // Already-captured samples stay drainable (calibration takes them
        // after stopping collection).
        XCTAssertEqual(sink.takeAll(), [1, 2])
    }

    func testDrainZeroOrNegativeReturnsNil() {
        let sink = SampleSink()
        sink.setCollecting(true)
        sink.ingest([1])
        XCTAssertNil(sink.drain(0))
        XCTAssertEqual(sink.drain(1), [1])
    }

    func testConcurrentIngestLosesNothing() {
        let sink = SampleSink()
        sink.setCollecting(true)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            sink.ingest([0.25, 0.75])
        }
        XCTAssertEqual(sink.takeAll().count, 200)
    }
}
