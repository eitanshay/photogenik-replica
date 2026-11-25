import XCTest
@testable import FrameCore

final class AttitudeTests: XCTestCase {
    func testUprightPortraitIsLevel() {
        let a = Attitude.from(gx: 0, gy: -1, gz: 0, side: .back)
        XCTAssertEqual(a.roll, 0, accuracy: 0.001)
        XCTAssertEqual(a.elevation, 0, accuracy: 0.001)
        XCTAssertEqual(a.hold, .portrait)
        XCTAssertEqual(a.levelError, 0, accuracy: 0.001)
    }

    func testFlatOnTableRearCameraPointsDown() {
        let back = Attitude.from(gx: 0, gy: 0, gz: -1, side: .back)
        XCTAssertEqual(back.elevation, -90, accuracy: 0.001)
        XCTAssertTrue(back.isFlat)
        let front = Attitude.from(gx: 0, gy: 0, gz: -1, side: .front)
        XCTAssertEqual(front.elevation, 90, accuracy: 0.001)
    }

    func testClockwiseTiltGivesPositiveLevelError() {
        let r = MathX.rad(5)
        let a = Attitude.from(gx: sin(r), gy: -cos(r), gz: 0, side: .back)
        XCTAssertEqual(a.levelError, 5, accuracy: 0.01)
    }

    func testLandscapeIsLevelAtNinety() {
        let a = Attitude.from(gx: 1, gy: 0, gz: 0, side: .back)
        XCTAssertEqual(a.hold, .landscapeLeft)
        XCTAssertEqual(a.levelError, 0, accuracy: 0.01)
        let r = MathX.rad(93)
        let b = Attitude.from(gx: sin(r), gy: -cos(r), gz: 0, side: .back)
        XCTAssertEqual(b.levelError, 3, accuracy: 0.01)
    }

    func testTiltedUpRearCameraHasPositiveElevation() {
        // Top of the phone tipped back 20°: the lens looks up.
        let r = MathX.rad(20)
        let a = Attitude.from(gx: 0, gy: -cos(r), gz: sin(r), side: .back)
        XCTAssertEqual(a.elevation, 20, accuracy: 0.01)
    }
}

final class SunTests: XCTestCase {
    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func testEquatorEquinoxNoonIsOverhead() {
        let p = Sun.position(at: date("2024-03-20T12:07:00Z"), latitude: 0, longitude: 0)
        XCTAssertGreaterThan(p.elevation, 87)
    }

    func testPaloAltoSummerSolsticeNoon() {
        // Solar noon in Palo Alto on June 21 is about 13:12 PDT = 20:12 UTC. Max elevation = 90 - 37.44 + 23.44 = 76.
        let p = Sun.position(at: date("2024-06-21T20:12:00Z"), latitude: 37.44, longitude: -122.14)
        XCTAssertEqual(p.elevation, 76, accuracy: 1.0)
        XCTAssertEqual(p.azimuth, 180, accuracy: 6)
        XCTAssertEqual(p.phase, .harsh)
    }

    func testMorningSunIsInTheEast() {
        // 08:00 PDT = 15:00 UTC.
        let p = Sun.position(at: date("2024-06-21T15:00:00Z"), latitude: 37.44, longitude: -122.14)
        XCTAssertGreaterThan(p.azimuth, 45)
        XCTAssertLessThan(p.azimuth, 110)
        XCTAssertGreaterThan(p.elevation, 15)
        XCTAssertLessThan(p.elevation, 40)
    }

    func testNightIsNight() {
        // 01:00 PDT.
        let p = Sun.position(at: date("2024-06-21T08:00:00Z"), latitude: 37.44, longitude: -122.14)
        XCTAssertEqual(p.phase, .night)
    }

    func testGoldenWindowBeforeSunset() {
        // From noon PDT, the next golden hour is the evening one, around 19:40 to 20:45 PDT.
        let w = Sun.goldenWindow(from: date("2024-06-21T19:00:00Z"), latitude: 37.44, longitude: -122.14)
        XCTAssertNotNil(w)
        let start = w!.start.timeIntervalSince(date("2024-06-22T02:40:00Z"))
        XCTAssertLessThan(abs(start), 45 * 60)
        XCTAssertGreaterThan(w!.end.timeIntervalSince(w!.start), 30 * 60)
    }

    func testRelativeAzimuthWraps() {
        XCTAssertEqual(Sun.relativeAzimuth(sunAzimuth: 10, lensHeading: 350), 20, accuracy: 0.001)
        XCTAssertEqual(Sun.relativeAzimuth(sunAzimuth: 350, lensHeading: 10), -20, accuracy: 0.001)
    }
}

