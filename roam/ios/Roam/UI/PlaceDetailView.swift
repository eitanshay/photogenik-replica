import MapKit
import SwiftUI

struct PlaceDetailView: View {
    let placeID: String
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(Narrator.self) private var narrator
    @Environment(\.dismiss) private var dismiss
    @State private var showScript = false
    @State private var noteDraft = ""

    var body: some View {
        NavigationStack {
            if let p = model.place(placeID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let c = p.coordinate, c.isValid {
                            Map(initialPosition: .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 700, longitudinalMeters: 700))) {
                                Marker(p.name, coordinate: c.cl).tint(ES.signal)
                                UserAnnotation()
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Badge(text: p.kind.label, tone: p.kind == .saved ? .signal : .neutral)
                                if p.scenic || p.kind == .scenic { Badge(text: "photogenic", tone: .warn) }
                                if let d = model.distance(to: p) { Badge(text: "\(Geo.walkingMinutes(d)) min walk", tone: .neutral) }
                            }
                            Text(p.name).font(ESFont.h2).foregroundStyle(ES.ink).fixedSize(horizontal: false, vertical: true)
                            if let b = p.blurb, !b.isEmpty { Text(b.capitalizedFirst).font(ESFont.lead).foregroundStyle(ES.ink2) }
                            if let a = p.address { Text(a).font(ESFont.mono(12)).foregroundStyle(ES.ink3) }
                            if !p.lists.isEmpty {
                                Text(p.lists.joined(separator: " · ")).font(ESFont.mono(11)).foregroundStyle(ES.ink3)
                            }
                        }

                        HStack(spacing: 10) {
                            Button { Task { await model.listen(p.id) } } label: {
                                Label(listenTitle(p), systemImage: narrator.speakingPlaceID == p.id && !narrator.isPaused ? "pause.fill" : "headphones")
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary, size: .lg, full: true))
                            .disabled(model.isGenerating(p.id))
                            if let c = p.coordinate {
                                Button { Navigator.walk(to: c, name: p.name, using: settings.navApp) } label: {
                                    Image(systemName: "figure.walk")
                                }
                                .buttonStyle(PillButtonStyle(kind: .ink, size: .lg))
                                .accessibilityLabel("Walk there")
                            }
                        }
                        if narrator.speakingPlaceID == p.id {
                            ProgressView(value: narrator.progress).tint(ES.signal)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel("Your note")
                            TextField("Why it is on your list, what to order…", text: $noteDraft, axis: .vertical)
                                .font(ESFont.body)
                                .onSubmit { saveNote(p) }
                        }
                        .raisedSurface()

                        VStack(spacing: 0) {
                            Toggle("Photogenic spot", isOn: Binding(get: { p.scenic }, set: { v in var q = p; q.scenic = v; model.update(q) }))
                                .padding(.vertical, 6)
                            Divider().overlay(ES.lineSoft)
                            Toggle("Alerts near this place", isOn: Binding(get: { !p.muted }, set: { model.setMuted(p.id, !$0) }))
                                .padding(.vertical, 6)
                        }
                        .font(ESFont.body)
                        .tint(ES.signal)
                        .raisedSurface(padding: 14)

                        if let s = p.guideScript {
                            DisclosureGroup(isExpanded: $showScript) {
                                Text(s).font(ESFont.body).foregroundStyle(ES.ink).padding(.top, 8)
                                    .textSelection(.enabled)
                                Button("Write a new version") {
                                    var q = p
                                    q.guideScript = nil
                                    model.update(q)
                                }
                                .font(ESFont.small)
                                .padding(.top, 6)
                            } label: {
                                MonoLabel("Read the story · \(Guide.estimatedSeconds(s) / 60):\(String(format: "%02d", Guide.estimatedSeconds(s) % 60))")
                            }
                            .tint(ES.ink)
                            .raisedSurface()
                        }

                        HStack(spacing: 10) {
                            if let u = p.url { Button("Open link") { Navigator.open(u) }.buttonStyle(PillButtonStyle(kind: .secondary, size: .sm)) }
                            if p.kind != .saved {
                                Button("Save it") {
                                    var q = p
                                    q.kind = .saved
                                    q.lists = q.lists.isEmpty ? ["Added in roam"] : q.lists
                                    q.score = 1
                                    model.update(q)
                                }
                                .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                            }
                            Spacer()
                        }
                    }
                    .padding(ES.gutter)
                }
                .background(ES.base.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { saveNote(p); dismiss() } } }
                .onAppear { noteDraft = p.note ?? "" }
                .task {
                    if model.autoplayPlaceID == p.id {
                        model.autoplayPlaceID = nil
                        if narrator.speakingPlaceID != p.id { await model.listen(p.id) }
                    }
                }
            } else {
                Text("This place was removed.").font(ESFont.body).padding()
            }
        }
    }

    private func listenTitle(_ p: Place) -> String {
        if model.isGenerating(p.id) { return "Writing the story…" }
        if narrator.speakingPlaceID == p.id { return narrator.isPaused ? "Resume" : "Pause" }
        return "Listen · 2 min"
    }

    private func saveNote(_ p: Place) {
        let n = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n != (p.note ?? "") else { return }
        var q = p
        q.note = n.isEmpty ? nil : n
        model.update(q)
    }
}
