import XCTest
@testable import GonaviCore

final class AudioPeaksTests: XCTestCase {
    func testSilenceQuietAndLoudRetainSharedScale() throws {
        var accumulator = try AudioPeakAccumulator(duration: 3, sampleRate: 100, bucketsPerSecond: 10)
        let samples = Array(repeating: Float(0), count: 100) + Array(repeating: Float(0.05), count: 100) + Array(repeating: Float(-0.8), count: 100)
        try samples.withUnsafeBufferPointer { try accumulator.append($0, at: 0) }
        let waveform = try accumulator.finish()
        XCTAssertEqual(waveform.level(in: 0..<1), .silence)
        XCTAssertEqual(waveform.level(in: 1..<2).peak, 0.05, accuracy: 0.001)
        XCTAssertEqual(waveform.level(in: 2..<3).rms, 0.8, accuracy: 0.001)
        XCTAssertEqual(waveform.level(in: 0..<3).peak, 0.8, accuracy: 0.001)
    }
    func testTimestampGapAndDuplicateBuffers() throws {
        var accumulator = try AudioPeakAccumulator(duration: 2, sampleRate: 100, bucketsPerSecond: 10)
        let data = Array(repeating: Float(0.5), count: 50)
        try data.withUnsafeBufferPointer { try accumulator.append($0, at: 1) }
        try data.withUnsafeBufferPointer { try accumulator.append($0, at: 1) }
        let waveform = try accumulator.finish()
        XCTAssertEqual(waveform.level(in: 0..<1), .silence)
        XCTAssertEqual(waveform.level(in: 1..<1.5).rms, 0.5, accuracy: 0.001)
        XCTAssertEqual(waveform.level(in: 1.5..<2), .silence)
        let restored = try JSONDecoder().decode(WaveformData.self, from: JSONEncoder().encode(waveform))
        XCTAssertEqual(restored.level(in: 0..<2), waveform.level(in: 0..<2))
    }
    func testSummaryPreservesShortLoudTransient() throws {
        var values = Array(repeating: Float(0), count: 100_000)
        values[33333] = 0.95
        let waveform = try WaveformData(bucketDuration: 0.01, duration: 1000, peaks: values, rms: values)
        XCTAssertEqual(waveform.level(in: 0..<1000).peak, 0.95)
        XCTAssertEqual(waveform.level(in: 0..<300), .silence)
        XCTAssertThrowsError(try WaveformData(bucketDuration: 0.01, duration: 1, peaks: [1], rms: [1]))
    }
}