final class CoachSelfieTests: XCTestCase {
    func goodFace() -> FaceInfo {
        FaceInfo(rect: Rect(x: 0.32, y: 0.24, w: 0.36, h: 0.27), yaw: 14, roll: 3, quality: 0.7,
                 leftEyeOpen: 0.3, rightEyeOpen: 0.3, noseRatio: 0.6, lumaLeft: 0.55, lumaRight: 0.5)
    }

    func frame(_ face: FaceInfo?, elevation: Double = -12) -> FrameAnalysis {
        FrameAnalysis(side: .front, attitude: Attitude(roll: 0, elevation: elevation, hold: .portrait),
                      faces: face.map { [$0] } ?? [], scene: SceneStats(meanLuma: 0.5, backgroundLuma: 0.5, clutter: 0.1, sharpness: 300))
    }

    func testGoodSelfieIsReady() {
        let out = Coach.evaluate(frame(goodFace()))
        XCTAssertEqual(out.mode, .selfie)
        XCTAssertTrue(out.cues.isEmpty, "unexpected cues: \(out.cues.map(\.id))")
        XCTAssertTrue(out.isReady)
        XCTAssertEqual(out.readiness, 100)
    }

    func testNoFace() {
        let out = Coach.evaluate(frame(nil))
        XCTAssertEqual(out.primary?.id, .noFace)
        XCTAssertFalse(out.isReady)
        XCTAssertEqual(out.readiness, 0)
    }

    func testShootingFromBelowIsTheTopFix() {
        var f = goodFace()
        f.yaw = 0 // also a nice-to-have cue, which must rank below
        let out = Coach.evaluate(frame(f, elevation: 15))
        XCTAssertEqual(out.primary?.id, .phoneLow)
        XCTAssertEqual(out.primary?.arrow, .raise)
        XCTAssertTrue(out.cues.contains { $0.id == .faceTurn })
        XCTAssertFalse(out.isReady)
    }

    func testTooCloseIsFlagged() {
        var f = goodFace()
        f.rect = Rect(x: 0.1, y: 0.15, w: 0.8, h: 0.6)
        let out = Coach.evaluate(frame(f))
        XCTAssertEqual(out.primary?.id, .tooClose)
    }

    func testClosedEyesBlockReady() {
        var f = goodFace()
        f.leftEyeOpen = 0.05
        f.rightEyeOpen = 0.06
        let out = Coach.evaluate(frame(f))
        XCTAssertTrue(out.eyesClosed)
        XCTAssertFalse(out.isReady)
    }

    func testBacklitSelfie() {
        var a = frame(goodFace())
        a.faces[0].lumaLeft = 0.2
        a.faces[0].lumaRight = 0.22
        a.scene.backgroundLuma = 0.8
        let out = Coach.evaluate(a)
        XCTAssertEqual(out.primary?.id, .backlit)
        XCTAssertEqual(out.primary?.actor, .you)
    }

    func testChinCues() {
        var f = goodFace()
        f.noseRatio = 0.3
        XCTAssertTrue(Coach.evaluate(frame(f)).cues.contains { $0.id == .chinUp })
        f.noseRatio = 0.9
        XCTAssertTrue(Coach.evaluate(frame(f)).cues.contains { $0.id == .chinDown })
    }

    func testPreferredSideWording() {
        var f = goodFace()
        f.yaw = 1
        let out = Coach.evaluate(frame(f), settings: CoachSettings(mode: .auto, preferredSide: .left))
        XCTAssertEqual(out.cues.first { $0.id == .faceTurn }?.text, "Show a bit more of your left side")
    }
}

final class CoachPortraitTests: XCTestCase {
    func body(kneesAt y: Double, ankles: Bool) -> BodyInfo {
        var j: [Joint: Vec2] = [
            .nose: Vec2(0.5, 0.2), .leftShoulder: Vec2(0.42, 0.3), .rightShoulder: Vec2(0.58, 0.3),
            .leftHip: Vec2(0.45, 0.55), .rightHip: Vec2(0.55, 0.55),
            .leftKnee: Vec2(0.45, y), .rightKnee: Vec2(0.55, y),
            .leftElbow: Vec2(0.35, 0.42), .rightElbow: Vec2(0.65, 0.42),
            .leftWrist: Vec2(0.4, 0.5), .rightWrist: Vec2(0.62, 0.5)
        ]
        if ankles {
            j[.leftAnkle] = Vec2(0.45, 0.9)
            j[.rightAnkle] = Vec2(0.55, 0.9)
        }
        return BodyInfo(joints: j)
    }

