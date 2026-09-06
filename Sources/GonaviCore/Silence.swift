import Foundation

public struct SilenceSettings: Equatable, Sendable {
    public var thresholdDB: Double
    public var minimumDuration: Double
    public var padding: Double

    public init(thresholdDB: Double = -38, minimumDuration: Double = 0.5, padding: Double = 0.12) {
        self.thresholdDB = thresholdDB; self.minimumDuration = minimumDuration; self.padding = padding
    }

    public func validate() throws {
        guard thresholdDB.isFinite, (-60 ... -20).contains(thresholdDB),
              minimumDuration.isFinite, minimumDuration > 0, minimumDuration <= 60,
              padding.isFinite, (0...10).contains(padding) else {
            throw ProjectError.invalid("Sessizlik eşiği −60–−20 dB, en kısa süre 0–60 saniye, kenar payı 0–10 saniye arasında olmalı.")
        }
    }
}

/// An interval in the original timeline, not in the already shortened preview.
public struct SilenceCandidate: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var clipID: UUID
    public var start: EditTime
    public var end: EditTime
    public var duration: EditTime { end - start }

    public init(clipID: UUID, start: EditTime, end: EditTime) {
        id = UUID(); self.clipID = clipID; self.start = start; self.end = end
    }
}

public enum SilenceDetector {
    /// Uses source RMS, unaffected by the clip's volume control. Peaks preserve
    /// short consonants/transients that a bucket's average level could conceal.
    public static func candidates(waveform: WaveformData, clip: VideoClip,
                                  timelineStart: EditTime, fps: Int,
                                  settings: SilenceSettings) throws -> [SilenceCandidate] {
        try Task.checkCancellation()
        try settings.validate()
        guard [24, 25, 30, 60].contains(fps), clip.sourceStart.ticks >= 0,
              clip.duration.ticks > 0, clip.duration.seconds <= 86_400,
              clip.sourceStart.ticks <= Int64.max - clip.duration.ticks,
              timelineStart.ticks >= 0, timelineStart.ticks <= Int64.max - clip.duration.ticks else {
            throw ProjectError.invalid("Sessizlik analizi için klip süresi veya kare hızı geçersiz.")
        }
        let sourceEnd = clip.sourceStart + clip.duration
        // Compare at the project's tick precision: a decoded duration can differ
        // by less than half a tick after project serialization. Never interpret
        // an uncovered tail of the clip as silence.
        guard sourceEnd <= EditTime(seconds: waveform.duration) else { return [] }
        let sourceLower = clip.sourceStart.seconds
        let sourceUpper = min(sourceEnd.seconds, waveform.duration)
        let bucketDuration = waveform.bucketDuration
        let first = max(0, Int(floor(sourceLower / bucketDuration)))
        let last = min(waveform.peaks.count, Int(ceil(sourceUpper / bucketDuration)))
        guard first < last else { return [] }
        let rmsThreshold = Float(pow(10, settings.thresholdDB / 20))
        let peakThreshold = Float(pow(10, (settings.thresholdDB + 6) / 20))
        let frameTicks = EditTime.scale / Int64(fps)
        var result: [SilenceCandidate] = []
        var quietStart: Double?
        var quietEnd = sourceLower

        func finishRun() throws {
            guard let lower = quietStart else { return }
            defer { quietStart = nil }
            guard quietEnd - lower + 1e-9 >= settings.minimumDuration else { return }
            let paddedLower = lower - sourceLower + settings.padding
            let paddedUpper = quietEnd - sourceLower - settings.padding
            guard paddedUpper > paddedLower else { return }
            // Round inward twice: first to integer edit ticks, then to the
            // global timeline frame grid. Source trims need not be frame aligned.
            let lowerOffset = Int64(ceil(paddedLower * Double(EditTime.scale) - 1e-7))
            let upperOffset = Int64(floor(paddedUpper * Double(EditTime.scale) + 1e-7))
            let lowerTick = timelineStart.ticks + max(0, lowerOffset)
            let upperTick = timelineStart.ticks + min(clip.duration.ticks, upperOffset)
            let remainder = lowerTick % frameTicks
            let adjustment = remainder == 0 ? 0 : frameTicks - remainder
            guard lowerTick <= Int64.max - adjustment else { return }
            let start = lowerTick + adjustment
            let end = upperTick - upperTick % frameTicks
            guard start < end else { return }
            guard result.count < 10_000 else {
                throw ProjectError.invalid("Bu klipte 10.000'den fazla sessiz aralık bulundu. En kısa sessizlik süresini artırın.")
            }
            result.append(SilenceCandidate(clipID: clip.id, start: EditTime(ticks: start), end: EditTime(ticks: end)))
        }

        for index in first..<last {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let lower = max(sourceLower, Double(index) * bucketDuration)
            let upper = min(sourceUpper, Double(index + 1) * bucketDuration)
            guard upper > lower else { continue }
            if waveform.rms[index] < rmsThreshold && waveform.peaks[index] < peakThreshold {
                if quietStart == nil { quietStart = lower }
                quietEnd = upper
            } else {
                try finishRun()
            }
        }
        try finishRun()
        try Task.checkCancellation()
        return result
    }
}

