import XCTest
@testable import GonaviCore

final class SilenceTests: XCTestCase {
    private func waveform(duration: Int = 3, quiet: [Range<Double>]) throws -> WaveformData {
        let amplitudes: [Float] = (0..<(duration * 100)).map { index in
            let time = Double(index) / 100.0
            return quiet.contains(where: { $0.contains(time) }) ? 0 : 0.25
        }
        return try WaveformData(bucketDuration: 0.01, duration: Double(duration), peaks: amplitudes, rms: amplitudes)
    }

    private func clip(duration: Double = 3) -> VideoClip {
        VideoClip(sourceID: UUID(), duration: EditTime(seconds: duration))
    }

    private func candidate(_ clip: VideoClip, _ start: Double, _ end: Double) -> SilenceCandidate {
        SilenceCandidate(clipID: clip.id, start: .init(seconds: start), end: .init(seconds: end))
    }

    func testDefaultsAndInvalidSettings() throws {
        let defaults = SilenceSettings()
        XCTAssertEqual(defaults.thresholdDB, -38)
        XCTAssertEqual(defaults.minimumDuration, 0.5)
        XCTAssertEqual(defaults.padding, 0.12)
        try defaults.validate()
        for value in [Double.nan, .infinity, -61, -19] {
            XCTAssertThrowsError(try SilenceSettings(thresholdDB: value).validate())
        }
        XCTAssertThrowsError(try SilenceSettings(minimumDuration: -0.1).validate())
        XCTAssertThrowsError(try SilenceSettings(padding: -0.1).validate())
        XCTAssertThrowsError(try SilenceSettings(minimumDuration: .nan).validate())
        XCTAssertThrowsError(try SilenceSettings(padding: .infinity).validate())
    }

    func testPaddingPreservesBothSidesAndQuantizesInward() throws {
        let clip = clip()
        let result = try SilenceDetector.candidates(waveform: waveform(quiet: [1..<2]), clip: clip,
            timelineStart: .zero, fps: 30, settings: SilenceSettings())
        XCTAssertEqual(result.count, 1)
        let cut = try XCTUnwrap(result.first)
        XCTAssertEqual(cut.clipID, clip.id)
        XCTAssertEqual(cut.start.ticks, 68_000) // 1.12 rounded inward to 34/30.
        XCTAssertEqual(cut.end.ticks, 112_000) // 1.88 rounded inward to 56/30.
        XCTAssertEqual(cut.duration, cut.end - cut.start)
    }

    func testShortPauseIsRetainedButLongRunQualifiesBeforePadding() throws {
        let result = try SilenceDetector.candidates(waveform: waveform(quiet: [0.2..<0.5, 1..<1.6]),
            clip: clip(), timelineStart: .zero, fps: 30, settings: SilenceSettings())
        XCTAssertEqual(result.count, 1)
        let cut = try XCTUnwrap(result.first)
        XCTAssertGreaterThanOrEqual(cut.start.seconds, 1.12)
        XCTAssertLessThanOrEqual(cut.end.seconds, 1.48)
        XCTAssertLessThan(cut.duration.seconds, 0.5)
    }

    func testPeakGuardProtectsTransientDespiteQuietRMS() throws {
        let data = try WaveformData(bucketDuration: 0.01, duration: 1,
            peaks: Array(repeating: 0.1, count: 100), rms: Array(repeating: 0.001, count: 100))
        let result = try SilenceDetector.candidates(waveform: data, clip: clip(duration: 1),
            timelineStart: .zero, fps: 30, settings: SilenceSettings(padding: 0))
        XCTAssertTrue(result.isEmpty)
    }

    func testThresholdUsesOriginalLevelAndCanBeAdjusted() throws {
        let data = try WaveformData(bucketDuration: 0.01, duration: 1,
            peaks: Array(repeating: 0.02, count: 100), rms: Array(repeating: 0.02, count: 100))
        var sourceClip = clip(duration: 1)
        sourceClip.volume = 0
        let retained = try SilenceDetector.candidates(waveform: data, clip: sourceClip,
            timelineStart: .zero, fps: 30, settings: SilenceSettings(padding: 0))
        let quiet = try SilenceDetector.candidates(waveform: data, clip: sourceClip,
            timelineStart: .zero, fps: 30, settings: SilenceSettings(thresholdDB: -20, padding: 0))
        XCTAssertTrue(retained.isEmpty, "Muting the edited clip must not change source analysis")
        XCTAssertEqual(quiet.count, 1)
    }

