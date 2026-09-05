import XCTest
@testable import GonaviCore

final class TranscriptionTests: XCTestCase {
    private func decode(_ json: String, offset: Double = 0, limit: Double = 10) throws -> [Caption] {
        try WhisperTranscript.captions(from: Data(json.utf8), offset: .init(seconds: offset), limit: .init(seconds: limit))
    }
    func testTurkishAndSourceOffsetClamping() throws {
        let captions = try decode(#"{"transcription":[{"text":" İstanbul’da ışık, çığ ve %25!","offsets":{"from":1500,"to":8000}}]}"#, offset: 12, limit: 4)
        XCTAssertEqual(captions.first?.text, "İstanbul’da ışık, çığ ve %25!")
        XCTAssertEqual(captions.first?.start.seconds, 13.5)
        XCTAssertEqual(captions.first?.duration.seconds, 2.5)
    }
    func testEmptyAndSpecialTokens() throws {
        XCTAssertTrue(try decode(#"{"transcription":[]}"#).isEmpty)
        XCTAssertTrue(try decode(#"{"transcription":[{"text":" [_BEG_] <|endoftext|> ","offsets":{"from":0,"to":1000}}]}"#).isEmpty)
    }
    func testMalformedAndNegativeTimingRejected() {
        XCTAssertThrowsError(try decode("{}"))
        XCTAssertThrowsError(try decode(#"{"transcription":[{"text":"bad","offsets":{"from":-1,"to":1000}}]}"#))
        XCTAssertThrowsError(try decode(#"{"transcription":[{"text":"bad","offsets":{"from":0,"to":1e30}}]}"#))
    }
    func testOrderingAndOverlapBoundaries() throws {
        let captions = try decode(#"{"transcription":[{"text":"ikinci","offsets":{"from":900,"to":2000}},{"text":"ilk","offsets":{"from":0,"to":1000}},{"text":"dışarı","offsets":{"from":10000,"to":11000}}]}"#)
        XCTAssertEqual(captions.map(\.text), ["ilk", "ikinci"])
        XCTAssertEqual(captions[1].start.seconds, 1)
        XCTAssertEqual(captions[1].duration.seconds, 1)
    }
    func testLongTextKeepsAllWordsWithinTime() throws {
        let text = Array(repeating: "Türkçe konuşmayı düzenleyelim.", count: 12).joined(separator: " ")
        let data = try JSONSerialization.data(withJSONObject: ["transcription": [["text": text, "offsets": ["from": 0, "to": 10000]]]])
        let captions = try WhisperTranscript.captions(from: data, limit: .init(seconds: 10))
        XCTAssertEqual(captions.map(\.text).joined(separator: " "), text)
        XCTAssertTrue(captions.allSatisfy { $0.text.count <= 80 && $0.duration > .zero })
        XCTAssertEqual(captions.last!.start + captions.last!.duration, .init(seconds: 10))
    }
}