    func face() -> FaceInfo {
        FaceInfo(rect: Rect(x: 0.46, y: 0.14, w: 0.08, h: 0.08), yaw: 15, roll: 0, quality: 0.6,
                 leftEyeOpen: 0.3, rightEyeOpen: 0.3, noseRatio: 0.6, lumaLeft: 0.5, lumaRight: 0.5)
    }

    func frame(body: BodyInfo, elevation: Double = 0, roll: Double = 0, zoom: Double = 1) -> FrameAnalysis {
        FrameAnalysis(side: .back, attitude: Attitude(roll: roll, elevation: elevation, hold: .portrait), zoom: zoom,
                      faces: [face()], bodies: [body], scene: SceneStats(meanLuma: 0.5, backgroundLuma: 0.5))
    }

    func testKneeCrop() {
        let out = Coach.evaluate(frame(body: body(kneesAt: 0.9, ankles: false)))
        XCTAssertEqual(out.mode, .portrait)
        XCTAssertTrue(out.cues.contains { $0.id == .kneeCrop })
        XCTAssertEqual(out.cues.first { $0.id == .kneeCrop }?.marks.count, 2)
    }

    func testFullBodyShotFromAboveSaysLower() {
        let out = Coach.evaluate(frame(body: body(kneesAt: 0.72, ankles: true), elevation: -20))
        XCTAssertTrue(out.cues.contains { $0.id == .shootDownOnBody })
        XCTAssertFalse(out.cues.contains { $0.id == .kneeCrop })
    }

    func testLevel() {
        let out = Coach.evaluate(frame(body: body(kneesAt: 0.72, ankles: true), roll: 8))
        XCTAssertEqual(out.primary?.id, .level)
        XCTAssertEqual(out.primary?.severity, .fix)
        XCTAssertEqual(out.primary?.arrow, .rotateCCW)
        XCTAssertEqual(out.levelError ?? 0, 8, accuracy: 0.01)
    }

    func testHorizonOverridesPhoneRoll() {
        var a = frame(body: body(kneesAt: 0.72, ankles: true), roll: 0)
        a.scene.horizonAngle = -4
        let out = Coach.evaluate(a)
        XCTAssertEqual(out.cues.first { $0.id == .level }?.arrow, .rotateCW)
    }

    func testCloseFaceAtOneXSuggestsTele() {
        var a = frame(body: body(kneesAt: 0.72, ankles: true))
        a.faces[0].rect = Rect(x: 0.35, y: 0.2, w: 0.3, h: 0.3)
        a.bodies = []
        let out = Coach.evaluate(a)
        XCTAssertEqual(out.cues.first { $0.id == .useTele }?.action, .lens(2))
    }

    func testUltraWideOnPeople() {
        let out = Coach.evaluate(frame(body: body(kneesAt: 0.72, ankles: true), zoom: 0.5))
        XCTAssertEqual(out.cues.first { $0.id == .avoidUltraWide }?.action, .lens(1))
    }

    func testArmsGlued() {
        var b = body(kneesAt: 0.72, ankles: true)
        b.joints[.leftElbow] = Vec2(0.43, 0.42)
        b.joints[.leftWrist] = Vec2(0.43, 0.54)
        b.joints[.rightElbow] = Vec2(0.57, 0.42)
        b.joints[.rightWrist] = Vec2(0.57, 0.54)
        let out = Coach.evaluate(frame(body: b))
        XCTAssertTrue(out.cues.contains { $0.id == .armsGlued })
        XCTAssertEqual(out.cues.first { $0.id == .armsGlued }?.actor, .subject)
    }

    func testBacklitWithSunBehindOffersExposeAction() {
        var a = frame(body: body(kneesAt: 0.72, ankles: true))
        a.faces[0].lumaLeft = 0.2
        a.faces[0].lumaRight = 0.2
        a.scene.backgroundLuma = 0.85
        a.sun = SunContext(elevation: 10, relativeAzimuth: 12, phase: .daylight)
        let out = Coach.evaluate(a)
        let c = out.cues.first { $0.id == .sunBehind }
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.action, .exposeFace)
    }

    func testSmallCentredSubjectGetsThirds() {
        var a = frame(body: body(kneesAt: 0.72, ankles: true))
        a.faces[0].rect = Rect(x: 0.48, y: 0.4, w: 0.04, h: 0.04)
        a.bodies = []
        let out = Coach.evaluate(a)
        XCTAssertTrue(out.cues.contains { $0.id == .thirds })
        XCTAssertNotNil(out.targetZone)
    }
}

