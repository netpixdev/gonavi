import XCTest
@testable import GonaviCore

final class TimelineTests: XCTestCase {
    private func media(_ seconds: Double = 10, video: Bool = true) -> MediaSource {
        MediaSource(name: video ? "video.mov" : "audio.wav", path: "/fixture", duration: EditTime(seconds: seconds), isVideo: video)
    }

    func testAudioSourcesCanBeEditedWithoutOverwritingMusic() throws {
        var project = Project()
        let video = media(), audio = media(4, video: false)
        project.sources = [video, audio]; project.music = MusicClip(sourceID: audio.id)
        let first = project.appendSourceToTimeline(source: video)
        let second = project.appendSourceToTimeline(source: audio)
        XCTAssertEqual(project.start(of: first).seconds, 0)
        XCTAssertEqual(project.start(of: second).seconds, 10)
        XCTAssertEqual(project.duration.seconds, 14)
        XCTAssertEqual(project.music?.sourceID, audio.id)
        try project.validate()
        var onlyAudio = Project()
        onlyAudio.appendSourceToTimeline(source: audio)
        try onlyAudio.validate()
        XCTAssertEqual(onlyAudio.duration.seconds, 4)
    }

    func testLegacyMusicOnlyProjectHasDuration() throws {
        var project = Project(); let audio = media(20, video: false)
        project.sources = [audio]; project.music = MusicClip(sourceID: audio.id)
        project.captions = [Caption(start: .zero, duration: EditTime(seconds: 2), text: "Ses")]
        XCTAssertEqual(project.duration.seconds, 20)
        try project.validate()
    }

