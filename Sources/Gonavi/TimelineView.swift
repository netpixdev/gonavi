import AppKit
import Combine
import GonaviCore
import SwiftUI

@MainActor final class TimelineViewport: ObservableObject {
    @Published var offset = 0.0
    @Published var pixelsPerSecond = 48.0
    @Published var snapping = true
    @Published var visibleWidth = 800.0
    func pan(_ pixels: Double) { offset = TimelineGeometry.pannedStart(offset, byPixels: pixels, pixelsPerSecond: pixelsPerSecond) }
    func reveal(_ time: Double) { offset = max(0, time - visibleWidth / pixelsPerSecond * 0.25) }
    func fit(_ duration: Double) { offset = 0; pixelsPerSecond = min(240, max(0.001, visibleWidth / max(5, duration + 1))) }
}

struct TimelinePanel: View {
    @ObservedObject var store: EditorStore
    @ObservedObject var viewport: TimelineViewport
    @ObservedObject var waveforms: WaveformStore
    init(store: EditorStore) { self.store = store; viewport = store.timeline; waveforms = store.waveforms }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("ZAMAN ÇİZELGESİ").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Divider().frame(height: 16)
                Button(action: store.split) { Label("Böl", systemImage: "scissors") }.disabled(store.activeClip == nil || !store.editable)
                Button(action: store.deleteClip) { Image(systemName: "trash") }.help("Klibi sil ve boşluğu kapat").disabled(store.activeClip == nil || !store.editable)
                Button { viewport.snapping.toggle() } label: {
                    Label("Mıknatıs", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(viewport.snapping ? Theme.accent : Theme.secondary)
                }.help("Klip uçlarına ve oynatma çizgisine hizala · S · ⌥ ile geçici kapat")
                Button(action: store.automaticSilences) { Label("Sessizlik", systemImage: "waveform.path") }
                    .help("Sessiz alanları analiz et, dinle ve seçerek çıkar").disabled(store.project.clips.isEmpty || !store.editable)
                Spacer()
                Button { viewport.reveal(store.playhead) } label: { Image(systemName: "scope") }.help("Oynatma çizgisini göster")
                Button { viewport.fit(store.project.duration.seconds) } label: { Text("Sığdır") }
                Button { viewport.pixelsPerSecond = max(0.001, viewport.pixelsPerSecond / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                Slider(value: Binding(get: { log2(viewport.pixelsPerSecond) }, set: { viewport.pixelsPerSecond = pow(2, $0) }), in: -10...8)
                    .frame(width: 100).accessibilityLabel("Zaman çizelgesi yakınlaştırma")
                Button { viewport.pixelsPerSecond = min(256, viewport.pixelsPerSecond * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
            }.buttonStyle(.borderless).padding(.horizontal, 18).frame(height: 42).background(Theme.panel)
            TimelineSurface(store: store, waveforms: waveforms.entries, offset: viewport.offset, scale: viewport.pixelsPerSecond)
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text("Tepe / RMS · sabit ölçek")
                Text("·").foregroundStyle(Theme.secondary)
                Text("Kaydır: iki parmak / tekerlek · Yakınlaştır: ⌘ + kaydır")
                Spacer()
                Text(String(format: "%02d:%02d", Int(viewport.offset) / 60, Int(viewport.offset) % 60)).monospacedDigit()
                Button { viewport.pan(-viewport.visibleWidth * 0.8) } label: { Image(systemName: "chevron.left") }
                Button { viewport.pan(viewport.visibleWidth * 0.8) } label: { Image(systemName: "chevron.right") }
            }.font(.system(size: 10)).foregroundStyle(Theme.secondary).buttonStyle(.borderless)
                .padding(.horizontal, 18).frame(height: 28).background(Theme.panel)
        }.background(Theme.inset)
    }
}

private struct TimelineSurface: NSViewRepresentable {
    let store: EditorStore
    let waveforms: [UUID: WaveformEntry]
    let offset: Double
    let scale: Double
    func makeNSView(context: Context) -> TimelineNativeView { TimelineNativeView() }
    func updateNSView(_ view: TimelineNativeView, context: Context) {
        view.configure(store: store, waveforms: waveforms)
    }
}

/// A viewport-sized view: panning does not allocate a view proportional to project duration.
@MainActor final class TimelineNativeView: NSView {
    static let libraryType = NSPasteboard.PasteboardType("app.gonavi.media-source")
    private(set) weak var store: EditorStore?
    private var waveforms: [UUID: WaveformEntry] = [:]
    private var layoutClips: [(VideoClip, Double, MediaSource?)] = []
    private var configuredRevision = -1
    private let gutter: CGFloat = 108
    private var heldClip: UUID?
    private var pointerOffset = 0.0
    private var initialPoint = NSPoint.zero
    private var currentPoint = NSPoint.zero
    private var isMoving = false
    private var ghost: (time: Double, duration: Double)?
    private var guide: Double?
    private var externalSource: UUID?
    private var edgeTimer: Timer?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, Self.libraryType, .string])
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Zaman çizelgesi. Oklarla gezin, boşlukla oynatın. S ile mıknatıs, Delete ile klip silme.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(store: EditorStore, waveforms: [UUID: WaveformEntry]) {
        if self.store !== store || configuredRevision != store.revision || layoutClips.count != store.project.clips.count {
            let sources = Dictionary(uniqueKeysWithValues: store.project.sources.map { ($0.id, $0) })
            var cursor = 0.0
            layoutClips = store.project.clips.map { clip in
                let start = clip.timelineStart?.seconds ?? cursor
                cursor = start + clip.duration.seconds
                return (clip, start, sources[clip.sourceID])
            }
            configuredRevision = store.revision
        }
        self.store = store; self.waveforms = waveforms
        needsDisplay = true
        if store.isPlaying && !isMoving {
            let right = store.timeline.offset + Double(max(1, bounds.width - gutter)) / store.timeline.pixelsPerSecond
            if store.playhead > right || store.playhead < store.timeline.offset {
                DispatchQueue.main.async { [weak store] in if let store { store.timeline.reveal(store.playhead) } }
            }
        }
    }
    override func layout() {
        super.layout()
        let width = Double(max(1, bounds.width - gutter))
        if let store, abs(store.timeline.visibleWidth - width) > 1 {
            DispatchQueue.main.async { [weak store] in store?.timeline.visibleWidth = width }
        }
    }
    private func x(_ time: Double) -> CGFloat {
        guard let store else { return gutter }
        return gutter + TimelineGeometry.x(for: time, viewportStart: store.timeline.offset, pixelsPerSecond: store.timeline.pixelsPerSecond)
    }
    private func time(_ x: CGFloat) -> Double {
        guard let store else { return 0 }
        return TimelineGeometry.time(atX: Double(x - gutter), viewportStart: store.timeline.offset, pixelsPerSecond: store.timeline.pixelsPerSecond)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let store else { return }
        Theme.insetColor.setFill(); bounds.fill()
        let lane = NSRect(x: gutter, y: 31, width: max(0, bounds.width - gutter), height: 86)
        Theme.panelColor.withAlphaComponent(0.65).setFill(); lane.fill()
        NSRect(x: gutter, y: 123, width: lane.width, height: 50).fill()
        NSRect(x: gutter, y: 180, width: lane.width, height: 32).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: gutter, y: 0, width: lane.width, height: bounds.height)).addClip()
        drawRuler()
        for (clip, start, source) in layoutClips {
            let end = start + clip.duration.seconds
            guard x(end) >= gutter, x(start) <= bounds.width else { continue }
            let rect = NSRect(x: x(start), y: 33, width: max(2, clip.duration.seconds * store.timeline.pixelsPerSecond), height: 82)
            let color = source?.isVideo == true ? Theme.videoColor : Theme.audioColor
            color.withAlphaComponent(0.26).setFill(); NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            color.withAlphaComponent(0.8).setStroke(); let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            outline.lineWidth = 1; outline.stroke()
            if store.selectedClip == clip.id {
                Theme.accentColor.setStroke(); outline.lineWidth = 2; outline.stroke()
            }
            let visible = rect.intersection(NSRect(x: gutter, y: 0, width: lane.width, height: bounds.height))
            text((source?.isVideo == true ? "▸  " : "♫  ") + (source?.name ?? "Klip"),
                 at: NSPoint(x: max(rect.minX + 9, gutter + 6), y: 40), color: .white, size: 11,
                 width: max(0, visible.width - 15), weight: .medium)
            drawWaveform(waveforms[clip.sourceID], rect: NSRect(x: rect.minX, y: 62, width: rect.width, height: 44),
                         sourceStart: clip.sourceStart.seconds, duration: clip.duration.seconds, gain: clip.volume, color: color)
        }
        if let music = store.project.music, let source = store.project.sources.first(where: { $0.id == music.sourceID }) {
            let length = min(source.duration.seconds, store.project.duration.seconds)
            let rect = NSRect(x: x(0), y: 125, width: length * store.timeline.pixelsPerSecond, height: 46)
            Theme.audioColor.withAlphaComponent(0.18).setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            drawWaveform(waveforms[source.id], rect: rect.insetBy(dx: 0, dy: 5), sourceStart: 0, duration: length, gain: music.volume, color: Theme.audioColor)
        } else {
            text("Medya listesinde sağ tık → Müzik Olarak Ekle", at: NSPoint(x: gutter + 16, y: 143), color: .secondaryLabelColor, size: 10, width: lane.width - 24)
        }
        for caption in store.project.captions {
            let rect = NSRect(x: x(caption.start.seconds), y: 182, width: max(2, caption.duration.seconds * store.timeline.pixelsPerSecond), height: 28)
            guard rect.maxX >= gutter && rect.minX < bounds.width else { continue }
            Theme.captionColor.withAlphaComponent(0.3).setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            text(caption.text, at: NSPoint(x: max(rect.minX + 7, gutter + 5), y: 188), color: Theme.captionColor, size: 10, width: min(rect.maxX, bounds.width) - max(rect.minX, gutter) - 12)
        }
        if let ghost {
            let rect = NSRect(x: x(ghost.time), y: 33, width: max(4, ghost.duration * store.timeline.pixelsPerSecond), height: 82)
            Theme.accentColor.withAlphaComponent(0.12).setFill(); rect.fill()
            Theme.accentColor.setStroke(); let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.setLineDash([5, 3], count: 2, phase: 0); border.stroke()
        }
        if let guide {
            let line = NSBezierPath(); line.move(to: NSPoint(x: x(guide), y: 0)); line.line(to: NSPoint(x: x(guide), y: bounds.height))
            Theme.captionColor.setStroke(); line.lineWidth = 1.5; line.stroke()
            text("HİZALI", at: NSPoint(x: x(guide) + 6, y: 4), color: Theme.captionColor, size: 9, width: 60, weight: .semibold)
        }
        let playheadX = x(store.playhead)
        if playheadX >= gutter && playheadX <= bounds.width {
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let line = NSBezierPath(); line.move(to: NSPoint(x: playheadX, y: 22)); line.line(to: NSPoint(x: playheadX, y: bounds.height)); line.lineWidth = 1; line.stroke()
            NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: playheadX - 4, y: 17, width: 8, height: 12), xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        Theme.panelColor.setFill(); NSRect(x: 0, y: 0, width: gutter, height: bounds.height).fill()
        text("ZAMAN", at: NSPoint(x: 16, y: 9), color: .secondaryLabelColor, size: 9, width: 82, weight: .semibold)
        text(store.hasVideo ? "VIDEO + SES" : "SES", at: NSPoint(x: 16, y: 46), color: Theme.accentColor, size: 9, width: 86, weight: .semibold)
        text("Ana kurgu", at: NSPoint(x: 16, y: 64), color: .secondaryLabelColor, size: 10, width: 84)
        text("MÜZİK", at: NSPoint(x: 16, y: 140), color: Theme.audioColor, size: 9, width: 84, weight: .semibold)
        text("ALTYAZI", at: NSPoint(x: 16, y: 191), color: Theme.captionColor, size: 9, width: 84, weight: .semibold)
        if store.project.clips.isEmpty {
            text("Video veya ses dosyasını buraya bırakın", at: NSPoint(x: gutter + 18, y: 66), color: .secondaryLabelColor, size: 12, width: lane.width - 30)
        }
    }
    private func drawRuler() {
        guard let store else { return }
        let desired = 90 / store.timeline.pixelsPerSecond
        let power = pow(10, floor(log10(max(0.01, desired))))
        let interval = [1.0, 2, 5, 10].map { $0 * power }.first { $0 >= desired } ?? power * 10
        var second = floor(store.timeline.offset / interval) * interval
        let end = time(bounds.width)
        var count = 0
        while second <= end && count < 200 {
            let point = x(second)
            let line = NSBezierPath(); line.move(to: NSPoint(x: point, y: 25)); line.line(to: NSPoint(x: point, y: bounds.height))
            NSColor.white.withAlphaComponent(0.06).setStroke(); line.stroke()
            let label = second >= 3600 ? String(format: "%02d:%02d:%02d", Int(second) / 3600, Int(second) / 60 % 60, Int(second) % 60)
                : (interval < 1 ? String(format: "%.1fs", second) : String(format: "%02d:%02d", Int(second) / 60, Int(second) % 60))
            text(label, at: NSPoint(x: point + 5, y: 7), color: .secondaryLabelColor, size: 9, width: 86)
            second += interval; count += 1
        }
    }
    private func drawWaveform(_ entry: WaveformEntry?, rect: NSRect, sourceStart: Double, duration: Double, gain: Double, color: NSColor) {
        let lower = max(gutter, rect.minX), upper = min(bounds.width, rect.maxX)
        guard upper > lower, duration > 0, let store else { return }
        guard case .ready(let waveform) = entry else {
            let label: String
            switch entry { case .noAudio: label = "Ses hattı yok"; case .failed: label = "Dalga okunamadı · Medyadan yeniden dene"; default: label = "Dalga hazırlanıyor…" }
            text(label, at: NSPoint(x: lower + 8, y: rect.midY - 6), color: .secondaryLabelColor, size: 9, width: upper - lower - 12); return
        }
        let base = NSBezierPath(); base.move(to: NSPoint(x: lower, y: rect.midY)); base.line(to: NSPoint(x: upper, y: rect.midY)); color.withAlphaComponent(0.25).setStroke(); base.stroke()
        var pixel = lower
        while pixel < upper {
            let a = sourceStart + Double(pixel - rect.minX) / store.timeline.pixelsPerSecond
            let b = min(sourceStart + duration, a + 2 / store.timeline.pixelsPerSecond)
            let level = waveform.level(in: a..<max(a, b))
            let peak = min(1, Double(level.peak) * gain), rms = min(1, Double(level.rms) * gain)
            let height: CGFloat = CGFloat(sqrt(peak)) * rect.height * 0.92
            if height > 0.1 {
                (peak >= 0.98 ? NSColor.systemOrange : color.withAlphaComponent(0.66)).setFill()
                NSRect(x: pixel, y: rect.midY - height / 2, width: 1.4, height: height).fill()
                color.setFill(); let body: CGFloat = CGFloat(sqrt(rms)) * rect.height * 0.92
                NSRect(x: pixel, y: rect.midY - body / 2, width: 1.4, height: body).fill()
            }
            pixel += 2
        }
    }
    private func text(_ value: String, at point: NSPoint, color: NSColor, size: CGFloat, width: CGFloat, weight: NSFont.Weight = .regular) {
        guard width > 2 else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: NSRect(x: point.x, y: point.y, width: width, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    override func mouseDown(with event: NSEvent) {
        guard let store else { return }
        window?.makeFirstResponder(self)
        initialPoint = convert(event.locationInWindow, from: nil); currentPoint = initialPoint
        if initialPoint.x < gutter { return }
        if (33...115).contains(initialPoint.y), let clip = layoutClips.first(where: { time(initialPoint.x) >= $0.1 && time(initialPoint.x) < $0.1 + $0.0.duration.seconds }) {
            store.selectedClip = clip.0.id; store.selectedCaption = nil
            heldClip = clip.0.id; pointerOffset = time(initialPoint.x) - clip.1
        } else if (180...214).contains(initialPoint.y), let caption = store.project.captions.first(where: { time(initialPoint.x) >= $0.start.seconds && time(initialPoint.x) < ($0.start + $0.duration).seconds }) {
            store.selectedCaption = caption.id; store.seek(caption.start.seconds)
        } else { scrub(event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let store, store.editable else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        if heldClip != nil {
            if abs(currentPoint.x - initialPoint.x) > 3 { isMoving = true }
            if isMoving { updateMove(); startEdgeTimer() }
        } else { scrub(event) }
    }
    private func updateMove() {
        guard let store, let id = heldClip, let clip = store.project.clips.first(where: { $0.id == id }) else { return }
        let result = store.snappedTime(time(currentPoint.x) - pointerOffset, duration: clip.duration.seconds, excluding: id,
                                       bypass: NSEvent.modifierFlags.contains(.option))
        ghost = (result.time, clip.duration.seconds); guide = result.guide; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let store, let id = heldClip {
            if isMoving, let ghost { store.moveClip(id, to: ghost.time) }
            else { store.seek(store.project.start(of: id).seconds) }
        }
        clearDrag()
    }
    private func scrub(_ event: NSEvent) {
        guard let store else { return }
        let point = convert(event.locationInWindow, from: nil)
        let result = TimelineGeometry.snap(proposedStart: time(point.x), duration: 0,
            candidates: layoutClips.flatMap { [$0.1, $0.1 + $0.0.duration.seconds] }, pixelsPerSecond: store.timeline.pixelsPerSecond,
            fps: store.project.fps, enabled: store.timeline.snapping && !event.modifierFlags.contains(.option))
        store.seek(result.time); guide = result.guide; needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard let store else { return }
        if event.modifierFlags.contains(.command) {
            let anchor = convert(event.locationInWindow, from: nil).x
            let previous = time(anchor)
            store.timeline.pixelsPerSecond = min(256, max(0.001, store.timeline.pixelsPerSecond * exp(-Double(event.scrollingDeltaY) * 0.015)))
            store.timeline.offset = max(0, previous - Double(max(0, anchor - gutter)) / store.timeline.pixelsPerSecond)
        } else {
            let delta = abs(event.scrollingDeltaX) > 0.01 ? event.scrollingDeltaX : event.scrollingDeltaY
            store.timeline.pan(-Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : 12))
        }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard let store else { return }
        switch event.keyCode {
        case 49: store.togglePlayback()
        case 123: store.seek(store.playhead - 1 / Double(store.project.fps))
        case 124: store.seek(store.playhead + 1 / Double(store.project.fps))
        case 51, 117: store.deleteClip()
        case 53: clearDrag()
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "s" { store.timeline.snapping.toggle() }
            else { super.keyDown(with: event) }
        }
    }
    private func sourceID(_ sender: NSDraggingInfo) -> UUID? {
        let pasteboard = sender.draggingPasteboard
        let value = pasteboard.data(forType: Self.libraryType).flatMap { String(data: $0, encoding: .utf8) } ?? pasteboard.string(forType: .string)
        guard let value, value.hasPrefix("gonavi-media:") else { return nil }
        return UUID(uuidString: String(value.dropFirst(13)))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let store, store.editable else { return [] }
        currentPoint = convert(sender.draggingLocation, from: nil)
        guard currentPoint.x >= gutter else { return [] }
        externalSource = sourceID(sender)
        if let id = externalSource, let source = store.project.sources.first(where: { $0.id == id }) {
            let result = store.snappedTime(time(currentPoint.x), duration: source.duration.seconds,
                                           bypass: NSEvent.modifierFlags.contains(.option))
            ghost = (result.time, source.duration.seconds); guide = result.guide
        } else if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            // Duration is known after inspection; show an insertion guide until then.
            guide = TimelineGeometry.snap(proposedStart: time(currentPoint.x), duration: 0,
                candidates: layoutClips.flatMap { [$0.1, $0.1 + $0.0.duration.seconds] } + [store.playhead],
                pixelsPerSecond: store.timeline.pixelsPerSecond, fps: store.project.fps,
                enabled: store.timeline.snapping && !NSEvent.modifierFlags.contains(.option)).time
        } else { return [] }
        startEdgeTimer(); needsDisplay = true; return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let store, store.editable else { clearDrag(); return false }
        defer { clearDrag() }
        if let id = sourceID(sender), let source = store.project.sources.first(where: { $0.id == id }) {
            let result = store.snappedTime(time(currentPoint.x), duration: source.duration.seconds,
                                           bypass: NSEvent.modifierFlags.contains(.option))
            store.addSource(source, at: result.time); return true
        }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        store.importURLs(urls, at: time(currentPoint.x), snap: !NSEvent.modifierFlags.contains(.option)); return true
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDrag() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearDrag() }
    private func startEdgeTimer() {
        guard edgeTimer == nil else { return }
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.edgeScroll() }
        }
        if let edgeTimer { RunLoop.main.add(edgeTimer, forMode: .eventTracking) }
    }
    private func edgeScroll() {
        guard let store else { return }
        var delta = 0.0
        if currentPoint.x > bounds.width - 40 { delta = Double(currentPoint.x - (bounds.width - 40)) * 0.4 }
        if currentPoint.x < gutter + 40 { delta = -Double(gutter + 40 - currentPoint.x) * 0.4 }
        guard delta != 0 else { return }
        store.timeline.pan(delta)
        if heldClip != nil { updateMove() }
        else if let id = externalSource, let source = store.project.sources.first(where: { $0.id == id }) {
            let result = store.snappedTime(time(currentPoint.x), duration: source.duration.seconds)
            ghost = (result.time, source.duration.seconds); guide = result.guide
        } else { guide = time(currentPoint.x) }
        needsDisplay = true
    }
    private func clearDrag() {
        edgeTimer?.invalidate(); edgeTimer = nil; heldClip = nil; externalSource = nil
        ghost = nil; guide = nil; isMoving = false; needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { clearDrag() }; super.viewWillMove(toWindow: newWindow) }
}