final class CoachGroupAndSceneTests: XCTestCase {
    func f(_ x: Double, w: Double = 0.08, y: Double = 0.3) -> FaceInfo {
        FaceInfo(rect: Rect(x: x, y: y, w: w, h: w), leftEyeOpen: 0.3, rightEyeOpen: 0.3)
    }

    func testGroupGapsAndEdge() {
        let a = FrameAnalysis(side: .back, attitude: Attitude(roll: 0, elevation: 0, hold: .portrait),
                              faces: [f(0.01), f(0.2), f(0.7)])
        let out = Coach.evaluate(a)
        XCTAssertEqual(out.mode, .group)
        XCTAssertTrue(out.cues.contains { $0.id == .edgePerson })
        XCTAssertTrue(out.cues.contains { $0.id == .gaps })
    }

    func testGroupBlinkBlocksReady() {
        var faces = [f(0.2), f(0.4), f(0.6)]
        faces[1].leftEyeOpen = 0.02
        faces[1].rightEyeOpen = 0.02
        let a = FrameAnalysis(side: .back, attitude: Attitude(roll: 0, elevation: 0, hold: .portrait), faces: faces)
        let out = Coach.evaluate(a)
        XCTAssertTrue(out.eyesClosed)
        XCTAssertFalse(out.isReady)
    }

    func testSceneVerticalsAndLevel() {
        let a = FrameAnalysis(side: .back, attitude: Attitude(roll: 2, elevation: 15, hold: .portrait))
        let out = Coach.evaluate(a)
        XCTAssertEqual(out.mode, .scene)
        XCTAssertTrue(out.cues.contains { $0.id == .level })
        XCTAssertEqual(out.cues.first { $0.id == .verticals }?.arrow, .tiltDown)
    }

    func testSceneLevelToleranceIsTight() {
        let a = FrameAnalysis(side: .back, attitude: Attitude(roll: 1, elevation: 0, hold: .portrait))
        XCTAssertFalse(Coach.evaluate(a).cues.contains { $0.id == .level })
        let b = FrameAnalysis(side: .back, attitude: Attitude(roll: 2, elevation: 0, hold: .portrait))
        XCTAssertTrue(Coach.evaluate(b).cues.contains { $0.id == .level })
    }

    func testTinyBackgroundFacesDoNotMakeAGroup() {
        let a = FrameAnalysis(side: .back, attitude: Attitude(roll: 0, elevation: 0, hold: .portrait),
                              faces: [f(0.4, w: 0.2), f(0.05, w: 0.03), f(0.85, w: 0.03)])
        XCTAssertEqual(Coach.resolveMode(a, requested: .auto), .portrait)
    }
}

final class LumaTests: XCTestCase {
    /// 48x64 frame, flat grey, a person mask where the face is.
    func base() -> (LumaImage, LumaImage, FaceInfo) {
        let w = 48, h = 64
        let luma = LumaImage(width: w, height: h, fill: 120)
        var mask = LumaImage(width: w, height: h, fill: 0)
        let face = FaceInfo(rect: Rect(x: 0.4, y: 0.4, w: 0.2, h: 0.15))
        for y in Int(0.4 * Double(h))..<h {
            for x in Int(0.38 * Double(w))..<Int(0.62 * Double(w)) { mask.pixels[y * w + x] = 255 }
        }
        return (luma, mask, face)
    }

    func testFlatBackgroundHasNoMergersOrClutter() {
        let (luma, mask, face) = base()
        XCTAssertTrue(luma.mergers(face: face, mask: mask).isEmpty)
        XCTAssertEqual(luma.clutter(mask: mask), 0, accuracy: 0.0001)
        XCTAssertEqual(luma.laplacianVariance(), 0, accuracy: 0.0001)
    }

    func testPoleAboveHeadIsAVerticalMerger() {
        var (luma, mask, face) = base()
        // A dark pole two pixels wide straight above the head, x = 24...25.
        for y in 0..<Int(0.4 * 64) {
            luma.pixels[y * 48 + 24] = 10
            luma.pixels[y * 48 + 25] = 10
        }
        _ = mask
        let m = luma.mergers(face: face, mask: mask)
        XCTAssertTrue(m.contains { $0.kind == .vertical }, "\(m)")
    }

    func testHorizonThroughNeckIsAHorizontalMerger() {
        var (luma, mask, face) = base()
        // Bright sky above y = 34, dark sea below: a line at about the neck (face spans y 25.6...35.2).
        for y in 0..<64 {
            for x in 0..<48 { luma.pixels[y * 48 + x] = y < 34 ? 220 : 60 }
        }
        _ = mask
        let m = luma.mergers(face: face, mask: mask)
        XCTAssertTrue(m.contains { $0.kind == .horizontal }, "\(m)")
    }

