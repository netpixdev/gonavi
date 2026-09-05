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
    let player = AVPlayer()
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
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var activeClip: VideoClip? { project.clips.first { $0.id == selectedClip } }
    var editable: Bool { !importing && !exporting }
    var canExport: Bool { !project.clips.isEmpty && prepared != nil && !isBuilding && editable }

    init() {
        recoveryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gonavi/recovery.json")
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if time.seconds.isFinite { self.playhead = max(0, time.seconds) }
                self.isPlaying = self.player.rate != 0
            }
        }
        if let data = try? Data(contentsOf: recoveryURL), let recovered = try? Project.decode(data),
           !recovered.sources.isEmpty {
            project = recovered; dirty = true; selectedClip = project.clips.first?.id
            status = "Önceki oturum kurtarıldı. Projeyi kaydedebilirsiniz."
            rebuild()
        }
    }

    func mutate(_ action: (inout Project) throws -> Void) {
        guard editable else { return }
        var next = project
        do {
            try action(&next); try next.validate()
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
        guard !exporting && !importing else { return false }
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
        guard confirmDiscard() else { return }
        project = Project(); fileURL = nil; dirty = false; resetHistory(); autosave(); rebuild()
    }
    private func resetHistory() {
        undoStack.removeAll(); redoStack.removeAll(); revision += 1
        selectedClip = project.clips.first?.id; selectedCaption = nil; playhead = 0
    }
    func open() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gonavi") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try Project.decode(Data(contentsOf: url))
            project = loaded; fileURL = url; dirty = false; resetHistory(); autosave(); rebuild()
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
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func chooseMedia() {
        guard editable else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }
    func importURLs(_ urls: [URL]) {
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
                for source in imported where !p.sources.contains(where: { $0.path == source.path }) {
                    p.sources.append(source)
                    if source.isVideo { p.clips.append(VideoClip(sourceID: source.id, duration: source.duration)) }
                    else { p.music = MusicClip(sourceID: source.id) }
                }
            }
            if selectedClip == nil { selectedClip = project.clips.first?.id }
            status = "\(imported.count) medya okundu."
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    func addSource(_ source: MediaSource) {
        mutate { p in
            if source.isVideo { p.clips.append(VideoClip(sourceID: source.id, duration: source.duration)) }
            else { p.music = MusicClip(sourceID: source.id) }
        }
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
            } catch { importing = false; self.error = error.localizedDescription }
        }
    }
    func seek(_ seconds: Double) {
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
        guard id != target else { return }
        mutate { p in
            guard let source = p.clips.firstIndex(where: { $0.id == id }) else { return }
            let clip = p.clips.remove(at: source)
            guard let destination = p.clips.firstIndex(where: { $0.id == target }) else { return }
            p.clips.insert(clip, at: destination)
        }
    }
    func addCaption() {
        guard project.duration.ticks > 0 else { return }
        let start = EditTime(seconds: min(playhead, max(0, project.duration.seconds - 1)))
        let caption = Caption(start: start, duration: min(EditTime(seconds: 3), project.duration - start), text: "Altyazınızı yazın")
        mutate { $0.captions.append(caption) }; selectedCaption = caption.id
    }
    func exportSRT() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = project.name + ".srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try project.srt().write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
    func rebuild() {
        buildTask?.cancel(); player.pause(); isPlaying = false; prepared = nil
        playerStatusObserver = nil; player.replaceCurrentItem(with: nil)
        if project.clips.isEmpty { isBuilding = false; playhead = 0; return }
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
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = project.name + ".mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        // Export to a sibling temporary file; an existing destination survives failure/cancellation.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".gonavi-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: prepared.composition, presetName: AVAssetExportPresetHighestQuality) else {
            error = "Export oturumu oluşturulamadı."; return
        }
        session.outputURL = temporary; session.outputFileType = .mp4
        session.videoComposition = prepared.videoComposition; session.audioMix = prepared.audioMix
        session.shouldOptimizeForNetworkUse = true
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
                exportProgress = 1; status = "Video hazır: \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                self.error = "Export dosyası taşınamadı: \(error.localizedDescription). Geçici dosya: \(temporary.path)"
            }
        }
    }
    func cancelExport() { exportSession?.cancelExport() }
}