    func testOppositeStereoChannelsAreNeverClassifiedAsSilence() throws {
        var accumulator = try AudioPeakAccumulator(duration: 1, sampleRate: 100, bucketsPerSecond: 10)
        let samples = (0..<100).flatMap { _ in [Float(0.8), Float(-0.8)] }
        try samples.withUnsafeBufferPointer { try accumulator.append($0, at: 0, channels: 2) }
        let result = try SilenceDetector.candidates(waveform: accumulator.finish(), clip: clip(duration: 1),
            timelineStart: .zero, fps: 30, settings: SilenceSettings(padding: 0))
        XCTAssertTrue(result.isEmpty)
    }

    func testSourceTrimAndNonFrameTimelineOriginUseGlobalFrameGrid() throws {
        var sourceClip = clip(duration: 2.5)
        sourceClip.sourceStart = .init(seconds: 0.013)
        let result = try SilenceDetector.candidates(waveform: waveform(quiet: [1..<2]), clip: sourceClip,
            timelineStart: .init(seconds: 1.007), fps: 30, settings: SilenceSettings(padding: 0))
        let cut = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(cut.start.ticks, 120_000)
        XCTAssertEqual(cut.end.ticks, 178_000)
        XCTAssertEqual(cut.start.ticks % 2_000, 0)
        XCTAssertEqual(cut.end.ticks % 2_000, 0)
    }

    func testUnanalysedSourceTailIsNotAssumedSilent() throws {
        let result = try SilenceDetector.candidates(waveform: waveform(quiet: [0..<3]),
            clip: clip(duration: 4), timelineStart: .zero, fps: 30, settings: SilenceSettings(padding: 0))
        XCTAssertTrue(result.isEmpty)
    }

    private func project() -> Project {
        var project = Project()
        let source = MediaSource(name: "source.mov", path: "/source.mov", duration: .init(seconds: 10), isVideo: true)
        var first = VideoClip(sourceID: source.id, duration: .init(seconds: 6))
        first.sourceStart = .init(seconds: 2); first.timelineStart = .init(seconds: 3)
        first.zoom = 1.5; first.offsetX = 0.2; first.offsetY = -0.1; first.fill = true; first.volume = 0.7
        var second = VideoClip(sourceID: source.id, duration: .init(seconds: 2))
        second.timelineStart = .init(seconds: 12)
        project.sources = [source]; project.clips = [first, second]
        project.music = MusicClip(sourceID: source.id)
        return project
    }

    func testRemovalPreservesFragmentsSourceOffsetsAndTransforms() throws {
        var project = project()
        let first = project.clips[0], second = project.clips[1], music = project.music
        try project.removeSilences([candidate(first, 4, 5), candidate(first, 7, 8)])
        XCTAssertEqual(project.clips.count, 4)
        XCTAssertEqual(project.clips.map { $0.timelineStart?.seconds }, [3, 4, 6, 10])
        XCTAssertEqual(project.clips.map { $0.duration.seconds }, [1, 2, 1, 2])
        XCTAssertEqual(project.clips.map { $0.sourceStart.seconds }, [2, 4, 7, 0])
        XCTAssertEqual(project.clips[0].id, first.id)
        XCTAssertEqual(project.clips[3].id, second.id)
        XCTAssertEqual(Set(project.clips.map(\.id)).count, 4)
        for fragment in project.clips.prefix(3) {
            XCTAssertEqual(fragment.zoom, first.zoom); XCTAssertEqual(fragment.offsetX, first.offsetX)
            XCTAssertEqual(fragment.offsetY, first.offsetY); XCTAssertEqual(fragment.fill, first.fill)
            XCTAssertEqual(fragment.volume, first.volume)
        }
        XCTAssertEqual(project.music, music)
        XCTAssertEqual(project.duration.seconds, 12)
        try project.validate()
    }

