import AppKit
import AVFoundation
import GonaviCore
import SwiftUI

enum TimelineSmokeTest {
    @MainActor static func run(directory: URL) async throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("Sessiz · Hafif · Güçlü.wav")
        try makeAudio(audioURL)
        let audio = try await MediaEngine.inspect(audioURL)
        guard case .ready(let waveform) = try await WaveformDecoder.decode(audio, useCache: false) else {
            throw ProjectError.invalid("Audio waveform missing")
        }
        try SmokeTest.require(waveform.level(in: 0.2..<1.8).peak < 0.001, "Silence waveform must be flat")
        try SmokeTest.require(waveform.level(in: 2.2..<3.8).peak < 0.08 && waveform.level(in: 2.2..<3.8).peak > 0.02, "Quiet amplitude was normalized")
        try SmokeTest.require(waveform.level(in: 4.2..<5.8).peak > 0.7, "Loud region peak missing")
        let picture = directory.appendingPathComponent("picture.mov")
        try await SmokeTest.makeVideo(picture, red: 0.12, green: 0.38)
        let mux = AVMutableComposition()
        let vt = mux.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let at = mux.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let videoAsset = AVURLAsset(url: picture), audioAsset = AVURLAsset(url: audioURL)
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        for second in stride(from: 0, to: 12, by: 2) {
            try vt.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 60000)),
                                   of: videoTrack, at: CMTime(seconds: Double(second), preferredTimescale: 60000))
        }
        try at.insertTimeRange(CMTimeRange(start: .zero, duration: audio.duration.cm), of: audioTrack, at: .zero)
        let movieURL = directory.appendingPathComponent("Stüdyo kaydı.mov")
        let muxer = AVAssetExportSession(asset: mux, presetName: AVAssetExportPresetHighestQuality)!
        muxer.outputURL = movieURL; muxer.outputFileType = .mov; await muxer.export()
        try SmokeTest.require(muxer.status == .completed, "Waveform video fixture export failed")
        let movie = try await MediaEngine.inspect(movieURL)
        guard case .ready(let videoWaveform) = try await WaveformDecoder.decode(movie, useCache: false) else { throw ProjectError.invalid("Video waveform missing") }
        try SmokeTest.require(videoWaveform.level(in: 0.2..<1.8).peak < 0.001 && videoWaveform.level(in: 4.2..<5.8).peak > 0.65,
                              "Video waveform lost silence/loudness")

        let store = EditorStore(storageDirectory: directory.appendingPathComponent("editor-state"))
        _ = store.createProject(name: "Sesin ritmini yakala", scene: .landscape, fps: 30)
        store.importURLs([movieURL])
        while store.importing { try await Task.sleep(nanoseconds: 20_000_000) }
        try SmokeTest.require(store.project.clips.count == 1, "Video import failed")
        let firstID = store.project.clips[0].id
        store.mutate { p in
            p.clips[0].duration = EditTime(seconds: 6)
            var second = VideoClip(sourceID: p.clips[0].sourceID, duration: EditTime(seconds: 4))
            second.sourceStart = EditTime(seconds: 8); second.timelineStart = EditTime(seconds: 8)
            p.clips.append(second)
            p.sources.append(audio)
            var sound = VideoClip(sourceID: audio.id, duration: EditTime(seconds: 4))
            sound.sourceStart = EditTime(seconds: 4); sound.timelineStart = EditTime(seconds: 13); p.clips.append(sound)
            p.music = MusicClip(sourceID: audio.id)
            p.captions = [Caption(start: EditTime(seconds: 2), duration: EditTime(seconds: 3.7), text: "Sessizliği gör. Sesin ritmini yakala.")]
        }
        try await waitForStore(store)
        store.timeline.pixelsPerSecond = 60; store.selectedClip = firstID
        store.seek(4.8)
        try SmokeTest.snapshot(EditorView(store: store), size: CGSize(width: 1440, height: 900), to: directory.appendingPathComponent("editor-waveforms.png"))
        try SmokeTest.snapshot(EditorView(store: store), size: CGSize(width: 1040, height: 720), to: directory.appendingPathComponent("editor-compact.png"))
        try await exportAndCheckGaps(store.project, directory: directory)

        // Native mouse events use the same canvas implementation as interactive dragging.
        let canvas = TimelineNativeView(frame: NSRect(x: 0, y: 0, width: 1100, height: 230))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 230), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas; window.orderFront(nil)
        store.timeline.pixelsPerSecond = 40
        canvas.configure(store: store, waveforms: store.waveforms.entries)
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        // Move the 6s first clip so its end snaps to the start of the audio clip at 13s.
        // Occupied 8..12 prevents that location, so placement must resolve without overlap.
        let before = store.project
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 128, y: 70)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 930, y: 70)))
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 930, y: 70)))
        try SmokeTest.require(store.project.start(of: firstID).seconds > 17, "Native dragging did not move the clip into blank time")
        try store.project.validate()
        store.undo(); try SmokeTest.require(store.project == before, "Native move must undo once")
        store.timeline.offset = 200_000
        canvas.configure(store: store, waveforms: store.waveforms.entries)
        try SmokeTest.require(canvas.frame.width == 1100, "Long timeline allocated giant canvas")
        store.timeline.offset = 0; window.orderOut(nil)

        let audioStore = EditorStore(storageDirectory: directory.appendingPathComponent("audio-state"))
        _ = audioStore.createProject(name: "Sadece ses · yeni bir başlangıç", scene: .landscape, fps: 30)
        audioStore.importURLs([audioURL])
        while audioStore.importing { try await Task.sleep(nanoseconds: 20_000_000) }
        try await waitForStore(audioStore)
        try SmokeTest.require(audioStore.project.clips.count == 1 && !audioStore.hasVideo && audioStore.canExport, "Audio-only import/edit/export path failed")
        audioStore.timeline.pixelsPerSecond = 70
        try SmokeTest.snapshot(EditorView(store: audioStore), size: CGSize(width: 1440, height: 900), to: directory.appendingPathComponent("audio-only.png"))
        let prepared = try await MediaEngine.prepare(audioStore.project)
        try SmokeTest.require(prepared.videoComposition == nil, "Audio-only preview must not require video")
        let exporter = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetAppleM4A)!
        exporter.audioMix = prepared.audioMix; exporter.outputURL = directory.appendingPathComponent("audio-only.m4a"); exporter.outputFileType = .m4a
        await exporter.export(); try SmokeTest.require(exporter.status == .completed, "Audio-only M4A export failed")
        let report = "PASS: real video/audio peak+RMS decoding; silence, quiet and loud levels; source waveform cache; native mouse drag and undo; virtual viewport at 200000s; gapped video/audio MP4 frames; audio-only import, preview, M4A export; full/compact SwiftUI screenshots.\n"
        try report.write(to: directory.appendingPathComponent("timeline-report.txt"), atomically: true, encoding: .utf8)
    }
    @MainActor private static func waitForStore(_ store: EditorStore) async throws {
        for _ in 0..<1500 {
            let pending = store.waveforms.entries.values.contains { if case .loading = $0 { return true }; return false }
            if !store.isBuilding && !pending { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(store.error == nil && !store.isBuilding, store.error ?? "Preview build timed out")
    }
    private static func makeAudio(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        for second in 0..<12 {
            buffer.frameLength = 16000
            for sample in 0..<16000 {
                let t = Double(second) + Double(sample) / 16000
                let amplitude: Double = second < 2 || second == 6 || second == 10 ? 0 : (second < 4 ? 0.05 : 0.78)
                let envelope = 0.6 + 0.4 * pow(sin(t * 3.7), 2)
                buffer.floatChannelData![0][sample] = Float(amplitude * envelope * sin(t * 2 * .pi * 220))
            }
            try file.write(from: buffer)
        }
    }
    private static func exportAndCheckGaps(_ project: Project, directory: URL) async throws {
        let prepared = try await MediaEngine.prepare(project)
        let url = directory.appendingPathComponent("gapped-timeline.mp4")
        let exporter = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetHighestQuality)!
        exporter.outputURL = url; exporter.outputFileType = .mp4
        exporter.videoComposition = prepared.videoComposition; exporter.audioMix = prepared.audioMix
        await exporter.export()
        try SmokeTest.require(exporter.status == .completed, exporter.error?.localizedDescription ?? "Gapped export failed")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        try SmokeTest.require(abs(duration.seconds - 17) < 0.05, "Gapped export duration mismatch")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for second in [7.0, 14.0] {
            let frame = try generator.copyCGImage(at: CMTime(seconds: second, preferredTimescale: 60000), actualTime: nil)
            let pixel = NSBitmapImageRep(cgImage: frame).colorAt(x: 100, y: 100)!.usingColorSpace(.deviceRGB)!
            try SmokeTest.require(pixel.redComponent < 0.02 && pixel.greenComponent < 0.02, "Gap/audio-only video segment must be black")
        }
    }
}
