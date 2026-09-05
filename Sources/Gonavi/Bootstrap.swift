import AppKit
import SwiftUI

@main
enum Bootstrap {
    @MainActor static func main() async {
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
