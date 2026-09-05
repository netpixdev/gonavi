import AppKit
import SwiftUI

@main
enum Bootstrap {
    @MainActor static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--caption-smoke-test") {
            guard CommandLine.arguments.count > index + 3 else { exit(2) }
            do {
                try await CaptionSmokeTest.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                                               speech: URL(fileURLWithPath: CommandLine.arguments[index + 2]),
                                               language: CommandLine.arguments[index + 3])
                exit(0)
            } catch { fputs("Caption test failed: \(error)\n", stderr); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test") {
            guard CommandLine.arguments.count > index + 1 else { exit(2) }
            do {
                try await SmokeTest.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                print("Gonavi media smoke test passed")
                exit(0)
            } catch {
                fputs("Smoke test failed: \(error)\n", stderr); exit(1)
            }
        }
        GonaviApp.main()
    }
}