    func testLegacySchemaMigrationRetainsSequentialTiming() throws {
        var old = Project(); old.schemaVersion = 1
        let source = media(); old.sources = [source]
        old.clips = [VideoClip(sourceID: source.id, duration: source.duration), VideoClip(sourceID: source.id, duration: source.duration)]
        let bytes = try JSONEncoder().encode(old)
        let raw = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(raw.contains("timelineStart"))
        let migrated = try Project.decode(bytes)
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.clips.map { $0.timelineStart?.seconds }, [0, 10])
        XCTAssertEqual(try Project.decode(migrated.encoded()), migrated)
    }

    func testMoveLeavesGapAndAvoidsOverwritingOtherClip() throws {
        var project = Project(); let source = media()
        let first = project.appendSourceToTimeline(source: source)
        let second = project.appendSourceToTimeline(source: source)
        XCTAssertEqual(project.placeClip(id: first, at: EditTime(seconds: 30)).seconds, 30)
        XCTAssertEqual(project.start(of: second).seconds, 10)
        XCTAssertEqual(project.duration.seconds, 40)
        XCTAssertEqual(project.placeClip(id: first, at: EditTime(seconds: 12)).seconds, 20)
        XCTAssertEqual(project.start(of: second).seconds, 10)
        try project.validate()
    }

    func testPlacementChoosesNearestLegalGapWithEarlierTie() throws {
        var project = Project(); let source = media()
        project.appendSourceToTimeline(source: source, at: EditTime(seconds: 10))
        XCTAssertEqual(project.resolvedPlacement(at: EditTime(seconds: 8), duration: EditTime(seconds: 4)).seconds, 6)
        XCTAssertEqual(project.resolvedPlacement(at: EditTime(seconds: 14), duration: EditTime(seconds: 4)).seconds, 20)
        XCTAssertEqual(project.resolvedPlacement(at: EditTime(seconds: 13), duration: EditTime(seconds: 4)).seconds, 6)
        XCTAssertEqual(project.resolvedPlacement(at: EditTime(seconds: -20), duration: EditTime(seconds: 4)), .zero)
        project.appendSourceToTimeline(source: source, at: EditTime(seconds: 13))
        try project.validate()
    }

    func testSplitRespectsGapAndSourceOffset() throws {
        var project = Project(); let source = media()
        let id = project.appendSourceToTimeline(source: source, at: EditTime(seconds: 20))
        try project.split(id, at: EditTime(seconds: 23))
        XCTAssertEqual(project.clips.map { $0.timelineStart?.seconds }, [20, 23])
        XCTAssertEqual(project.clips.map { $0.duration.seconds }, [3, 7])
        XCTAssertEqual(project.clips[1].sourceStart.seconds, 3)
        XCTAssertEqual(project.duration.seconds, 30)
        try project.validate()
    }

    func testRipplePreservesGapsAndMapsCaptions() throws {
        var project = Project(); let source = media(5)
        let first = project.appendSourceToTimeline(source: source, at: EditTime(seconds: 10))
        let second = project.appendSourceToTimeline(source: source, at: EditTime(seconds: 20))
        project.captions = [Caption(start: EditTime(seconds: 12), duration: EditTime(seconds: 10), text: "Devam")]
        project.remove(first)
        XCTAssertEqual(project.start(of: second).seconds, 15)
        XCTAssertEqual(project.duration.seconds, 20)
        XCTAssertEqual(project.captions[0].start.seconds, 10)
        XCTAssertEqual(project.captions[0].duration.seconds, 7)
        try project.validate()
    }

    func testCrossingCaptionSplitsAndIntersectionFollowsMovedClip() throws {
        var project = Project(); let source = media(5)
        let clip = project.appendSourceToTimeline(source: source, at: EditTime(seconds: 10))
        project.appendSourceToTimeline(source: source, at: EditTime(seconds: 20))
        project.captions = [Caption(start: EditTime(seconds: 8), duration: EditTime(seconds: 9), text: "Konuşma")]
        project.placeClip(id: clip, at: EditTime(seconds: 30))
        XCTAssertEqual(project.captions.map { $0.start.seconds }, [8, 15, 30])
        XCTAssertEqual(project.captions.map { $0.duration.seconds }, [2, 2, 5])
        XCTAssertEqual(Set(project.captions.map(\.id)).count, 3)
        try project.validate()
    }

    func testProjectCanExceed24HoursAndRejectsOverlap() throws {
        var project = Project(); let source = media(86_400)
        project.appendSourceToTimeline(source: source)
        project.appendSourceToTimeline(source: source)
        XCTAssertEqual(project.duration.seconds, 172_800)
        try project.validate()
        project.clips[1].timelineStart = EditTime(seconds: 1)
        XCTAssertThrowsError(try project.validate())
        project.clips[1].timelineStart = EditTime(ticks: Int64.max)
        XCTAssertThrowsError(try project.validate())
    }

    func testSnapsBothEdgesUsingPixelThreshold() {
        let head = TimelineGeometry.snap(proposedStart: 9.94, duration: 2, candidates: [10], pixelsPerSecond: 100, fps: 30)
        XCTAssertEqual(head, SnapResult(time: 10, guide: 10))
        let tail = TimelineGeometry.snap(proposedStart: 8.04, duration: 2, candidates: [10], pixelsPerSecond: 100, fps: 30)
        XCTAssertEqual(tail, SnapResult(time: 8, guide: 10))
        let far = TimelineGeometry.snap(proposedStart: 9.9, duration: 2, candidates: [10], pixelsPerSecond: 100, fps: 30)
        XCTAssertNil(far.guide)
        let zoomedOut = TimelineGeometry.snap(proposedStart: 9.9, duration: 2, candidates: [10], pixelsPerSecond: 20, fps: 30)
        XCTAssertEqual(zoomedOut.guide, 10)
    }

    func testDisabledSnapStillAlignsFramesAndHandlesInvalidNumbers() {
        let disabled = TimelineGeometry.snap(proposedStart: 10.013, duration: 1, candidates: [10], pixelsPerSecond: 50, fps: 30, enabled: false)
        XCTAssertEqual(disabled, SnapResult(time: 10))
        let invalid = TimelineGeometry.snap(proposedStart: .nan, duration: .infinity, candidates: [.nan], pixelsPerSecond: 0, fps: 0)
        XCTAssertEqual(invalid, SnapResult(time: 0))
    }

    func testViewportCoordinatesStayLocalBeyond24Hours() {
        let viewport = 200_000.0
        XCTAssertEqual(TimelineGeometry.x(for: viewport + 2, viewportStart: viewport, pixelsPerSecond: 50), 100)
        XCTAssertEqual(TimelineGeometry.time(atX: 100, viewportStart: viewport, pixelsPerSecond: 50), viewport + 2)
        XCTAssertEqual(TimelineGeometry.visibleRange(viewportStart: viewport, width: 1000, pixelsPerSecond: 50), (viewport - 2)...(viewport + 22))
        XCTAssertEqual(TimelineGeometry.pannedStart(viewport, byPixels: 1000, pixelsPerSecond: 50), viewport + 20)
    }
}
