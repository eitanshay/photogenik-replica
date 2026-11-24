import SwiftUI

// MARK: - Review the last burst

struct ReviewSheet: View {
    @Environment(CoachSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let burst = session.lastBurst {
                    let current = selected ?? burst.bestIndex
                    VStack(spacing: 14) {
                        if let f = burst.frames.first(where: { $0.index == current }) {
                            Image(uiImage: f.thumbnail)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous))
                                .frame(maxHeight: .infinity)
                            HStack(spacing: 8) {
                                if f.index == burst.bestIndex { Badge(text: "best · \(burst.reason)", tone: .ok) }
                                if f.eyesClosed > 0 { Badge(text: "eyes closed", tone: .warn) }
                                if burst.savedIndices.contains(f.index) { Badge(text: "saved", tone: .signal) }
                            }
                            Button(burst.savedIndices.contains(f.index) ? "Save again" : "Save this one") {
                                Task { await session.save(frameIndex: f.index) }
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary, size: .lg, full: true))
                        }
                        if burst.frames.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(burst.frames) { f in
                                        Button { selected = f.index } label: {
                                            Image(uiImage: f.thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 64, height: 84)
                                                .clipShape(RoundedRectangle(cornerRadius: ES.radiusSm, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: ES.radiusSm, style: .continuous)
                                                        .strokeBorder(f.index == current ? ES.signal : (f.index == burst.bestIndex ? ES.ok : .clear), lineWidth: 3)
                                                )
                                                .overlay(alignment: .topTrailing) {
                                                    if f.eyesClosed > 0 {
                                                        Image(systemName: "eye.slash.fill").font(.system(size: 11)).foregroundStyle(ES.warn).padding(4)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(ES.gutter)
                } else {
                    Text("No shots yet").font(ESFont.body).foregroundStyle(ES.ink2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Last shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pose ideas

struct PoseSheet: View {
    let mode: ShootMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PoseLibrary.sets(for: mode)) { set in
                    Section(set.name) {
                        ForEach(set.tips) { tip in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.title).font(ESFont.sans(16, .semibold)).foregroundStyle(ES.ink)
                                Text(tip.how).font(ESFont.small).foregroundStyle(ES.ink2)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Pose ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var keyStatus: String?
    @State private var checking = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    SecureField("Gemini API key", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(ESFont.mono(13))
                    HStack {
                        Button("Save key") {
                            settings.geminiKey = keyDraft
                            keyStatus = keyDraft.isEmpty ? "Key removed" : "Saved to the Keychain"
                        }
                        Spacer()
                        Button(checking ? "Checking…" : "Test") { Task { await check() } }
                            .disabled(keyDraft.isEmpty || checking)
                    }
                    if let keyStatus { Text(keyStatus).font(ESFont.small).foregroundStyle(ES.ink2) }
                    Picker("Model", selection: $settings.directorModel) {
                        ForEach(DirectorModels.all, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("AI director")
                } footer: {
                    Text("Only used when you tap director: one frame goes to Gemini with the context (time, sun, tilt). Live coaching runs on the phone.")
                }

                Section("Coaching") {
                    Toggle("Show coaching", isOn: $settings.showCoaching)
                    Picker("Your better side", selection: $settings.preferredSide) {
                        Text("Either").tag(PreferredSide.either)
                        Text("Left").tag(PreferredSide.left)
                        Text("Right").tag(PreferredSide.right)
                    }
                    Picker("Speak cues", selection: $settings.voice) {
                        ForEach(VoiceMode.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Thirds grid", isOn: $settings.showGrid)
                }

                Section {
                    Picker("Burst", selection: $settings.burstCount) {
                        Text("1 shot").tag(1)
                        Text("3 shots").tag(3)
                        Text("5 shots").tag(5)
                        Text("8 shots").tag(8)
                    }
                    Toggle("Save the best automatically", isOn: $settings.autoSaveBest)
                    Toggle("Mirror selfies", isOn: $settings.mirrorSelfies)
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Each press takes a short burst and keeps the frame with open eyes and the sharpest face. All frames stay in Last shot until the next press.")
                }

                Section("About") {
                    HStack {
                        LogoMark(size: 14)
                        Text("frame").font(ESFont.sans(16, .semibold))
                        Spacer()
                        ModelTag(code: "ES-10")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear { keyDraft = settings.geminiKey }
        }
        .preferredColorScheme(.dark)
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            try await GeminiClient(apiKey: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)).checkKey()
            keyStatus = "Key works"
            settings.geminiKey = keyDraft
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
