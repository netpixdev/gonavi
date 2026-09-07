import AppKit
import AVFoundation
import CoreImage
import GonaviCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Actual ImageIO import, composition export and AppKit interaction coverage.
/// The fixtures are generated locally and never require external media.
enum TransformSmokeTest {
    @MainActor static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("Transform: creating PNG and EXIF-oriented JPEG fixtures")
        let pngURL = directory.appendingPathComponent("Renkli fotoğraf.png")
        let jpegURL = directory.appendingPathComponent("Yön bilgili fotoğraf.jpg")
        try makePhoto(pngURL, type: UTType.png.identifier, orientation: 1)
        try makePhoto(jpegURL, type: UTType.jpeg.identifier, orientation: 6)
        let png = try await MediaEngine.inspect(pngURL), jpeg = try await MediaEngine.inspect(jpegURL)
        try SmokeTest.require(png.isStillImage && jpeg.isStillImage && !png.isVideo && png.isVisual,
                              "PNG/JPEG import must identify still visual sources")
        try SmokeTest.require(png.defaultClipDuration == EditTime(seconds: 5) && jpeg.defaultClipDuration == EditTime(seconds: 5),
                              "New photo clips must default to five seconds")
        let oriented = try referencePhoto(jpegURL)
        try SmokeTest.require(oriented.width == 180 && oriented.height == 320,
                              "JPEG EXIF orientation fixture must rotate 320x180 into 180x320")
        let sourcePreview = try await MediaEngine.previewSourceImage(jpeg, at: 0)
        try SmokeTest.require(sourcePreview.width == oriented.width && sourcePreview.height == oriented.height,
                              "Photo preview ignored orientation dimensions")
        try compareWholeImage(sourcePreview, expected: oriented, message: "Photo source preview orientation")

