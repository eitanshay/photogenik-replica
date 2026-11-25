import AVFoundation
import UIKit

/// One selectable lens, as the user sees it (0.5x, 1x, 2x, 3x, 5x).
struct LensOption: Hashable, Identifiable {
    var display: Double
    var factor: CGFloat
    var id: Double { display }
    var label: String {
        display < 1 ? "0.5" : (display == display.rounded() ? String(Int(display)) : String(format: "%.1f", display))
    }
}

struct CameraState: Equatable {
    var side: CameraSide = .back
    var lenses: [LensOption] = []
    var zoom: Double = 1
    var hasUltraWide = false
    /// Clockwise rotation applied to analysis frames (90 = upright portrait).
    var analysisAngle: Double = 90
    var running = false
    /// What this camera can capture, and what is switched on.
    var liveSupported = false
    var rawSupported = false
    /// True when RAW means Apple ProRAW (Pro iPhones), false for plain Bayer RAW.
    var rawIsProRAW = false
    var liveOn = false
    var rawOn = false
    /// Horizontal field of view at zoom 1 (the widest lens), degrees.
    var horizontalFOV: Double = 0
}

/// The iPhone's current exposure, used as a light meter.
struct MeterReading {
    var aperture: Double
    var seconds: Double
    var iso: Double
    var targetOffset: Double
}

/// One captured photo: the processed image, plus the RAW file and Live Photo movie when asked for.
struct CapturedShot: @unchecked Sendable {
    var photo: Data
    var raw: Data?
    var liveMovie: URL?
}

