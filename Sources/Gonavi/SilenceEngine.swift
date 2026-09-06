import Foundation
import GonaviCore

/// Analyze original source audio before clip gain and background music. A
/// project snapshot keeps the proposed cuts independent of subsequent UI edits.
enum SilenceEngine {
    struct Result: Sendable {
        let candidates: [SilenceCandidate]
        let skippedSources: [String]
    }

    typealias Report = @Sendable (String, Double) -> Void

    private struct PositionedClip: Sendable {
        let clip: VideoClip
        let timelineStart: EditTime
    }
    private static let maximumCandidates = 10_000

    static func analyze(project: Project, clipIDs: Set<UUID>?, settings: SilenceSettings,
                        report: @escaping Report) async throws -> Result {
        try Task.checkCancellation()
        // Decoding a cached waveform still performs I/O and builds summaries.
        // Both that work and scanning its buckets stay off the main actor.
        let task = Task.detached(priority: .userInitiated) {
            try await analyzeSnapshot(project: project, clipIDs: clipIDs, settings: settings, report: report)
        }
        return try await withTaskCancellationHandler(operation: {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        }, onCancel: {
            task.cancel()
        })
    }

    private static func analyzeSnapshot(project: Project, clipIDs: Set<UUID>?, settings: SilenceSettings,
                                        report: @escaping Report) async throws -> Result {
        try Task.checkCancellation()
        try project.validate()
        try settings.validate()
        let sources = Dictionary(uniqueKeysWithValues: project.sources.map { ($0.id, $0) })
        var groups: [UUID: [PositionedClip]] = [:]
        var sourceOrder: [UUID] = []
        var cursor = EditTime.zero
        // Resolve implicit legacy positions in one pass, including unselected
        // clips. Analyzing a selection must preserve its real timeline offset.
        for clip in project.clips {
            try Task.checkCancellation()
            let start = clip.timelineStart ?? cursor
            cursor = start + clip.duration
            guard clipIDs == nil || clipIDs!.contains(clip.id) else { continue }
            if groups[clip.sourceID] == nil { sourceOrder.append(clip.sourceID) }
            groups[clip.sourceID, default: []].append(PositionedClip(clip: clip, timelineStart: start))
        }
        guard !sourceOrder.isEmpty else {
            report("Analiz edilecek klip yok.", 1)
            return Result(candidates: [], skippedSources: [])
        }

        var candidates: [SilenceCandidate] = []
        var skippedSources: [String] = []
        let count = Double(sourceOrder.count)
        for (index, sourceID) in sourceOrder.enumerated() {
            try Task.checkCancellation()
            guard let source = sources[sourceID], let clips = groups[sourceID] else {
                throw ProjectError.invalid("Sessizlik analizi için kaynak medya bulunamadı.")
            }
            let base = Double(index) / count
            report("Ses inceleniyor · \(source.name) · \(index + 1)/\(sourceOrder.count)", base)
            // A source shared by several timeline clips is decoded only once.
            // Its waveform is released when this helper returns, before the
            // next source is decoded; the project never retains all waveforms.
            if let detected = try await analyzeSource(source, clips: clips, fps: project.fps,
                settings: settings, remaining: maximumCandidates - candidates.count,
                report: { message, fraction in report(message, base + fraction / count) }) {
                candidates.append(contentsOf: detected)
            } else {
                skippedSources.append(source.name)
            }
            try Task.checkCancellation()
            report("Kaynak incelendi · \(source.name)", Double(index + 1) / count)
        }
        candidates.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        try Task.checkCancellation()
        report("Sessizlik analizi tamamlandı.", 1)
        return Result(candidates: candidates, skippedSources: skippedSources)
    }

    /// nil means the source has no audio track. It must never be confused with
    /// an existing audio track whose actual decoded samples are silent.
    private static func analyzeSource(_ source: MediaSource, clips: [PositionedClip], fps: Int,
                                      settings: SilenceSettings, remaining: Int,
                                      report: @escaping Report) async throws -> [SilenceCandidate]? {
        let entry: WaveformEntry
        do {
            entry = try await WaveformDecoder.decode(source, useCache: true)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw ProjectError.invalid("\(source.name): \(error.localizedDescription)")
        }
        try Task.checkCancellation()
        switch entry {
        case .noAudio:
            return nil
        case .failed(let message):
            throw ProjectError.invalid("\(source.name): \(message)")
        case .loading:
            throw ProjectError.invalid("\(source.name): Ses dalga formu analize hazır değil. Yeniden deneyin.")
        case .ready(let waveform):
            report("Sessiz aralıklar aranıyor · \(source.name)", 0.65)
            var candidates: [SilenceCandidate] = []
            for (index, positioned) in clips.enumerated() {
                try Task.checkCancellation()
                let detected = try SilenceDetector.candidates(waveform: waveform, clip: positioned.clip,
                    timelineStart: positioned.timelineStart, fps: fps, settings: settings)
                guard detected.count <= remaining - candidates.count else {
                    throw ProjectError.invalid("10.000'den fazla sessiz aralık bulundu. Minimum sessizlik süresini artırın veya daha az klip seçerek yeniden analiz edin.")
                }
                candidates.append(contentsOf: detected)
                report("Sessiz aralıklar aranıyor · \(source.name)", 0.65 + 0.35 * Double(index + 1) / Double(clips.count))
            }
            try Task.checkCancellation()
            return candidates
        }
    }
}