    func testCheckerboardIsSharpAndBusy() {
        var px = [UInt8](repeating: 0, count: 32 * 32)
        for y in 0..<32 { for x in 0..<32 { px[y * 32 + x] = ((x / 2 + y / 2) % 2 == 0) ? 30 : 220 } }
        let img = LumaImage(width: 32, height: 32, pixels: px)
        XCTAssertGreaterThan(img.laplacianVariance(), 1000)
        XCTAssertGreaterThan(img.clutter(mask: nil), 0.3)
    }

    func testRegionMeans() {
        let (luma, mask, _) = base()
        XCTAssertEqual(luma.mean, 120.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(luma.backgroundMean(mask: mask) ?? 0, 120.0 / 255, accuracy: 0.0001)
        let resized = mask.resized(width: 24, height: 32)
        XCTAssertEqual(resized.width, 24)
        XCTAssertEqual(resized[12, 31], 255)
        XCTAssertEqual(resized[0, 0], 0)
    }
}

final class SmootherTests: XCTestCase {
    func out(_ cues: [Cue], ready: Bool = false) -> CoachOutput {
        CoachOutput(mode: .selfie, cues: cues, readiness: ready ? 100 : 50, isReady: ready, eyesClosed: false,
                    levelError: nil, targetZone: nil)
    }

    func testCueMustPersistBeforeShowing() {
        let s = CueSmoother()
        let c = Cue(.tooFar, .nice, .you, "closer")
        XCTAssertNil(s.update(out([c]), at: 0).primary)
        XCTAssertNil(s.update(out([c]), at: 0.2).primary)
        XCTAssertEqual(s.update(out([c]), at: 0.5).primary?.id, .tooFar)
    }

    func testPrimaryDwellsThenYieldsToMoreSevere() {
        let s = CueSmoother()
        let nice = Cue(.tooFar, .nice, .you, "closer")
        let improve = Cue(.chinUp, .improve, .you, "chin")
        _ = s.update(out([nice]), at: 0)
        XCTAssertEqual(s.update(out([nice]), at: 0.5).primary?.id, .tooFar)
        // Frames arrive every 0.1 s.
        var t = 0.6
        var shownAt12: CueID?
        while t < 2.25 {
            let shown = s.update(out([improve, nice]), at: t)
            if abs(t - 1.2) < 0.01 { shownAt12 = shown.primary?.id }
            t += 0.1
        }
        XCTAssertEqual(shownAt12, .tooFar, "must dwell")
        XCTAssertEqual(s.update(out([improve, nice]), at: 2.3).primary?.id, .chinUp)
    }

    func testFixInterruptsImmediately() {
        let s = CueSmoother()
        let nice = Cue(.tooFar, .nice, .you, "closer")
        let fix = Cue(.phoneLow, .fix, .you, "raise")
        _ = s.update(out([nice]), at: 0)
        _ = s.update(out([nice]), at: 0.5)
        _ = s.update(out([fix, nice]), at: 0.6)
        XCTAssertEqual(s.update(out([fix, nice]), at: 0.9).primary?.id, .phoneLow)
    }

    func testSteadyReadyNeedsHold() {
        let s = CueSmoother()
        XCTAssertFalse(s.update(out([], ready: true), at: 0).steadyReady)
        XCTAssertFalse(s.update(out([], ready: true), at: 0.4).steadyReady)
        XCTAssertTrue(s.update(out([], ready: true), at: 0.8).steadyReady)
        XCTAssertFalse(s.update(out([], ready: false), at: 0.9).steadyReady)
    }

    func testSpeechGate() {
        var g = SpeechGate()
        let a = Cue(.phoneLow, .fix, .you, "raise")
        let b = Cue(.chinUp, .improve, .you, "chin")
        XCTAssertTrue(g.shouldSpeak(a, at: 0))
        XCTAssertFalse(g.shouldSpeak(a, at: 1))
        XCTAssertFalse(g.shouldSpeak(b, at: 1), "too soon after the last line")
        XCTAssertTrue(g.shouldSpeak(b, at: 3))
        XCTAssertFalse(g.shouldSpeak(a, at: 6))
        XCTAssertTrue(g.shouldSpeak(a, at: 13))
    }
}

final class RankerTests: XCTestCase {
    func testBlinkLosesEvenWhenSharper() {
        let open = FaceInfo(rect: Rect(x: 0, y: 0, w: 0.3, h: 0.3), quality: 0.6, leftEyeOpen: 0.3, rightEyeOpen: 0.3)
        var closed = open
        closed.leftEyeOpen = 0.05
        closed.rightEyeOpen = 0.05
        let r = ShotRanker.rank([ShotCandidate(faces: [closed], sharpness: 900),
                                 ShotCandidate(faces: [open], sharpness: 500)])
        XCTAssertEqual(r.first?.index, 1)
        XCTAssertTrue(r.first?.reason.contains("eyes open") ?? false)
    }

