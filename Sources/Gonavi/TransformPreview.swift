import AppKit
import CoreImage
import GonaviCore
import SwiftUI

enum PreviewTool: String, CaseIterable {
    case move = "Taşı", crop = "Kırp"
}

private struct SourceFrameKey: Equatable {
    let source: MediaSource?
    let frame: Int64
}

@MainActor
private final class PreviewSourceLoader: ObservableObject {
    @Published var image: CGImage?
    @Published var message: String?
    func load(_ source: MediaSource?, time: Double) async {
        image = nil; message = nil
        guard let source else { return }
        do {
            let result = try await MediaEngine.previewSourceImage(source, at: time)
            try Task.checkCancellation()
            image = result
        } catch {
            if !Task.isCancelled { message = "Görüntü düzenleme karesi okunamadı. Dosyayı yeniden bağlayın." }
        }
    }
}

struct TransformPreview: View {
    @ObservedObject var store: EditorStore
    @State private var tool: PreviewTool = .move
    @StateObject private var loader = PreviewSourceLoader()

    private var clip: VideoClip? {
        guard !store.isPlaying, let clip = store.activeClip,
              store.project.sources.first(where: { $0.id == clip.sourceID })?.isVisual == true else { return nil }
        let start = store.project.start(of: clip.id).seconds
        return store.playhead >= start - 0.0001 && store.playhead < start + clip.duration.seconds ? clip : nil
    }
    private var source: MediaSource? { store.project.sources.first { $0.id == clip?.sourceID } }
    private var sourceTime: Double {
        guard let clip else { return 0 }
        return max(0, clip.sourceStart.seconds + store.playhead - store.project.start(of: clip.id).seconds)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Önizleme aracı", selection: $tool) {
                    Label("Taşı", systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(PreviewTool.move)
                    Label("Kırp", systemImage: "crop").tag(PreviewTool.crop)
                }.pickerStyle(.segmented).frame(width: 155).disabled(clip == nil || !store.editable)
                Spacer(minLength: 4)
                Button { store.focusSelectedVisualClip() } label: { Image(systemName: "scope") }
                    .help("Seçili klibe git").disabled(store.activeClip == nil || !store.editable)
                Button { store.resetVisualTransform() } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Görüntüyü sıfırla").disabled(clip == nil || !store.editable)
            }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 8)
            GeometryReader { proxy in
                let rect = TransformCanvas.stageRect(in: CGRect(origin: .zero, size: proxy.size), scene: store.project.scene)
                ZStack {
                    PlayerSurface(player: store.player)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    if !store.isPlaying, let frame = store.previewFrame {
                        Image(nsImage: frame).resizable().scaledToFit()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
                    }
                    TransformSurface(store: store, clip: clip, image: loader.image, tool: tool)
                }
            }
            Text(loader.message ?? (clip == nil ? "Düzenlemek için timeline’dan bir görüntü seçin." :
                tool == .move ? "Sürükle: taşı · Köşeler: ölçekle · Üst tutamak: döndür · Esc: vazgeç" :
                "Kenar tutamaklarını sürükleyerek kırpın · Esc: vazgeç"))
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
                .frame(minHeight: 28).padding(.horizontal, 12)
        }
        .task(id: SourceFrameKey(source: source, frame: source?.isStillImage == true ? 0 : Int64((sourceTime * Double(store.project.fps)).rounded()))) {
            await loader.load(source, time: sourceTime)
        }
    }
}

private struct TransformSurface: NSViewRepresentable {
    let store: EditorStore
    let clip: VideoClip?
    let image: CGImage?
    let tool: PreviewTool
    func makeNSView(context: Context) -> TransformCanvas { TransformCanvas() }
    func updateNSView(_ view: TransformCanvas, context: Context) {
        view.configure(store: store, clip: clip, image: image, tool: tool)
    }
}

