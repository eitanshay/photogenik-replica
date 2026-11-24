import Foundation

/// One frame of a burst, measured after capture.
public struct ShotCandidate: Equatable, Sendable {
    public var faces: [FaceInfo]
    /// Laplacian variance of the main face (or the centre of the frame when there are no faces).
    public var sharpness: Double
    /// Coach readiness at the moment of capture, if known.
    public var readiness: Int?

    public init(faces: [FaceInfo], sharpness: Double, readiness: Int? = nil) {
        self.faces = faces
        self.sharpness = sharpness
        self.readiness = readiness
    }
}

public struct ShotScore: Equatable, Sendable {
    public var index: Int
    public var score: Double
    public var eyesClosed: Int
    public var reason: String
}

public enum ShotRanker {
    public static func score(_ c: ShotCandidate) -> Double {
        var s = 0.0
        let closed = c.faces.filter { $0.eyesClosed == true }.count
        s -= Double(min(closed, 3)) * 40
        let qualities = c.faces.compactMap(\.quality)
        if !qualities.isEmpty {
            s += qualities.reduce(0, +) / Double(qualities.count) * 30
        }
        // Log scale: doubling sharpness matters equally at any level.
        s += min(1, log10(1 + max(0, c.sharpness)) / 3.2) * 35
        if let r = c.readiness { s += Double(r) * 0.15 }
        return s
    }

    /// Scores every frame and returns them best first, with a short reason for the winner.
    public static func rank(_ candidates: [ShotCandidate]) -> [ShotScore] {
        guard !candidates.isEmpty else { return [] }
        let scored = candidates.enumerated().map { (i, c) in
            ShotScore(index: i, score: score(c), eyesClosed: c.faces.filter { $0.eyesClosed == true }.count, reason: "")
        }.sorted { $0.score > $1.score }
        var out = scored
        let best = candidates[out[0].index]
        var bits: [String] = []
        let anyClosedElsewhere = scored.dropFirst().contains { $0.eyesClosed > 0 }
        if !best.faces.isEmpty && out[0].eyesClosed == 0 {
            bits.append(anyClosedElsewhere ? "eyes open (others blinked)" : "eyes open")
        }
        let maxSharp = candidates.map(\.sharpness).max() ?? 0
        if best.sharpness >= maxSharp * 0.98 && candidates.count > 1 { bits.append("sharpest") }
        out[0].reason = bits.isEmpty ? "best overall" : bits.joined(separator: ", ")
        return out
    }
}