/// Owns the capture session: live frames for analysis, preview, lenses, focus and exposure, and bursts.
/// Everything that touches the session runs on `sessionQueue`.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()
    let videoQueue = DispatchQueue(label: "frame.camera.video", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "frame.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var device: AVCaptureDevice?
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private var delegates: [Int64: PhotoDelegate] = [:]
    private var configured = false
    private var side: CameraSide = .back
    private var baseFactor: CGFloat = 1
    private var wantLive = false
    private var wantRaw = false

    /// Called on `videoQueue` for every live frame, with the side it came from.
    var onFrame: ((CMSampleBuffer, CameraSide) -> Void)?
    /// Called on the main queue whenever lenses, zoom or orientation change.
    var onState: ((CameraState) -> Void)?
    private var state = CameraState()

    override init() {
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: Permission and start

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(side: CameraSide = .back) {
        sessionQueue.async { [self] in
            if !configured {
                configure(side: side)
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            state.running = session.isRunning
            publish()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            state.running = false
            publish()
        }
    }

    func flip() {
        sessionQueue.async { [self] in
            configure(side: side == .back ? .front : .back)
        }
    }

    private func publish() {
        let s = state
        DispatchQueue.main.async { [weak self] in self?.onState?(s) }
    }

    // MARK: Configuration

    private static func bestDevice(_ side: CameraSide) -> AVCaptureDevice? {
        if side == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        for t in [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera] {
            if let d = AVCaptureDevice.default(t, for: .video, position: .back) { return d }
        }
        return nil
    }

    private func configure(side newSide: CameraSide) {
        guard let dev = CameraController.bestDevice(newSide), let newInput = try? AVCaptureDeviceInput(device: dev) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
            device = dev
            side = newSide
        } else if let input {
            session.addInput(input)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        applyCaptureFeaturesLocked()
        session.commitConfiguration()

        setupLenses(dev)
        setupRotation(dev)
        if let dev = device, (try? dev.lockForConfiguration()) != nil {
            if dev.isFocusModeSupported(.continuousAutoFocus) { dev.focusMode = .continuousAutoFocus }
            if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            dev.isSubjectAreaChangeMonitoringEnabled = true
            dev.unlockForConfiguration()
        }
        state.side = side
        state.horizontalFOV = Double(dev.activeFormat.videoFieldOfView)
        publish()
    }

    private func setupLenses(_ dev: AVCaptureDevice) {
        var options: [LensOption] = []
        if side == .front {
            baseFactor = 1
            options = [LensOption(display: 1, factor: 1)]
            state.hasUltraWide = false
        } else {
            let switches = dev.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
            let hasUltra = dev.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            baseFactor = hasUltra ? (switches.first ?? 2) : 1
            state.hasUltraWide = hasUltra
            if hasUltra { options.append(LensOption(display: 0.5, factor: 1)) }
            options.append(LensOption(display: 1, factor: baseFactor))
            var tele: Double?
            if dev.constituentDevices.contains(where: { $0.deviceType == .builtInTelephotoCamera }), let last = switches.last {
                tele = Double(last / baseFactor)
            }
            if let tele, tele > 2.4 {
                options.append(LensOption(display: 2, factor: baseFactor * 2))
                options.append(LensOption(display: (tele * 2).rounded() / 2, factor: CGFloat(Double(baseFactor) * tele)))
            } else if let tele {
                options.append(LensOption(display: (tele * 2).rounded() / 2, factor: CGFloat(Double(baseFactor) * tele)))
            } else {
                options.append(LensOption(display: 2, factor: baseFactor * 2))
            }
            options = options.filter { $0.factor <= dev.maxAvailableVideoZoomFactor }
        }
        state.lenses = options
        setZoomLocked(display: 1)
    }

    private func setupRotation(_ dev: AVCaptureDevice) {
        observations.removeAll()
        // The coordinator reads the preview layer, which belongs to the main thread.
        let layer = previewLayer
        let rc = DispatchQueue.main.sync { AVCaptureDevice.RotationCoordinator(device: dev, previewLayer: layer) }
        coordinator = rc
        applyRotation()
        observations.append(rc.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.sessionQueue.async { [weak self] in self?.applyRotation() }
        })
        observations.append(rc.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in self?.applyPreviewRotation() }
        })
        DispatchQueue.main.async { [weak self] in self?.applyPreviewRotation() }
    }

    private func applyPreviewRotation() {
        guard let rc = coordinator, let conn = previewLayer.connection else { return }
        let a = rc.videoRotationAngleForHorizonLevelPreview
        if conn.isVideoRotationAngleSupported(a) { conn.videoRotationAngle = a }
    }

    /// Analysis frames arrive upright for the holder. The selfie camera stays portrait and mirrored, as on screen.
    private func applyRotation() {
        guard let rc = coordinator, let conn = videoOutput.connection(with: .video) else { return }
        let angle: CGFloat = side == .front ? 90 : rc.videoRotationAngleForHorizonLevelCapture
        if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = side == .front
        }
        state.analysisAngle = Double(conn.videoRotationAngle)
        publish()
    }

    // MARK: Live Photo and RAW

    /// Turns Live Photo and RAW capture on or off. They are exclusive, as in the Camera app.
    func setCaptureFeatures(live: Bool, raw: Bool) {
        sessionQueue.async { [self] in
            wantLive = live && !raw
            wantRaw = raw
            guard configured else { return }
            session.beginConfiguration()
            applyCaptureFeaturesLocked()
            session.commitConfiguration()
            publish()
        }
    }

    /// Call inside a session configuration block.
    private func applyCaptureFeaturesLocked() {
        let liveOK = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isLivePhotoCaptureEnabled = liveOK && wantLive
        let proRAW = photoOutput.isAppleProRAWSupported
        if proRAW { photoOutput.isAppleProRAWEnabled = wantRaw }
        state.liveSupported = liveOK
        state.rawIsProRAW = proRAW
        state.rawSupported = proRAW || rawFormat(proRAW: false) != nil
        state.liveOn = photoOutput.isLivePhotoCaptureEnabled
        state.rawOn = wantRaw && state.rawSupported
    }

    private func rawFormat(proRAW: Bool) -> OSType? {
        photoOutput.availableRawPhotoPixelFormatTypes.first { format in
            proRAW ? AVCapturePhotoOutput.isAppleProRAWPixelFormat(format) : AVCapturePhotoOutput.isBayerRAWPixelFormat(format)
        }
    }

    // MARK: Lenses, focus, exposure

    /// Zooms to a 35mm-equivalent focal length (for matching another camera's framing).
    func setZoom(equivalent focal: Double) {
        sessionQueue.async { [self] in
            guard let dev = device else { return }
            let fov = Double(dev.activeFormat.videoFieldOfView)
            let factor = CGFloat(FujiPlanner.zoomFactor(forEquivalent: focal, deviceHorizontalFOV: fov))
            do {
                try dev.lockForConfiguration()
                dev.videoZoomFactor = min(max(factor, dev.minAvailableVideoZoomFactor), dev.maxAvailableVideoZoomFactor)
                dev.unlockForConfiguration()
                state.zoom = Double(dev.videoZoomFactor / baseFactor)
                publish()
            } catch {}
        }
    }

    /// Current exposure, read straight from the device (these properties are safe to read off the session queue).
    func meter() -> MeterReading? {
        guard let dev = device else { return nil }
        let seconds = CMTimeGetSeconds(dev.exposureDuration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return MeterReading(aperture: Double(dev.lensAperture), seconds: seconds, iso: Double(dev.iso),
                            targetOffset: Double(dev.exposureTargetOffset))
    }

    func setZoom(display: Double) {
        sessionQueue.async { [self] in setZoomLocked(display: display) }
    }

    private func setZoomLocked(display: Double) {
        guard let dev = device else { return }
        let option = state.lenses.min { abs($0.display - display) < abs($1.display - display) }
        let factor = option?.factor ?? baseFactor
        do {
            try dev.lockForConfiguration()
            dev.videoZoomFactor = min(max(factor, dev.minAvailableVideoZoomFactor), dev.maxAvailableVideoZoomFactor)
            dev.unlockForConfiguration()
            state.zoom = option?.display ?? 1
            publish()
        } catch {}
    }

    /// Focus and expose at a point in capture-device coordinates (0...1, landscape sensor space).
    func focusAndExpose(at devicePoint: CGPoint, lockExposure: Bool = false) {
        sessionQueue.async { [self] in
            guard let dev = device, (try? dev.lockForConfiguration()) != nil else { return }
            if dev.isFocusPointOfInterestSupported {
                dev.focusPointOfInterest = devicePoint
                if dev.isFocusModeSupported(.autoFocus) { dev.focusMode = .autoFocus }
            }
            if dev.isExposurePointOfInterestSupported {
                dev.exposurePointOfInterest = devicePoint
                if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            }
            dev.setExposureTargetBias(0, completionHandler: nil)
            dev.unlockForConfiguration()
        }
    }

    /// Back to continuous focus and exposure over the whole frame.
    func resetFocus() {
        sessionQueue.async { [self] in
            guard let dev = device, (try? dev.lockForConfiguration()) != nil else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            if dev.isFocusPointOfInterestSupported { dev.focusPointOfInterest = center }
            if dev.isFocusModeSupported(.continuousAutoFocus) { dev.focusMode = .continuousAutoFocus }
            if dev.isExposurePointOfInterestSupported { dev.exposurePointOfInterest = center }
            if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
            dev.unlockForConfiguration()
        }
    }

    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [self] in
            guard let dev = device, (try? dev.lockForConfiguration()) != nil else { return }
            let v = min(max(ev, dev.minExposureTargetBias), dev.maxExposureTargetBias)
            dev.setExposureTargetBias(v, completionHandler: nil)
            dev.unlockForConfiguration()
        }
    }

    // MARK: Live frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer, side)
    }

    // MARK: Burst capture

    /// Takes `count` photos spaced by `interval` seconds. Completion runs on the main queue with the
    /// encoded photos in shot order (failed frames are dropped).
    func captureBurst(count: Int, interval: TimeInterval, mirrorSelfie: Bool, completion: @escaping ([CapturedShot]) -> Void) {
        sessionQueue.async { [self] in
            guard session.isRunning else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let collector = BurstCollector(count: count, completion: completion)
            let finishOne: (Int, CapturedShot?) -> Void = { index, shot in collector.add(index, shot) }
            for i in 0..<count {
                sessionQueue.asyncAfter(deadline: .now() + interval * Double(i)) { [self] in
                    shoot(index: i, burst: count > 1, mirrorSelfie: mirrorSelfie, done: finishOne)
                }
            }
        }
    }

    private func shoot(index: Int, burst: Bool, mirrorSelfie: Bool, done: @escaping (Int, CapturedShot?) -> Void) {
        let processed: [String: Any] = photoOutput.availablePhotoCodecTypes.contains(.hevc)
            ? [AVVideoCodecKey: AVVideoCodecType.hevc] : [AVVideoCodecKey: AVVideoCodecType.jpeg]
        let settings: AVCapturePhotoSettings
        if state.rawOn, let raw = rawFormat(proRAW: state.rawIsProRAW) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: raw, processedFormat: processed)
        } else {
            settings = AVCapturePhotoSettings(format: processed)
        }
        settings.photoQualityPrioritization = burst ? .speed : (state.rawOn ? .quality : .balanced)
        if photoOutput.isLivePhotoCaptureEnabled && !burst {
            settings.livePhotoMovieFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("live-\(UUID().uuidString).mov")
        }
        if let conn = photoOutput.connection(with: .video) {
            if let rc = coordinator {
                let a = rc.videoRotationAngleForHorizonLevelCapture
                if conn.isVideoRotationAngleSupported(a) { conn.videoRotationAngle = a }
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = side == .front && mirrorSelfie
            }
        }
        let id = settings.uniqueID
        let queue = sessionQueue
        let delegate = PhotoDelegate { [weak self] shot in
            queue.async { [weak self] in self?.delegates[id] = nil }
            done(index, shot)
        }
        delegates[id] = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

