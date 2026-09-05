import AppKit
import AVFoundation
import GonaviCore
import SwiftUI

enum SmokeTest {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ProjectError.invalid(message) }
    }

    static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let red = directory.appendingPathComponent("red.mov")
        let green = directory.appendingPathComponent("green.mov")
        let sound = directory.appendingPathComponent("tone.caf")
        try await makeVideo(red, red: 0.8, green: 0.1)
        try await makeVideo(green, red: 0.1, green: 0.8)
        try makeAudio(sound)
        var project = Project(); project.name = "Gonavi smoke"; project.scene = .landscape
        let first = try await MediaEngine.inspect(red), second = try await MediaEngine.inspect(green)
        let music = try await MediaEngine.inspect(sound)
        project.sources = [first, second, music]
        project.clips = [VideoClip(sourceID: first.id, duration: first.duration), VideoClip(sourceID: second.id, duration: second.duration)]
        project.clips[1].zoom = 1.5; project.clips[1].fill = true
        project.music = MusicClip(sourceID: music.id)
        project.captions = [Caption(start: .init(seconds: 0.5), duration: .init(seconds: 1), text: "Gonavi · İstanbul")]
        let persisted = try project.encoded()
        try persisted.write(to: directory.appendingPathComponent("smoke.gonavi"))
        project = try Project.decode(persisted)
        let prepared = try await MediaEngine.prepare(project)
        let output = directory.appendingPathComponent("result.mp4")
        guard let session = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProjectError.invalid("Missing exporter")
        }
        session.outputURL = output; session.outputFileType = .mp4
        session.videoComposition = prepared.videoComposition; session.audioMix = prepared.audioMix
        await session.export()
        try require(session.status == .completed, session.error?.localizedDescription ?? "Export failed")
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        try require(abs(duration.seconds - 4) < 1.0 / 30.0, "Export duration drift")
        let audio = try await asset.loadTracks(withMediaType: .audio)
        try require(audio.count == 1, "Missing mixed audio")
        let rms = try audioRMS(asset: asset, track: audio[0])
        try require(rms > 0.005 && rms < 0.04, "Mixed audio is silent or gain is incorrect: \(rms)")
        let video = try await asset.loadTracks(withMediaType: .video)
        let size = try await video[0].load(.naturalSize)
        try require(size == CGSize(width: 1920, height: 1080), "Wrong export resolution")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let frame1 = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60000), actualTime: nil)
        let frame2 = try generator.copyCGImage(at: CMTime(seconds: 3, preferredTimescale: 60000), actualTime: nil)
        let firstSample = sample(frame1), secondSample = sample(frame2)
        try require(firstSample.red > firstSample.green * 2, "First clip should be red")
        try require(secondSample.green > secondSample.red * 2, "Second clip should be green")
        try require(firstSample.bright > 100, "Caption was not rendered")
        try require(secondSample.bright < 30, "Caption remains outside its time range")
        let png = NSBitmapImageRep(cgImage: frame1)
        try png.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("caption-frame.png"))
        try project.srt().write(to: directory.appendingPathComponent("captions.srt"), atomically: true, encoding: .utf8)
        try await snapshotUI(directory: directory)
        let report = "PASS: project round-trip, 4s export, 1920×1080, two ordered clips, audio RMS \(rms), caption visibility and timing. Welcome/create/recent/recovery navigation passed. Native UI snapshots generated for visual inspection.\n"
        try report.write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    private static func audioRMS(asset: AVAsset, track: AVAssetTrack) throws -> Double {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        try require(reader.startReading(), "Audio reader failed")
        var sum: Double = 0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let result = bytes.withUnsafeMutableBytes { data in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: data.baseAddress!)
            }
            try require(result == kCMBlockBufferNoErr, "Audio PCM copy failed")
            for value in bytes { sum += Double(value * value); count += 1 }
        }
        try require(reader.status == .completed && count > 0, "Audio decode incomplete")
        return sqrt(sum / Double(count))
    }

    @MainActor private static func snapshotUI(directory: URL) throws {
        _ = NSApplication.shared
        let stateDirectory = directory.appendingPathComponent("ui-state")
        let store = EditorStore(storageDirectory: stateDirectory)
        try require(store.showingHome && !store.hasOpenProject, "Fresh launch must show welcome")
        try snapshot(WelcomeView(store: store), size: CGSize(width: 1280, height: 820),
                     to: directory.appendingPathComponent("welcome.png"))
        try snapshot(NewProjectView(store: store), size: CGSize(width: 714, height: 568),
                     to: directory.appendingPathComponent("new-project.png"))
        try require(store.createProject(name: "Hafta sonu günlüğü", scene: .portrait, fps: 30), "Create project failed")
        try require(!store.showingHome && store.hasOpenProject && store.project.scene == .portrait, "Create must enter editor")
        let projectBeforeHome = store.project
        store.goHome()
        try require(store.showingHome && store.project == projectBeforeHome, "Home navigation discarded project")
        store.resumeProject()
        try require(!store.showingHome && store.project == projectBeforeHome, "Resume changed project")
        try snapshot(EditorView(store: store), size: CGSize(width: 1280, height: 820),
                     to: directory.appendingPathComponent("editor-empty.png"))
        let restored = EditorStore(storageDirectory: stateDirectory)
        try require(restored.showingHome && restored.recoveryAvailable, "Recovery must be offered, not auto-opened")
        restored.resumeProject()
        try require(restored.project == projectBeforeHome && !restored.showingHome, "Recovery failed")
        let opener = EditorStore(storageDirectory: directory.appendingPathComponent("recent-state"))
        opener.loadProject(at: directory.appendingPathComponent("smoke.gonavi"))
        try require(opener.recentProjects.count == 1 && !opener.showingHome, "Open must record recent project")
        opener.goHome()
        try snapshot(WelcomeView(store: opener), size: CGSize(width: 1280, height: 820),
                     to: directory.appendingPathComponent("welcome-recent.png"))
        opener.openRecent(opener.recentProjects[0])
        try require(opener.recentProjects.count == 1 && !opener.showingHome, "Recent reopening failed")
        opener.removeRecent(opener.recentProjects[0])
        try require(opener.recentProjects.isEmpty && FileManager.default.fileExists(atPath: directory.appendingPathComponent("smoke.gonavi").path), "Remove recent must preserve project file")
    }

    @MainActor private static func snapshot<V: View>(_ root: V, size: CGSize, to url: URL) throws {
        let view = NSHostingView(rootView: root.preferredColorScheme(.dark).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: size)
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded(); view.display()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ProjectError.invalid("UI bitmap creation failed")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    private static func makeVideo(_ url: URL, red: CGFloat, green: CGFloat) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                       AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        try require(writer.startWriting(), "Fixture writer failed")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<60 {
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing, "Fixture writer stopped")
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var optional: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &optional)
            guard let buffer = optional else { throw ProjectError.invalid("No fixture buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180,
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.setFillColor(CGColor(red: red, green: green, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)), "Fixture append failed")
        }
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 30))
        input.markAsFinished(); await writer.finishWriting()
        try require(writer.status == .completed, "Fixture finish failed")
    }

    private static func makeAudio(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 192000)!
        buffer.frameLength = 192000
        for index in 0..<192000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000) * 0.1) }
        try file.write(from: buffer)
    }

    private static func sample(_ image: CGImage) -> (red: Double, green: Double, bright: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let center = ((height / 2) * width + width / 2) * 4
        var bright = 0
        for index in stride(from: 0, to: data.count, by: 4) {
            if data[index] > 210 && data[index + 1] > 210 && data[index + 2] > 210 { bright += 1 }
        }
        return (Double(data[center]), Double(data[center + 1]), bright)
    }
}
