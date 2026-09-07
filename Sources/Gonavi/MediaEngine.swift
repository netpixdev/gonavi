import AppKit
import AVFoundation
import CoreImage
import GonaviCore

extension EditTime {
    var cm: CMTime { CMTime(value: ticks, timescale: CMTimeScale(Self.scale)) }
}

struct RenderCaption {
    let start: Double
    let end: Double
    let image: CIImage
}

final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    // Captions can change while a held source frame stays identical. Request every
    // output frame, including trailing black regions, on both hardware encoders.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let clip: VideoClip
    let captions: [RenderCaption]
    let stillImage: CIImage?
    init(range: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform,
         clip: VideoClip, captions: [RenderCaption], stillImage: CIImage? = nil) {
        timeRange = range; self.trackID = trackID; self.transform = transform
        self.clip = clip; self.captions = captions; self.stillImage = stillImage
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Both AVPlayer and AVAssetExportSession consume these same instructions.
/// Rendering stays off the main thread. No mutable project state is read here.
final class GonaviCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()]
    }
    private let queue = DispatchQueue(label: "app.gonavi.compositor", qos: .userInitiated)
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            autoreleasepool { self.render(request) }
        }
    }
    private func render(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: ProjectError.invalid("Video karesi oluşturulamadı.")); return
        }
        let bounds = CGRect(origin: .zero, size: request.renderContext.size)
        var image: CIImage
        if let still = instruction.stillImage {
            image = still
        } else if let source = request.sourceFrame(byTrackID: instruction.trackID) {
            image = CIImage(cvPixelBuffer: source).transformed(by: instruction.transform)
        } else {
            request.finish(with: ProjectError.invalid("Kaynak video karesi okunamadı.")); return
        }
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else {
            request.finish(with: ProjectError.invalid("Kaynak görüntü boyutu geçersiz.")); return
        }
        image = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        let layout = VisualGeometry.layout(sourceSize: extent.size, sceneSize: bounds.size, clip: instruction.clip)
        image = image.cropped(to: layout.cropRect).transformed(by: layout.transform)
        var frame = image.composited(over: CIImage(color: .black).cropped(to: bounds)).cropped(to: bounds)
        let time = request.compositionTime.seconds
        for caption in instruction.captions where time >= caption.start && time < caption.end {
            frame = caption.image.composited(over: frame)
        }
        context.render(frame, to: output, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        request.finish(withComposedVideoFrame: output)
    }
}

struct PreparedTimeline {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition?
    let audioMix: AVMutableAudioMix
    func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition; item.audioMix = audioMix
        return item
    }
}

enum MediaEngine {
    static func resolve(_ source: MediaSource) throws -> URL {
        if let data = source.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
                                  bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let url = URL(fileURLWithPath: source.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.invalid("Medya bulunamadı: \(source.name). Medya listesinden yeniden bağlayın.")
        }
        return url
    }

