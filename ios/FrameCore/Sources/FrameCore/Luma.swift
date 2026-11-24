import Foundation

/// A small 8-bit grayscale image in image space (upright for the holder, row 0 at the top).
/// Used for the luminance of the analysis frame and for the person mask (255 = person).
public struct LumaImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    public func value(x: Int, y: Int) -> Double { Double(pixels[y * width + x]) / 255 }

    /// Nearest-neighbour resample, used to bring the person mask to the luma grid's size.
    public func resized(width w: Int, height h: Int) -> LumaImage {
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let sy = min(height - 1, y * height / h)
            for x in 0..<w {
                let sx = min(width - 1, x * width / w)
                out[y * w + x] = pixels[sy * width + sx]
            }
        }
        return LumaImage(width: w, height: h, pixels: out)
    }

    /// Pixel bounds of a normalized rect, clamped. nil when empty.
    public func pixelBounds(_ r: Rect) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let c = r.clamped
        let x0 = Int((c.minX * Double(width)).rounded(.down))
        let y0 = Int((c.minY * Double(height)).rounded(.down))
        let x1 = min(width, Int((c.maxX * Double(width)).rounded(.up)))
        let y1 = min(height, Int((c.maxY * Double(height)).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return (x0, y0, x1, y1)
    }

    // MARK: Exposure

    public var mean: Double {
        guard !pixels.isEmpty else { return 0 }
        var s = 0
        for p in pixels { s += Int(p) }
        return Double(s) / Double(pixels.count) / 255
    }

    public func clipFractions(high: UInt8 = 247, low: UInt8 = 8) -> (high: Double, low: Double) {
        guard !pixels.isEmpty else { return (0, 0) }
        var hi = 0, lo = 0
        for p in pixels {
            if p >= high { hi += 1 } else if p <= low { lo += 1 }
        }
        return (Double(hi) / Double(pixels.count), Double(lo) / Double(pixels.count))
    }

    /// Mean of a region, optionally only where `mask` is background (< 128) or person (>= 128).
    public func mean(in r: Rect, mask: LumaImage? = nil, person: Bool? = nil) -> Double? {
        guard let b = pixelBounds(r) else { return nil }
        var s = 0, n = 0
        for y in b.y0..<b.y1 {
            for x in b.x0..<b.x1 {
                if let mask, let person {
                    let isPerson = mask[x, y] >= 128
                    if isPerson != person { continue }
                }
                s += Int(self[x, y])
                n += 1
            }
        }
        return n > 0 ? Double(s) / Double(n) / 255 : nil
    }

    /// Mean of everything outside the people.
    public func backgroundMean(mask: LumaImage) -> Double? {
        mean(in: Rect(x: 0, y: 0, w: 1, h: 1), mask: mask, person: false)
    }

    // MARK: Edges

    /// Horizontal and vertical intensity differences (central difference), 0...255 scale.
    public func gradients() -> (gx: [Int], gy: [Int]) {
        var gx = [Int](repeating: 0, count: width * height)
        var gy = [Int](repeating: 0, count: width * height)
        guard width > 2, height > 2 else { return (gx, gy) }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                gx[i] = abs(Int(pixels[i + 1]) - Int(pixels[i - 1]))
                gy[i] = abs(Int(pixels[i + width]) - Int(pixels[i - width]))
            }
        }
        return (gx, gy)
    }

    /// Variance of the 4-neighbour Laplacian over a region: a standard focus/sharpness measure.
    public func laplacianVariance(in r: Rect = Rect(x: 0, y: 0, w: 1, h: 1)) -> Double {
        guard let b = pixelBounds(r) else { return 0 }
        let x0 = max(1, b.x0), y0 = max(1, b.y0), x1 = min(width - 1, b.x1), y1 = min(height - 1, b.y1)
        guard x1 > x0, y1 > y0 else { return 0 }
        var sum = 0.0, sum2 = 0.0, n = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let c = 4 * Int(self[x, y])
                let l = c - Int(self[x - 1, y]) - Int(self[x + 1, y]) - Int(self[x, y - 1]) - Int(self[x, y + 1])
                let v = Double(l)
                sum += v
                sum2 += v * v
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        let m = sum / n
        return max(0, sum2 / n - m * m)
    }

    /// True when the 3x3 neighbourhood is all background (keeps the subject's own outline out of edge checks).
    @inline(__always) private static func isDeepBackground(_ mask: LumaImage?, _ x: Int, _ y: Int) -> Bool {
        guard let mask else { return true }
        for dy in -1...1 {
            for dx in -1...1 {
                let xx = min(max(x + dx, 0), mask.width - 1)
                let yy = min(max(y + dy, 0), mask.height - 1)
                if mask[xx, yy] >= 128 { return false }
            }
        }
        return true
    }

    /// Background busyness, 0...1: share of background pixels with a strong edge.
    public func clutter(mask: LumaImage?) -> Double {
        let (gx, gy) = gradients()
        var strong = 0, n = 0
        for y in 1..<max(1, height - 1) {
            for x in 1..<max(1, width - 1) where LumaImage.isDeepBackground(mask, x, y) {
                let i = y * width + x
                n += 1
                if max(gx[i], gy[i]) > 22 { strong += 1 }
            }
        }
        guard n > 20 else { return 0 }
        return Double(strong) / Double(n)
    }

    private func edgeEnergy(_ gx: [Int], _ gy: [Int], in r: Rect, mask: LumaImage?) -> Double? {
        guard let b = pixelBounds(r) else { return nil }
        var s = 0, n = 0
        for y in max(1, b.y0)..<min(height - 1, b.y1) {
            for x in max(1, b.x0)..<min(width - 1, b.x1) where LumaImage.isDeepBackground(mask, x, y) {
                let i = y * width + x
                s += gx[i] + gy[i]
                n += 1
            }
        }
        return n >= 6 ? Double(s) / Double(n) : nil
    }

    /// Looks for background lines that collide with a head: a pole or trunk rising out of it,
    /// or a horizon or wall edge slicing through the head or neck.
    public func mergers(face: FaceInfo, mask: LumaImage?, threshold: Int = 28) -> [Merger] {
        guard width > 8, height > 8 else { return [] }
        let (gx, gy) = gradients()
        let r = face.rect
        var found: [Merger] = []

        // Which side is calmer, for the suggested move.
        let leftBand = Rect(x: r.minX - r.w * 1.6, y: r.minY - r.h * 0.6, w: r.w * 1.3, h: r.h * 1.8)
        let rightBand = Rect(x: r.maxX + r.w * 0.3, y: r.minY - r.h * 0.6, w: r.w * 1.3, h: r.h * 1.8)
        var calmer = 0
        if let l = edgeEnergy(gx, gy, in: leftBand, mask: mask), let rr = edgeEnergy(gx, gy, in: rightBand, mask: mask) {
            if l < rr * 0.8 { calmer = -1 } else if rr < l * 0.8 { calmer = 1 }
        }

        // 1. Vertical line rising out of the head.
        let above = Rect(x: r.midX - r.w * 0.6, y: max(0, face.headTop - r.h * 1.1), w: r.w * 1.2, h: r.h * 1.25)
        if let b = pixelBounds(above), b.y1 - b.y0 >= 4 {
            var best = 0.0
            var bestX = 0
            for x in max(2, b.x0)..<min(width - 2, b.x1) {
                var hits = 0, rows = 0
                for y in max(1, b.y0)..<min(height - 1, b.y1) where LumaImage.isDeepBackground(mask, x, y) {
                    rows += 1
                    let i = y * width + x
                    if max(gx[i - 1], gx[i], gx[i + 1]) > threshold { hits += 1 }
                }
                if rows >= 4 {
                    let f = Double(hits) / Double(rows)
                    if f > best { best = f; bestX = x }
                }
            }
            if best >= 0.7 {
                let cx = (Double(bestX) + 0.5) / Double(width)
                found.append(Merger(kind: .vertical,
                                    zone: Rect(x: cx - r.w * 0.15, y: above.minY, w: r.w * 0.3, h: above.h).clamped,
                                    calmerSide: calmer))
            }
        }

        // 2. Horizontal line through the head or neck, visible on both sides of it.
        let y0 = r.minY + r.h * 0.15, y1 = r.maxY + r.h * 0.5
        let leftSpan = Rect(x: r.minX - r.w * 1.0, y: y0, w: r.w * 0.9, h: y1 - y0)
        let rightSpan = Rect(x: r.maxX + r.w * 0.1, y: y0, w: r.w * 0.9, h: y1 - y0)
        if let lb = pixelBounds(leftSpan), let rb = pixelBounds(rightSpan), lb.x1 - lb.x0 >= 3, rb.x1 - rb.x0 >= 3 {
            func rowFraction(_ bb: (x0: Int, y0: Int, x1: Int, y1: Int), _ y: Int) -> Double? {
                var hits = 0, n = 0
                for x in max(1, bb.x0)..<min(width - 1, bb.x1) where LumaImage.isDeepBackground(mask, x, y) {
                    n += 1
                    let i = y * width + x
                    let up = max(0, i - width), down = min(gy.count - 1, i + width)
                    if max(gy[up], gy[i], gy[down]) > threshold { hits += 1 }
                }
                return n >= 3 ? Double(hits) / Double(n) : nil
            }
            for y in max(1, lb.y0)..<min(height - 1, lb.y1) {
                if let fl = rowFraction(lb, y), let fr = rowFraction(rb, y), fl >= 0.65, fr >= 0.65 {
                    let cy = (Double(y) + 0.5) / Double(height)
                    found.append(Merger(kind: .horizontal,
                                        zone: Rect(x: leftSpan.minX, y: cy - 0.015, w: rightSpan.maxX - leftSpan.minX, h: 0.03).clamped,
                                        calmerSide: 0))
                    break
                }
            }
        }
        return found
    }
}
