import CoreGraphics
import Foundation
import GonaviCore

struct VisualLayout {
    /// Coordinates in the oriented, origin-normalized source image.
    let cropRect: CGRect
    /// Maps those original source coordinates directly into scene coordinates.
    let transform: CGAffineTransform
    /// Top-left, top-right, bottom-right, bottom-left after all transforms.
    let corners: [CGPoint]
    let center: CGPoint
    /// Cropped, scaled dimensions before rotation.
    let size: CGSize
    let scale: CGFloat
}

/// One geometry implementation for rendering and the interactive canvas. Both
/// source and scene coordinates use a bottom-left origin. Positive rotation is
/// counterclockwise; legacy offsets are measured in half-scene dimensions.
enum VisualGeometry {
    static func layout(sourceSize: CGSize, sceneSize: CGSize, clip: VideoClip) -> VisualLayout {
        func positive(_ value: CGFloat) -> CGFloat { value.isFinite && value > 0 ? value : 1 }
        func fraction(_ value: Double) -> CGFloat { value.isFinite ? CGFloat(min(1, max(0, value))) : 0 }
        let width = positive(sourceSize.width), height = positive(sourceSize.height)
        let sceneWidth = positive(sceneSize.width), sceneHeight = positive(sceneSize.height)
        let left = fraction(clip.crop.left), top = fraction(clip.crop.top)
        let right = fraction(clip.crop.right), bottom = fraction(clip.crop.bottom)
        let crop = CGRect(x: width * left, y: height * bottom,
                          width: width * max(0.000001, 1 - left - right),
                          height: height * max(0.000001, 1 - top - bottom))
        let xScale = sceneWidth / crop.width, yScale = sceneHeight / crop.height
        let baseScale = clip.fill ? max(xScale, yScale) : min(xScale, yScale)
        let zoom = clip.zoom.isFinite && clip.zoom > 0 ? CGFloat(clip.zoom) : 1
        let scale = baseScale * zoom
        let offsetX = clip.offsetX.isFinite ? CGFloat(clip.offsetX) : 0
        let offsetY = clip.offsetY.isFinite ? CGFloat(clip.offsetY) : 0
        let center = CGPoint(x: sceneWidth * (1 + offsetX) / 2, y: sceneHeight * (1 + offsetY) / 2)
        let radians = CGFloat(clip.rotation.isFinite ? clip.rotation * .pi / 180 : 0)
        let cosine = cos(radians) * scale, sine = sin(radians) * scale
        // Translate the crop center to zero, scale, rotate, then translate to
        // the scene center. An explicit matrix avoids concatenation ambiguity.
        let transform = CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine,
            tx: center.x - cosine * crop.midX + sine * crop.midY,
            ty: center.y - sine * crop.midX - cosine * crop.midY)
        let corners = [CGPoint(x: crop.minX, y: crop.maxY), CGPoint(x: crop.maxX, y: crop.maxY),
                       CGPoint(x: crop.maxX, y: crop.minY), CGPoint(x: crop.minX, y: crop.minY)]
            .map { $0.applying(transform) }
        return VisualLayout(cropRect: crop, transform: transform, corners: corners, center: center,
                            size: CGSize(width: crop.width * scale, height: crop.height * scale), scale: scale)
    }
}
