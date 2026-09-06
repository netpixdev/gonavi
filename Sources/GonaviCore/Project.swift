import Foundation

/// Persist integer ticks, never rounded display seconds. 29.97 fps = 2002 ticks.
public struct EditTime: Codable, Hashable, Comparable, Sendable {
    public static let scale: Int64 = 60_000
    public var ticks: Int64
    public init(ticks: Int64) { self.ticks = ticks }
    public init(seconds: Double) {
        ticks = seconds.isFinite && abs(seconds) < 1e10
            ? Int64((seconds * Double(Self.scale)).rounded()) : 0
    }
    public var seconds: Double { Double(ticks) / Double(Self.scale) }
    public static let zero = EditTime(ticks: 0)
    public static func < (a: Self, b: Self) -> Bool { a.ticks < b.ticks }
    public static func + (a: Self, b: Self) -> Self {
        let result = a.ticks.addingReportingOverflow(b.ticks)
        return .init(ticks: result.overflow ? (b.ticks >= 0 ? .max : .min) : result.partialValue)
    }
    public static func - (a: Self, b: Self) -> Self {
        let result = a.ticks.subtractingReportingOverflow(b.ticks)
        return .init(ticks: result.overflow ? (b.ticks < 0 ? .max : .min) : result.partialValue)
    }
}

public enum ScenePreset: String, CaseIterable, Codable, Sendable {
    case portrait = "9:16", landscape = "16:9", square = "1:1", social = "4:5"
    public var width: Int { switch self { case .portrait: 1080; case .landscape: 1920; case .square, .social: 1080 } }
    public var height: Int { switch self { case .portrait: 1920; case .landscape: 1080; case .square: 1080; case .social: 1350 } }
}

public struct MediaSource: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var duration: EditTime
    public var isVideo: Bool
    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil,
                duration: EditTime, isVideo: Bool) {
        self.id = id; self.name = name; self.path = path; self.bookmark = bookmark
        self.duration = duration; self.isVideo = isVideo
    }
}

public struct VideoClip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var sourceID: UUID
    public var sourceStart: EditTime = .zero
    /// Missing in schema 1: the clip follows the preceding clip. New edits persist explicit positions.
    public var timelineStart: EditTime? = nil
    public var duration: EditTime
    public var zoom: Double = 1
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var fill: Bool = false
    public var volume: Double = 1
    public init(sourceID: UUID, duration: EditTime) { self.sourceID = sourceID; self.duration = duration }
}

public struct MusicClip: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public var volume: Double = 0.25
    public init(sourceID: UUID) { self.sourceID = sourceID }
}

public enum CaptionStyle: String, Codable, CaseIterable, Sendable {
    case clean = "Sade", bold = "Vurgu", box = "Kutu"
}

public struct Caption: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var start: EditTime
    public var duration: EditTime
    public var text: String
    public var style: CaptionStyle = .clean
    public init(start: EditTime, duration: EditTime, text: String) {
        self.start = start; self.duration = duration; self.text = text
    }
}

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}

