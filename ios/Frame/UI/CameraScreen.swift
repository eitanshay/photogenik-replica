import AVFoundation
import SwiftUI

struct CameraScreen: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var flash = false

    var body: some View {
        @Bindable var session = session
        ZStack {
            Color.black.ignoresSafeArea()
            if session.permissionDenied {
                PermissionView()
            } else {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                    viewfinder
                    Spacer(minLength: 10)
                    if settings.fujiMode {
                        ScrollView(.horizontal, showsIndicators: false) {
                            PillTabs(items: FujiIntent.allCases.map { ($0, $0.label) }, selection: settings.fujiIntent) { i in
                                session.setFujiIntent(i)
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        PillTabs(items: ShootMode.allCases.map { ($0, $0.label) }, selection: settings.mode) { m in
                            session.setMode(m)
                        }
                    }
                    Spacer(minLength: 10)
                    bottomControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 6)
                }
            }
            if let toast = session.toast {
                VStack {
                    ToastView(message: toast.message, tone: toast.tone)
                        .padding(.top, 58)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                        .task(id: toast.id) { [session] in
                            try? await Task.sleep(nanoseconds: 3_200_000_000)
                            if session.toast?.id == toast.id {
                                withAnimation(ES.easeSlow) { session.toast = nil }
                            }
                        }
                    Spacer()
                }
            }
        }
        .animation(ES.easeSlow, value: session.toast)
        .statusBarHidden(true)
        .sheet(isPresented: $session.showSettings) {
            SettingsView().environment(settings).environment(session)
        }
        .sheet(isPresented: $session.showPoses) {
            PoseSheet(mode: session.live?.shown.mode ?? settings.mode)
        }
        .sheet(isPresented: $session.showReview) {
            ReviewSheet().environment(session)
        }
        .sheet(isPresented: $session.showFujiDetail) {
            FujiDetailSheet().environment(session).environment(settings)
        }
        .onAppear { session.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: if session.started { session.camera.start() }
            case .background: session.pause()
            default: break
            }
        }
        .onChange(of: session.shutterFlash) { _, _ in
            flash = true
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
        .tint(ES.signal)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            barButton("gearshape", label: "Settings") { session.showSettings = true }
            if let light = session.lightLabel {
                HStack(spacing: 6) {
                    Image(systemName: session.sun?.phase == .goldenHour ? "sun.horizon.fill" : (session.sun?.phase == .night ? "moon.fill" : "sun.max.fill"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(light).font(ESFont.mono(11, .medium)).lineLimit(1)
                }
                .foregroundStyle(session.sun?.phase == .goldenHour ? ES.onSignal : ES.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(session.sun?.phase == .goldenHour ? ES.signal : ES.panel))
            }
            Spacer(minLength: 4)
            toggle(settings.timerSeconds == 0 ? "timer" : "timer", on: settings.timerSeconds > 0,
                   text: settings.timerSeconds > 0 ? "\(settings.timerSeconds)s" : nil, label: "Timer") { session.cycleTimer() }
            toggle("hand.raised", on: settings.handsFree, label: "Hands-free palm trigger") { session.toggleHandsFree() }
            toggle("a.circle", on: settings.autoCapture, label: "Auto capture when ready") { session.toggleAuto() }
            barButton("figure.stand", label: "Pose ideas") { session.showPoses = true }
        }
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ES.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ES.panel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pill(_ text: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(ESFont.mono(11, .bold))
                .foregroundStyle(on ? ES.onSignal : .white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(on ? ES.signal : Color.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ symbol: String, on: Bool, text: String? = nil, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let text {
                    Text(text).font(ESFont.mono(12, .bold))
                } else {
                    Image(systemName: on ? symbol + ".fill" : symbol).font(.system(size: 15, weight: .medium))
                }
            }
            .foregroundStyle(on ? ES.onSignal : ES.ink)
            .frame(width: 36, height: 36)
            .background(Circle().fill(on ? ES.signal : ES.panel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                CameraPreview(previewLayer: session.camera.previewLayer)
                    .contentShape(Rectangle())
                    .onTapGesture { location in session.focus(atLayerPoint: location) }
                OverlayView(size: size)
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        pill("X100VI", on: settings.fujiMode, label: "Plan for the Fujifilm X100VI") { session.toggleFuji() }
                        if session.cam.liveSupported && !settings.fujiMode {
                            pill("LIVE", on: session.cam.liveOn, label: "Live Photo") { session.toggleLive() }
                        }
                        if session.cam.rawSupported && !settings.fujiMode {
                            pill(session.cam.rawIsProRAW ? "ProRAW" : "RAW", on: session.cam.rawOn, label: "RAW capture") { session.toggleRaw() }
                        }
                        Spacer()
                        directorButton
                    }
                    .padding(10)
                    Spacer()
                    if settings.fujiMode {
                        FujiCropChips()
                    } else if session.cam.lenses.count > 1 {
                        lensChips
                    }
                    if case .idle = session.director {
                        if settings.fujiMode { FujiCard() } else { CueHUD() }
                    } else {
                        DirectorPanel()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                if flash { Color.white.opacity(0.85).allowsHitTesting(false) }
                if session.steadyReady && settings.showCoaching {
                    RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous)
                        .strokeBorder(ES.ok, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous))
        .animation(ES.ease, value: session.steadyReady)
    }

    private var directorButton: some View {
        Button {
            if case .thinking = session.director { return }
            session.askDirector()
        } label: {
            HStack(spacing: 6) {
                if case .thinking = session.director {
                    ProgressView().tint(ES.onSignal).scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                }
                Text("director").font(ESFont.mono(12, .bold))
            }
            .foregroundStyle(ES.onSignal)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(ES.signal))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask the AI director")
    }

    private var lensChips: some View {
        HStack(spacing: 6) {
            ForEach(session.cam.lenses) { lens in
                let on = abs(lens.display - session.cam.zoom) < 0.01
                Button { session.setLens(lens.display) } label: {
                    Text(on ? lens.label + "×" : lens.label)
                        .font(ESFont.mono(on ? 12 : 11, .bold))
                        .foregroundStyle(on ? ES.signal : .white)
                        .frame(width: on ? 40 : 32, height: on ? 40 : 32)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .animation(ES.ease, value: session.cam.zoom)
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        HStack {
            Button { if session.lastBurst != nil { session.showReview = true } } label: {
                Group {
                    if let img = session.lastBurst?.best?.thumbnail {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: ES.radiusMd).fill(ES.panel)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ES.radiusMd, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Last shots")
            Spacer()
            ShutterButton(readiness: session.live?.shown.readiness ?? 0,
                          ready: session.steadyReady,
                          busy: session.isCapturing,
                          counting: session.countdown != nil) { session.shutter() }
            Spacer()
            Button { session.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ES.ink)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(ES.panel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch camera")
        }
    }
}

struct ShutterButton: View {
    let readiness: Int
    let ready: Bool
    let busy: Bool
    let counting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(readiness) / 100)
                    .stroke(ready ? ES.ok : ES.signal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(ES.easeSlow, value: readiness)
                Circle()
                    .fill(counting ? ES.signal : .white)
                    .padding(9)
                    .scaleEffect(busy ? 0.82 : 1)
                    .animation(ES.easeFast, value: busy)
                if counting {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .bold)).foregroundStyle(ES.onSignal)
                }
            }
            .frame(width: 78, height: 78)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counting ? "Cancel timer" : "Take photo")
        .accessibilityValue("Shot readiness \(readiness) percent")
    }
}

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            LogoMark(size: 26)
            Text("frame needs the camera").font(ESFont.h3).foregroundStyle(ES.ink)
            Text("It coaches you on the live view, so it cannot work without camera access. Nothing leaves your phone unless you ask the director.")
                .font(ESFont.body)
                .foregroundStyle(ES.ink2)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PillButtonStyle(kind: .primary, size: .lg))
        }
        .padding(32)
    }
}
