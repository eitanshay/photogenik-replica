import SwiftUI

/// The X100VI settings card at the bottom of the viewfinder: the three dials big, then the switches,
/// focus, the recipe and the first warning. Tap for the full plan.
struct FujiCard: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.showCoaching, let cue = session.live?.shown.primary, cue.severity != .nice {
                HStack(spacing: 8) {
                    Circle().fill(cue.severity == .fix ? ES.error : ES.signal).frame(width: 7, height: 7)
                    Text(cue.text).font(ESFont.sans(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    ActorTag(actor: cue.actor)
                }
            }
            if let p = session.fujiPlan {
                Button { session.showFujiDetail = true } label: { planBody(p) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the full X100VI plan")
            } else {
                Text("Metering the light…")
                    .font(ESFont.sans(15, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES.radiusMd + 2, style: .continuous).fill(Color.black.opacity(0.62)))
    }

    @ViewBuilder
    private func planBody(_ p: FujiPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                dial(FujiFormat.aperture(p.aperture), "aperture")
                dial(FujiFormat.shutter(p.shutter), "shutter")
                dial("\(p.iso)", "ISO")
                Spacer(minLength: 0)
                Button { session.toggleFujiLock() } label: {
                    Image(systemName: session.fujiLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(session.fujiLocked ? ES.onSignal : .white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(session.fujiLocked ? ES.signal : .white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.fujiLocked ? "Unlock the plan" : "Hold this plan")
            }
            HStack(spacing: 6) {
                if p.nd { tag("ND on", strong: true) }
                tag(p.shutterKind == .mechanical ? "MS" : "ES", strong: p.shutterKind == .electronic)
                if p.compensation != 0 { tag("\(FujiFormat.compensation(p.compensation)) EV", strong: true) }
                tag("DR\(p.dynamicRange)", strong: false)
                tag(p.recipe.simulation, strong: false)
                if p.flash != nil { tag("flash", strong: true) }
            }
            Text(p.focus + (p.depthOfField.map { "  ·  sharp \(FujiFormat.meters($0.near)) to \(FujiFormat.meters($0.far))" } ?? ""))
                .font(ESFont.sans(12))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
            if let w = p.warnings.first {
                Text(w).font(ESFont.sans(12, .medium)).foregroundStyle(ES.warn).lineLimit(2)
            }
        }
    }

    private func dial(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(ESFont.mono(22, .bold)).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(ESFont.mono(9, .medium)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func tag(_ text: String, strong: Bool) -> some View {
        Text(text)
            .font(ESFont.mono(10, .bold))
            .foregroundStyle(strong ? ES.onSignal : .white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(strong ? ES.signal : .white.opacity(0.15)))
    }
}

/// 35 / 50 / 70 mm: the lens and the two digital teleconverter crops.
struct FujiCropChips: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FujiCrop.allCases) { c in
                let on = settings.fujiCrop == c
                Button { session.setFujiCrop(c) } label: {
                    Text("\(c.rawValue)")
                        .font(ESFont.mono(on ? 12 : 11, .bold))
                        .foregroundStyle(on ? ES.signal : .white)
                        .frame(width: on ? 40 : 34, height: on ? 40 : 34)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c == .mm35 ? "35 millimetre, the lens" : "\(c.rawValue) millimetre teleconverter")
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .animation(ES.ease, value: settings.fujiCrop)
    }
}

/// Everything behind the card: each setting, why, how to dial it in, focus, flash and the full recipe.
struct FujiDetailSheet: View {
    @Environment(CoachSession.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let p = session.fujiPlan {
                    Section {
                        row("Aperture ring", FujiFormat.aperture(p.aperture))
                        row("Shutter", "\(FujiFormat.shutter(p.shutter)) · \(p.shutterKind.label)")
                        row("ISO dial", "\(p.iso)")
                        row("ND filter", p.nd ? "On (4 stops)" : "Off")
                        row("Exposure comp dial", FujiFormat.compensation(p.compensation))
                        row("Metering", p.metering)
                        row("Focus", p.focus)
                        if let d = p.depthOfField, let dist = p.subjectDistance {
                            row("Depth of field", "At \(FujiFormat.meters(dist)): \(FujiFormat.meters(d.near)) to \(FujiFormat.meters(d.far))")
                        }
                        row("Framing", p.crop == .mm35 ? "35mm (no teleconverter)" : "Digital teleconverter \(p.crop.label)")
                        if let f = p.flash { row("Flash", f) }
                    } header: {
                        Text("Set on the X100VI · \(p.intent.label) · scene EV \(String(format: "%.1f", p.ev100))")
                    } footer: {
                        Text("Shutter: set the dial to the nearest full stop, then fine-tune thirds with the rear command dial. EV is measured by the iPhone and is usually within about a stop of the X100VI's meter, so check the histogram on the first frame.")
                    }

                    if !p.warnings.isEmpty {
                        Section("Watch out") {
                            ForEach(p.warnings, id: \.self) { w in
                                Text(w).font(ESFont.body).foregroundStyle(ES.warn)
                            }
                        }
                    }

                    Section("Why") {
                        ForEach(p.reasons, id: \.self) { r in
                            Text(r).font(ESFont.body).foregroundStyle(ES.ink)
                        }
                    }

                    Section {
                        Picker("Look", selection: Binding(get: { settings.fujiLook }, set: { session.setFujiLook($0) })) {
                            ForEach(FujiLook.allCases) { Text($0.label).tag($0) }
                        }
                        ForEach(Array(p.recipe.rows(effectiveDR: p.dynamicRange).enumerated()), id: \.offset) { item in
                            row(item.element.0, item.element.1)
                        }
                    } header: {
                        Text("Film recipe · \(p.recipe.name)")
                    } footer: {
                        Text(p.recipe.why + " Save it once to a custom slot (C1 to C7) and recall it from the Q menu.")
                    }
                } else {
                    Text("Point the phone at the scene to meter the light.").font(ESFont.body).foregroundStyle(ES.ink2)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("X100VI plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(session.fujiLocked ? "Unlock" : "Hold") { session.toggleFujiLock() }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(ESFont.small).foregroundStyle(ES.ink2)
            Spacer(minLength: 12)
            Text(value).font(ESFont.mono(13, .medium)).foregroundStyle(ES.ink).multilineTextAlignment(.trailing)
        }
    }
}
