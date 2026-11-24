import SwiftUI

/// The coaching card at the bottom of the viewfinder: the one thing to do now, why, and what is next.
struct CueHUD: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let shown = session.live?.shown
        VStack(alignment: .leading, spacing: 8) {
            if !settings.showCoaching {
                EmptyView()
            } else if let c = shown?.primary {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color(c.severity)).frame(width: 8, height: 8).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.text)
                            .font(ESFont.sans(19, .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = c.detail {
                            Text(d)
                                .font(ESFont.sans(13))
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    ActorTag(actor: c.actor)
                }
                if let action = c.action {
                    Button(actionTitle(action)) { session.perform(action) }
                        .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
                }
                if let rest = shown?.secondary, !rest.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(rest) { s in
                                Text(s.text)
                                    .font(ESFont.sans(12, .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(.white.opacity(0.14)))
                            }
                        }
                    }
                }
            } else if let shown {
                HStack(spacing: 10) {
                    Circle().fill(shown.eyesClosed ? ES.warn : ES.ok).frame(width: 8, height: 8)
                    Text(shown.eyesClosed ? "Wait for open eyes" : (shown.steadyReady ? "Looks great. Take it." : "Looking good"))
                        .font(ESFont.sans(19, .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(shown.readiness)")
                        .font(ESFont.mono(13, .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Text(session.started ? "Reading the scene…" : "Starting the camera…")
                    .font(ESFont.sans(15, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES.radiusMd + 2, style: .continuous).fill(Color.black.opacity(settings.showCoaching ? 0.55 : 0)))
        .animation(ES.ease, value: shown?.primary?.id)
    }

    private func color(_ s: Severity) -> Color {
        switch s {
        case .fix: return ES.error
        case .improve: return ES.signal
        case .nice: return ES.ok
        }
    }

    private func actionTitle(_ a: CueAction) -> String {
        switch a {
        case .exposeFace: return "Expose for the face"
        case .lens(let x): return x < 1 ? "Switch to 0.5×" : "Switch to \(x == x.rounded() ? String(Int(x)) : String(x))×"
        }
    }
}

struct ActorTag: View {
    let actor: Who
    var body: some View {
        Text(actor.label)
            .font(ESFont.mono(10, .bold))
            .foregroundStyle(actor == .subject ? ES.onSignal : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(actor == .subject ? ES.signal : .white.opacity(0.18)))
    }
}

/// The AI director's answer, in place of the coaching card.
struct DirectorPanel: View {
    @Environment(CoachSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(ES.signal)
                Text("director").font(ESFont.mono(11, .bold)).foregroundStyle(.white.opacity(0.8))
                if case .ready(let a) = session.director, let r = a.rating {
                    Text("\(r)/10 now").font(ESFont.mono(11, .bold)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button { session.askDirector() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask again")
                Button { session.dismissDirector() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close director")
            }
            switch session.director {
            case .idle:
                EmptyView()
            case .thinking:
                Text("Looking at your shot…").font(ESFont.sans(16, .medium)).foregroundStyle(.white)
                SignalProgress()
            case .failed(let msg):
                Text(msg).font(ESFont.sans(15)).foregroundStyle(.white)
                if msg.localizedCaseInsensitiveContains("settings") || msg.localizedCaseInsensitiveContains("key") {
                    Button("Open Settings") { session.showSettings = true }
                        .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
                }
            case .ready(let a):
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(a.headline)
                            .font(ESFont.sans(18, .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(a.moves.enumerated()), id: \.offset) { pair in
                            let m = pair.element
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(pair.offset + 1)").font(ESFont.mono(12, .bold)).foregroundStyle(ES.signal).frame(width: 14)
                                Text(m.instruction).font(ESFont.sans(14)).foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                ActorTag(actor: m.who)
                            }
                        }
                        if !a.pose.isEmpty {
                            MonoLabel("pose", color: .white.opacity(0.6))
                            ForEach(a.pose, id: \.self) { p in
                                Text("· " + p).font(ESFont.sans(14)).foregroundStyle(.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let l = a.light { line("light", l) }
                        if let b = a.background { line("background", b) }
                        if let idea = a.idea { line("try", idea) }
                        if let lens = a.lens, session.cam.side == .back, abs(lens - session.cam.zoom) > 0.2,
                           session.cam.lenses.contains(where: { abs($0.display - lens) < 0.3 }) {
                            Button("Switch to \(lens < 1 ? "0.5" : String(Int(lens.rounded())))×") { session.perform(.lens(lens)) }
                                .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES.radiusMd + 2, style: .continuous).fill(Color.black.opacity(0.7)))
    }

    private func line(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            MonoLabel(label, color: .white.opacity(0.6))
            Text(text).font(ESFont.sans(14)).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
