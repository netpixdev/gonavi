import SwiftUI

// Hallmark · native editing workbench · utilitarian dark surfaces / restrained mint accent.
// Pre-emit critique: P4 H4 E3 S5 R5 V4. Execution requires a physical Mac visual check.
// Desktop scope: native window chrome, system typography, no web/mobile layout.
enum Theme {
    static let canvasColor = NSColor(srgbRed: 0.075, green: 0.085, blue: 0.095, alpha: 1)
    static let panelColor = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.135, alpha: 1)
    static let insetColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
    static let raisedColor = NSColor(srgbRed: 0.16, green: 0.175, blue: 0.19, alpha: 1)
    static let accentColor = NSColor(srgbRed: 0.49, green: 0.89, blue: 0.72, alpha: 1)
    static let videoColor = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.66, alpha: 1)
    static let audioColor = NSColor(srgbRed: 0.63, green: 0.60, blue: 0.91, alpha: 1)
    static let captionColor = NSColor(srgbRed: 0.92, green: 0.72, blue: 0.39, alpha: 1)
    static let canvas = Color(nsColor: canvasColor)
    static let panel = Color(nsColor: panelColor)
    static let inset = Color(nsColor: insetColor)
    static let raised = Color(nsColor: raisedColor)
    static let ink = Color(white: 0.94)
    static let secondary = Color(white: 0.62)
    static let accent = Color(red: 0.49, green: 0.89, blue: 0.72)
    static let onAccent = Color(red: 0.07, green: 0.16, blue: 0.12)
    static let video = Color(red: 0.22, green: 0.43, blue: 0.39)
    static let audio = Color(red: 0.31, green: 0.35, blue: 0.56)
    static let caption = Color(red: 0.55, green: 0.43, blue: 0.22)
    static let rule = Color.primary.opacity(0.12)
}

struct StudioButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .background(primary ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.rule, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.38)
    }
}
