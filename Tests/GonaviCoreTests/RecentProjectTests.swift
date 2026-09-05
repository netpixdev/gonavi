import XCTest
@testable import GonaviCore

final class RecentProjectTests: XCTestCase {
    private func entry(_ index: Int) -> RecentProject {
        RecentProject(path: "/project-\(index).gonavi", name: "Proje \(index)", scene: .portrait,
                      duration: .zero, openedAt: Date(timeIntervalSince1970: 0))
    }
    func testRecentListDeduplicatesAndMovesOpenedProjectFirst() {
        let original = [entry(1), entry(2), entry(3)]
        let result = RecentProject.recording(entry(2), in: original)
        XCTAssertEqual(result.map(\.path), ["/project-2.gonavi", "/project-1.gonavi", "/project-3.gonavi"])
    }
    func testRecentListCapsAtTwelveWithoutDeletingFiles() {
        let original = (0..<12).map(entry)
        let result = RecentProject.recording(entry(12), in: original)
        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(result.first?.path, "/project-12.gonavi")
        XCTAssertEqual(result.last?.path, "/project-10.gonavi")
    }
    func testRecentMetadataRoundTrip() throws {
        let data = try JSONEncoder().encode([entry(1)])
        XCTAssertEqual(try JSONDecoder().decode([RecentProject].self, from: data), [entry(1)])
    }
}
