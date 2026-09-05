import SwiftUI

// Hallmark · native editing workbench · utilitarian dark surfaces / restrained mint accent.
// Pre-emit critique: P4 H4 E3 S5 R5 V4. Execution requires a physical Mac visual check.
// Desktop scope: native window chrome, system typography, no web/mobile layout.
enum Theme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let inset = Color(nsColor: .underPageBackgroundColor)
    static let ink = Color.primary
    static let secondary = Color.secondary
    static let accent = Color(red: 0.49, green: 0.89, blue: 0.72)
    static let video = Color(red: 0.22, green: 0.43, blue: 0.39)
    static let audio = Color(red: 0.31, green: 0.35, blue: 0.56)
    static let caption = Color(red: 0.55, green: 0.43, blue: 0.22)
    static let rule = Color.primary.opacity(0.12)
}
