import ImageIO
import UIKit
import Vision

/// One frame of a finished burst.
struct BurstFrame: Identifiable, @unchecked Sendable {
    let id = UUID()
    let index: Int
    let shot: CapturedShot
    let thumbnail: UIImage
    var data: Data { shot.photo }
    var score: Double = 0
    var eyesClosed = 0
}

struct BurstResult: Identifiable, @unchecked Sendable {
    let id = UUID()
    var frames: [BurstFrame]
    var bestIndex: Int
    var reason: String
    var savedIndices: Set<Int> = []

    var best: BurstFrame? { frames.first { $0.index == bestIndex } }
}

/// Measures captured photos (eyes, face quality, sharpness) to pick the best of a burst.
enum StillAnalyzer {
    static func cgImage(_ data: Data, maxSide: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Grayscale copy of a region of an image, `side` pixels square, for the sharpness measure.
    static func grayCrop(_ image: CGImage, rect: Rect, side: Int = 160) -> LumaImage? {
        let w = Double(image.width), h = Double(image.height)
        let crop = CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.w * w, height: rect.h * h).integral
        guard let piece = image.cropping(to: crop) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? LumaImage(width: side, height: side, pixels: pixels) : nil
    }

    static func candidate(_ image: CGImage) -> ShotCandidate {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        let faceReq = VNDetectFaceRectanglesRequest()
        faceReq.revision = VNDetectFaceRectanglesRequestRevision3
        try? handler.perform([faceReq])
        let raw = Array((faceReq.results ?? []).sorted { $0.boundingBox.width > $1.boundingBox.width }.prefix(6))
        var faces: [FaceInfo] = []
        if !raw.isEmpty {
            let lm = VNDetectFaceLandmarksRequest()
            lm.inputFaceObservations = raw
            let q = VNDetectFaceCaptureQualityRequest()
            q.inputFaceObservations = raw
            try? handler.perform([lm, q])
            let size = CGSize(width: image.width, height: image.height)
            let biggest = raw.first?.boundingBox.width ?? 0
            for f in raw where f.boundingBox.width >= biggest * 0.45 {
                let bb = f.boundingBox
                var info = FaceInfo(rect: Rect.fromBottomLeft(x: bb.minX, y: bb.minY, w: bb.width, h: bb.height))
                if let l = FrameAnalyzer.closest(to: bb, in: lm.results ?? [])?.landmarks {
                    FrameAnalyzer.applyLandmarks(l, imageSize: size, to: &info)
                }
                if let qq = FrameAnalyzer.closest(to: bb, in: q.results ?? [])?.faceCaptureQuality {
                    info.quality = (qq as NSNumber).doubleValue
                }
                faces.append(info)
            }
        }
        let region = faces.first.map { $0.rect.insetBy(dx: $0.rect.w * 0.1, dy: $0.rect.h * 0.1) }
            ?? Rect(x: 0.3, y: 0.3, w: 0.4, h: 0.4)
        let sharp = grayCrop(image, rect: region.clamped).map { $0.laplacianVariance() } ?? 0
        return ShotCandidate(faces: faces, sharpness: sharp)
    }

    /// Ranks a burst. Call off the main thread: each frame runs Vision.
    static func analyze(_ shots: [CapturedShot]) -> BurstResult? {
        guard !shots.isEmpty else { return nil }
        var frames: [BurstFrame] = []
        var candidates: [ShotCandidate] = []
        for (i, shot) in shots.enumerated() {
            guard let img = cgImage(shot.photo, maxSide: 1280) else { continue }
            let thumbImg = cgImage(shot.photo, maxSide: 600) ?? img
            frames.append(BurstFrame(index: i, shot: shot, thumbnail: UIImage(cgImage: thumbImg)))
            candidates.append(candidate(img))
        }
        guard !frames.isEmpty else { return nil }
        let ranked = ShotRanker.rank(candidates)
        for r in ranked {
            frames[r.index].score = r.score
            frames[r.index].eyesClosed = r.eyesClosed
        }
        let best = ranked.first.map { frames[$0.index].index } ?? 0
        return BurstResult(frames: frames, bestIndex: best, reason: ranked.first?.reason ?? "")
    }
}
