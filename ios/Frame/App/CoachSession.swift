import AVFoundation
import CoreLocation
import Observation
import SwiftUI

struct Toast: Equatable {
    var message: String
    var tone: BadgeTone
    var id = UUID()
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

enum DirectorPhase: Equatable {
    case idle
    case thinking
    case ready(DirectorAdvice)
    case failed(String)
}

struct GoldenWindow: Equatable {
    var start: Date
    var end: Date
}

/// The live coaching session: camera, sensors, analysis, capture, voice and the AI director.
@Observable
@MainActor
final class CoachSession {
    let settings: SettingsStore
    @ObservationIgnored let camera = CameraController()
    @ObservationIgnored let analyzer = FrameAnalyzer()
    @ObservationIgnored private let sensors = Sensors()
    @ObservationIgnored private let voice = Voice()
    @ObservationIgnored private var speechGate = SpeechGate()
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var palmSince: CFTimeInterval?
    @ObservationIgnored private var lastCaptureEnd: CFTimeInterval = 0
    @ObservationIgnored private var lastSunUpdate: CFTimeInterval = 0
    @ObservationIgnored private var geocodedAt: CLLocation?
    @ObservationIgnored private var lastMotion: Sensors.MotionSample?

    var cam = CameraState()
    var live: LiveState?
    var permissionDenied = false
    var started = false
    var countdown: Int?
    var isCapturing = false
    var shutterFlash = 0
    var lastBurst: BurstResult?
    var showReview = false
    var showSettings = false
    var showPoses = false
    var toast: Toast?
    var attitude = Attitude(roll: 0, elevation: 0, hold: .portrait)
    var lensHeading: Double?
    var sun: SunPosition?
    var golden: GoldenWindow?
    var place: String?
    var director: DirectorPhase = .idle
    var steadyReady = false

    init(settings: SettingsStore) {
        self.settings = settings
        camera.onFrame = analyzer.frameHandler()
        analyzer.onState = { [weak self] s in self?.handleLive(s) }
        camera.onState = { [weak self] s in self?.handleCamera(s) }
        sensors.onMotion = { [weak self] m in self?.handleMotion(m) }
        sensors.onLocation = { [weak self] l in self?.handleLocation(l) }
        syncInputs()
    }

    // MARK: Lifecycle

    func start() {
        Task {
            let ok = await CameraController.requestAccess()
            permissionDenied = !ok
            guard ok else { return }
            let side: CameraSide = settings.mode == .selfie ? .front : .back
            camera.start(side: side)
            sensors.start()
            started = true
        }
    }

    func pause() {
        camera.stop()
        sensors.stop()
        voice.stop()
        countdownTask?.cancel()
        countdown = nil
    }

    // MARK: Inputs

    var overlayRotation: Double {
        cam.side == .front ? 0 : (90 - cam.analysisAngle).truncatingRemainder(dividingBy: 360)
    }

    private func syncInputs() {
        let coach = settings.coach
        let hands = settings.handsFree
        let att = attitude
        let zoom = cam.zoom
        let ultra = cam.hasUltraWide
        let sunCtx = sunContext
        analyzer.update { i in
            i.settings = coach
            i.wantsHands = hands
            i.attitude = att
            i.zoom = zoom
            i.hasUltraWide = ultra
            i.sun = sunCtx
        }
    }

    var sunContext: SunContext? {
        guard let sun else { return nil }
        let rel = lensHeading.map { Sun.relativeAzimuth(sunAzimuth: sun.azimuth, lensHeading: $0) }
        return SunContext(elevation: sun.elevation, relativeAzimuth: rel, phase: sun.phase)
    }

    private func handleCamera(_ s: CameraState) {
        let sideChanged = s.side != cam.side
        cam = s
        if sideChanged {
            analyzer.resetSmoothing()
            live = nil
            director = .idle
        }
        syncInputs()
    }

    private func handleMotion(_ m: Sensors.MotionSample) {
        lastMotion = m
        attitude = Attitude.from(gx: m.gravity.x, gy: m.gravity.y, gz: m.gravity.z, side: cam.side)
        if m.northReferenced, let h = LensHeading.heading(m: m.matrix, gravity: m.gravity, side: cam.side) {
            var t = h + sensors.declination
            if t < 0 { t += 360 }
            if t >= 360 { t -= 360 }
            lensHeading = t
        } else {
            lensHeading = nil
        }
        let now = CACurrentMediaTime()
        if now - lastSunUpdate > 30, let loc = sensors.location {
            updateSun(loc)
        }
        syncInputs()
    }

