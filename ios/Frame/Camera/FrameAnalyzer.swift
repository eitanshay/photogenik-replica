import AVFoundation
import CoreImage
import UIKit
import Vision

/// What the coach needs from outside the frame. Written on the main thread, read on the video queue.
struct AnalyzerInputs {
    var attitude = Attitude(roll: 0, elevation: 0, hold: .portrait)
    var zoom: Double = 1
    var hasUltraWide = true
    var sun: SunContext?
    var wantsHands = false
    var settings = CoachSettings()
}

/// Everything the screen draws for one analysed frame.
struct LiveState: Equatable {
    var shown: CueSmoother.Shown
    var faces: [FaceInfo]
    var marks: [Vec2]
    var zones: [Rect]
    var openPalm: Bool
    var people: Int
    var scene: SceneStats
    /// Width over height of the analysed frame (in its own upright orientation).
    var aspect: Double
}

/// Runs Vision on live frames about ten times a second and turns the results into coaching.
/// All work happens on the camera's video queue; results are delivered on the main queue.
final class FrameAnalyzer: @unchecked Sendable {
    var onState: ((LiveState) -> Void)?

    private let lock = NSLock()
    private var inputs = AnalyzerInputs()
    private var latestBuffer: CVPixelBuffer?
    private let smoother = CueSmoother()
    private var lastRun: CFTimeInterval = 0
    private var frameIndex = 0
    private var lastSide: CameraSide?
    private let interval: CFTimeInterval = 0.1
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// The camera's per-frame callback. Built here so it carries no main-actor isolation.
    func frameHandler() -> (CMSampleBuffer, CameraSide) -> Void {
        { [weak self] buffer, side in self?.process(buffer, side: side) }
    }

    func update(_ change: (inout AnalyzerInputs) -> Void) {
        lock.lock()
        change(&inputs)
        lock.unlock()
    }

    private func readInputs() -> AnalyzerInputs {
        lock.lock()
        defer { lock.unlock() }
        return inputs
    }

    func resetSmoothing() {
        lock.lock()
        smoother.reset()
        lock.unlock()
    }

    // MARK: Snapshot for the director

    /// The latest analysed frame as a JPEG, longest side `maxSide`, oriented as the holder sees it.
    func snapshotJPEG(maxSide: CGFloat = 1024) -> Data? {
        lock.lock()
        let pb = latestBuffer
        lock.unlock()
        guard let pb else { return nil }
        var image = CIImage(cvPixelBuffer: pb)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxSide {
            let s = maxSide / longest
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.75)
    }

    // MARK: Per frame

