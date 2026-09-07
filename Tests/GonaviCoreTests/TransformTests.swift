import Foundation
import XCTest
@testable import GonaviCore

final class TransformTests: XCTestCase {
    private func fixture() -> Project {
        var project = Project()
        let source = MediaSource(name: "video.mov", path: "/video.mov", duration: .init(seconds: 20), isVideo: true)
        project.sources = [source]
        project.clips = [VideoClip(sourceID: source.id, duration: .init(seconds: 10))]
        return project
    }

    func testSchemasOneAndTwoDecodeWithoutPhotoOrTransformFields() throws {
        for schema in [1, 2] {
            var legacy = fixture()
            legacy.schemaVersion = schema
            legacy.clips[0].zoom = 1.25
            legacy.clips[0].offsetX = 0.3
            legacy.clips[0].timelineStart = schema == 2 ? .init(seconds: 20) : nil
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            var sources = try XCTUnwrap(object["sources"] as? [[String: Any]])
            sources[0].removeValue(forKey: "isStillImage")
            object["sources"] = sources
            var clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
            clips[0].removeValue(forKey: "rotation")
            clips[0].removeValue(forKey: "crop")
            object["clips"] = clips
            let restored = try Project.decode(JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored.schemaVersion, 3)
            XCTAssertFalse(restored.sources[0].isStillImage)
            XCTAssertTrue(restored.sources[0].isVisual)
            XCTAssertEqual(restored.clips[0].rotation, 0)
            XCTAssertEqual(restored.clips[0].crop, ClipCrop())
            XCTAssertEqual(restored.clips[0].zoom, 1.25)
            XCTAssertEqual(restored.clips[0].offsetX, 0.3)
            XCTAssertEqual(restored.clips[0].timelineStart?.seconds, schema == 2 ? 20 : 0)
            XCTAssertEqual(try Project.decode(restored.encoded()), restored)
        }
    }

    func testPhotoDefaultsToFiveSecondsAndCanRepeatOnTimeline() throws {
        let photo = MediaSource(name: "photo.png", path: "/photo.png", duration: .init(seconds: 86_400), isVideo: false, isStillImage: true)
        let audio = MediaSource(name: "voice.wav", path: "/voice.wav", duration: .init(seconds: 7), isVideo: false)
        XCTAssertTrue(photo.isVisual)
        XCTAssertFalse(audio.isVisual)
        XCTAssertEqual(photo.defaultClipDuration.seconds, 5)
        XCTAssertEqual(audio.defaultClipDuration.seconds, 7)
        var project = Project()
        let first = project.appendSourceToTimeline(source: photo)
        let second = project.appendSourceToTimeline(source: photo)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(project.sources.count, 1)
        XCTAssertEqual(project.clips.map { $0.duration.seconds }, [5, 5])
        XCTAssertEqual(project.start(of: second).seconds, 5)
        XCTAssertEqual(project.duration.seconds, 10)
        project.clips[1].duration = .init(seconds: 12)
        try project.validate()
        XCTAssertEqual(project.duration.seconds, 17)
        XCTAssertEqual(try Project.decode(project.encoded()), project)
    }

    func testPhotoCannotBeVideoAndCannotBeUsedAsMusic() throws {
        var project = Project()
        let photo = MediaSource(name: "photo.png", path: "/photo.png", duration: .init(seconds: 86_400), isVideo: false, isStillImage: true)
        project.appendSourceToTimeline(source: photo)
        project.music = MusicClip(sourceID: photo.id)
        XCTAssertThrowsError(try project.validate())
        project.music = nil
        project.sources[0].isVideo = true
        XCTAssertThrowsError(try project.validate())
        project.sources[0].isVideo = false
        try project.validate()
    }

    func testTransformLimitsPermitShrinkingAndMovingOutsideCanvas() throws {
        var project = fixture()
        project.clips[0].zoom = 0.05
        project.clips[0].offsetX = -4
        project.clips[0].offsetY = 4
        project.clips[0].rotation = -180
        project.clips[0].crop = ClipCrop(left: 0.95, bottom: 0.95)
        try project.validate()
        project.clips[0].zoom = 8
        project.clips[0].offsetX = 4
        project.clips[0].offsetY = -4
        project.clips[0].rotation = 180
        project.clips[0].crop = ClipCrop(top: 0.95, right: 0.95)
        try project.validate()
        XCTAssertEqual(try Project.decode(project.encoded()), project)
    }

    func testInvalidTransformsAndCropsAreRejected() {
        let edits: [(inout VideoClip) -> Void] = [
            { $0.zoom = -1 }, { $0.zoom = 0 }, { $0.zoom = 0.049 }, { $0.zoom = 8.01 },
            { $0.zoom = .nan }, { $0.zoom = .infinity },
            { $0.offsetX = -4.01 }, { $0.offsetY = 4.01 }, { $0.offsetX = .nan }, { $0.offsetY = .infinity },
            { $0.rotation = -180.01 }, { $0.rotation = 180.01 }, { $0.rotation = .nan }, { $0.rotation = .infinity },
            { $0.crop.left = -0.01 }, { $0.crop.right = 0.951 }, { $0.crop.top = .nan }, { $0.crop.bottom = .infinity },
            { $0.crop = ClipCrop(left: 0.5, right: 0.46) },
            { $0.crop = ClipCrop(top: 0.5, bottom: 0.46) }
        ]
        for edit in edits {
            var project = fixture()
            edit(&project.clips[0])
            XCTAssertThrowsError(try project.validate())
        }
    }

    func testSplitMoveAndSilenceRemovalPreserveTransforms() throws {
        var project = fixture()
        let id = project.clips[0].id
        project.clips[0].sourceStart = .init(seconds: 2)
        project.clips[0].zoom = 0.6
        project.clips[0].offsetX = -2.5
        project.clips[0].offsetY = 1.75
        project.clips[0].rotation = 37
        project.clips[0].crop = ClipCrop(left: 0.1, top: 0.2, right: 0.3, bottom: 0.1)
        project.clips[0].fill = true
        project.clips[0].volume = 0.7
        let reference = project.clips[0]
        try project.split(id, at: .init(seconds: 4))
        let rightID = project.clips[1].id
        project.placeClip(id: rightID, at: .init(seconds: 10))
        try project.removeSilences([SilenceCandidate(clipID: rightID, start: .init(seconds: 12), end: .init(seconds: 13))])
        XCTAssertEqual(project.clips.count, 3)
        XCTAssertEqual(project.clips.map { $0.sourceStart.seconds }, [2, 6, 9])
        XCTAssertEqual(project.clips.map { $0.timelineStart?.seconds }, [0, 10, 12])
        for fragment in project.clips {
            XCTAssertEqual(fragment.zoom, reference.zoom)
            XCTAssertEqual(fragment.offsetX, reference.offsetX)
            XCTAssertEqual(fragment.offsetY, reference.offsetY)
            XCTAssertEqual(fragment.rotation, reference.rotation)
            XCTAssertEqual(fragment.crop, reference.crop)
            XCTAssertEqual(fragment.fill, reference.fill)
            XCTAssertEqual(fragment.volume, reference.volume)
        }
        XCTAssertEqual(try Project.decode(project.encoded()), project)
    }
}
