import SwiftUI

struct TripsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var loading = false
    @State private var calendarAllowed = CalendarService.hasAccess

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !calendarAllowed {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Find trips in your calendar").font(ESFont.sans(17, .semibold))
                            Text("roam looks for events far from home (flights, hotels, dinners) and groups them into trips, then finds the Google Docs that mention each destination.")
                                .font(ESFont.small).foregroundStyle(ES.ink2)
                            Button("Allow calendar access") {
                                Task {
                                    calendarAllowed = await CalendarService.requestAccess()
                                    await reload()
                                }
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary, size: .sm))
                        }
                        .raisedSurface()
                    }
                    if !GoogleAccount.shared.isSignedIn {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect Google Docs").font(ESFont.sans(17, .semibold))
                            Text("Sign in to your personal Google account in Settings to see trip docs here and pull their places onto your map.")
                                .font(ESFont.small).foregroundStyle(ES.ink2)
                            Button("Open Settings") { model.sheet = .settings }.buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                        }
                        .raisedSurface()
                    }
                    if loading { SignalProgress() }
                    if let current = model.currentTrip {
                        SectionTitle(text: "You are here")
                        TripCard(trip: current, isCurrent: true)
                    }
                    let upcoming = model.trips.filter { $0.id != model.currentTrip?.id && $0.end > Date() }
                    if !upcoming.isEmpty {
                        SectionTitle(text: "Upcoming", trailing: "\(upcoming.count)")
                        ForEach(upcoming) { TripCard(trip: $0, isCurrent: false) }
                    }
                    if calendarAllowed && model.trips.isEmpty && !loading {
                        Text(settings.home == nil
                             ? "Set your home in Settings so roam can tell which events are trips."
                             : "No events more than 100 km from home in the next 60 days.")
                            .font(ESFont.small).foregroundStyle(ES.ink2).raisedSurface()
                    }
                    if GoogleAccount.shared.isSignedIn { DocSearchCard() }
                }
                .padding(ES.gutter)
            }
            .background(ES.base.ignoresSafeArea())
            .navigationTitle("Trips")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard CalendarService.hasAccess else { return }
        loading = true
        await model.loadTrips()
        loading = false
    }
}

struct TripCard: View {
    let trip: Trip
    let isCurrent: Bool
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var docs: [DriveFile]?
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trip.city).font(ESFont.h3).foregroundStyle(ES.ink)
                Spacer()
                Text(dateRange).font(ESFont.mono(11)).foregroundStyle(ES.ink3)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(trip.events.prefix(6), id: \.self) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Text(e.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(ESFont.mono(11)).foregroundStyle(ES.ink3)
                            .frame(width: 92, alignment: .leading)
                        Text(e.title).font(ESFont.small).foregroundStyle(ES.ink).lineLimit(1)
                    }
                }
            }
            if GoogleAccount.shared.isSignedIn {
                Divider().overlay(ES.lineSoft)
                if let docs = docs {
                    if docs.isEmpty {
                        Text("No Google Docs mention \(trip.city).").font(ESFont.small).foregroundStyle(ES.ink2)
                    }
                    ForEach(docs) { f in
                        DocRow(file: f, busy: busy == f.id) {
                            Task { await extract(f) }
                        }
                    }
                } else {
                    Button("Find docs about \(trip.city)") { Task { await findDocs() } }
                        .buttonStyle(PillButtonStyle(kind: .secondary, size: .sm))
                }
            }
            if let e = error { Text(e).font(ESFont.small).foregroundStyle(ES.badgeErrorFG) }
        }
        .panelSurface()
        .overlay(RoundedRectangle(cornerRadius: ES.radius2xl, style: .continuous).strokeBorder(isCurrent ? ES.signal.opacity(0.5) : .clear, lineWidth: 1.5))
        .task { if isCurrent && GoogleAccount.shared.isSignedIn && docs == nil { await findDocs() } }
    }

    private var dateRange: String {
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(trip.start.formatted(f)) to \(trip.end.formatted(f))"
    }

    private func findDocs() async {
        error = nil
        do { docs = try await GoogleAccount.shared.searchDocs(trip.city, clientID: settings.googleClientID) }
        catch { self.error = error.localizedDescription }
    }

    private func extract(_ f: DriveFile) async {
        busy = f.id
        error = nil
        defer { busy = nil }
        do {
            let n = try await model.extractPlaces(from: f, trip: trip)
            model.toast = n == 0 ? "No specific places found in \(f.name)" : "Added \(n) places from \(f.name)"
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DocRow: View {
    let file: DriveFile
    let busy: Bool
    var extract: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(ES.ink2)
            Button { Navigator.open(file.link) } label: {
                Text(file.name).font(ESFont.sans(15, .medium)).foregroundStyle(ES.ink).lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer()
            if busy { ProgressView() }
            else {
                Button("Add places", action: extract).buttonStyle(PillButtonStyle(kind: .ink, size: .sm))
            }
        }
    }
}

/// Free search across docs, for trips that are not in the calendar.
struct DocSearchCard: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var text = ""
    @State private var docs: [DriveFile] = []
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Search your docs")
            HStack {
                TextField("City or trip name", text: $text).onSubmit { Task { await search() } }
                    .font(ESFont.body)
                Button("Search") { Task { await search() } }.disabled(text.isEmpty)
            }
            ForEach(docs) { f in
                DocRow(file: f, busy: busy == f.id) {
                    Task {
                        busy = f.id
                        defer { busy = nil }
                        do {
                            let n = try await model.extractPlaces(from: f, trip: Trip(city: text, start: Date(), end: Date(), center: nil, events: []))
                            model.toast = "Added \(n) places from \(f.name)"
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let e = error { Text(e).font(ESFont.small).foregroundStyle(ES.badgeErrorFG) }
        }
        .raisedSurface()
    }

    private func search() async {
        error = nil
        do { docs = try await GoogleAccount.shared.searchDocs(text, clientID: settings.googleClientID) }
        catch { self.error = error.localizedDescription }
    }
}