public struct Project: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 2
    public var name: String = "Yeni proje"
    public var scene: ScenePreset = .portrait
    public var fps: Int = 30
    public var sources: [MediaSource] = []
    public var clips: [VideoClip] = []
    public var music: MusicClip?
    public var captions: [Caption] = []
    public init() {}
    public var duration: EditTime {
        guard !clips.isEmpty else {
            return sources.first(where: { $0.id == music?.sourceID })?.duration ?? .zero
        }
        var cursor = EditTime.zero, end = EditTime.zero
        for clip in clips {
            cursor = (clip.timelineStart ?? cursor) + clip.duration
            end = max(end, cursor)
        }
        return end
    }
    public func start(of id: UUID) -> EditTime {
        var result = EditTime.zero
        for clip in clips {
            result = clip.timelineStart ?? result
            if clip.id == id { return result }
            result = result + clip.duration
        }
        return result
    }

    /// Resolve legacy implicit placement before any structural edit, preserving equal-time order.
    public mutating func normalizeTimeline() {
        var cursor = EditTime.zero
        for index in clips.indices {
            clips[index].timelineStart = clips[index].timelineStart ?? cursor
            cursor = clips[index].timelineStart! + clips[index].duration
        }
        clips = clips.enumerated().sorted {
            let left = $0.element.timelineStart!, right = $1.element.timelineStart!
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        schemaVersion = 2
    }

    /// Choose the nearest free placement; ties prefer the earlier gap. This never overwrites a clip.
    public func resolvedPlacement(at proposed: EditTime, duration length: EditTime,
                                  excluding excludedID: UUID? = nil) -> EditTime {
        let lengthTicks = max(0, length.ticks)
        let latest = Int64.max - lengthTicks
        let desired = min(latest, max(0, proposed.ticks))
        var cursor = EditTime.zero
        var occupied: [(start: Int64, end: Int64)] = []
        for clip in clips {
            let start = clip.timelineStart ?? cursor
            cursor = start + clip.duration
            if clip.id != excludedID { occupied.append((max(0, start.ticks), max(0, cursor.ticks))) }
        }
        occupied.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var best: Int64?, bestDistance = Int64.max, lower: Int64 = 0
        func consider(_ minimum: Int64, _ maximum: Int64) {
            guard minimum <= maximum, minimum <= latest else { return }
            let candidate = min(maximum, max(minimum, desired))
            let distance = candidate >= desired ? candidate - desired : desired - candidate
            if best == nil || distance < bestDistance || (distance == bestDistance && candidate < best!) {
                best = candidate; bestDistance = distance
            }
        }
        for interval in occupied {
            if interval.start >= lengthTicks { consider(lower, interval.start - lengthTicks) }
            lower = max(lower, interval.end)
        }
        consider(lower, latest)
        return EditTime(ticks: best ?? desired)
    }

    @discardableResult
    public mutating func appendSourceToTimeline(source: MediaSource, at time: EditTime? = nil) -> UUID {
        normalizeTimeline()
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        var clip = VideoClip(sourceID: source.id, duration: source.duration)
        let end = clips.last.map { ($0.timelineStart ?? .zero) + $0.duration } ?? .zero
        clip.timelineStart = resolvedPlacement(at: time ?? end, duration: clip.duration)
        clips.append(clip); normalizeTimeline()
        return clip.id
    }

    /// Caption fragments inside this clip follow it; fragments outside it remain timeline-anchored.
    @discardableResult
    public mutating func placeClip(id: UUID, at time: EditTime) -> EditTime {
        normalizeTimeline()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return time }
        let previous = clips[index].timelineStart!, length = clips[index].duration
        let placed = resolvedPlacement(at: time, duration: length, excluding: id)
        guard placed != previous else { return placed }
        let upper = previous + length, delta = placed - previous
        captions = captions.flatMap { caption -> [Caption] in
            let end = caption.start + caption.duration
            let insideStart = max(previous, caption.start), insideEnd = min(upper, end)
            guard insideStart < insideEnd else { return [caption] }
            var pieces: [Caption] = []
            func fragment(start: EditTime, end: EditTime, offset: EditTime = .zero) {
                guard start < end else { return }
                var piece = caption
                if !pieces.isEmpty { piece.id = UUID() }
                piece.start = start + offset; piece.duration = end - start
                pieces.append(piece)
            }
            fragment(start: caption.start, end: insideStart)
            fragment(start: insideStart, end: insideEnd, offset: delta)
            fragment(start: insideEnd, end: end)
            return pieces
        }.sorted { $0.start < $1.start }
        clips[index].timelineStart = placed
        normalizeTimeline()
        // Timeline-anchored captions outside a moved last clip cannot extend an otherwise empty project.
        let end = duration
        captions = captions.compactMap { caption in
            guard caption.start < end else { return nil }
            var clipped = caption; clipped.duration = min(caption.duration, end - caption.start)
            return clipped.duration.ticks > 0 ? clipped : nil
        }
        return placed
    }
    public func validate() throws {
        func check(_ test: Bool, _ message: String) throws {
            if !test { throw ProjectError.invalid(message) }
        }
        try check([1, 2].contains(schemaVersion), "Bu proje sürümü desteklenmiyor.")
        try check([24, 25, 30, 60].contains(fps), "Geçersiz kare hızı.")
        try check(sources.count <= 10_000 && clips.count <= 10_000 && captions.count <= 100_000,
                  "Proje öğe sınırını aşıyor.")
        try check(Set(sources.map(\.id)).count == sources.count, "Tekrarlanan medya kimliği.")
        try check(Set(clips.map(\.id)).count == clips.count, "Tekrarlanan klip kimliği.")
        try check(Set(captions.map(\.id)).count == captions.count, "Tekrarlanan altyazı kimliği.")
        for source in sources {
            try check(source.duration.ticks > 0 && source.duration.seconds <= 86400, "Geçersiz medya süresi.")
        }
        var total: Int64 = 0, previousEnd: Int64 = 0
        for clip in clips {
            guard let source = sources.first(where: { $0.id == clip.sourceID }) else {
                throw ProjectError.invalid("Klip için medya kaynağı bulunamadı.")
            }
            try check(clip.sourceStart.ticks >= 0 && clip.duration.ticks > 0
                      && clip.sourceStart.ticks <= source.duration.ticks
                      && clip.duration.ticks <= source.duration.ticks - clip.sourceStart.ticks,
                      "Klip kaynak süresinin dışında.")
            try check(clip.zoom.isFinite && (1...4).contains(clip.zoom)
                      && clip.offsetX.isFinite && (-1...1).contains(clip.offsetX)
                      && clip.offsetY.isFinite && (-1...1).contains(clip.offsetY)
                      && clip.volume.isFinite && (0...2).contains(clip.volume), "Geçersiz klip ayarı.")
            let start = clip.timelineStart?.ticks ?? previousEnd
            try check(start >= 0 && start >= previousEnd && start <= Int64.max - clip.duration.ticks,
                      "Klipler çakışamaz ve zaman çizelgesinde sıralı olmalı.")
            previousEnd = start + clip.duration.ticks
            total = max(total, previousEnd)
        }
        if let music {
            try check(sources.contains { $0.id == music.sourceID }, "Müzik kaynağı bulunamadı.")
            try check(music.volume.isFinite && (0...2).contains(music.volume), "Geçersiz müzik seviyesi.")
            if clips.isEmpty { total = sources.first(where: { $0.id == music.sourceID })!.duration.ticks }
        }
        for caption in captions {
            try check(caption.start.ticks >= 0 && caption.start.ticks < total
                      && caption.duration.ticks > 0 && caption.duration.ticks <= total - caption.start.ticks,
                      "Altyazı proje süresinin dışında.")
            try check(!caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && caption.text.count <= 500, "Altyazı 1–500 karakter olmalı.")
        }
    }

    public mutating func split(_ id: UUID, at timelineTime: EditTime) throws {
        normalizeTimeline()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let offset = timelineTime - start(of: id)
        let minimum = EditTime(ticks: EditTime.scale / Int64(fps))
        guard offset >= minimum, clips[index].duration - offset >= minimum else {
            throw ProjectError.invalid("Bölme noktası klibin içinde ve uçlardan en az bir kare uzakta olmalı.")
        }
        var right = clips[index]
        right.id = UUID(); right.sourceStart = right.sourceStart + offset
        right.timelineStart = timelineTime
        right.duration = right.duration - offset
        clips[index].duration = offset
        clips.insert(right, at: index + 1)
    }

    /// The first milestone uses timeline-anchored captions. A ripple removal maps
    /// both ends through the removed interval and drops fully removed captions.
    public mutating func remove(_ id: UUID) {
        normalizeTimeline()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let lower = start(of: id), upper = lower + clips[index].duration
        func map(_ time: EditTime) -> EditTime {
            if time <= lower { return time }
            if time < upper { return lower }
            return time - (upper - lower)
        }
        captions = captions.compactMap { caption in
            var updated = caption
            updated.start = map(caption.start)
            updated.duration = map(caption.start + caption.duration) - updated.start
            return updated.duration.ticks > 0 ? updated : nil
        }
        clips.remove(at: index)
        for index in clips.indices {
            clips[index].timelineStart = map(clips[index].timelineStart!)
        }
        let end = duration
        captions = captions.compactMap { caption in
            guard caption.start < end else { return nil }
            var clipped = caption; clipped.duration = min(caption.duration, end - caption.start)
            return clipped.duration.ticks > 0 ? clipped : nil
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32 * 1024 * 1024 else { throw ProjectError.invalid("Proje dosyası çok büyük.") }
        var project = try JSONDecoder().decode(Self.self, from: data)
        try project.validate()
        if project.schemaVersion == 1 { project.normalizeTimeline() }
        return project
    }
    public func srt() -> String {
        func stamp(_ value: EditTime) -> String {
            let ms = Int((value.seconds * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return captions.sorted { $0.start < $1.start }.enumerated().map { index, caption in
            "\(index + 1)\n\(stamp(caption.start)) --> \(stamp(caption.start + caption.duration))\n\(caption.text)\n"
        }.joined(separator: "\n")
    }
}
