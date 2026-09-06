import AppKit
import AVFoundation
import Combine
import GonaviCore
import UniformTypeIdentifiers

@MainActor
final class EditorStore: ObservableObject {
    @Published var project = Project()
    @Published var selectedClip: UUID?
    @Published var selectedCaption: UUID?
    @Published var playhead: Double = 0
    @Published var isPlaying = false
    @Published var isBuilding = false
    @Published var importing = false
    @Published var exporting = false
    @Published var exportProgress: Float = 0
    @Published var error: String?
    @Published var status = "Videolarınızı içe aktararak başlayın."
    @Published var dirty = false
    @Published var revision = 0
    @Published var showingHome = true
    @Published var creatingProject = false
    @Published var showingAutoCaptions = false
    @Published private(set) var hasOpenProject = false
    @Published private(set) var recoveryAvailable = false
    @Published private(set) var recentProjects: [RecentProject] = []
    let player = AVPlayer()
    let waveforms = WaveformStore()
    let timeline = TimelineViewport()
    private var fileURL: URL?
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    private var continuousEdit = false
    private var continuousRecorded = false
    private var buildTask: Task<Void, Never>?
    private var prepared: PreparedTimeline?
    private var exportSession: AVAssetExportSession?
    private var timeObserver: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private let recoveryURL: URL
    private let recentsURL: URL
    private var recoveredProject: Project?
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var activeClip: VideoClip? { project.clips.first { $0.id == selectedClip } }
    var editable: Bool { !importing && !exporting && !showingAutoCaptions }
    var hasVideo: Bool { project.clips.contains { clip in project.sources.contains { $0.id == clip.sourceID && $0.isVideo } } }
    var canExport: Bool { project.duration > .zero && prepared != nil && !isBuilding && editable }

