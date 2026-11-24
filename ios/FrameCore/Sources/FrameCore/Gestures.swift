import Foundation

/// Measurements computed from landmark points (any consistent coordinate space).
public enum Landmarks {
    /// Eye openness: height of the eye contour over its width. nil if the contour is degenerate.
    public static func eyeOpenness(_ contour: [Vec2]) -> Double? {
        guard contour.count >= 4,
              let minX = contour.map(\.x).min(), let maxX = contour.map(\.x).max(),
              let minY = contour.map(\.y).min(), let maxY = contour.map(\.y).max() else { return nil }
        let w = maxX - minX
        guard w > 1e-6 else { return nil }
        return (maxY - minY) / w
    }

    /// Where the nose tip sits between the eye line (0) and the mouth line (1).
    public static func noseRatio(leftEye: [Vec2], rightEye: [Vec2], noseTip: Vec2, mouth: [Vec2]) -> Double? {
        guard !leftEye.isEmpty, !rightEye.isEmpty, !mouth.isEmpty else { return nil }
        func meanY(_ pts: [Vec2]) -> Double {
            var s = 0.0
            for p in pts { s += p.y }
            return s / Double(pts.count)
        }
        let eyeY: Double = (meanY(leftEye) + meanY(rightEye)) / 2
        let mouthY: Double = meanY(mouth)
        let span = mouthY - eyeY
        guard abs(span) > 1e-6 else { return nil }
        return (noseTip.y - eyeY) / span
    }

    /// Lowest point of a set (largest y), used for the nose tip from the nose contour.
    public static func lowest(_ pts: [Vec2]) -> Vec2? { pts.max { $0.y < $1.y } }
}

/// One detected hand: wrist plus the base (MCP) and tip of each finger.
public struct HandPoints: Equatable, Sendable {
    public var wrist: Vec2
    /// Thumb, index, middle, ring, little. nil when that finger was not detected.
    public var tips: [Vec2?]
    public var bases: [Vec2?]
    public init(wrist: Vec2, tips: [Vec2?], bases: [Vec2?]) {
        self.wrist = wrist
        self.tips = tips
        self.bases = bases
    }
}

public enum HandGesture {
    /// An open palm: at least four fingers extended well past their knuckles, and spread apart.
    public static func isOpenPalm(_ h: HandPoints) -> Bool {
        var extended = 0
        var tips: [Vec2] = []
        for i in 0..<min(h.tips.count, h.bases.count) {
            guard let tip = h.tips[i], let base = h.bases[i] else { continue }
            let baseDist = base.distance(to: h.wrist)
            let tipDist = tip.distance(to: h.wrist)
            guard baseDist > 1e-6 else { continue }
            if tipDist > baseDist * 1.55 {
                extended += 1
                tips.append(tip)
            }
        }
        guard extended >= 4 else { return false }
        // Fingers must not be bunched into a fist pointing at the camera.
        let xs = tips.map(\.x), ys = tips.map(\.y)
        let spread = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        let palmSize = h.bases.compactMap { $0 }.map { $0.distance(to: h.wrist) }.max() ?? 0
        return spread > palmSize * 0.6
    }
}