    private func handleLocation(_ loc: CLLocation) {
        updateSun(loc)
        if geocodedAt == nil || geocodedAt!.distance(from: loc) > 5000 {
            geocodedAt = loc
            Task { [weak self] in
                let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
                guard let p = marks?.first else { return }
                let parts = [p.name, p.locality, p.country].compactMap { $0 }
                var seen = Set<String>()
                self?.place = parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
            }
        }
    }

    private func updateSun(_ loc: CLLocation) {
        lastSunUpdate = CACurrentMediaTime()
        let now = Date()
        sun = Sun.position(at: now, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        if let w = Sun.goldenWindow(from: now, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude) {
            golden = GoldenWindow(start: w.start, end: w.end)
        } else {
            golden = nil
        }
    }

    /// Short text for the light badge: "golden hour · 18m left", "golden in 1h 12m", "harsh sun".
    var lightLabel: String? {
        guard let sun else { return nil }
        let now = Date()
        if let g = golden {
            if g.start <= now && now < g.end {
                return "golden · \(CoachSession.duration(g.end.timeIntervalSince(now))) left"
            }
            let until = g.start.timeIntervalSince(now)
            if until > 0 && until < 6 * 3600 && sun.phase != .night {
                return "golden in \(CoachSession.duration(until))"
            }
        }
        return sun.phase.label
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    // MARK: Live coaching

    private func handleLive(_ s: LiveState) {
        live = s
        let now = CACurrentMediaTime()
        let ready = s.shown.steadyReady
        if ready && !steadyReady {
            Haptics.ready()
            if voiceOn && !settings.autoCapture && countdown == nil && !isCapturing {
                voice.say("Looks good. Take it.")
            }
        }
        steadyReady = ready

        if settings.autoCapture && ready && !isCapturing && countdown == nil && now - lastCaptureEnd > 4 {
            capture()
            return
        }

        if settings.handsFree && s.openPalm {
            if palmSince == nil { palmSince = now }
            if let since = palmSince, now - since > 0.4, countdown == nil, !isCapturing, now - lastCaptureEnd > 2 {
                palmSince = nil
                startCountdown(3)
            }
        } else {
            palmSince = nil
        }

        if voiceOn && countdown == nil && !isCapturing && settings.showCoaching,
           speechGate.shouldSpeak(s.shown.primary, at: now), let c = s.shown.primary {
            voice.say(c.spoken)
        }
    }

    var voiceOn: Bool {
        switch settings.voice {
        case .off: return false
        case .always: return true
        case .selfie: return cam.side == .front
        }
    }

    // MARK: Controls

    func setMode(_ m: ShootMode) {
        settings.mode = m
        if m == .selfie && cam.side == .back { flip() }
        if (m == .portrait || m == .scene) && cam.side == .front { flip() }
        analyzer.resetSmoothing()
        syncInputs()
    }

    func flip() {
        Haptics.tap()
        camera.flip()
    }

    func setLens(_ display: Double) {
        Haptics.tap()
        camera.setZoom(display: display)
    }

    func toggleAuto() {
        settings.autoCapture.toggle()
        show(settings.autoCapture ? "Auto: shoots when the shot is ready" : "Auto off", tone: .neutral)
    }

    func toggleHandsFree() {
        settings.handsFree.toggle()
        syncInputs()
        show(settings.handsFree ? "Hands-free: show an open palm for a 3 second timer" : "Hands-free off", tone: .neutral)
    }

    func cycleTimer() {
        settings.timerSeconds = settings.timerSeconds == 0 ? 3 : (settings.timerSeconds == 3 ? 10 : 0)
        show(settings.timerSeconds == 0 ? "Timer off" : "Timer \(settings.timerSeconds)s", tone: .neutral)
    }

    func shutter() {
        if countdown != nil {
            countdownTask?.cancel()
            countdown = nil
            return
        }
        if settings.timerSeconds > 0 {
            startCountdown(settings.timerSeconds)
        } else {
            capture()
        }
    }

    func startCountdown(_ seconds: Int) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for i in stride(from: seconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.countdown = i
                Haptics.tap()
                if self.settings.voice != .off && (i <= 3) { self.voice.say("\(i)", interrupt: true) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.countdown = nil
            self.capture()
        }
    }

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        shutterFlash += 1
        Haptics.shutter()
        let count = max(1, settings.burstCount)
        camera.captureBurst(count: count, interval: 0.12, mirrorSelfie: settings.mirrorSelfies) { [weak self] photos in
            guard let self else { return }
            Task { @MainActor in await self.finishBurst(photos) }
        }
    }

    private func finishBurst(_ photos: [Data]) async {
        defer {
            isCapturing = false
            lastCaptureEnd = CACurrentMediaTime()
        }
        guard !photos.isEmpty else {
            show("The camera did not return a photo. Try again.", tone: .error)
            return
        }
        let result = await Task.detached(priority: .userInitiated) { StillAnalyzer.analyze(photos) }.value
        guard var result else {
            show("Could not read the photos.", tone: .error)
            return
        }
        lastBurst = result
        guard settings.autoSaveBest, let best = result.best else { return }
        do {
            let inAlbum = try await PhotoSaver.save(best.data, location: sensors.location)
            result.savedIndices.insert(best.index)
            lastBurst = result
            Haptics.success()
            let where_ = inAlbum ? "Saved to the frame album" : "Saved to Photos"
            if result.frames.count > 1 {
                show("\(where_): best of \(result.frames.count), \(result.reason)", tone: .ok)
            } else {
                show(where_, tone: .ok)
            }
        } catch {
            show(error.localizedDescription, tone: .error)
        }
    }

    func save(frameIndex: Int) async {
        guard var b = lastBurst, let f = b.frames.first(where: { $0.index == frameIndex }) else { return }
        do {
            try await PhotoSaver.save(f.data, location: sensors.location)
            b.savedIndices.insert(frameIndex)
            lastBurst = b
            Haptics.success()
            show("Saved", tone: .ok)
        } catch {
            show(error.localizedDescription, tone: .error)
        }
    }

    // MARK: Focus and exposure

    /// Tap on the viewfinder, in the preview layer's coordinates.
    func focus(atLayerPoint p: CGPoint) {
        let device = camera.previewLayer.captureDevicePointConverted(fromLayerPoint: p)
        camera.focusAndExpose(at: device)
        Haptics.tap()
    }

    func perform(_ action: CueAction) {
        switch action {
        case .exposeFace:
            exposeFace()
        case .lens(let x):
            let best = cam.lenses.min { abs($0.display - x) < abs($1.display - x) }
            if let best { setLens(best.display) }
        }
    }

    func exposeFace() {
        guard let face = live?.faces.max(by: { $0.rect.area < $1.rect.area }) else {
            show("No face to expose for yet.", tone: .neutral)
            return
        }
        let size = camera.previewLayer.bounds.size
        let map = ViewMap(size: size, rotation: overlayRotation)
        focus(atLayerPoint: map.point(face.rect.center))
        show("Exposing for the face", tone: .neutral)
    }

    // MARK: Director

    func askDirector() {
        let key = settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            director = .failed("Add your Gemini API key in Settings to use the director.")
            return
        }
        director = .thinking
        let analyzer = self.analyzer
        let ctx = DirectorContext(mode: live?.shown.mode ?? settings.mode, side: cam.side, zoom: cam.zoom,
                                  elevation: attitude.elevation, levelError: attitude.levelError,
                                  people: live?.people ?? 0,
                                  localTime: Date().formatted(date: .omitted, time: .shortened),
                                  sun: sunContext.map(DirectorContext.sunPhrase), place: place)
        let model = settings.directorModel
        let side = cam.side
        Task { [weak self] in
            let jpeg = await Task.detached(priority: .userInitiated) { analyzer.snapshotJPEG() }.value
            guard let jpeg else {
                self?.director = .failed("No camera frame yet.")
                return
            }
            do {
                let client = GeminiClient(apiKey: key)
                let body = GeminiRequest.json(parts: [.text(Director.prompt(ctx)), .jpeg(jpeg)])
                let resp = try await client.generate(model: model, body: body)
                guard let advice = Director.parse(resp.joinedText, side: side) else {
                    self?.director = .failed("The director's answer could not be read. Try again.")
                    return
                }
                guard let self, self.director == .thinking else { return }
                self.director = .ready(advice)
                if self.voiceOn { self.voice.say(advice.headline, interrupt: true) }
            } catch {
                self?.director = .failed(error.localizedDescription)
            }
        }
    }

    func dismissDirector() { director = .idle }

    // MARK: Toast

    func show(_ message: String, tone: BadgeTone) {
        toast = Toast(message: message, tone: tone)
    }
}