    func testRippleMapsCaptionEndpointsAcrossCutsAndGaps() throws {
        var project = project()
        let first = project.clips[0]
        project.captions = [
            Caption(start: .init(seconds: 3.5), duration: .init(seconds: 5.5), text: "Crossing"),
            Caption(start: .init(seconds: 4.2), duration: .init(seconds: 0.6), text: "Removed"),
            Caption(start: .init(seconds: 10), duration: .init(seconds: 1), text: "Gap"),
            Caption(start: .init(seconds: 12.25), duration: .init(seconds: 1), text: "Later")
        ]
        try project.removeSilences([candidate(first, 4, 5), candidate(first, 7, 8)])
        XCTAssertEqual(project.captions.map(\.text), ["Crossing", "Gap", "Later"])
        XCTAssertEqual(project.captions.map { $0.start.seconds }, [3.5, 8, 10.25])
        XCTAssertEqual(project.captions.map { $0.duration.seconds }, [3.5, 1, 1])
        try project.validate()
    }

    func testDuplicateAndOverlappingCutsRemoveOnlyTheirUnion() throws {
        var project = project()
        let first = project.clips[0]
        let cut = candidate(first, 4, 6)
        try project.removeSilences([cut, cut, candidate(first, 5, 7)])
        XCTAssertEqual(project.duration.seconds, 11)
        XCTAssertEqual(project.clips.map { $0.duration.seconds }, [1, 2, 2])
        XCTAssertEqual(project.clips.map { $0.sourceStart.seconds }, [2, 6, 0])
        XCTAssertEqual(project.clips.last?.timelineStart?.seconds, 9)
        try project.validate()
    }

    func testInvalidBatchCannotPartiallyMutateProject() throws {
        let baseline = project(), first = baseline.clips[0]
        let invalid = [candidate(first, 2, 4), candidate(first, 8, 10), candidate(first, 5, 5),
            SilenceCandidate(clipID: UUID(), start: .init(seconds: 4), end: .init(seconds: 5))]
        for badCut in invalid {
            var edited = baseline
            XCTAssertThrowsError(try edited.removeSilences([candidate(first, 4, 5), badCut]))
            XCTAssertEqual(edited, baseline)
        }
    }

    func testRemovingAllMainClipsIsRejectedAtomicallyEvenWithMusic() {
        let baseline = project()
        var edited = baseline
        XCTAssertThrowsError(try edited.removeSilences([
            candidate(baseline.clips[0], 3, 9), candidate(baseline.clips[1], 12, 14)
        ]))
        XCTAssertEqual(edited, baseline)
    }

    func testEmptySelectionDoesNotChangeLegacyProject() throws {
        var baseline = project()
        baseline.schemaVersion = 1
        baseline.clips[0].timelineStart = nil; baseline.clips[1].timelineStart = nil
        var edited = baseline
        try edited.removeSilences([])
        XCTAssertEqual(edited, baseline)
    }

    func testRemovingFinalClipCannotDeleteUnselectedTrailingGapOrCaption() throws {
        var baseline = project()
        baseline.captions = [Caption(start: .init(seconds: 10), duration: .init(seconds: 1), text: "Keep this gap")]
        var edited = baseline
        XCTAssertThrowsError(try edited.removeSilences([candidate(baseline.clips[1], 12, 14)]))
        XCTAssertEqual(edited, baseline)
    }

    func testContiguousFinalClipMayBeRemovedWhenNoExtraGapIsLost() throws {
        var edited = project()
        edited.clips[1].timelineStart = .init(seconds: 9)
        let final = edited.clips[1]
        try edited.removeSilences([candidate(final, 9, 11)])
        XCTAssertEqual(edited.clips.count, 1)
        XCTAssertEqual(edited.duration.seconds, 9)
        try edited.validate()
    }

    func testFragmentLimitRejectsWholeBatchAtomically() throws {
        var baseline = Project()
        let source = MediaSource(name: "a.wav", path: "/a.wav", duration: .init(seconds: 1), isVideo: false)
        baseline.sources = [source]
        baseline.clips = (0..<10_000).map { index in
            var clip = VideoClip(sourceID: source.id, duration: .init(seconds: 1))
            clip.timelineStart = .init(seconds: Double(index)); return clip
        }
        var edited = baseline
        XCTAssertThrowsError(try edited.removeSilences([candidate(baseline.clips[0], 0.2, 0.8)]))
        XCTAssertEqual(edited, baseline)
    }
}
