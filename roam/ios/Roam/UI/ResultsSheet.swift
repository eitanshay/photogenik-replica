import SwiftUI

struct ResultsSheet: View {
    let need: Need
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var results: [RankedVenue] = []
    @State private var loading = true
    @State private var error: String?
    @State private var budget: Budget = .mid
    @State private var cuisine: Cuisine = .any
    @State private var origin: Coordinate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if need == .food { filters }
                    if loading {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loadingText).font(ESFont.small).foregroundStyle(ES.ink2)
                            SignalProgress()
                        }
                        .raisedSurface()
                    } else if let e = error {
                        Text(e).font(ESFont.small).foregroundStyle(ES.badgeErrorFG).raisedSurface()
                    } else if results.isEmpty {
                        Text(emptyText).font(ESFont.small).foregroundStyle(ES.ink2).raisedSurface()
                    } else {
                        if let best = results.first { BestCard(r: best, need: need, metric: settings.metric) { go(best) } }
                        if results.count > 1 {
                            SectionTitle(text: "Other options")
                            VStack(spacing: 0) {
                                ForEach(results.dropFirst().prefix(9)) { r in
                                    Button { go(r) } label: { VenueRow(r: r, metric: settings.metric).padding(.vertical, 10) }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Save to roam", systemImage: "bookmark") { save(r) }
                                            if let u = r.venue.mapsURL { Button("Open in Google Maps", systemImage: "map") { Navigator.open(u) } }
                                            if let u = r.venue.michelinURL, !u.isEmpty { Button("Michelin Guide page", systemImage: "star") { Navigator.open(u) } }
                                        }
                                    if r.id != results.dropFirst().prefix(9).last?.id { Divider().overlay(ES.lineSoft) }
                                }
                            }
                            .raisedSurface(padding: 14)
                        }
                        footnote
                    }
                }
                .padding(ES.gutter)
            }
            .background(ES.base.ignoresSafeArea())
            .navigationTitle(need.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                budget = Budget(rawValue: settings.lastBudget) ?? .mid
                cuisine = Cuisine(rawValue: settings.lastCuisine) ?? .any
                await load()
            }
        }
    }

    private var loadingText: String {
        switch need {
        case .coffee: return "Finding the best coffee within a walk…"
        case .food: return "Checking the Michelin Guide and what is open…"
        case .restroom: return "Finding the nearest restroom…"
        }
    }

    private var emptyText: String {
        switch need {
        case .coffee: return settings.hasGoogleKey ? "No well-rated coffee open within a 20-minute walk." : "Nothing found nearby. Add a Google Maps key in Settings for ratings and opening hours."
        case .food: return "Nothing open that matches. Try another budget or cuisine."
        case .restroom: return "No mapped restrooms nearby. Hotels, department stores and stations usually have one."
        }
    }

    private var footnote: some View {
        Text(need == .coffee ? "Ranked by rating weighted by review count, with a boost for specialty roasters and chains last. Closed places are hidden."
             : need == .food ? "Michelin Guide first (Bib Gourmand for $ and $$, stars for $$$), then places with strong ratings. Closed places are hidden."
             : "Nearest first. Places that usually have a restroom (libraries, stations, cafes) are a fallback.")
            .font(ESFont.mono(10)).foregroundStyle(ES.ink3)
            .padding(.horizontal, 4)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            PillTabs(items: Budget.allCases.map { ($0, $0.label) }, selection: budget) { b in
                budget = b
                settings.lastBudget = b.rawValue
                Task { await load() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Cuisine.allCases, id: \.self) { c in
                        TagChip(title: c.label, selected: c == cuisine) {
                            cuisine = c
                            settings.lastCuisine = c.rawValue
                            Task { await load() }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let loc = try await LocationEngine.shared.currentLocation(maxAge: 45)
            let here = loc.coord
            origin = here
            model.here = here
            let service = NearbyService(googleKey: settings.googleMapsKey)
            switch need {
            case .coffee: results = try await service.coffee(at: here)
            case .food: results = try await service.food(at: here, budget: budget, cuisine: cuisine)
            case .restroom: results = await service.restroom(at: here)
            }
        } catch {
            self.error = error.localizedDescription
            results = []
        }
    }

    private func go(_ r: RankedVenue) {
        Navigator.walk(to: r.venue.coordinate, name: r.venue.name, using: settings.navApp)
    }

    private func save(_ r: RankedVenue) {
        model.addManual(name: r.venue.name, at: r.venue.coordinate, note: r.reason)
        model.toast = "Saved \(r.venue.name)"
    }
}

struct BestCard: View {
    let r: RankedVenue
    let need: Need
    let metric: Bool
    var go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoLabel(need == .restroom ? "Nearest" : "Best pick", color: ES.badgeSignalFG)
                Spacer()
                if let a = r.venue.michelin { Badge(text: a.short == "BIB" ? "bib gourmand" : a.short, tone: .signal) }
                if r.venue.openNow == true { Badge(text: "open", tone: .ok) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(r.venue.name).font(ESFont.h3).foregroundStyle(ES.ink).fixedSize(horizontal: false, vertical: true)
                Text(r.reason).font(ESFont.small).foregroundStyle(ES.ink2)
                if let a = r.venue.address { Text(a).font(ESFont.mono(11)).foregroundStyle(ES.ink3).lineLimit(2) }
            }
            Button(action: go) {
                Label("Walk there · \(r.walkMinutes) min (\(Geo.formatDistance(r.distance, metric: metric)))", systemImage: "figure.walk")
            }
            .buttonStyle(PillButtonStyle(kind: .primary, size: .lg, full: true))
        }
        .panelSurface()
        .overlay(RoundedRectangle(cornerRadius: ES.radius2xl, style: .continuous).strokeBorder(ES.signal.opacity(0.5), lineWidth: 1.5))
    }
}

struct VenueRow: View {
    let r: RankedVenue
    let metric: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.venue.name).font(ESFont.sans(16, .semibold)).foregroundStyle(ES.ink).lineLimit(1)
                    if let a = r.venue.michelin { Text(a.short).font(ESFont.mono(10, .bold)).foregroundStyle(ES.badgeSignalFG) }
                }
                Text(r.reason).font(ESFont.small).foregroundStyle(ES.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(r.walkMinutes) min").font(ESFont.mono(12, .bold)).foregroundStyle(ES.ink)
                Text(Geo.formatDistance(r.distance, metric: metric)).font(ESFont.mono(11)).foregroundStyle(ES.ink3)
            }
        }
        .contentShape(Rectangle())
    }
}
