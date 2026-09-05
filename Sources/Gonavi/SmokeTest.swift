import AppKit
import AVFoundation
import GonaviCore

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
        let report = "PASS: project round-trip, 4s export, 1920×1080, two ordered clips, audio track, caption visibility and timing.\n"
        try report.write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
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
