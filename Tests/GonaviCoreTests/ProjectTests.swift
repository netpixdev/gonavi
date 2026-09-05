import XCTest
@testable import GonaviCore

final class ProjectTests: XCTestCase {
    func fixture() -> Project {
        var p = Project()
        let source = MediaSource(name: "test.mov", path: "/test.mov", duration: .init(seconds: 10), isVideo: true)
        p.sources = [source]; p.clips = [VideoClip(sourceID: source.id, duration: source.duration)]
        return p
    }
    func testSplitPreservesDurationAndSourceRange() throws {
        var p = fixture(); let original = p.clips[0]
        try p.split(original.id, at: .init(seconds: 3))
        XCTAssertEqual(p.duration, .init(seconds: 10))
        XCTAssertEqual(p.clips[1].sourceStart, .init(seconds: 3))
        XCTAssertEqual(p.clips[1].duration, .init(seconds: 7))
        XCTAssertNotEqual(p.clips[0].id, p.clips[1].id)
        try p.validate()
    }
    func testSplitRejectsEndpoints() {
        var p = fixture()
        XCTAssertThrowsError(try p.split(p.clips[0].id, at: .zero))
        XCTAssertThrowsError(try p.split(p.clips[0].id, at: .init(seconds: 10)))
        XCTAssertEqual(p.clips.count, 1)
    }
    func testRippleMapsCaptionsAndKeepsMusic() throws {
        var p = fixture()
        try p.split(p.clips[0].id, at: .init(seconds: 3))
        p.music = .init(sourceID: p.sources[0].id)
        p.captions = [Caption(start: .init(seconds: 1), duration: .init(seconds: 4), text: "Merhaba"),
                      Caption(start: .zero, duration: .init(seconds: 2), text: "Sil"),
                      Caption(start: .init(seconds: 7), duration: .init(seconds: 2), text: "Kaydır")]
        p.remove(p.clips[0].id)
        XCTAssertEqual(p.duration.seconds, 7)
        XCTAssertEqual(p.captions.count, 2)
        XCTAssertEqual(p.captions[0].start, .zero)
        XCTAssertEqual(p.captions[0].duration.seconds, 2)
        XCTAssertEqual(p.captions[1].start.seconds, 4)
        XCTAssertNotNil(p.music)
        try p.validate()
    }
    func testProjectRoundTrip() throws {
        let p = fixture()
        XCTAssertEqual(try Project.decode(p.encoded()), p)
    }
    func testRejectsFutureSchemaAndInvalidRange() throws {
        var p = fixture(); p.schemaVersion = 2
        XCTAssertThrowsError(try p.encoded())
        p.schemaVersion = 1; p.clips[0].sourceStart = .init(seconds: 9)
        XCTAssertThrowsError(try p.validate())
    }
    func testNTSCFramesDoNotDrift() {
        let frame = EditTime(ticks: 2002)
        let hour = (0..<107892).reduce(EditTime.zero) { time, _ in time + frame }
        XCTAssertEqual(hour.ticks, 215999784)
    }
    func testSRTFormattingAndOrdering() {
        var p = fixture()
        p.captions = [Caption(start: .init(seconds: 2.125), duration: .init(seconds: 1.25), text: "İstanbul")]
        XCTAssertEqual(p.srt(), "1\n00:00:02,125 --> 00:00:03,375\nİstanbul\n")
    }
    func testAllSceneDimensionsAreEven() {
        for preset in ScenePreset.allCases {
            XCTAssertEqual(preset.width % 2, 0); XCTAssertEqual(preset.height % 2, 0)
        }
    }
}