/// Drafts stay in this view. A mouse-up commits one validated project change.
/// The same bottom-left source-to-scene geometry is used by the video compositor.
@MainActor
final class TransformCanvas: NSView {
    private(set) weak var store: EditorStore?
    private(set) var clip: VideoClip?
    private(set) var draft: VideoClip?
    private var sourceImage: CGImage?
    var hasSourceImage: Bool { sourceImage != nil }
    private var tool = PreviewTool.move
    private var revision = -1
    private var captions: [RenderCaption] = []
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var drag: Drag?
    private struct Drag {
        enum Kind { case move, scale, rotate, crop(Int) }
        let kind: Kind
        let clip: VideoClip
        let start: CGPoint
        let layout: VisualLayout
        let stage: CGRect
        let revision: Int
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func stageRect(in bounds: CGRect, scene: ScenePreset) -> CGRect {
        let available = bounds.insetBy(dx: 32, dy: 32)
        let scale = max(0.001, min(available.width / CGFloat(scene.width), available.height / CGFloat(scene.height)))
        let size = CGSize(width: CGFloat(scene.width) * scale, height: CGFloat(scene.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    var stage: CGRect { Self.stageRect(in: bounds, scene: store?.project.scene ?? .portrait) }
    private var sceneSize: CGSize {
        CGSize(width: store?.project.scene.width ?? 1080, height: store?.project.scene.height ?? 1920)
    }
    private var sourceSize: CGSize { CGSize(width: sourceImage?.width ?? 1, height: sourceImage?.height ?? 1) }
    private var sceneToView: CGAffineTransform {
        let scale = stage.width / sceneSize.width
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: stage.minX, ty: stage.minY)
    }
    private var canInteract: Bool {
        store?.editable == true && store?.isPlaying == false && clip != nil && sourceImage != nil
    }
    func configure(store: EditorStore, clip: VideoClip?, image: CGImage?, tool: PreviewTool) {
        if self.revision != store.revision || self.clip?.id != clip?.id || self.tool != tool || !store.editable || store.isPlaying {
            cancelDraft()
        }
        if self.revision != store.revision {
            let size = CGSize(width: store.project.scene.width, height: store.project.scene.height)
            captions = store.project.captions.compactMap { MediaEngine.renderCaption($0, size: size) }
        }
        self.store = store; self.clip = clip; sourceImage = image; self.tool = tool; revision = store.revision
        needsDisplay = true
    }
    private func layout(for clip: VideoClip) -> VisualLayout {
        VisualGeometry.layout(sourceSize: sourceSize, sceneSize: sceneSize, clip: clip)
    }
    func handlePoints() -> [CGPoint] {
        guard let current = draft ?? clip else { return [] }
        let geometry = layout(for: current)
        return geometry.corners.map { $0.applying(sceneToView) }
    }
    private func midpoints(_ points: [CGPoint]) -> [CGPoint] {
        points.indices.map { i in
            let next = points[(i + 1) % points.count]
            return CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2)
        }
    }
    func rotationPoint() -> CGPoint? {
        let points = handlePoints()
        guard points.count == 4, let current = draft ?? clip else { return nil }
        let top = midpoints(points)[0], angle = CGFloat(current.rotation) * .pi / 180
        return CGPoint(x: top.x - sin(angle) * 24, y: top.y + cos(angle) * 24)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let sourceImage, let current = draft ?? clip {
            let geometry = layout(for: current)
            context.saveGState()
            context.clip(to: stage)
            context.setFillColor(NSColor.black.cgColor); context.fill(stage)
            context.concatenate(geometry.transform.concatenating(sceneToView))
            context.clip(to: geometry.cropRect)
            context.interpolationQuality = .high
            context.draw(sourceImage, in: CGRect(origin: .zero, size: sourceSize))
            context.restoreGState()
            if let store {
                context.saveGState(); context.clip(to: stage); context.concatenate(sceneToView)
                for caption in captions where store.playhead >= caption.start && store.playhead < caption.end {
                    if let image = imageContext.createCGImage(caption.image, from: caption.image.extent) {
                        context.draw(image, in: caption.image.extent)
                    }
                }
                context.restoreGState()
            }
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(1); context.stroke(stage)
        guard canInteract else { return }
        let points = handlePoints()
        guard points.count == 4 else { return }
        let accent = NSColor(calibratedRed: 0.42, green: 0.91, blue: 0.74, alpha: 1)
        context.setStrokeColor(accent.cgColor); context.setLineWidth(1.5)
        context.addLines(between: points); context.closePath(); context.strokePath()
        func handle(_ point: CGPoint, round: Bool = false) {
            let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.setFillColor(NSColor.white.cgColor); context.setStrokeColor(accent.cgColor)
            if round { context.fillEllipse(in: rect); context.strokeEllipse(in: rect) }
            else { context.fill(rect); context.stroke(rect) }
        }
        if tool == .crop {
            for point in midpoints(points) { handle(point) }
            context.saveGState(); context.setStrokeColor(accent.withAlphaComponent(0.35).cgColor)
            for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
                }
                context.move(to: mix(points[0], points[1])); context.addLine(to: mix(points[3], points[2]))
                context.move(to: mix(points[0], points[3])); context.addLine(to: mix(points[1], points[2]))
            }
            context.strokePath(); context.restoreGState()
        } else {
            points.forEach { handle($0) }
            if let rotation = rotationPoint() {
                context.move(to: midpoints(points)[0]); context.addLine(to: rotation); context.strokePath()
                handle(rotation, round: true)
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard canInteract, let clip else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil), points = handlePoints()
        func nearby(_ handle: CGPoint) -> Bool { hypot(point.x - handle.x, point.y - handle.y) <= 12 }
        let kind: Drag.Kind
        if tool == .crop, let index = midpoints(points).firstIndex(where: nearby) { kind = .crop(index) }
        else if tool == .move, let rotation = rotationPoint(), nearby(rotation) { kind = .rotate }
        else if tool == .move, points.contains(where: nearby) { kind = .scale }
        else {
            let polygon = NSBezierPath(); polygon.move(to: points[0])
            points.dropFirst().forEach { polygon.line(to: $0) }; polygon.close()
            guard tool == .move, polygon.contains(point) else { return }
            kind = .move
        }
        drag = Drag(kind: kind, clip: clip, start: point, layout: layout(for: clip), stage: stage, revision: revision)
        draft = clip; NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let drag, drag.revision == store?.revision, canInteract, drag.stage == stage else { cancelDraft(); return }
        let point = convert(event.locationInWindow, from: nil)
        let scale = stage.width / sceneSize.width
        let dx = (point.x - drag.start.x) / scale, dy = (point.y - drag.start.y) / scale
        var value = drag.clip
        switch drag.kind {
        case .move:
            value.offsetX = min(4, max(-4, value.offsetX + Double(dx * 2 / sceneSize.width)))
            value.offsetY = min(4, max(-4, value.offsetY + Double(dy * 2 / sceneSize.height)))
            if !event.modifierFlags.contains(.option) {
                if abs(value.offsetX * Double(stage.width) / 2) < 6 { value.offsetX = 0 }
                if abs(value.offsetY * Double(stage.height) / 2) < 6 { value.offsetY = 0 }
            }
        case .scale:
            let center = drag.layout.center.applying(sceneToView)
            let initial = hypot(drag.start.x - center.x, drag.start.y - center.y)
            let distance = hypot(point.x - center.x, point.y - center.y)
            value.zoom = min(8, max(0.05, value.zoom * Double(distance / max(1, initial))))
        case .rotate:
            let center = drag.layout.center.applying(sceneToView)
            let delta = atan2(point.y - center.y, point.x - center.x) - atan2(drag.start.y - center.y, drag.start.x - center.x)
            var angle = value.rotation + Double(delta * 180 / .pi)
            if event.modifierFlags.contains(.shift) { angle = (angle / 15).rounded() * 15 }
            angle = (angle + 180).truncatingRemainder(dividingBy: 360)
            if angle < 0 { angle += 360 }
            value.rotation = angle - 180
        case .crop(let edge):
            let inverse = drag.layout.transform.concatenating(sceneToView).inverted()
            let from = drag.start.applying(inverse), to = point.applying(inverse)
            let x = Double((to.x - from.x) / sourceSize.width), y = Double((to.y - from.y) / sourceSize.height)
            switch edge {
            case 0: value.crop.top = min(0.95 - value.crop.bottom, max(0, value.crop.top - y))
            case 1: value.crop.right = min(0.95 - value.crop.left, max(0, value.crop.right - x))
            case 2: value.crop.bottom = min(0.95 - value.crop.top, max(0, value.crop.bottom + y))
            default: value.crop.left = min(0.95 - value.crop.right, max(0, value.crop.left + x))
            }
            // Keep the untouched source pixels fixed instead of re-fitting each drag.
            let changed = layout(for: value)
            let center = CGPoint(x: changed.cropRect.midX, y: changed.cropRect.midY).applying(drag.layout.transform)
            value.zoom = min(8, max(0.05, value.zoom * Double(drag.layout.scale / changed.scale)))
            value.offsetX = min(4, max(-4, Double((center.x - sceneSize.width / 2) * 2 / sceneSize.width)))
            value.offsetY = min(4, max(-4, Double((center.y - sceneSize.height / 2) * 2 / sceneSize.height)))
        }
        draft = value; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let drag, let draft else { return }
        self.drag = nil; self.draft = nil; NSCursor.arrow.set()
        if drag.stage == stage { store?.commitVisualTransform(draft, expectedRevision: drag.revision) }
        needsDisplay = true
    }
    func cancelDraft() { drag = nil; draft = nil; needsDisplay = true; NSCursor.arrow.set() }
    override func cancelOperation(_ sender: Any?) { cancelDraft() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelDraft(); return }
        guard canInteract, drag == nil, var value = clip else { super.keyDown(with: event); return }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: value.offsetX -= step * 2 / Double(sceneSize.width)
        case 124: value.offsetX += step * 2 / Double(sceneSize.width)
        case 125: value.offsetY -= step * 2 / Double(sceneSize.height)
        case 126: value.offsetY += step * 2 / Double(sceneSize.height)
        default: super.keyDown(with: event); return
        }
        value.offsetX = min(4, max(-4, value.offsetX)); value.offsetY = min(4, max(-4, value.offsetY))
        store?.commitVisualTransform(value, expectedRevision: revision)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { cancelDraft() } }
}
