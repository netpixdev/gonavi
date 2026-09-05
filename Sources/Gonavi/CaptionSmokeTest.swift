import AppKit
import AVFoundation
import GonaviCore
import SwiftUI

enum CaptionSmokeTest {
    @MainActor static func run(directory: URL, speech: URL, language: String) async throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try await CaptionEngine.ensureModel(.small) { message, _ in print(message) }
        let clipURL = directory.appendingPathComponent("picture.mov")
        try await SmokeTest.makeVideo(clipURL, red: 0.15, green: 0.5)
        let voice = AVURLAsset(url: speech), picture = AVURLAsset(url: clipURL)
        let speechDuration = try await voice.load(.duration)
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let sourceVideo = try await picture.loadTracks(withMediaType: .video)[0]
        let sourceAudio = try await voice.loadTracks(withMediaType: .audio)[0]
        let duration = CMTimeAdd(speechDuration, CMTime(seconds: 1.2, preferredTimescale: 60000))
        var cursor = CMTime.zero
        while cursor < duration {
            let length = CMTimeMinimum(CMTime(seconds: 2, preferredTimescale: 60000), duration - cursor)
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: sourceVideo, at: cursor)
            cursor = cursor + length
        }
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: speechDuration), of: sourceAudio,
                                  at: CMTime(seconds: 0.6, preferredTimescale: 60000))
        let sourceURL = directory.appendingPathComponent("speech-video.mov")
        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        session.outputURL = sourceURL; session.outputFileType = .mov
        await session.export()
        try SmokeTest.require(session.status == .completed, "Speech video mux failed")
        var project = Project(); project.name = "Türkçe otomatik altyazı"; project.scene = .landscape
        let source = try await MediaEngine.inspect(sourceURL)
        let decoded = directory.appendingPathComponent("decoded.wav")
        let hasSpeech = try await CaptionEngine.extractAudio(asset: AVURLAsset(url: sourceURL),
                                                             start: .init(seconds: 0.3),
                                                             duration: source.duration - EditTime(seconds: 0.3), to: decoded)
        try SmokeTest.require(hasSpeech, "Extracted speech is silent")
        let wavData = try Data(contentsOf: decoded)
        let expectedFrames = Int(((source.duration.seconds - 0.3) * 16000).rounded())
        try SmokeTest.require(wavData.count == 44 + expectedFrames * 2, "PCM duration/sample-rate mismatch")
        // Audio begins 0.6s into source, trimmed by 0.3s: first 0.2s must remain silent.
        let leading = wavData.subdata(in: 44..<(44 + 6400))
        try SmokeTest.require(leading.allSatisfy { $0 == 0 }, "Delayed audio lost its leading gap after trim")
        project.sources = [source]
        var clip = VideoClip(sourceID: source.id, duration: source.duration - EditTime(seconds: 0.3))
        clip.sourceStart = EditTime(seconds: 0.3); project.clips = [clip]
        let started = Date()
        let captions = try await CaptionEngine.transcribe(project: project, model: model, language: language, style: .box) { message, _ in print(message) }
        try SmokeTest.require(!captions.isEmpty, "Real recognizer returned no captions")
        let text = captions.map(\.text).joined(separator: " ").lowercased()
        if language == "en" { try SmokeTest.require(text.contains("country"), "Speech fixture was not recognized: \(text)") }
        if language == "tr" { try SmokeTest.require(text.contains("merhaba") && text.contains("altyazı"), "Turkish speech fixture was not recognized: \(text)") }
        project.captions = captions; try project.validate()
        try project.encoded().write(to: directory.appendingPathComponent("automatic.gonavi"))
        try project.srt().write(to: directory.appendingPathComponent("automatic.srt"), atomically: true, encoding: .utf8)

        // Apply and undo exercise the exact editor command used by the review sheet.
        let store = EditorStore(storageDirectory: directory.appendingPathComponent("store"))
        store.project = project; store.project.captions = []
        store.showingAutoCaptions = true
        try SmokeTest.require(!store.editable, "Caption review must protect the project snapshot")
        store.applyGeneratedCaptions(captions)
        try SmokeTest.require(store.project.captions == captions && store.canUndo, "Caption apply failed")
        store.undo()
        try SmokeTest.require(store.project.captions.isEmpty, "Caption apply must undo in one step")
        store.redo()
        try SmokeTest.require(store.project.captions == captions, "Caption redo failed")
        try SmokeTest.snapshot(AutoCaptionView(store: store), size: CGSize(width: 676, height: 500),
                               to: directory.appendingPathComponent("automatic-captions-ui.png"))

        // The new track must also survive the real video export/render path.
        let prepared = try await MediaEngine.prepare(project)
        let rendered = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetHighestQuality)!
        rendered.outputURL = directory.appendingPathComponent("subtitled.mp4"); rendered.outputFileType = .mp4
        rendered.videoComposition = prepared.videoComposition; rendered.audioMix = prepared.audioMix
        await rendered.export()
        try SmokeTest.require(rendered.status == .completed, "Automatic caption video export failed")
        // A video without audio must produce no fabricated captions.
        let silent = try await MediaEngine.inspect(clipURL)
        var silentProject = Project(); silentProject.sources = [silent]
        silentProject.clips = [VideoClip(sourceID: silent.id, duration: silent.duration)]
        let empty = try await CaptionEngine.transcribe(project: silentProject, model: model, style: .clean) { _, _ in }
        try SmokeTest.require(empty.isEmpty, "Silent video generated captions")
        // Cancel before starting: no project edits and no partial result.
        let cancelled = Task { try await CaptionEngine.transcribe(project: project, model: model, style: .clean) { _, _ in } }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw ProjectError.invalid("Cancelled job returned a result") }
        catch is CancellationError {}
        let report = "PASS: \(language), real small-q5_1 recognition, \(captions.count) captions, source trim + delayed audio, JSON/SRT/project validation, apply/undo/redo, MP4 export, silent video, cancellation. Elapsed \(Int(Date().timeIntervalSince(started)))s. This fixture is an integration test, not a Turkish accuracy benchmark.\n"
        try report.write(to: directory.appendingPathComponent("caption-report.txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
