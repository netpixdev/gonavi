import Foundation

public struct RecentProject: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let bookmark: Data?
    public let name: String
    public let scene: ScenePreset
    public let duration: EditTime
    public let openedAt: Date

    public init(path: String, bookmark: Data? = nil, name: String, scene: ScenePreset,
                duration: EditTime, openedAt: Date = Date()) {
        self.path = path; self.bookmark = bookmark; self.name = name
        self.scene = scene; self.duration = duration; self.openedAt = openedAt
    }

    public static func recording(_ entry: Self, in existing: [Self]) -> [Self] {
        [entry] + Array(existing.filter { $0.path != entry.path }.prefix(11))
    }
}