    func testSharpestWinsWithoutFaces() {
        let r = ShotRanker.rank([ShotCandidate(faces: [], sharpness: 100), ShotCandidate(faces: [], sharpness: 800),
                                 ShotCandidate(faces: [], sharpness: 300)])
        XCTAssertEqual(r.first?.index, 1)
        XCTAssertEqual(r.first?.reason, "sharpest")
    }
}

final class GestureTests: XCTestCase {
    func testOpenPalmAndFist() {
        let wrist = Vec2(0.5, 0.8)
        let bases: [Vec2?] = [Vec2(0.42, 0.72), Vec2(0.45, 0.65), Vec2(0.5, 0.64), Vec2(0.55, 0.65), Vec2(0.58, 0.68)]
        let open: [Vec2?] = [Vec2(0.32, 0.62), Vec2(0.4, 0.45), Vec2(0.5, 0.42), Vec2(0.6, 0.45), Vec2(0.68, 0.52)]
        XCTAssertTrue(HandGesture.isOpenPalm(HandPoints(wrist: wrist, tips: open, bases: bases)))
        let fist: [Vec2?] = [Vec2(0.45, 0.7), Vec2(0.47, 0.68), Vec2(0.5, 0.68), Vec2(0.53, 0.68), Vec2(0.55, 0.7)]
        XCTAssertFalse(HandGesture.isOpenPalm(HandPoints(wrist: wrist, tips: fist, bases: bases)))
    }

