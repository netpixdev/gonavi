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
    public static func + (a: Self, b: Self) -> Self { .init(ticks: a.ticks + b.ticks) }
    public static func - (a: Self, b: Self) -> Self { .init(ticks: a.ticks - b.ticks) }
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
    public var schemaVersion: Int = 1
    public var name: String = "Yeni proje"
    public var scene: ScenePreset = .portrait
    public var fps: Int = 30
    public var sources: [MediaSource] = []
    public var clips: [VideoClip] = []
    public var music: MusicClip?
    public var captions: [Caption] = []
    public init() {}
    public var duration: EditTime { clips.reduce(.zero) { $0 + $1.duration } }
    public func start(of id: UUID) -> EditTime {
        var result = EditTime.zero
        for clip in clips { if clip.id == id { return result }; result = result + clip.duration }
        return result
    }
    public func validate() throws {
        func check(_ test: Bool, _ message: String) throws {
            if !test { throw ProjectError.invalid(message) }
        }
        try check(schemaVersion == 1, "Bu proje sürümü desteklenmiyor.")
        try check([24, 25, 30, 60].contains(fps), "Geçersiz kare hızı.")
        try check(sources.count <= 10_000 && clips.count <= 10_000 && captions.count <= 100_000,
                  "Proje öğe sınırını aşıyor.")
        try check(Set(sources.map(\.id)).count == sources.count, "Tekrarlanan medya kimliği.")
        try check(Set(clips.map(\.id)).count == clips.count, "Tekrarlanan klip kimliği.")
        try check(Set(captions.map(\.id)).count == captions.count, "Tekrarlanan altyazı kimliği.")
        for source in sources {
            try check(source.duration.ticks > 0 && source.duration.seconds <= 86400, "Geçersiz medya süresi.")
        }
        var total: Int64 = 0
        for clip in clips {
            guard let source = sources.first(where: { $0.id == clip.sourceID }), source.isVideo else {
                throw ProjectError.invalid("Klip için video kaynağı bulunamadı.")
            }
            try check(clip.sourceStart.ticks >= 0 && clip.duration.ticks > 0
                      && clip.sourceStart.ticks <= source.duration.ticks
                      && clip.duration.ticks <= source.duration.ticks - clip.sourceStart.ticks,
                      "Klip kaynak süresinin dışında.")
            try check(clip.zoom.isFinite && (1...4).contains(clip.zoom)
                      && clip.offsetX.isFinite && (-1...1).contains(clip.offsetX)
                      && clip.offsetY.isFinite && (-1...1).contains(clip.offsetY)
                      && clip.volume.isFinite && (0...2).contains(clip.volume), "Geçersiz klip ayarı.")
            total += clip.duration.ticks
        }
        try check(total <= EditTime.scale * 86400, "Proje en fazla 24 saat olabilir.")
        if let music {
            try check(sources.contains { $0.id == music.sourceID }, "Müzik kaynağı bulunamadı.")
            try check(music.volume.isFinite && (0...2).contains(music.volume), "Geçersiz müzik seviyesi.")
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
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let offset = timelineTime - start(of: id)
        let minimum = EditTime(ticks: EditTime.scale / Int64(fps))
        guard offset >= minimum, clips[index].duration - offset >= minimum else {
            throw ProjectError.invalid("Bölme noktası klibin içinde ve uçlardan en az bir kare uzakta olmalı.")
        }
        var right = clips[index]
        right.id = UUID(); right.sourceStart = right.sourceStart + offset
        right.duration = right.duration - offset
        clips[index].duration = offset
        clips.insert(right, at: index + 1)
    }

    /// The first milestone uses timeline-anchored captions. A ripple removal maps
    /// both ends through the removed interval and drops fully removed captions.
    public mutating func remove(_ id: UUID) {
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
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32 * 1024 * 1024 else { throw ProjectError.invalid("Proje dosyası çok büyük.") }
        let project = try JSONDecoder().decode(Self.self, from: data)
        try project.validate(); return project
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