public extension Project {
    /// Atomically ripple selected intervals out of the original timeline. The
    /// music bed remains anchored at source offset zero; only main clips are cut.
    mutating func removeSilences(_ candidates: [SilenceCandidate]) throws {
        try Task.checkCancellation()
        try validate()
        guard !candidates.isEmpty else { return }
        var next = self
        next.normalizeTimeline()
        let byID = Dictionary(uniqueKeysWithValues: next.clips.map { ($0.id, $0) })
        var ranges: [(lower: Int64, upper: Int64)] = []
        ranges.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            guard let clip = byID[candidate.clipID], let clipStart = clip.timelineStart,
                  candidate.start >= clipStart, candidate.start < candidate.end,
                  candidate.end <= clipStart + clip.duration else {
                throw ProjectError.invalid("Sessiz aralık klibin dışında veya klip artık bulunamıyor. Analizi yeniden çalıştırın.")
            }
            ranges.append((candidate.start.ticks, candidate.end.ticks))
        }
        ranges.sort { $0.lower == $1.lower ? $0.upper < $1.upper : $0.lower < $1.lower }
        var merged: [(lower: Int64, upper: Int64)] = []
        for range in ranges {
            if let last = merged.last, range.lower <= last.upper {
                merged[merged.count - 1].upper = max(last.upper, range.upper)
            } else { merged.append(range) }
        }
        var removedBefore: [Int64] = [0]
        for range in merged { removedBefore.append(removedBefore.last! + (range.upper - range.lower)) }

        func mapped(_ time: Int64) -> Int64 {
            // Locate the first interval which has not ended at this time.
            var lower = 0, upper = merged.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if merged[middle].upper <= time { lower = middle + 1 } else { upper = middle }
            }
            var removed = removedBefore[lower]
            if lower < merged.count && time > merged[lower].lower { removed += time - merged[lower].lower }
            return time - removed
        }

        var survivors: [VideoClip] = []
        var firstCut = 0
        for (clipIndex, clip) in next.clips.enumerated() {
            if clipIndex % 256 == 0 { try Task.checkCancellation() }
            let start = clip.timelineStart!.ticks, end = start + clip.duration.ticks
            while firstCut < merged.count && merged[firstCut].upper <= start { firstCut += 1 }
            var cursor = start, cutIndex = firstCut, hasFragment = false
            func appendFragment(until fragmentEnd: Int64) throws {
                guard cursor < fragmentEnd else { return }
                guard survivors.count < 10_000 else {
                    throw ProjectError.invalid("Sessizlik temizliği 10.000 klip sınırını aşıyor. Daha az aralık seçin.")
                }
                var fragment = clip
                if hasFragment { fragment.id = UUID() }
                fragment.sourceStart = clip.sourceStart + EditTime(ticks: cursor - start)
                fragment.timelineStart = EditTime(ticks: mapped(cursor))
                fragment.duration = EditTime(ticks: fragmentEnd - cursor)
                survivors.append(fragment); hasFragment = true
            }
            while cutIndex < merged.count && merged[cutIndex].lower < end {
                let cut = merged[cutIndex]
                try appendFragment(until: max(cursor, min(end, cut.lower)))
                cursor = max(cursor, min(end, cut.upper))
                cutIndex += 1
            }
            try appendFragment(until: end)
        }
        guard !survivors.isEmpty else {
            throw ProjectError.invalid("Seçilen aralıklar ana kurgunun tamamını kaldırıyor. En az bir ses veya video bölümü bırakın.")
        }
        next.clips = survivors
        let newEnd = next.duration.ticks
        // The current project schema has no independent trailing-blank duration.
        // Do not silently delete an unselected gap when its final clip disappears.
        guard newEnd == mapped(self.duration.ticks) else {
            throw ProjectError.invalid("Son klibin tamamını çıkarmak, önündeki boşluğu da kaldırır. Bu kesimin seçimini kaldırın veya uçlarda korunacak payı artırın.")
        }
        var updatedCaptions: [Caption] = []
        for (index, caption) in next.captions.enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            let start = mapped(caption.start.ticks)
            let end = min(newEnd, mapped((caption.start + caption.duration).ticks))
            guard start < end else { continue }
            var updated = caption
            updated.start = EditTime(ticks: start); updated.duration = EditTime(ticks: end - start)
            updatedCaptions.append(updated)
        }
        next.captions = updatedCaptions
        try next.validate()
        try Task.checkCancellation()
        self = next
    }
}