/// Gathers burst frames from the photo callbacks, which can arrive on any thread.
private final class BurstCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [CapturedShot?]
    private var remaining: Int
    private let completion: ([CapturedShot]) -> Void

    init(count: Int, completion: @escaping ([CapturedShot]) -> Void) {
        results = [CapturedShot?](repeating: nil, count: count)
        remaining = count
        self.completion = completion
    }

    func add(_ index: Int, _ shot: CapturedShot?) {
        lock.lock()
        if index < results.count { results[index] = shot }
        remaining -= 1
        let done = remaining == 0
        let out = results.compactMap { $0 }
        lock.unlock()
        if done {
            let completion = self.completion
            DispatchQueue.main.async { completion(out) }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (CapturedShot?) -> Void
    private var processed: Data?
    private var raw: Data?
    private var movie: URL?
    private var finished = false
    init(done: @escaping (CapturedShot?) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { raw = data } else { processed = data }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error == nil { movie = outputFileURL }
    }

    /// Called last, after the photo, the RAW file and the Live Photo movie are all done.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard !finished else { return }
        finished = true
        // Without a processed image there is nothing to rank or show; a lone RAW stands in for it.
        guard let photo = processed ?? raw else {
            done(nil)
            return
        }
        done(CapturedShot(photo: photo, raw: processed == nil ? nil : raw, liveMovie: movie))
    }
}