    func testEyeOpennessAndNoseRatio() {
        let open = [Vec2(0, 0.5), Vec2(0.5, 0.35), Vec2(1, 0.5), Vec2(0.5, 0.65)]
        XCTAssertEqual(Landmarks.eyeOpenness(open) ?? 0, 0.3, accuracy: 0.0001)
        let r = Landmarks.noseRatio(leftEye: [Vec2(0.3, 0.4)], rightEye: [Vec2(0.7, 0.4)], noseTip: Vec2(0.5, 0.52),
                                    mouth: [Vec2(0.5, 0.6)])
        XCTAssertEqual(r ?? 0, 0.6, accuracy: 0.0001)
    }
}

final class DirectorTests: XCTestCase {
    func testParsesFencedJSON() {
        let reply = """
        Here you go:
        ```json
        {"headline": "Step left so the lamp post clears her head", "rating": 6,
         "moves": [{"who": "photographer", "do": "Take two steps left", "direction": "left"},
                   {"who": "subject", "do": "Turn her shoulders 30 degrees to the water", "direction": "turn"}],
         "pose": ["Weight on the back leg"], "background": "Lamp post behind her head", "light": "Soft side light, good",
         "lens": "2", "subject_box": [200, 300, 900, 600], "idea": "Try her small on the left third with the bridge"}
        ```
        """
        let a = Director.parse(reply, side: .back)
        XCTAssertEqual(a?.headline, "Step left so the lamp post clears her head")
        XCTAssertEqual(a?.rating, 6)
        XCTAssertEqual(a?.moves.count, 2)
        XCTAssertEqual(a?.moves.first?.arrow, .left)
        XCTAssertEqual(a?.moves.last?.who, .subject)
        XCTAssertEqual(a?.lens, 2)
        XCTAssertEqual(a?.subjectBox?.x ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(a?.subjectBox?.h ?? 0, 0.7, accuracy: 0.0001)
    }

    func testBracesInsideStringsDoNotBreakExtraction() {
        let a = Director.parse(#"{"headline": "Use {curly} words", "moves": []}"#, side: .front)
        XCTAssertEqual(a?.headline, "Use {curly} words")
        XCTAssertNil(a?.subjectBox)
    }

    func testGarbageIsNil() {
        XCTAssertNil(Director.parse("sorry, no", side: .back))
    }

    func testPromptMentionsContext() {
        let p = Director.prompt(DirectorContext(mode: .portrait, side: .back, zoom: 2, elevation: -5, levelError: 1,
                                                people: 1, localTime: "6:40 PM", sun: "sun 5° above the horizon (golden hour)"))
        XCTAssertTrue(p.contains("2.0x"))
        XCTAssertTrue(p.contains("golden hour"))
        XCTAssertTrue(p.contains("Return only JSON"))
    }
}

final class HeadingTests: XCTestCase {
    // Phone upright in portrait, rear camera facing east. Device axes in (north, west, up):
    // x (right edge) = south, y (top) = up, z (toward the user) = west.
    let refToDevice: [[Double]] = [[-1, 0, 0], [0, 0, 1], [0, 1, 0]]
    var deviceToRef: [[Double]] { (0..<3).map { r in (0..<3).map { c in refToDevice[c][r] } } }
    let gravity = (x: 0.0, y: -1.0, z: 0.0)

    func testRearCameraFacingEastEitherConvention() {
        XCTAssertEqual(LensHeading.heading(m: refToDevice, gravity: gravity, side: .back) ?? -1, 90, accuracy: 0.001)
        XCTAssertEqual(LensHeading.heading(m: deviceToRef, gravity: gravity, side: .back) ?? -1, 90, accuracy: 0.001)
    }

    func testSelfieCameraFacesTheOtherWay() {
        XCTAssertEqual(LensHeading.heading(m: refToDevice, gravity: gravity, side: .front) ?? -1, 270, accuracy: 0.001)
    }

    func testFlatPhoneHasNoHeading() {
        let flat: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        XCTAssertNil(LensHeading.heading(m: flat, gravity: (0, 0, -1), side: .back))
    }
}

final class FujiPlannerTests: XCTestCase {
    /// Exposure the plan delivers, as EV100 it is correct for.
    func plannedEV(_ p: FujiPlan) -> Double {
        log2(p.aperture * p.aperture / p.shutter) - log2(Double(p.iso) / 100) + (p.nd ? 4 : 0) + p.compensation
    }

    func testSunnyPortraitUsesNDAtF2() {
        let p = FujiPlanner.plan(FujiInput(ev100: 15, intent: .portrait, people: 1))
        XCTAssertEqual(p.aperture, 2)
        XCTAssertTrue(p.nd)
        XCTAssertEqual(p.shutterKind, .mechanical)
        XCTAssertGreaterThanOrEqual(p.shutter, FujiPlanner.leafLimit(aperture: 2) * 0.99)
        XCTAssertEqual(plannedEV(p), 15, accuracy: 0.4)
        XCTAssertEqual(p.recipe.look, .soft)
    }

    func testSunnyStreetStaysAtF8WithoutND() {
        let p = FujiPlanner.plan(FujiInput(ev100: 15, intent: .street))
        XCTAssertEqual(p.aperture, 8)
        XCTAssertFalse(p.nd)
        XCTAssertLessThanOrEqual(p.shutter, 1.0 / 500)
        XCTAssertTrue(p.focus.hasPrefix("MF zone focus"))
        XCTAssertEqual(plannedEV(p), 15, accuracy: 0.4)
    }

    func testIndoorPortraitRaisesISO() {
        // EV 7: a bright living room.
        let p = FujiPlanner.plan(FujiInput(ev100: 7, intent: .portrait, people: 1))
        XCTAssertEqual(p.aperture, 2)
        XCTAssertLessThanOrEqual(p.shutter, 1.0 / 200)
        XCTAssertGreaterThanOrEqual(p.iso, 640)
        XCTAssertEqual(plannedEV(p), 7, accuracy: 0.4)
    }

    func testDarkNightWarns() {
        let p = FujiPlanner.plan(FujiInput(ev100: 0, intent: .night))
        XCTAssertEqual(p.aperture, 2)
        XCTAssertFalse(p.warnings.isEmpty)
        XCTAssertEqual(p.recipe.look, .night)
    }

    func testBacklitPortraitGetsPlusCompAndFillFlash() {
        let p = FujiPlanner.plan(FujiInput(ev100: 14, intent: .portrait, people: 1, backlightStops: 2))
        XCTAssertGreaterThan(p.compensation, 0.6)
        XCTAssertNotNil(p.flash)
        XCTAssertEqual(plannedEV(p), 14, accuracy: 0.4)
    }

    func testActionPrefersElectronicOverND() {
        let p = FujiPlanner.plan(FujiInput(ev100: 16, intent: .action))
        XCTAssertFalse(p.nd)
        XCTAssertLessThanOrEqual(p.shutter, 1.0 / 1000)
    }

    func testAutoIntent() {
        XCTAssertEqual(FujiPlanner.resolveIntent(FujiInput(ev100: 12, people: 4)), .group)
        XCTAssertEqual(FujiPlanner.resolveIntent(FujiInput(ev100: 12, people: 1)), .portrait)
        XCTAssertEqual(FujiPlanner.resolveIntent(FujiInput(ev100: 3)), .night)
        XCTAssertEqual(FujiPlanner.resolveIntent(FujiInput(ev100: 13)), .landscape)
    }

    func testDynamicRangeFollowsISO() {
        // Bright, contrasty portrait: base ISO cannot run DR400.
        let p = FujiPlanner.plan(FujiInput(ev100: 15, intent: .landscape, highlightClip: 0.1))
        if p.iso < 250 { XCTAssertEqual(p.dynamicRange, 100) }
        if p.iso >= 500 { XCTAssertLessThanOrEqual(p.dynamicRange, 400) }
    }

    func testOptics() {
        // 23mm at f/8 with c = 0.02 mm: hyperfocal about 3.3 m.
        XCTAssertEqual(FujiOptics.hyperfocal(aperture: 8), 3.33, accuracy: 0.05)
        let d = FujiOptics.depthOfField(distance: 2, aperture: 2)
        XCTAssertLessThan(d.near, 2)
        XCTAssertGreaterThan(d.far, 2)
        XCTAssertLessThan(d.far - d.near, 1.0)
        // A face 30% of a portrait frame's width at 35mm is about 0.8 m away.
        XCTAssertEqual(FujiOptics.distance(faceWidth: 0.3, focalEquivalent: 35, frameWidthEquivalent: 24) ?? 0, 0.78, accuracy: 0.05)
    }

    func testMeterAndZoomMath() {
        // f/1.78, 1/100 s, ISO 100 is EV ~8.3.
        XCTAssertEqual(FujiPlanner.ev100(aperture: 1.78, exposureSeconds: 0.01, iso: 100), 8.3, accuracy: 0.05)
        // A 24mm-equivalent camera (73.7° horizontal) zooms 35/24 ≈ 1.46x.
        XCTAssertEqual(FujiPlanner.zoomFactor(forEquivalent: 35, deviceHorizontalFOV: 73.74), 35.0 / 24, accuracy: 0.02)
    }

    func testFormatting() {
        XCTAssertEqual(FujiFormat.shutter(1.0 / 500), "1/500")
        XCTAssertEqual(FujiFormat.shutter(2), "2s")
        XCTAssertEqual(FujiFormat.aperture(2.8), "f/2.8")
        XCTAssertEqual(FujiFormat.aperture(8), "f/8")
        XCTAssertEqual(FujiFormat.compensation(2.0 / 3), "+2/3")
        XCTAssertEqual(FujiFormat.compensation(-4.0 / 3), "−1 1/3")
        XCTAssertEqual(FujiFormat.compensation(0), "±0")
    }

    func testSettingsAreOnTheCamerasScales() {
        for ev in stride(from: -2.0, through: 17, by: 1) {
            for intent in FujiIntent.allCases {
                let p = FujiPlanner.plan(FujiInput(ev100: ev, intent: intent, people: intent == .group ? 4 : 1))
                XCTAssertTrue(FujiScale.apertures.contains(p.aperture))
                XCTAssertTrue(FujiScale.isos.contains(p.iso))
                XCTAssertTrue(FujiScale.shutters.contains(p.shutter))
                if p.shutterKind == .mechanical {
                    XCTAssertGreaterThanOrEqual(p.shutter, 1.0 / 4000 * 0.99, "ev \(ev) \(intent)")
                }
            }
        }
    }
}

final class DirectorCameraTests: XCTestCase {
    func testCameraContextAndTip() {
        let ctx = DirectorContext(mode: .portrait, side: .back, zoom: 1.5, elevation: 0, levelError: 0, people: 1,
                                  localTime: "5:10 PM", camera: "Fujifilm X100VI, f/2, 1/640, ISO 125, ND on")
        let p = Director.prompt(ctx)
        XCTAssertTrue(p.contains("Final camera: Fujifilm X100VI"))
        XCTAssertTrue(p.contains("camera_tip"))
        XCTAssertFalse(Director.prompt(DirectorContext(mode: .portrait, side: .back, zoom: 1, elevation: 0, levelError: 0,
                                                       people: 1, localTime: "x")).contains("camera_tip"))
        let a = Director.parse(#"{"headline": "h", "moves": [], "camera_tip": "Drop to f/2.8 for two faces."}"#, side: .back)
        XCTAssertEqual(a?.cameraTip, "Drop to f/2.8 for two faces.")
    }
}
