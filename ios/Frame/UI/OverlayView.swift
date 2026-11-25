import SwiftUI

/// Everything drawn over the live preview: grid, level, faces, target zone, crop marks,
/// background collisions, the director's framing box and the movement arrow.
struct OverlayView: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings
    let size: CGSize

    var body: some View {
        let map = ViewMap(size: size, rotation: session.overlayRotation)
        let live = session.live
        let shown = live?.shown
        ZStack {
            let showGrid = settings.showGrid
            let coaching = settings.showCoaching
            // X100VI frames are 3:2. The zoom matches the long side, so the short side loses 1/18 at each edge.
            let fuji = settings.fujiMode
            let frameRect = fuji ? CGRect(x: size.width / 18, y: 0, width: size.width * 8 / 9, height: size.height)
                                 : CGRect(origin: .zero, size: size)
            let directorBox: Rect? = {
                if case .ready(let advice) = session.director { return advice.subjectBox }
                return nil
            }()
            Canvas { ctx, sz in
                if fuji {
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: frameRect.minX, height: sz.height)), with: .color(.black.opacity(0.6)))
                    ctx.fill(Path(CGRect(x: frameRect.maxX, y: 0, width: sz.width - frameRect.maxX, height: sz.height)), with: .color(.black.opacity(0.6)))
                    ctx.stroke(Path(frameRect), with: .color(.white.opacity(0.5)), lineWidth: 1)
                }
                if showGrid { OverlayDraw.grid(&ctx, frameRect) }
                if let live, coaching {
                    for f in live.faces { OverlayDraw.brackets(&ctx, map.rect(f.rect), closed: f.eyesClosed == true) }
                    if let t = live.shown.targetZone { OverlayDraw.dashed(&ctx, map.rect(t), color: ES.signal) }
                    for z in live.zones { OverlayDraw.zone(&ctx, map.rect(z)) }
                    for m in live.marks { OverlayDraw.mark(&ctx, map.point(m)) }
                }
                if let directorBox { OverlayDraw.dashed(&ctx, map.rect(directorBox), color: ES.ok) }
            }
            .allowsHitTesting(false)

            if settings.showCoaching, let err = shown?.levelError {
                LevelBar(error: err, rotation: Double(map.r))
                    .position(x: size.width / 2, y: size.height / 2)
                    .allowsHitTesting(false)
            }

            if settings.showCoaching, let c = shown?.primary, let arrow = c.arrow, c.severity != .nice,
               session.countdown == nil, session.director == .idle {
                arrowView(arrow, map: map)
                    .allowsHitTesting(false)
            }

            if case .ready(let advice) = session.director, let box = advice.subjectBox {
                let r = map.rect(box)
                Text(session.cam.side == .front ? "you here" : "subject here")
                    .font(ESFont.mono(11, .bold))
                    .foregroundStyle(ES.onSignal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ES.ok))
                    .position(x: r.midX, y: max(14, r.minY - 12))
                    .allowsHitTesting(false)
            }

            if let n = session.countdown {
                Text("\(n)")
                    .font(ESFont.sans(120, .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .transition(.scale.combined(with: .opacity))
                    .id(n)
                    .allowsHitTesting(false)
            }

            if settings.handsFree && (live?.openPalm ?? false) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ES.onSignal)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(ES.signal))
                    .position(x: size.width / 2, y: 34)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(ES.ease, value: session.countdown)
    }

    @ViewBuilder
    private func arrowView(_ arrow: Arrow, map: ViewMap) -> some View {
        let sym = arrow.symbol
        // The offset is in image space; rotate it onto the screen.
        let o = arrow.offset
        let a = MathX.rad(Double(map.r))
        let dx = Double(o.dx) * cos(a) - Double(o.dy) * sin(a)
        let dy = Double(o.dx) * sin(a) + Double(o.dy) * cos(a)
        Image(systemName: sym.name)
            .font(.system(size: 46, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 8)
            .rotationEffect(.degrees(sym.angle.map { map.angle($0) } ?? 0))
            .position(x: size.width / 2 + CGFloat(dx) * size.width * 0.36,
                      y: size.height / 2 + CGFloat(dy) * size.height * 0.30)
            .transition(.opacity)
            .id(arrow.rawValue)
    }
}

/// Canvas drawing for the overlay. Kept outside the view so it has no actor isolation.
enum OverlayDraw {

    static func grid(_ ctx: inout GraphicsContext, _ r: CGRect) {
        var p = Path()
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3
            let y = r.minY + r.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 0.7)
    }

    static func brackets(_ ctx: inout GraphicsContext, _ r: CGRect, closed: Bool) {
        let l = min(r.width, r.height) * 0.22
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        ctx.stroke(p, with: .color(closed ? ES.warn : .white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if closed {
            ctx.draw(Text("eyes closed").font(ESFont.mono(10, .bold)).foregroundColor(ES.warn),
                     at: CGPoint(x: r.midX, y: r.maxY + 10))
        }
    }

    static func dashed(_ ctx: inout GraphicsContext, _ r: CGRect, color: Color) {
        let p = Path(roundedRect: r, cornerRadius: 10)
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
    }

    static func zone(_ ctx: inout GraphicsContext, _ r: CGRect) {
        let p = Path(roundedRect: r, cornerRadius: 6)
        ctx.fill(p, with: .color(ES.error.opacity(0.18)))
        ctx.stroke(p, with: .color(ES.error.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    static func mark(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        let r: CGFloat = 11
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .color(ES.signal.opacity(0.25)))
        ctx.stroke(circle, with: .color(ES.signal), lineWidth: 2)
        var x = Path()
        x.move(to: CGPoint(x: c.x - 4, y: c.y - 4)); x.addLine(to: CGPoint(x: c.x + 4, y: c.y + 4))
        x.move(to: CGPoint(x: c.x + 4, y: c.y - 4)); x.addLine(to: CGPoint(x: c.x - 4, y: c.y + 4))
        ctx.stroke(x, with: .color(ES.signal), lineWidth: 2)
    }
}

/// Fixed reference ticks plus a line that stays parallel to the real horizon.
struct LevelBar: View {
    let error: Double
    let rotation: Double

    var body: some View {
        let ok = abs(error) < 1.0
        ZStack {
            HStack(spacing: 150) {
                Capsule().fill(.white.opacity(0.6)).frame(width: 22, height: 2)
                Capsule().fill(.white.opacity(0.6)).frame(width: 22, height: 2)
            }
            Capsule()
                .fill(ok ? ES.ok : ES.warn)
                .frame(width: 140, height: 2.5)
                .rotationEffect(.degrees(-error))
            if !ok {
                Text(String(format: "%.0f°", abs(error)))
                    .font(ESFont.mono(11, .bold))
                    .foregroundStyle(.white)
                    .offset(y: 16)
            }
        }
        .rotationEffect(.degrees(rotation))
        .animation(ES.easeFast, value: ok)
    }
}