    init(storageDirectory: URL? = nil) {
        let directory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gonavi")
        recoveryURL = directory.appendingPathComponent("recovery.json")
        recentsURL = directory.appendingPathComponent("recents.json")
        if let data = try? Data(contentsOf: recentsURL),
           let recents = try? JSONDecoder().decode([RecentProject].self, from: data) {
            recentProjects = Array(recents.prefix(12))
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if time.seconds.isFinite { self.playhead = max(0, time.seconds) }
                self.isPlaying = self.player.rate != 0
            }
        }
        if let data = try? Data(contentsOf: recoveryURL), let recovered = try? Project.decode(data),
           !recovered.sources.isEmpty || recovered.name != "Yeni proje" {
            recoveredProject = recovered; recoveryAvailable = true
        }
    }

    func mutate(_ action: (inout Project) throws -> Void) {
        guard editable else { return }
        var next = project
        do {
            try action(&next); next.normalizeTimeline(); try next.validate()
            guard next != project else { return }
            if !continuousEdit || !continuousRecorded {
                undoStack.append(project)
                if undoStack.count > 100 { undoStack.removeFirst() }
                continuousRecorded = true
            }
            redoStack.removeAll(); project = next; dirty = true; revision += 1
            autosave(); rebuild()
        } catch { self.error = error.localizedDescription }
    }
    func sliderEditing(_ active: Bool) {
        continuousEdit = active; continuousRecorded = false
    }
    func updateClip(_ action: (inout VideoClip) -> Void) {
        guard let id = selectedClip else { return }
        mutate { p in if let index = p.clips.firstIndex(where: { $0.id == id }) { action(&p.clips[index]) } }
    }
    func updateCaption(_ action: (inout Caption) -> Void) {
        guard let id = selectedCaption else { return }
        mutate { p in if let index = p.captions.firstIndex(where: { $0.id == id }) { action(&p.captions[index]) } }
    }
    func undo() {
        guard editable, let previous = undoStack.popLast() else { return }
        redoStack.append(project); project = previous; dirty = true; revision += 1; autosave(); rebuild()
    }
    func redo() {
        guard editable, let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next; dirty = true; revision += 1; autosave(); rebuild()
    }
    func autosave() {
        do {
            try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try project.encoded().write(to: recoveryURL, options: .atomic)
        } catch { self.error = "Otomatik kayıt başarısız: \(error.localizedDescription)" }
    }
    func confirmDiscard() -> Bool {
        guard editable else { return false }
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Projedeki değişiklikler kaydedilsin mi?"
        alert.informativeText = "Kaydetmezseniz bu projedeki son değişiklikler kaybolur."
        alert.addButton(withTitle: "Kaydet"); alert.addButton(withTitle: "Vazgeç"); alert.addButton(withTitle: "Kaydetme")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func newProject() {
        guard editable else { return }
        creatingProject = true
    }
    @discardableResult func createProject(name: String, scene: ScenePreset, fps: Int) -> Bool {
        guard confirmDiscard() else { return false }
        var next = Project()
        next.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.name.isEmpty { next.name = "İsimsiz proje" }
        next.scene = scene; next.fps = fps
        do { try next.validate(); try preserveRecovery() }
        catch { self.error = error.localizedDescription; return false }
        project = next; fileURL = nil; dirty = true; resetHistory()
        hasOpenProject = true; showingHome = false; creatingProject = false
        autosave(); rebuild(); status = "Proje hazır. Video eklemek için ⌘I."
        return true
    }
    func goHome() {
        guard editable else { return }
        player.pause(); isPlaying = false; showingHome = true
    }
    func resumeProject() {
        if hasOpenProject { showingHome = false; return }
        guard let recovered = recoveredProject else { return }
        project = recovered; hasOpenProject = true; dirty = true
        recoveredProject = nil; recoveryAvailable = false; showingHome = false
        resetHistory(); rebuild(); status = "Önceki oturum kurtarıldı. Projeyi kaydedebilirsiniz."
    }
    /// Starting another project must not silently destroy a recoverable session.
    private func preserveRecovery() throws {
        guard recoveryAvailable, let recovered = recoveredProject,
              FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        let directory = recoveryURL.deletingLastPathComponent().appendingPathComponent("Recovered Projects")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("\(UUID().uuidString).gonavi")
        try Data(contentsOf: recoveryURL).write(to: backup, options: .atomic)
        let entry = RecentProject(path: backup.path, name: "Kurtarma · \(recovered.name)",
                                  scene: recovered.scene, duration: recovered.duration)
        recentProjects = RecentProject.recording(entry, in: recentProjects)
        saveRecents()
        recoveredProject = nil; recoveryAvailable = false
    }
    private func remember(_ url: URL) {
        let entry = RecentProject(path: url.path,
                                  bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                                  name: project.name, scene: project.scene, duration: project.duration)
        recentProjects = RecentProject.recording(entry, in: recentProjects)
        saveRecents()
    }
    private func saveRecents() {
        do {
            try FileManager.default.createDirectory(at: recentsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(recentProjects).write(to: recentsURL, options: .atomic)
        } catch { self.error = "Proje geçmişi kaydedilemedi: \(error.localizedDescription)" }
    }
    func removeRecent(_ recent: RecentProject) {
        recentProjects.removeAll { $0.id == recent.id }; saveRecents()
    }
    func openRecent(_ recent: RecentProject) {
        var stale = false
        let bookmarked = recent.bookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        let url = bookmarked ?? URL(fileURLWithPath: recent.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "\(recent.name) bulunamadı. Dosya taşındıysa ‘Proje Aç’ ile yeni konumunu seçin."
            return
        }
        loadProject(at: url)
    }
    private func resetHistory() {
        undoStack.removeAll(); redoStack.removeAll(); revision += 1
        selectedClip = project.clips.first?.id; selectedCaption = nil; playhead = 0
        timeline.offset = 0; waveforms.cancelAll()
    }
    func open() {
        guard editable else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gonavi") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(at: url)
    }
    func loadProject(at url: URL) {
        guard confirmDiscard() else { return }
        do {
            let loaded = try Project.decode(Data(contentsOf: url))
            try preserveRecovery()
            project = loaded; fileURL = url; dirty = false; resetHistory(); autosave(); rebuild()
            hasOpenProject = true; showingHome = false; remember(url)
            status = "Proje açıldı: \(url.lastPathComponent)"
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save(asNew: Bool = false) -> Bool {
        var destination = fileURL
        if destination == nil || asNew {
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gonavi") ?? .json]
            panel.nameFieldStringValue = project.name + ".gonavi"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let destination else { return false }
        do {
            try project.encoded().write(to: destination, options: .atomic)
            fileURL = destination; dirty = false; status = "Kaydedildi: \(destination.lastPathComponent)"
            remember(destination)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func chooseMedia() {
        guard editable else { return }
        if !hasOpenProject { newProject(); return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }
    func importURLs(_ urls: [URL], at dropTime: Double? = nil, snap: Bool = true) {
        guard editable, !urls.isEmpty else { return }
        importing = true; status = "Medya okunuyor…"
        Task {
            var imported: [MediaSource] = []
            var failures: [String] = []
            for url in urls {
                do { imported.append(try await MediaEngine.inspect(url)) }
                catch { failures.append(error.localizedDescription) }
            }
            importing = false
            mutate { p in
                var position = dropTime
                for source in imported {
                    let registered = p.sources.first(where: { $0.path == source.path }) ?? source
                    let target = position.map { self.snappedTime($0, duration: registered.duration.seconds, in: p, bypass: !snap).time }
                    let id = p.appendSourceToTimeline(source: registered, at: target.map(EditTime.init(seconds:)))
                    if position != nil { position = p.start(of: id).seconds + registered.duration.seconds }
                }
            }
            if selectedClip == nil { selectedClip = project.clips.first?.id }
            status = "\(imported.count) medya okundu."
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    func addSource(_ source: MediaSource, at time: Double? = nil) {
        var id: UUID?
        mutate { p in id = p.appendSourceToTimeline(source: source, at: time.map(EditTime.init(seconds:))) }
        selectedClip = id
    }
    func addMusic(_ source: MediaSource) {
        mutate { $0.music = MusicClip(sourceID: source.id) }
    }
    func relink(_ source: MediaSource) {
        guard editable else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = source.isVideo ? [.movie] : [.audio, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        Task {
            do {
                var replacement = try await MediaEngine.inspect(url)
                guard replacement.isVideo == source.isVideo else { throw ProjectError.invalid("Medya türü eşleşmiyor.") }
                replacement.id = source.id; importing = false
                mutate { p in if let index = p.sources.firstIndex(where: { $0.id == source.id }) { p.sources[index] = replacement } }
                waveforms.invalidate(source.id)
            } catch { importing = false; self.error = error.localizedDescription }
        }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let time = max(0, min(seconds, project.duration.seconds))
        playhead = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func togglePlayback() {
        guard prepared != nil, !isBuilding else { return }
        if player.rate != 0 { player.pause(); isPlaying = false }
        else { if playhead >= project.duration.seconds - 0.02 { seek(0) }; player.play(); isPlaying = true }
    }
    func split() {
        guard let id = selectedClip else { return }
        let frame = Int64((playhead * Double(project.fps)).rounded())
        let point = EditTime(ticks: frame * EditTime.scale / Int64(project.fps))
        mutate { try $0.split(id, at: point) }
    }
    func deleteClip() {
        guard let id = selectedClip else { return }
        mutate { $0.remove(id) }; selectedClip = project.clips.first?.id
    }
    func moveClip(_ id: UUID, before target: UUID) {
        moveClip(id, to: project.start(of: target).seconds)
    }
    func moveClip(_ id: UUID, to seconds: Double) {
        mutate { _ = $0.placeClip(id: id, at: EditTime(seconds: seconds)) }
        selectedClip = id
    }
    func snappedTime(_ proposed: Double, duration: Double, excluding: UUID? = nil, in snapshot: Project? = nil,
                     bypass: Bool = false) -> SnapResult {
        let p = snapshot ?? project
        var targets = [0.0, playhead]
        for clip in p.clips where clip.id != excluding {
            let start = p.start(of: clip.id).seconds
            targets += [start, start + clip.duration.seconds]
        }
        let snapped = TimelineGeometry.snap(proposedStart: proposed, duration: duration, candidates: targets,
                                             pixelsPerSecond: timeline.pixelsPerSecond, fps: p.fps,
                                             enabled: timeline.snapping && !bypass)
        let resolved = p.resolvedPlacement(at: EditTime(seconds: snapped.time), duration: EditTime(seconds: duration), excluding: excluding).seconds
        return SnapResult(time: resolved, guide: abs(resolved - snapped.time) < 0.0001 ? snapped.guide : nil)
    }
    func addCaption() {
        guard project.duration.ticks > 0 else { return }
        let start = EditTime(seconds: min(playhead, max(0, project.duration.seconds - 1)))
        let caption = Caption(start: start, duration: min(EditTime(seconds: 3), project.duration - start), text: "Altyazınızı yazın")
        mutate { $0.captions.append(caption) }; selectedCaption = caption.id
    }
    func automaticCaptions() {
        guard editable, !project.clips.isEmpty else { return }
        player.pause(); isPlaying = false; showingHome = false; showingAutoCaptions = true
    }
    func applyGeneratedCaptions(_ captions: [Caption]) {
        guard showingAutoCaptions, !captions.isEmpty else { return }
        showingAutoCaptions = false
        mutate { $0.captions = captions }
        selectedCaption = project.captions.first?.id
        status = "\(project.captions.count) otomatik altyazı eklendi. Metinleri kontrol edip düzenleyebilirsiniz."
    }
    func exportSRT() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = project.name + ".srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try project.srt().write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
    func rebuild() {
        waveforms.load(project.sources)
        buildTask?.cancel(); player.pause(); isPlaying = false; prepared = nil
        playerStatusObserver = nil; player.replaceCurrentItem(with: nil)
        if project.duration == .zero { isBuilding = false; playhead = 0; return }
        isBuilding = true
        let snapshot = project, position = min(playhead, project.duration.seconds)
        buildTask = Task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let result = try await MediaEngine.prepare(snapshot)
                try Task.checkCancellation()
                prepared = result
                let item = result.playerItem()
                playerStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Önizleme açılamadı."
                    Task { @MainActor [weak self] in self?.error = message }
                }
                player.replaceCurrentItem(with: item); seek(position); isBuilding = false
            } catch is CancellationError {} catch {
                if !Task.isCancelled { isBuilding = false; self.error = error.localizedDescription }
            }
        }
    }
    func exportVideo() {
        guard canExport, let prepared else { return }
        let audioOnly = !hasVideo
        let fileType: AVFileType = audioOnly ? .m4a : .mp4
        let ext = audioOnly ? "m4a" : "mp4"
        let panel = NSSavePanel(); panel.allowedContentTypes = [audioOnly ? .mpeg4Audio : .mpeg4Movie]
        panel.nameFieldStringValue = project.name + "." + ext
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        // Export to a sibling temporary file; an existing destination survives failure/cancellation.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".gonavi-\(UUID().uuidString).\(ext)")
        guard let session = AVAssetExportSession(asset: prepared.composition, presetName: audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality) else {
            error = "Export oturumu oluşturulamadı."; return
        }
        session.outputURL = temporary; session.outputFileType = fileType
        session.videoComposition = prepared.videoComposition; session.audioMix = prepared.audioMix
        session.shouldOptimizeForNetworkUse = true
        showingHome = false
        exporting = true; exportProgress = 0; exportSession = session
        player.pause(); isPlaying = false
        Task {
            let progress = Task { @MainActor in
                while !Task.isCancelled {
                    exportProgress = session.progress
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            await session.export()
            progress.cancel(); exporting = false; exportSession = nil
            do {
                guard session.status == .completed else {
                    if session.status == .cancelled { status = "Export iptal edildi." }
                    else { error = session.error?.localizedDescription ?? "Export tamamlanamadı." }
                    try? FileManager.default.removeItem(at: temporary); return
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else { try FileManager.default.moveItem(at: temporary, to: destination) }
                exportProgress = 1; status = "Dışa aktarıldı: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                self.error = "Export dosyası taşınamadı: \(error.localizedDescription). Geçici dosya: \(temporary.path)"
            }
        }
    }
    func cancelExport() { exportSession?.cancelExport() }
}
