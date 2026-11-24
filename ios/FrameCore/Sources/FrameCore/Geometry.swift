import Foundation

/// A point in normalized image space: origin top-left, x right, y down, both 0...1.
/// "Image space" is always the frame as the holder sees it (upright, and mirrored for selfies).
public struct Vec2: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    public static func midpoint(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2((a.x + b.x) / 2, (a.y + b.y) / 2) }
}

/// A rectangle in normalized image space (top-left origin).
public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var center: Vec2 { Vec2(midX, midY) }
    public var area: Double { max(0, w) * max(0, h) }

    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    public func intersection(_ o: Rect) -> Rect? {
        let x0 = max(minX, o.minX), y0 = max(minY, o.minY)
        let x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }

    public func iou(_ o: Rect) -> Double {
        guard let i = intersection(o) else { return 0 }
        let u = area + o.area - i.area
        return u > 0 ? i.area / u : 0
    }

    /// Clamped to the unit square.
    public var clamped: Rect {
        let x0 = min(max(minX, 0), 1), y0 = min(max(minY, 0), 1)
        let x1 = min(max(maxX, 0), 1), y1 = min(max(maxY, 0), 1)
        return Rect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    public func insetBy(dx: Double, dy: Double) -> Rect { Rect(x: x + dx, y: y + dy, w: w - 2 * dx, h: h - 2 * dy) }

    /// Converts a Vision-style rect (origin bottom-left) to top-left origin.
    public static func fromBottomLeft(x: Double, y: Double, w: Double, h: Double) -> Rect {
        Rect(x: x, y: 1 - y - h, w: w, h: h)
    }
}

public enum MathX {
    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    public static func deg(_ rad: Double) -> Double { rad * 180 / .pi }
    public static func rad(_ deg: Double) -> Double { deg * .pi / 180 }

    /// Wraps an angle to -180...180.
    public static func wrap180(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}
