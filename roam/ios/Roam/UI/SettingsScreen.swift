import AVFoundation
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var mapsKey = ""
    @State private var claudeKey = ""
    @State private var clientID = ""
    @State private var signedIn = GoogleAccount.shared.isSignedIn
    @State private var status: String?
    @State private var working = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    KeyField(title: "Anthropic API key", placeholder: "sk-ant-…", text: $claudeKey, saved: settings.anthropicKey) {
                        settings.anthropicKey = claudeKey
                    }
                    KeyField(title: "Google Maps key", placeholder: "AIza…", text: $mapsKey, saved: settings.googleMapsKey) {
                        settings.googleMapsKey = mapsKey
                    }
                    TextField("Claude model", text: $settings.claudeModel)
                        .font(ESFont.mono(13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Keys")
                } footer: {
                    Text("Google Maps key (Places API (New) enabled): ratings and open-now for coffee and food, and accurate import. Without it roam uses Apple Maps. Anthropic key: writes the 2-minute stories and reads trip docs. Without it stories are the start of the Wikipedia article.")
                }

                Section {
                    TextField("iOS OAuth client ID", text: $clientID)
                        .font(ESFont.mono(12)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if signedIn {
                        HStack {
                            Label("Signed in to Google", systemImage: "checkmark.circle.fill").foregroundStyle(ES.ok)
                            Spacer()
                            Button("Sign out", role: .destructive) {
                                GoogleAccount.shared.signOut()
                                signedIn = false
                            }
                        }
                    } else {
                        Button(working ? "Opening Google…" : "Sign in with Google") { Task { await signIn() } }
                            .disabled(clientID.isEmpty || working)
                    }
                } header: {
                    Text("Google Docs")
                } footer: {
                    Text("Read-only access to your Drive so roam can find docs about a trip. The client ID comes from your own Google Cloud project (type iOS, bundle ID com.eitanshay.roam).")
                }

                Section {
                    if let h = settings.home {
                        LabeledContent("Home", value: String(format: "%.3f, %.3f", h.lat, h.lng))
                    }
                    Button(settings.home == nil ? "Set home to where I am now" : "Move home to where I am now") {
                        if let h = model.here { settings.home = h; status = "Home set" }
                    }
                    .disabled(model.here == nil)
                    Picker("Trip mode", selection: $settings.tripMode) {
                        ForEach(TripModeSetting.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Home and trips")
                } footer: {
                    Text("Trip mode turns on discovery alerts (sights and scenic spots). Saved places alert anywhere, but near home only once every two weeks.")
                }

                Section("Alerts") {
                    Toggle("Sights worth a look", isOn: $settings.discoveryEnabled)
                    Toggle("Scenic and photogenic spots", isOn: $settings.scenicEnabled)
                    Toggle("Discover near home too", isOn: $settings.discoverNearHome)
                    Stepper("Up to \(settings.maxDiscoveryPerDay) discovery alerts a day", value: $settings.maxDiscoveryPerDay, in: 0...10)
                    Stepper("Quiet from \(hour(settings.quietStart))", value: $settings.quietStart, in: 0...23)
                    Stepper("Quiet until \(hour(settings.quietEnd))", value: $settings.quietEnd, in: 0...23)
                    Button("Look for sights around me now") {
                        Task {
                            if let h = model.here {
                                await model.refreshDiscoveryIfNeeded(at: h, force: true)
                                model.replan(from: h)
                                status = "Updated: \(model.library.discovered.count) sights and scenic spots loaded"
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Voice", value: Narrator.bestVoice()?.name ?? "Default")
                    if !Narrator.hasHighQualityVoice {
                        Text("For a much more natural voice, download a Premium or Enhanced English voice: Settings, Accessibility, Spoken Content, Voices, English.")
                            .font(ESFont.small).foregroundStyle(ES.ink2)
                    }
                    VStack(alignment: .leading) {
                        Text("Speed").font(ESFont.small)
                        Slider(value: $settings.speechRate, in: 0.42...0.58)
                    }
                    Button("Test voice") {
                        Narrator.shared.speak("This is how your two-minute stories will sound when you walk up to a place.", placeID: "test", rate: settings.speechRate)
                    }
                } header: {
                    Text("Audio guide")
                }

                Section("Display") {
                    Toggle("Metric units", isOn: $settings.metric)
                    Picker("Walk with", selection: $settings.navApp) {
                        ForEach(NavApp.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Wikipedia language", selection: $settings.wikiLang) {
                        Text("English").tag("en")
                        Text("Local (French, Spanish…)").tag(Locale.current.language.languageCode?.identifier ?? "en")
                    }
                }

                Section("Status") {
                    LabeledContent("Saved places", value: "\(model.library.saved.count)")
                    LabeledContent("Discovered nearby", value: "\(model.library.discovered.count)")
                    LabeledContent("Geofences armed", value: "\(LocationEngine.shared.monitoredCount) of 20")
                    LabeledContent("Location", value: statusText)
                }

                if let s = status {
                    Section { Text(s).font(ESFont.small).foregroundStyle(ES.ink2) }
                }

                Section {
                    HStack {
                        LogoMark(size: 14)
                        Text("roam").font(ESFont.sans(16, .semibold))
                        Spacer()
                        ModelTag(code: "ES-11")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Settings")
            .onAppear {
                mapsKey = settings.googleMapsKey
                claudeKey = settings.anthropicKey
                clientID = settings.googleClientID
                signedIn = GoogleAccount.shared.isSignedIn
            }
        }
    }

    private var statusText: String {
        switch model.locationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using (alerts off)"
        case .denied, .restricted: return "Off"
        default: return "Not asked"
        }
    }

    private func hour(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        let d = Calendar.current.date(from: c) ?? Date()
        return d.formatted(.dateTime.hour())
    }

    private func signIn() async {
        working = true
        defer { working = false }
        settings.googleClientID = clientID.trimmingCharacters(in: .whitespaces)
        do {
            try await GoogleAccount.shared.signIn(clientID: settings.googleClientID)
            signedIn = true
            status = "Google connected"
        } catch {
            status = error.localizedDescription
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var notificationsOK = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    LogoMark(size: 18)
                    Text("roam").font(ESFont.display).foregroundStyle(ES.ink)
                }
                .padding(.top, 40)
                Text("A quiet travel companion. It taps you on the shoulder near places you saved or should see, finds the best coffee, the best food and the nearest restroom, and tells you a two-minute story about where you are standing.")
                    .font(ESFont.lead).foregroundStyle(ES.ink2)

                step(1, "Location: Always",
                     "Uses geofences and cell-tower updates, never continuous GPS. iOS asks twice: first While Using, then Always.",
                     done: model.locationStatus == .authorizedAlways,
                     action: model.locationStatus == .notDetermined ? "Allow" : "Allow Always") {
                    if model.locationStatus == .notDetermined { LocationEngine.shared.requestWhenInUse() }
                    else { LocationEngine.shared.requestAlways() }
                }
                step(2, "Notifications", "For the nudges. At most 3 discovery alerts a day, never at night.",
                     done: notificationsOK, action: "Allow") {
                    Task { notificationsOK = await Notifier.requestPermission() }
                }
                step(3, "Home", "So trip mode can switch on by itself when you are 50 km away. Set it from home, or later in Settings.",
                     done: settings.home != nil, action: "I'm home now") {
                    Task {
                        if let l = try? await LocationEngine.shared.currentLocation(maxAge: 300) {
                            model.here = l.coord
                            settings.home = l.coord
                        }
                    }
                }

                Button("Start") { settings.onboarded = true }
                    .buttonStyle(PillButtonStyle(kind: .primary, size: .lg, full: true))
                    .padding(.top, 8)
            }
            .padding(ES.gutter)
        }
        .background(ES.base.ignoresSafeArea())
        .task {
            if let l = try? await LocationEngine.shared.currentLocation(maxAge: 600) { model.here = l.coord }
        }
    }

    private func step(_ n: Int, _ title: String, _ body: String, done: Bool, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(ESFont.mono(13, .bold)).foregroundStyle(done ? ES.onSignal : ES.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(done ? ES.signal : ES.panel))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(ESFont.sans(17, .semibold)).foregroundStyle(ES.ink)
                Text(body).font(ESFont.small).foregroundStyle(ES.ink2)
                if !done {
                    Button(action, action: perform).buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                }
            }
        }
        .raisedSurface()
    }
}

/// One key per row with its own Save, so each can be set on its own; shows whether the saved value matches.
struct KeyField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let saved: String
    var save: () -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSaved: Bool { !saved.isEmpty && trimmed == saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(ESFont.small).foregroundStyle(ES.ink2)
                Spacer()
                if isSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill").font(ESFont.mono(11)).foregroundStyle(ES.ok)
                } else if !saved.isEmpty && trimmed.isEmpty {
                    Text("will remove").font(ESFont.mono(11)).foregroundStyle(ES.warn)
                }
            }
            HStack(spacing: 10) {
                SecureField(placeholder, text: $text)
                    .font(ESFont.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                Button("Save", action: save)
                    .buttonStyle(.borderless)
                    .disabled(trimmed == saved)
            }
        }
        .padding(.vertical, 4)
    }
}
