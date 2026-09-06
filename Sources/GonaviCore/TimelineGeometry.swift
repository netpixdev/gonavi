import Foundation

public struct SnapResult: Equatable, Sendable {
    public var time: Double
    public var guide: Double?
    public init(time: Double, guide: Double? = nil) { self.time = time; self.guide = guide }
}

/// Coordinates are relative to a moving viewport, so a long project never needs a giant SwiftUI view.
public enum TimelineGeometry {
    public static func frameAligned(_ seconds: Double, fps: Int) -> Double {
        guard seconds.isFinite else { return 0 }
        let rate = Double(max(1, fps))
        let value = max(0, seconds)
        guard value <= Double.greatestFiniteMagnitude / rate else { return value }
        return (value * rate).rounded() / rate
    }

    public static func snap(proposedStart: Double, duration: Double, candidates: [Double],
                            pixelsPerSecond: Double, fps: Int, enabled: Bool = true,
                            thresholdPixels: Double = 8) -> SnapResult {
        let start = frameAligned(proposedStart, fps: fps)
        guard enabled, proposedStart.isFinite, duration.isFinite, duration >= 0,
              pixelsPerSecond.isFinite, pixelsPerSecond > 0,
              thresholdPixels.isFinite, thresholdPixels >= 0 else { return SnapResult(time: start) }
        let proposed = max(0, proposedStart), threshold = thresholdPixels / pixelsPerSecond
        var bestDistance = Double.infinity
        var result = SnapResult(time: start)
        // Sorted unique candidates make equidistant outcomes independent of model ordering.
        let targets = Set(candidates.filter { $0.isFinite && $0 >= 0 } + [0]).sorted()
        for target in targets {
            for offset in [0.0, duration] {
                let requested = target - offset
                guard requested >= 0 else { continue }
                let distance = abs(requested - proposed)
                let aligned = frameAligned(requested, fps: fps)
                guard distance <= threshold + 1e-9 else { continue }
                if distance < bestDistance - 1e-9 ||
                    (abs(distance - bestDistance) <= 1e-9 && aligned < result.time) {
                    bestDistance = distance; result = SnapResult(time: aligned, guide: target)
                }
            }
        }
        return result
    }

    public static func x(for time: Double, viewportStart: Double, pixelsPerSecond: Double) -> Double {
        guard time.isFinite, viewportStart.isFinite, pixelsPerSecond.isFinite, pixelsPerSecond > 0 else { return 0 }
        let result = (time - max(0, viewportStart)) * pixelsPerSecond
        return result.isFinite ? result : 0
    }

    public static func time(atX x: Double, viewportStart: Double, pixelsPerSecond: Double) -> Double {
        guard x.isFinite, viewportStart.isFinite, pixelsPerSecond.isFinite, pixelsPerSecond > 0 else { return 0 }
        let result = max(0, viewportStart) + x / pixelsPerSecond
        return result.isFinite ? max(0, result) : 0
    }

    public static func visibleRange(viewportStart: Double, width: Double,
                                    pixelsPerSecond: Double, overscanPixels: Double = 100) -> ClosedRange<Double> {
        let start = viewportStart.isFinite ? max(0, viewportStart) : 0
        guard width.isFinite, width >= 0, pixelsPerSecond.isFinite, pixelsPerSecond > 0 else { return start...start }
        let overscan = overscanPixels.isFinite ? max(0, overscanPixels) / pixelsPerSecond : 0
        let end = start + width / pixelsPerSecond + overscan
        return max(0, start - overscan)...(end.isFinite ? end : start)
    }

    /// Pan without clamping to current media duration; dropping into blank time can extend a project.
    public static func pannedStart(_ viewportStart: Double, byPixels delta: Double,
                                   pixelsPerSecond: Double) -> Double {
        time(atX: delta, viewportStart: viewportStart, pixelsPerSecond: pixelsPerSecond)
    }
}