        let store = EditorStore(storageDirectory: directory.appendingPathComponent("photo-state"))
        _ = store.createProject(name: "Fotoğraflarla kurgu", scene: .portrait, fps: 30)
        store.importURLs([jpegURL, pngURL])
        try await ready(store)
        try SmokeTest.require(store.project.clips.count == 2 && store.project.clips.allSatisfy { $0.duration == EditTime(seconds: 5) },
                              "Editor import did not create two five-second photo clips")
        try SmokeTest.require(store.hasVideo && store.canExport, "Photo-only project must enable visual preview and MP4 export")
        try SmokeTest.require(store.project.schemaVersion == 3, "Photo projects must persist schema 3")
        let photoProject = store.project
        store.setPhotoDuration(8)
        try SmokeTest.require(store.project.clips[0].duration.seconds == 8 && store.project.start(of: store.project.clips[1].id).seconds == 8,
                              "Photo duration edit must move later clips by the duration delta")
        store.undo()
        try SmokeTest.require(store.project == photoProject, "Photo duration did not undo in one step")
        try await ready(store)
        try photoProject.encoded().write(to: directory.appendingPathComponent("photos.gonavi"))
        try SmokeTest.require(try Project.decode(photoProject.encoded()) == photoProject, "Photo project round-trip mismatch")
        store.player.replaceCurrentItem(with: nil)
        print("Transform: exporting photo-only timeline and checking first/last frames")
        let photoOutput = try await export(photoProject, to: directory.appendingPathComponent("photos.mp4"))
        let generator = AVAssetImageGenerator(asset: photoOutput)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 60000)).image
        let last = try await generator.image(at: CMTime(seconds: 9.9, preferredTimescale: 60000)).image
        try compareWholeImage(first, expected: oriented, message: "Exported JPEG orientation")
        let plain = try referencePhoto(pngURL)
        try comparePlacedImage(last, source: plain, scene: photoProject.scene, clip: photoProject.clips[1], message: "Final PNG frame")
        try save(first, to: directory.appendingPathComponent("oriented-photo-frame.png"))

        // Non-symmetric crop, a 90 degree rotation, zoom and translation together
        // catch lost crop origins, clockwise rotation and wrong scene coordinate axes.
        let transformedStore = EditorStore(storageDirectory: directory.appendingPathComponent("transform-state"))
        _ = transformedStore.createProject(name: "Kadrajı kendin belirle", scene: .landscape, fps: 30)
        transformedStore.importURLs([pngURL])
        try await ready(transformedStore)
        try SmokeTest.require(transformedStore.project.clips.count == 1, "Transform photo import failed")
        transformedStore.mutate { project in
            project.clips[0].crop = ClipCrop(left: 0.25, top: 0.10, right: 0.05, bottom: 0.10)
            project.clips[0].zoom = 0.45
            project.clips[0].rotation = 90
            project.clips[0].offsetX = 0.25
            project.clips[0].offsetY = -0.20
        }
        try await ready(transformedStore)
        let transformed = transformedStore.project
        try SmokeTest.require(try Project.decode(transformed.encoded()) == transformed, "Transform fields lost on project save/reopen")
        try transformed.encoded().write(to: directory.appendingPathComponent("transformed.gonavi"))
        let geometry = VisualGeometry.layout(sourceSize: CGSize(width: 320, height: 180),
                                             sceneSize: CGSize(width: 1920, height: 1080), clip: transformed.clips[0])
        let cropCenter = CGPoint(x: 192, y: 90).applying(geometry.transform)
        try SmokeTest.require(abs(cropCenter.x - 1200) < 0.01 && abs(cropCenter.y - 432) < 0.01,
                              "Transform moved the cropped source around the wrong center")
        // With fit scale 7.5 and zoom .45, a 16px vector to the right turns 54px upward.
        let rotatedRight = CGPoint(x: 208, y: 90).applying(geometry.transform)
        try SmokeTest.require(abs(rotatedRight.x - 1200) < 0.01 && abs(rotatedRight.y - 486) < 0.01,
                              "Positive rotation must be counterclockwise with the expected scale")
        transformedStore.selectedClip = transformed.clips[0].id
        transformedStore.seek(1)
        try await previewReady(transformedStore)
        try await snapshotEditor(transformedStore, size: CGSize(width: 1440, height: 900),
                               to: directory.appendingPathComponent("transform-colors-editor.png"))
        try await snapshotEditor(transformedStore, size: CGSize(width: 1040, height: 720),
                               to: directory.appendingPathComponent("transform-colors-compact.png"))
        transformedStore.player.replaceCurrentItem(with: nil)
        print("Transform: exporting cropped, rotated and positioned photo")
        let transformOutput = try await export(transformed, to: directory.appendingPathComponent("transformed.mp4"))
        let transformGenerator = AVAssetImageGenerator(asset: transformOutput)
        transformGenerator.requestedTimeToleranceBefore = .zero; transformGenerator.requestedTimeToleranceAfter = .zero
        let frame = try await transformGenerator.image(at: CMTime(seconds: 1, preferredTimescale: 60000)).image
        try comparePlacedImage(frame, source: plain, scene: .landscape, clip: transformed.clips[0], message: "Crop/rotate/move export")
        for point in [CGPoint(x: 100, y: 100), CGPoint(x: 1800, y: 900)] {
            let color = pixel(frame, at: point)
            try SmokeTest.require(color.prefix(3).allSatisfy { $0 < 0.035 }, "Transformed photo must leave scene background black")
        }
        try save(frame, to: directory.appendingPathComponent("transformed-frame.png"))
        print("Transform: native preview move/resize/rotate/crop, undo and cancellation")
        try await nativeInteractions(store: transformedStore, source: plain, directory: directory)
        try await videoAndPhotoScene(directory: directory)

        let report: [String: Any] = [
            "status": "PASS", "projectSchema": 3, "defaultPhotoSeconds": 5,
            "photoTimelineSeconds": photoProject.duration.seconds,
            "checks": ["PNG and EXIF-oriented JPEG import", "oriented source preview",
                       "five-second photo clips", "photo-only MP4 first and final frames",
                       "source crop, CCW rotation, zoom and translation pixels", "black scene outside transformed photo",
                       "photo and transform project round-trip", "full and compact native editor screenshots",
                       "native preview move, resize, rotate and crop", "draft does not mutate project",
                       "single undo per gesture", "Escape and stale draft cancellation"]
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("transform-smoke.json"))
    }

    @MainActor private static func videoAndPhotoScene(directory: URL) async throws {
        let videoURL = directory.appendingPathComponent("Kıyı yürüyüşü.mov")
        try await SmokeTest.makeVideo(videoURL, red: 0.2, green: 0.5, illustrated: true)
        let media = try await MediaEngine.inspect(videoURL)
        let source = try await MediaEngine.previewSourceImage(media, at: 0.5)
        let photoURL = directory.appendingPathComponent("Kıyıdan bir kare.png")
        try save(source, to: photoURL)
        let store = EditorStore(storageDirectory: directory.appendingPathComponent("visual-scene-state"))
        _ = store.createProject(name: "Kıyı günlüğü · Kadraj çalışması", scene: .landscape, fps: 30)
        store.importURLs([videoURL, photoURL]); try await ready(store)
        store.mutate { project in
            for i in project.clips.indices {
                project.clips[i].zoom = 0.78
                project.clips[i].rotation = -8
                project.clips[i].crop = ClipCrop(left: 0.05, right: 0.05)
                project.clips[i].offsetX = -0.05; project.clips[i].offsetY = 0.1
            }
            var caption = Caption(start: .init(seconds: 2), duration: .init(seconds: 4), text: "Hikâyeye kendi açından bak.")
            caption.style = .clean; project.captions = [caption]
        }
        try await ready(store)
        let project = store.project
        let output = try await export(project, to: directory.appendingPathComponent("visual-scene.mp4"))
        let generator = AVAssetImageGenerator(asset: output)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let videoFrame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 60000)).image
        try comparePlacedImage(videoFrame, source: source, scene: .landscape, clip: project.clips[0], message: "Video transform export")
        store.selectedClip = project.clips[1].id; store.seek(3)
        try await previewReady(store)
        try await snapshotEditor(store, size: CGSize(width: 1440, height: 900), to: directory.appendingPathComponent("transform-editor.png"))
        try await snapshotEditor(store, size: CGSize(width: 1040, height: 720), to: directory.appendingPathComponent("transform-compact.png"))
    }

    @MainActor private static func nativeInteractions(store: EditorStore, source: CGImage, directory: URL) async throws {
        store.mutate { project in
            project.clips[0].zoom = 0.70; project.clips[0].rotation = 0
            project.clips[0].crop = ClipCrop(); project.clips[0].offsetX = 0; project.clips[0].offsetY = 0
        }
        try await ready(store)
        let canvas = TransformCanvas(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func configure(_ tool: PreviewTool = .move) {
            canvas.configure(store: store, clip: store.project.clips[0], image: source, tool: tool)
        }
        func mouse(_ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers,
                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                              eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func drag(from: CGPoint, to: CGPoint) {
            canvas.mouseDown(with: mouse(.leftMouseDown, at: from))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: to))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: to))
        }
        let original = store.project
        configure()
        let center = CGPoint(x: canvas.stage.midX, y: canvas.stage.midY)
        let destination = CGPoint(x: center.x + 90, y: center.y + 30)
        let moveRevision = store.revision
        canvas.mouseDown(with: mouse(.leftMouseDown, at: center))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: center.x + 30, y: center.y + 10)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: destination))
        try SmokeTest.require(store.project == original && canvas.draft != nil, "Preview drag mutated committed project before mouse-up")
        canvas.mouseUp(with: mouse(.leftMouseUp, at: destination))
        try SmokeTest.require(store.revision == moveRevision + 1 && store.project.clips[0].offsetX > 0.1 && store.project.clips[0].offsetY > 0.05,
                              "Native move must commit once and move right/up")
        store.undo(); try SmokeTest.require(store.project == original, "Native preview move did not undo once")
        try await ready(store); configure()

        store.updateClip { $0.zoom = 2 }
        try await ready(store)
        canvas.configure(store: store, clip: store.project.clips[0], image: source, tool: .move, viewportZoom: 0.25)
        try SmokeTest.require(canvas.handlePoints().allSatisfy { canvas.bounds.contains($0) }, "Viewport zoom did not recover off-canvas resize handles")
        store.undo(); try SmokeTest.require(store.project == original, "Viewport zoom changed project transform")
        try await ready(store); configure()

        canvas.mouseDown(with: mouse(.leftMouseDown, at: center))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: destination))
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                                            charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53) else {
            throw ProjectError.invalid("Escape fixture event missing")
        }
        canvas.keyDown(with: escape)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: destination))
        try SmokeTest.require(canvas.draft == nil && store.project == original, "Escape failed to abandon preview gesture")

        configure()
        let corner = canvas.handlePoints()[1]
        let grown = CGPoint(x: center.x + (corner.x - center.x) * 1.25, y: center.y + (corner.y - center.y) * 1.25)
        drag(from: corner, to: grown)
        try SmokeTest.require(abs(store.project.clips[0].zoom - 0.875) < 0.001, "Native corner resize failed")
        store.undo(); try SmokeTest.require(store.project == original, "Native resize did not undo once")
        try await ready(store); configure()

        guard let rotation = canvas.rotationPoint() else { throw ProjectError.invalid("Rotation handle missing") }
        let left = CGPoint(x: center.x - (rotation.y - center.y), y: center.y)
        drag(from: rotation, to: left)
        try SmokeTest.require(abs(store.project.clips[0].rotation - 90) < 0.01, "Native rotation direction or angle incorrect")
        store.undo(); try SmokeTest.require(store.project == original, "Native rotation did not undo once")
        try await ready(store); configure(.crop)

        let cropCorners = canvas.handlePoints()
        let top = CGPoint(x: (cropCorners[0].x + cropCorners[1].x) / 2, y: (cropCorners[0].y + cropCorners[1].y) / 2)
        let cropEnd = CGPoint(x: top.x, y: top.y - 40)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: top))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: cropEnd))
        try SmokeTest.require((canvas.draft?.crop.top ?? 0) > 0.05 && store.project == original, "Native crop did not preserve draft semantics")
        canvas.display()
        guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds), let draft = canvas.draft else {
            throw ProjectError.invalid("Crop canvas capture missing")
        }
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("transform-crop-canvas.png"))
        guard let canvasImage = bitmap.cgImage else { throw ProjectError.invalid("Canvas pixels missing") }
        let geometry = VisualGeometry.layout(sourceSize: CGSize(width: source.width, height: source.height),
                                             sceneSize: CGSize(width: 1920, height: 1080), clip: draft)
        for x in [CGFloat(0.25), CGFloat(0.75)] {
            for y in [CGFloat(0.25), CGFloat(0.75)] {
                let sourcePoint = CGPoint(x: geometry.cropRect.minX + geometry.cropRect.width * x,
                                          y: geometry.cropRect.minY + geometry.cropRect.height * y)
                let scenePoint = sourcePoint.applying(geometry.transform)
                let viewPoint = CGPoint(x: canvas.stage.minX + scenePoint.x * canvas.stage.width / 1920,
                                        y: canvas.stage.minY + scenePoint.y * canvas.stage.height / 1080)
                let pixelPoint = CGPoint(x: viewPoint.x * CGFloat(canvasImage.width) / canvas.bounds.width,
                                         y: viewPoint.y * CGFloat(canvasImage.height) / canvas.bounds.height)
                try compare(pixel(canvasImage, at: pixelPoint), pixel(source, at: sourcePoint), message: "Native crop canvas orientation/geometry")
            }
        }
        canvas.mouseUp(with: mouse(.leftMouseUp, at: cropEnd))
        try SmokeTest.require(store.project.clips[0].crop.top > 0.05 && store.project.clips[0].crop.bottom == 0,
                              "Native top crop changed the wrong source edge")
        store.undo(); try SmokeTest.require(store.project == original, "Native crop did not undo once")
        try await ready(store); configure()

        canvas.mouseDown(with: mouse(.leftMouseDown, at: center))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: destination))
        store.mutate { $0.name = "Dışarıdan güncellenen proje" }
        let externallyChanged = store.project
        configure()
        canvas.mouseUp(with: mouse(.leftMouseUp, at: destination))
        try SmokeTest.require(canvas.draft == nil && store.project == externallyChanged,
                              "Stale preview gesture overwrote a newer project revision")
    }

    @MainActor private static func ready(_ store: EditorStore) async throws {
        for _ in 0..<2000 {
            if !store.importing && !store.isBuilding { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(!store.importing && !store.isBuilding && store.error == nil, store.error ?? "Photo preview build timed out")
    }

    @MainActor private static func snapshotEditor(_ store: EditorStore, size: CGSize, to url: URL) async throws {
        let view = NSHostingView(rootView: EditorView(store: store).preferredColorScheme(.dark).frame(width: size.width, height: size.height))
        let window = TransformSnapshotWindow(contentRect: NSRect(origin: .zero, size: size),
                                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        view.sizingOptions = []; window.contentView = view; window.appearance = NSAppearance(named: .darkAqua)
        window.orderFront(nil); window.setContentSize(size); view.frame = NSRect(origin: .zero, size: size)
        defer { window.orderOut(nil) }
        func canvas(in node: NSView) -> TransformCanvas? {
            if let result = node as? TransformCanvas { return result }
            return node.subviews.compactMap { canvas(in: $0) }.first
        }
        for _ in 0..<500 {
            view.layoutSubtreeIfNeeded(); view.display()
            if canvas(in: view)?.hasSourceImage == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try SmokeTest.require(canvas(in: view)?.hasSourceImage == true, "Interactive editor failed to load its source image")
        try SmokeTest.require(view.bounds.size == size, "Interactive editor capture was clipped by runner display")
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ProjectError.invalid("Editor capture allocation failed") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor private static func previewReady(_ store: EditorStore) async throws {
        for _ in 0..<500 {
            if store.previewFrame != nil { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ProjectError.invalid(store.error ?? "Transformed paused preview frame missing")
    }

    private static func makePhoto(_ url: URL, type: String, orientation: Int) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ProjectError.invalid("Photo fixture bitmap allocation failed")
        }
        let colors = [NSColor(srgbRed: 0.85, green: 0.12, blue: 0.10, alpha: 1),
                      NSColor(srgbRed: 0.12, green: 0.80, blue: 0.18, alpha: 1),
                      NSColor(srgbRed: 0.10, green: 0.18, blue: 0.85, alpha: 1),
                      NSColor(srgbRed: 0.85, green: 0.75, blue: 0.10, alpha: 1)]
        for y in 0..<180 {
            for x in 0..<320 { bitmap.setColor(colors[(y >= 90 ? 2 : 0) + (x >= 160 ? 1 : 0)], atX: x, y: y) }
        }
        guard let cgImage = bitmap.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw ProjectError.invalid("Photo fixture destination failed")
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: orientation,
                                                        kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        try SmokeTest.require(CGImageDestinationFinalize(destination), "Photo fixture encoding failed")
    }

    /// ImageIO's oriented thumbnail is an independent reference for import orientation.
    private static func referencePhoto(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw ProjectError.invalid("Reference photo decode failed") }
        return image
    }

    private static func export(_ project: Project, to url: URL) async throws -> AVURLAsset {
        let prepared = try await MediaEngine.prepare(project)
        try SmokeTest.require(prepared.videoComposition != nil, "Photo composition must have a video renderer")
        guard let exporter = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProjectError.invalid("Photo exporter unavailable")
        }
        exporter.outputURL = url; exporter.outputFileType = .mp4
        exporter.videoComposition = prepared.videoComposition; exporter.audioMix = prepared.audioMix
        await exporter.export()
        try SmokeTest.require(exporter.status == .completed, exporter.error.map { String(reflecting: $0 as NSError) } ?? "Photo export failed")
        let asset = AVURLAsset(url: url), duration = try await asset.load(.duration)
        try SmokeTest.require(abs(duration.seconds - project.duration.seconds) < 1.0 / Double(project.fps), "Photo export duration mismatch")
        return asset
    }

    private static func compareWholeImage(_ actual: CGImage, expected: CGImage, message: String) throws {
        for x in [0.25, 0.75] {
            for y in [0.25, 0.75] {
                let actualPoint = CGPoint(x: Double(actual.width) * x, y: Double(actual.height) * y)
                let expectedPoint = CGPoint(x: Double(expected.width) * x, y: Double(expected.height) * y)
                try compare(pixel(actual, at: actualPoint), pixel(expected, at: expectedPoint), message: message)
            }
        }
    }

    private static func comparePlacedImage(_ actual: CGImage, source: CGImage, scene: ScenePreset,
                                            clip: VideoClip, message: String) throws {
        let geometry = VisualGeometry.layout(sourceSize: CGSize(width: source.width, height: source.height),
                                             sceneSize: CGSize(width: scene.width, height: scene.height), clip: clip)
        for x in [CGFloat(0.25), CGFloat(0.75)] {
            for y in [CGFloat(0.25), CGFloat(0.75)] {
                let point = CGPoint(x: geometry.cropRect.minX + geometry.cropRect.width * x,
                                    y: geometry.cropRect.minY + geometry.cropRect.height * y)
                let position = point.applying(geometry.transform)
                try SmokeTest.require(position.x > 0 && position.x < CGFloat(actual.width) &&
                                      position.y > 0 && position.y < CGFloat(actual.height), "Transform fixture sample left scene")
                try compare(pixel(actual, at: position), pixel(source, at: point), message: message)
            }
        }
    }

    private static func compare(_ actual: [Float], _ expected: [Float], message: String) throws {
        // SDR video encoding and ColorSync conversions may differ slightly from the still.
        let maximumError = zip(actual.prefix(3), expected.prefix(3)).map { abs($0 - $1) }.max() ?? 1
        try SmokeTest.require(maximumError < 0.13, "\(message): actual \(actual), expected \(expected)")
    }

    /// Both Core Image and VisualGeometry use a bottom-left source origin.
    private static func pixel(_ image: CGImage, at point: CGPoint) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var components = [Float](repeating: 0, count: 4)
        components.withUnsafeMutableBytes { bytes in
            context.render(CIImage(cgImage: image), toBitmap: bytes.baseAddress!, rowBytes: 16,
                           bounds: CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return components
    }

    private static func save(_ image: CGImage, to url: URL) throws {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}

private final class TransformSnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