    static func inspect(_ url: URL) async throws -> MediaSource {
        try Task.checkCancellation()
        if PhotoSource.isImageURL(url) {
            try PhotoSource.validate(url)
            try Task.checkCancellation()
            var source = MediaSource(name: url.lastPathComponent, path: url.path,
                bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                duration: EditTime(seconds: 86_400), isVideo: false)
            source.isStillImage = true
            return source
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 86400,
              !video.isEmpty || !audio.isEmpty else { throw ProjectError.invalid("Desteklenmeyen medya: \(url.lastPathComponent)") }
        return MediaSource(name: url.lastPathComponent, path: url.path,
                           bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                           duration: EditTime(seconds: duration.seconds), isVideo: !video.isEmpty)
    }

    /// A raw, source-oriented frame for the live canvas. The canvas applies the
    /// same VisualGeometry used by the compositor; captions remain independent.
    static func previewSourceImage(_ source: MediaSource, at seconds: Double) async throws -> CGImage {
        try Task.checkCancellation()
        let url = try resolve(source)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if source.isStillImage {
            let image = try PhotoSource.thumbnail(url, maximum: 1920)
            try Task.checkCancellation()
            return image
        }
        guard source.isVideo else { throw ProjectError.invalid("Ses dosyasının görüntü karesi yok.") }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Never request the exclusive end of a video track.
        let position = max(0, min(seconds.isFinite ? seconds : 0, max(0, source.duration.seconds - 1.0 / 60_000)))
        return try await withTaskCancellationHandler(operation: {
            let result = try await generator.image(at: CMTime(seconds: position, preferredTimescale: 60_000))
            try Task.checkCancellation()
            return result.image
        }, onCancel: { generator.cancelAllCGImageGeneration() })
    }

    static func prepare(_ project: Project) async throws -> PreparedTimeline {
        try project.validate()
        let composition = AVMutableComposition()
        let hasVideo = project.clips.contains { clip in project.sources.contains { $0.id == clip.sourceID && $0.isVisual } }
        let videoTrack = hasVideo ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        guard let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.invalid("Kurgu hatları oluşturulamadı.")
        }
        let size = CGSize(width: project.scene.width, height: project.scene.height)
        let renderedCaptions = project.captions.compactMap { renderCaption($0, size: size) }
        var instructions: [FrameInstruction] = []
        let soundParameters = AVMutableAudioMixInputParameters(track: soundTrack)
        var mixParameters = [soundParameters]
        var cursor = CMTime.zero
        var stillImages: [UUID: CIImage] = [:]
        func background(start: CMTime, duration: CMTime, clip: VideoClip? = nil, stillImage: CIImage? = nil) async throws {
            guard let videoTrack, duration > .zero else { return }
            let asset = AVURLAsset(url: try await BlackFrameSource.shared.url())
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ProjectError.invalid("Sahne oluşturulamadı.") }
            let frame = CMTime(value: 1, timescale: 30)
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: frame), of: track, at: start)
            videoTrack.scaleTimeRange(CMTimeRange(start: start, duration: frame), toDuration: duration)
            let placeholder = clip ?? VideoClip(sourceID: UUID(), duration: EditTime(seconds: duration.seconds))
            instructions.append(FrameInstruction(range: CMTimeRange(start: start, duration: duration), trackID: videoTrack.trackID,
                                                 transform: .identity, clip: placeholder, captions: renderedCaptions.filter {
                $0.end > start.seconds && $0.start < (start + duration).seconds
            }, stillImage: stillImage))
        }
        for clip in project.clips {
            try Task.checkCancellation()
            guard let media = project.sources.first(where: { $0.id == clip.sourceID }) else {
                throw ProjectError.invalid("Klip kaynağı bulunamadı.")
            }
            let start = project.start(of: clip.id).cm
            if start > cursor { try await background(start: cursor, duration: start - cursor) }
            cursor = start
            let range = CMTimeRange(start: clip.sourceStart.cm, duration: clip.duration.cm)
            if media.isStillImage {
                let still: CIImage
                if let cached = stillImages[media.id] { still = cached }
                else {
                    still = try PhotoSource.image(resolve(media))
                    stillImages[media.id] = still
                }
                try await background(start: cursor, duration: clip.duration.cm, clip: clip, stillImage: still)
            } else {
                let asset = AVURLAsset(url: try resolve(media))
                if media.isVideo, let videoTrack {
                    guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ProjectError.invalid("Video hattı bulunamadı: \(media.name)")
                    }
                    try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
                    let transform = try await sourceVideo.load(.preferredTransform)
                    instructions.append(FrameInstruction(range: CMTimeRange(start: cursor, duration: clip.duration.cm),
                                                         trackID: videoTrack.trackID, transform: transform, clip: clip,
                                                         captions: renderedCaptions.filter {
                        $0.end > cursor.seconds && $0.start < (cursor + clip.duration.cm).seconds
                    }))
                } else { try await background(start: cursor, duration: clip.duration.cm) }
                if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                    let available = try await sourceAudio.load(.timeRange)
                    let intersection = CMTimeRangeGetIntersection(range, otherRange: available)
                    if intersection.duration > .zero {
                        let position = cursor + (intersection.start - range.start)
                        try soundTrack.insertTimeRange(intersection, of: sourceAudio, at: position)
                    }
                }
            }
            soundParameters.setVolume(Float(clip.volume), at: cursor)
            cursor = cursor + clip.duration.cm
        }
        cursor = project.duration.cm
        if soundTrack.timeRange.duration < cursor {
            soundTrack.insertEmptyTimeRange(CMTimeRange(start: soundTrack.timeRange.duration, duration: cursor - soundTrack.timeRange.duration))
        }
        if let music = project.music, cursor > .zero,
           let source = project.sources.first(where: { $0.id == music.sourceID }),
           let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let asset = AVURLAsset(url: try resolve(source))
            guard let audio = try await asset.loadTracks(withMediaType: .audio).first else {
                throw ProjectError.invalid("Seçilen dosyada ses hattı yok.")
            }
            let available = try await audio.load(.timeRange)
            let length = CMTimeMinimum(cursor, available.duration)
            try musicTrack.insertTimeRange(.init(start: available.start, duration: length), of: audio, at: .zero)
            let parameters = AVMutableAudioMixInputParameters(track: musicTrack)
            parameters.setVolume(Float(music.volume), at: .zero)
            let fade = CMTimeMinimum(CMTime(seconds: 0.2, preferredTimescale: 60000), length)
            parameters.setVolumeRamp(fromStartVolume: Float(music.volume), toEndVolume: 0,
                                     timeRange: .init(start: length - fade, duration: fade))
            mixParameters.append(parameters)
        }
        let mix = AVMutableAudioMix(); mix.inputParameters = mixParameters
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = GonaviCompositor.self
        video.renderSize = size; video.frameDuration = CMTime(value: 1, timescale: Int32(project.fps))
        video.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        video.instructions = instructions
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return PreparedTimeline(composition: composition, videoComposition: hasVideo ? video : nil, audioMix: mix)
    }

    /// Rasterize once per caption, not once per video frame. Same CI image in preview/export.
    static func renderCaption(_ caption: Caption, size: CGSize) -> RenderCaption? {
        let fontSize = size.width * 0.044
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: caption.style == .bold ? .heavy : .semibold),
            .foregroundColor: caption.style == .bold ? NSColor.systemYellow : NSColor.white,
            .strokeColor: NSColor.black, .strokeWidth: -3,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: caption.text, attributes: attributes)
        let textWidth = size.width * 0.84
        let measured = text.boundingRect(with: CGSize(width: textWidth, height: size.height * 0.5),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        // Keep only the caption-sized bitmap; a full 1080p bitmap per line would
        // retain hundreds of MB for an ordinary transcript.
        let rect = CGRect(x: 16, y: 8, width: textWidth, height: ceil(measured.height) + 12)
        let bitmapSize = CGSize(width: ceil(textWidth + 32), height: ceil(rect.height + 16))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bitmapSize.width),
                                           pixelsHigh: Int(bitmapSize.height), bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        NSColor.clear.setFill(); NSRect(origin: .zero, size: bitmapSize).fill(using: .copy)
        if caption.style == .box {
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -16, dy: -8), xRadius: 12, yRadius: 12).fill()
        }
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = bitmap.cgImage else { return nil }
        return RenderCaption(start: caption.start.seconds, end: (caption.start + caption.duration).seconds,
                             image: CIImage(cgImage: cgImage).transformed(by: .init(
                                translationX: size.width * 0.08 - 16, y: size.height * 0.1 - 8)))
    }
}