    func process(_ sampleBuffer: CMSampleBuffer, side: CameraSide) {
        let now = CACurrentMediaTime()
        guard now - lastRun >= interval, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now
        frameIndex += 1
        if side != lastSide {
            resetSmoothing()
            lastSide = side
        }
        let input = readInputs()
        lock.lock()
        latestBuffer = pb
        lock.unlock()

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        guard width > 0, height > 0 else { return }
        let imageSize = CGSize(width: width, height: height)
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])

        // Pass 1: detectors that work on the whole frame.
        let faceReq = VNDetectFaceRectanglesRequest()
        faceReq.revision = VNDetectFaceRectanglesRequestRevision3
        let segReq = VNGeneratePersonSegmentationRequest()
        segReq.qualityLevel = .fast
        segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
        var requests: [VNRequest] = [faceReq, segReq]
        let bodyReq = VNDetectHumanBodyPoseRequest()
        if side == .back { requests.append(bodyReq) }
        let horizonReq = VNDetectHorizonRequest()
        if side == .back { requests.append(horizonReq) }
        let handReq = VNDetectHumanHandPoseRequest()
        handReq.maximumHandCount = 2
        if input.wantsHands { requests.append(handReq) }
        let salReq = VNGenerateAttentionBasedSaliencyImageRequest()
        let wantSaliency = side == .back && frameIndex % 4 == 0
        if wantSaliency { requests.append(salReq) }
        try? handler.perform(requests)

        // Pass 2: landmarks and quality for the biggest faces.
        let rawFaces = (faceReq.results ?? []).sorted { $0.boundingBox.width > $1.boundingBox.width }.prefix(6)
        var landmarkFaces: [VNFaceObservation] = []
        var qualityFaces: [VNFaceObservation] = []
        if !rawFaces.isEmpty {
            let lmReq = VNDetectFaceLandmarksRequest()
            lmReq.inputFaceObservations = Array(rawFaces)
            let qReq = VNDetectFaceCaptureQualityRequest()
            qReq.inputFaceObservations = Array(rawFaces)
            try? handler.perform([lmReq, qReq])
            landmarkFaces = lmReq.results ?? []
            qualityFaces = qReq.results ?? []
        }

        // Low-resolution luminance and person mask, in the same upright space as Vision's results.
        let luma = FrameAnalyzer.lumaGrid(pb)
        var mask: LumaImage?
        if let seg = segReq.results?.first?.pixelBuffer, let luma {
            mask = FrameAnalyzer.maskImage(seg)?.resized(width: luma.width, height: luma.height)
        }

        var faces: [FaceInfo] = []
        for f in rawFaces {
            let bb = f.boundingBox
            var info = FaceInfo(rect: Rect.fromBottomLeft(x: bb.minX, y: bb.minY, w: bb.width, h: bb.height))
            if let y = f.yaw { info.yaw = MathX.deg((y as NSNumber).doubleValue) }
            if let r = f.roll { info.roll = MathX.deg((r as NSNumber).doubleValue) }
            if let lm = FrameAnalyzer.closest(to: bb, in: landmarkFaces)?.landmarks {
                FrameAnalyzer.applyLandmarks(lm, imageSize: imageSize, to: &info)
            }
            if let q = FrameAnalyzer.closest(to: bb, in: qualityFaces)?.faceCaptureQuality { info.quality = (q as NSNumber).doubleValue }
            if let luma {
                let inner = info.rect.insetBy(dx: info.rect.w * 0.15, dy: info.rect.h * 0.15)
                info.lumaLeft = luma.mean(in: Rect(x: inner.minX, y: inner.minY, w: inner.w / 2, h: inner.h))
                info.lumaRight = luma.mean(in: Rect(x: inner.midX, y: inner.minY, w: inner.w / 2, h: inner.h))
            }
            faces.append(info)
        }

        var bodies: [BodyInfo] = []
        if side == .back, let obs = bodyReq.results {
            for o in obs.prefix(4) {
                if let b = FrameAnalyzer.body(o) { bodies.append(b) }
            }
        }

        var scene = SceneStats()
        if let luma {
            scene.meanLuma = luma.mean
            let clip = luma.clipFractions()
            scene.highlightClip = clip.high
            scene.shadowClip = clip.low
            scene.sharpness = luma.laplacianVariance()
            if let mask {
                scene.backgroundLuma = luma.backgroundMean(mask: mask)
                scene.clutter = luma.clutter(mask: mask)
                if let main = faces.max(by: { $0.rect.area < $1.rect.area }), main.rect.w > 0.06 {
                    scene.mergers = luma.mergers(face: main, mask: mask)
                }
            } else {
                scene.clutter = luma.clutter(mask: nil)
            }
        }
        if let h = horizonReq.results?.first, h.confidence >= 0.7, side == .back {
            scene.horizonAngle = MathX.deg(Double(h.angle))
        }
        if wantSaliency, let s = salReq.results?.first?.salientObjects?.first {
            let bb = s.boundingBox
            scene.salient = Rect.fromBottomLeft(x: bb.minX, y: bb.minY, w: bb.width, h: bb.height)
        }

        var palm = false
        if input.wantsHands, let hands = handReq.results {
            palm = hands.contains { FrameAnalyzer.hand($0, imageSize: imageSize).map(HandGesture.isOpenPalm) ?? false }
        }

        let analysis = FrameAnalysis(side: side, attitude: input.attitude, zoom: side == .front ? 1 : input.zoom,
                                     hasUltraWide: input.hasUltraWide, faces: faces, bodies: bodies, scene: scene,
                                     sun: input.sun, aspect: Double(width) / Double(height))
        let out = Coach.evaluate(analysis, settings: input.settings)
        lock.lock()
        let shown = smoother.update(out, at: now)
        lock.unlock()
        var marks: [Vec2] = []
        var zones: [Rect] = []
        for c in [shown.primary].compactMap({ $0 }) + shown.secondary {
            marks += c.marks
            zones += c.zones
        }
        let state = LiveState(shown: shown, faces: analysis.subjectFaces, marks: marks, zones: zones, openPalm: palm,
                              people: analysis.subjectFaces.count, scene: scene, aspect: analysis.aspect)
        DispatchQueue.main.async { [weak self] in self?.onState?(state) }
    }

    // MARK: Helpers

    static func closest(to bb: CGRect, in faces: [VNFaceObservation]) -> VNFaceObservation? {
        faces.min { a, b in
            hypot(a.boundingBox.midX - bb.midX, a.boundingBox.midY - bb.midY) < hypot(b.boundingBox.midX - bb.midX, b.boundingBox.midY - bb.midY)
        }
    }

    /// Landmark points in pixels with a top-left origin.
    static func points(_ region: VNFaceLandmarkRegion2D?, _ size: CGSize) -> [Vec2] {
        guard let region else { return [] }
        return region.pointsInImage(imageSize: size).map { Vec2(Double($0.x), Double(size.height - $0.y)) }
    }

    static func applyLandmarks(_ lm: VNFaceLandmarks2D, imageSize: CGSize, to info: inout FaceInfo) {
        let le = points(lm.leftEye, imageSize)
        let re = points(lm.rightEye, imageSize)
        info.leftEyeOpen = Landmarks.eyeOpenness(le)
        info.rightEyeOpen = Landmarks.eyeOpenness(re)
        let nose = points(lm.nose, imageSize)
        let lips = points(lm.outerLips, imageSize)
        if let tip = Landmarks.lowest(nose) {
            info.noseRatio = Landmarks.noseRatio(leftEye: le, rightEye: re, noseTip: tip, mouth: lips)
        }
    }

    static func body(_ o: VNHumanBodyPoseObservation) -> BodyInfo? {
        guard let pts = try? o.recognizedPoints(.all) else { return nil }
        let map: [VNHumanBodyPoseObservation.JointName: Joint] = [
            .nose: .nose, .leftEye: .leftEye, .rightEye: .rightEye, .leftEar: .leftEar, .rightEar: .rightEar, .neck: .neck,
            .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder, .leftElbow: .leftElbow, .rightElbow: .rightElbow,
            .leftWrist: .leftWrist, .rightWrist: .rightWrist, .root: .root, .leftHip: .leftHip, .rightHip: .rightHip,
            .leftKnee: .leftKnee, .rightKnee: .rightKnee, .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle
        ]
        var joints: [Joint: Vec2] = [:]
        for (name, p) in pts where p.confidence > 0.3 {
            if let j = map[name] { joints[j] = Vec2(Double(p.location.x), 1 - Double(p.location.y)) }
        }
        return joints.count >= 4 ? BodyInfo(joints: joints) : nil
    }

    static func hand(_ o: VNHumanHandPoseObservation, imageSize: CGSize) -> HandPoints? {
        guard let pts = try? o.recognizedPoints(.all) else { return nil }
        func v(_ n: VNHumanHandPoseObservation.JointName) -> Vec2? {
            guard let p = pts[n], p.confidence > 0.3 else { return nil }
            return Vec2(Double(p.location.x * imageSize.width), Double((1 - p.location.y) * imageSize.height))
        }
        guard let wrist = v(.wrist) else { return nil }
        return HandPoints(wrist: wrist,
                          tips: [v(.thumbTip), v(.indexTip), v(.middleTip), v(.ringTip), v(.littleTip)],
                          bases: [v(.thumbMP), v(.indexMCP), v(.middleMCP), v(.ringMCP), v(.littleMCP)])
    }

    /// Averages the Y plane into a small grid (54 x 72 in portrait).
    static func lumaGrid(_ pb: CVPixelBuffer) -> LumaImage? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pb)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pb, 0) : CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = planar ? CVPixelBufferGetWidthOfPlane(pb, 0) : CVPixelBufferGetWidth(pb)
        let h = planar ? CVPixelBufferGetHeightOfPlane(pb, 0) : CVPixelBufferGetHeight(pb)
        let bpr = planar ? CVPixelBufferGetBytesPerRowOfPlane(pb, 0) : CVPixelBufferGetBytesPerRow(pb)
        guard w > 0, h > 0 else { return nil }
        let gw = w < h ? 54 : 72
        let gh = w < h ? 72 : 54
        let src = base.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                // Four samples per cell, at the quarter points.
                var sum = 0
                for sy in 0..<2 {
                    for sx in 0..<2 {
                        let x = min(w - 1, (gx * 4 + 1 + sx * 2) * w / (gw * 4))
                        let y = min(h - 1, (gy * 4 + 1 + sy * 2) * h / (gh * 4))
                        sum += Int(src[y * bpr + x])
                    }
                }
                out[gy * gw + gx] = UInt8(sum / 4)
            }
        }
        return LumaImage(width: gw, height: gh, pixels: out)
    }

    static func maskImage(_ pb: CVPixelBuffer) -> LumaImage? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        guard w > 0, h > 0 else { return nil }
        let src = base.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { out[y * w + x] = src[y * bpr + x] }
        }
        return LumaImage(width: w, height: h, pixels: out)
    }
}
