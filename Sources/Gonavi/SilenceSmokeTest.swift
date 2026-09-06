import AppKit
import AVFoundation
import GonaviCore
import SwiftUI

enum SilenceSmokeTest {
    @MainActor static func run(directory: URL, movieURL: URL, audioURL: URL, silentVideoURL: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = EditorStore(storageDirectory: directory.appendingPathComponent("state"))
        _ = store.createProject(name: "Duraklamaları düzenle", scene: .landscape, fps: 30)
        store.importURLs([movieURL, audioURL, silentVideoURL])
        while store.importing { try await Task.sleep(nanoseconds: 20_000_000) }
        try SmokeTest.require(store.project.clips.count == 3, "Silence fixture import failed")
        store.mutate { project in
            project.clips[0].timelineStart = .zero
            project.clips[1].sourceStart = EditTime(seconds: 4)
            project.clips[1].duration = EditTime(seconds: 4)
            project.clips[1].timelineStart = EditTime(seconds: 14)
            project.clips[2].timelineStart = EditTime(seconds: 20)
            project.music = MusicClip(sourceID: project.clips[1].sourceID)
            project.captions = [Caption(start: EditTime(seconds: 4), duration: EditTime(seconds: 1), text: "Konuşma korunur."),
                                Caption(start: EditTime(seconds: 10.2), duration: EditTime(seconds: 0.2), text: "Sessiz aralıkta"),
                                Caption(start: EditTime(seconds: 20.5), duration: EditTime(seconds: 1), text: "Son görüntü")]
        }
        try await ready(store)
        let original = store.project, originalRevision = store.revision
        store.selectedClip = original.clips[0].id
        store.automaticSilences()
        let controller = SilenceController(hasSelection: true)
        controller.onlySelected = false
        let settingsController = SilenceController(hasSelection: true)
        settingsController.onlySelected = false
        try SmokeTest.snapshot(SilenceView(store: store, controller: settingsController), size: CGSize(width: 740, height: 510),
                               to: directory.appendingPathComponent("silence-settings.png"))
        // Snapshot teardown delivers SwiftUI onDisappear on the next run-loop turn.
        // Let it finish before starting an analysis or audition on another view.
        try await Task.sleep(nanoseconds: 150_000_000)
        controller.generate(store: store)
        for _ in 0..<3000 {
            if !controller.working { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(!controller.working && controller.failure == nil, controller.failure ?? "Silence analysis timeout")
        guard let result = controller.result else { throw ProjectError.invalid("Silence review missing: \(controller.message)") }
        try SmokeTest.require(result.candidates.count == 4, "Expected four source silence regions, got \(result.candidates.count)")
        try SmokeTest.require(result.skippedSources.count == 1, "Video without audio must be skipped")
        try SmokeTest.require(store.project == original && store.revision == originalRevision, "Analysis mutated project before approval")
        for cut in result.candidates {
            try SmokeTest.require(cut.start.ticks % 2000 == 0 && cut.end.ticks % 2000 == 0, "Cut not frame aligned")
        }
        try SmokeTest.snapshot(SilenceView(store: store, controller: controller), size: CGSize(width: 740, height: 640),
                               to: directory.appendingPathComponent("silence-review.png"))
        try await Task.sleep(nanoseconds: 150_000_000)

        // A short audition automatically stops and leaves the project unchanged.
        let audition = result.candidates[1]
        controller.audition(audition, store: store)
        var didPlay = false
        for _ in 0..<300 {
            try await Task.sleep(nanoseconds: 50_000_000)
            didPlay = didPlay || store.isPlaying
            if controller.auditionID == nil { break }
        }
        try SmokeTest.require(didPlay && controller.auditionID == nil && !store.isPlaying, "Silence audition did not play and stop")
        try SmokeTest.require(store.project == original, "Audition changed project")

        // Selection excludes the final audio cut; only approved intervals disappear.
        let excluded = result.candidates.last!
        controller.selected.remove(excluded.id)
        let chosen = controller.chosen
        let removed = chosen.reduce(0.0) { $0 + $1.duration.seconds }
        do {
            try store.applySilences(chosen, expectedRevision: originalRevision + 1)
            throw ProjectError.invalid("Stale analysis was accepted")
        } catch {
            try SmokeTest.require(store.project == original && store.showingSilences, "Stale analysis mutated or dismissed project")
        }
        controller.apply(store: store)
        try SmokeTest.require(!store.showingSilences && controller.failure == nil, controller.failure ?? "Apply did not close review")
        try SmokeTest.require(abs(store.project.duration.seconds - (22 - removed)) < 0.0001, "Silence ripple duration drift")
        try SmokeTest.require(store.project.music == original.music, "Background music was cut")
        try SmokeTest.require(store.project.captions.map(\.text) == ["Konuşma korunur.", "Son görüntü"], "Caption in removed interval remains")
        try SmokeTest.require(store.project.clips.contains { $0.id == original.clips[1].id && $0.sourceStart == EditTime(seconds: 4) && $0.duration == EditTime(seconds: 4) }, "Unselected audio cut was applied")
        let edited = store.project
        store.undo(); try SmokeTest.require(store.project == original, "Silence batch did not undo once")
        store.redo(); try SmokeTest.require(store.project == edited, "Silence redo mismatch")
        try SmokeTest.require(try Project.decode(edited.encoded()) == edited, "Cleaned project persistence mismatch")
        try await ready(store)
        store.timeline.fit(store.project.duration.seconds)
        store.seek(store.project.captions[0].start.seconds + 0.3)
        try await Task.sleep(nanoseconds: 350_000_000)
        try SmokeTest.snapshot(EditorView(store: store), size: CGSize(width: 1440, height: 900), to: directory.appendingPathComponent("silence-applied.png"))
        store.player.replaceCurrentItem(with: nil)
        try await export(edited, to: directory.appendingPathComponent("silence-cleaned.mp4"), audioOnly: false)

        var audioProject = Project()
        let audio = try await MediaEngine.inspect(audioURL)
        audioProject.sources = [audio]; audioProject.clips = [VideoClip(sourceID: audio.id, duration: audio.duration)]
        let audioResult = try await SilenceEngine.analyze(project: audioProject, clipIDs: nil, settings: SilenceSettings()) { _, _ in }
        try SmokeTest.require(audioResult.candidates.count == 3, "Audio-only silence regions missing")
        try audioProject.removeSilences(audioResult.candidates)
        try await export(audioProject, to: directory.appendingPathComponent("silence-cleaned.m4a"), audioOnly: true)
        let selectedResult = try await SilenceEngine.analyze(project: original, clipIDs: Set([original.clips[1].id]), settings: SilenceSettings()) { _, _ in }
        try SmokeTest.require(selectedResult.candidates.count == 1 && selectedResult.candidates[0].start.seconds > 16, "Selected trimmed source mapping failed")

        // Cancellation reaches the detached analyzer and never applies a partial result.
        let cancelTask = Task {
            try await SilenceEngine.analyze(project: original, clipIDs: nil, settings: SilenceSettings()) { _, _ in }
        }
        cancelTask.cancel()
        do { _ = try await cancelTask.value; throw ProjectError.invalid("Cancelled analysis returned a result") }
        catch is CancellationError {}
        store.showingSilences = true
        let cancelledController = SilenceController(hasSelection: false)
        cancelledController.generate(store: store); cancelledController.cancel()
        for _ in 0..<500 {
            if !cancelledController.working { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(!cancelledController.working && cancelledController.result == nil && store.project == edited, "Cancelled UI analysis retained cuts or changed project")
        store.showingSilences = false
        let report = "PASS: source-level silence detection for video/audio; source trims; selected/all scopes; no-audio skip; review before apply; real audition with automatic stop; deselected cut preservation; stale rejection; one-step undo/redo; caption ripple; continuous music; project round-trip; shortened MP4/M4A export and final frame; engine/UI cancellation; native settings/review/applied screenshots.\n"
        try report.write(to: directory.appendingPathComponent("silence-report.txt"), atomically: true, encoding: .utf8)
    }
    @MainActor private static func ready(_ store: EditorStore) async throws {
        for _ in 0..<1500 {
            if !store.isBuilding { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(!store.isBuilding && store.error == nil, store.error ?? "Silence preview timeout")
    }
    private static func export(_ project: Project, to url: URL, audioOnly: Bool) async throws {
        let prepared = try await MediaEngine.prepare(project)
        let session = AVAssetExportSession(asset: prepared.composition, presetName: audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality)!
        session.outputURL = url; session.outputFileType = audioOnly ? .m4a : .mp4
        session.videoComposition = prepared.videoComposition; session.audioMix = prepared.audioMix
        await session.export()
        try SmokeTest.require(session.status == .completed, session.error?.localizedDescription ?? "Cleaned export failed")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        try SmokeTest.require(abs(duration.seconds - project.duration.seconds) < 0.1, "Cleaned export duration mismatch")
        if !audioOnly {
            let generator = AVAssetImageGenerator(asset: asset)
            _ = try await generator.image(at: CMTime(seconds: project.duration.seconds - 0.1, preferredTimescale: 60000))
        }
    }
}
