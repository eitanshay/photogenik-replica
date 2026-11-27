import MapKit
import UIKit
import SwiftUI
import UniformTypeIdentifiers

enum PlaceFilter: String, CaseIterable, Hashable {
    case saved, attraction, scenic
    var label: String {
        switch self {
        case .saved: return "saved"
        case .attraction: return "sights"
        case .scenic: return "scenic"
        }
    }
}

struct PlacesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var filter: PlaceFilter = .saved
    @State private var query = ""
    @State private var importing = false
    @State private var adding = false
    @State private var discovering = false
    @State private var listLink = false

    private var items: [Place] {
        let q = Place.fold(query)
        return model.library.places.filter { p in
            let kindOK: Bool
            switch filter {
            case .saved: kindOK = p.kind == .saved
            case .attraction: kindOK = p.kind == .attraction
            case .scenic: kindOK = p.kind == .scenic || p.scenic
            }
            guard kindOK else { return false }
            if q.isEmpty { return true }
            return Place.fold(p.name).contains(q) || p.lists.contains { Place.fold($0).contains(q) } || Place.fold(p.note ?? "").contains(q)
        }
        .sorted { a, b in
            switch (model.distance(to: a), model.distance(to: b)) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name < b.name
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PillTabs(items: PlaceFilter.allCases.map { ($0, $0.label) }, selection: filter) { filter = $0 }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    if let s = model.importStatus {
                        HStack(spacing: 10) {
                            if model.resolving > 0 { ProgressView() }
                            Text(model.resolving > 0 ? "Finding \(model.resolving) places on the map…" : s)
                                .font(ESFont.small).foregroundStyle(ES.ink2)
                        }
                    }
                }
                Section {
                    if items.isEmpty {
                        Text(emptyText).font(ESFont.small).foregroundStyle(ES.ink2)
                        if filter != .saved {
                            Button(discovering ? "Looking around…" : "Look for sights around me now") {
                                Task {
                                    discovering = true
                                    defer { discovering = false }
                                    guard let loc = try? await LocationEngine.shared.currentLocation(maxAge: 300) else {
                                        model.toast = "Couldn't get your location"
                                        return
                                    }
                                    model.here = loc.coord
                                    await model.refreshDiscoveryIfNeeded(at: loc.coord, force: true)
                                    model.replan(from: loc.coord)
                                    let n = model.library.discovered.count
                                    model.toast = n == 0 ? "Nothing notable found within 10 km" : "Found \(n) sights and scenic spots"
                                }
                            }
                            .disabled(discovering)
                        }
                    }
                    ForEach(items.prefix(300)) { p in
                        Button { model.detailPlaceID = p.id } label: {
                            PlaceRow(place: p, distance: model.distance(to: p), metric: settings.metric)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { model.delete(p.id) } label: { Label("Delete", systemImage: "trash") }
                            Button { model.setMuted(p.id, !p.muted) } label: {
                                Label(p.muted ? "Unmute" : "Mute", systemImage: p.muted ? "bell" : "bell.slash")
                            }
                            .tint(ES.warn)
                        }
                        .opacity(p.muted ? 0.5 : 1)
                    }
                } header: {
                    MonoLabel("\(items.count) places")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ES.base.ignoresSafeArea())
            .searchable(text: $query, prompt: "Name, list or note")
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import a Google Maps list link", systemImage: "link") { listLink = true }
                        Button("Import Google Takeout files", systemImage: "square.and.arrow.down") { importing = true }
                        Button("Add a place", systemImage: "plus") { adding = true }
                    } label: { Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(ES.signal) }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await model.importFiles(urls) } }
            }
            .sheet(isPresented: $adding) { AddPlaceSheet() }
            .sheet(isPresented: $listLink) { ListLinkSheet().presentationDetents([.medium]) }
        }
    }

    private var importTypes: [UTType] {
        [.commaSeparatedText, .json] + [UTType(filenameExtension: "geojson")].compactMap { $0 }
    }

    private var emptyText: String {
        switch filter {
        case .saved: return "Fastest: in Google Maps open Saved, pick a list, Share, and choose roam (or copy the link and use + then Import a Google Maps list link). Or import your Google Maps lists: takeout.google.com, select only \"Saved\" (and \"Maps (your places)\" for starred places), unzip in Files, then tap + and pick the CSV files. New places: share them from Google Maps to roam."
        case .attraction: return "Sights appear here as you travel (Wikipedia articles about places within 10 km)."
        case .scenic: return "Viewpoints, waterfalls, lighthouses and gardens near you appear here on trips. Flag any saved place as scenic from its page."
        }
    }
}

struct AddPlaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Place name or Google Maps link", text: $text)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await search() } }
                    TextField("Note (optional)", text: $note)
                }
                if searching { ProgressView() }
                ForEach(results, id: \.self) { item in
                    Button {
                        let c = item.placemark.coordinate
                        model.addManual(name: item.name ?? text, at: Coordinate(lat: c.latitude, lng: c.longitude), note: note.isEmpty ? nil : note)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place").font(ESFont.sans(16, .semibold))
                            Text(item.placemark.title ?? "").font(ESFont.small).foregroundStyle(ES.ink2)
                        }
                    }
                }
                Section {
                    Button("Save my current spot") {
                        model.addManual(name: text.isEmpty ? "Pinned spot" : text, at: model.here, note: note.isEmpty ? nil : note)
                        dismiss()
                    }
                    .disabled(model.here == nil)
                }
            }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Search") { Task { await search() } }.disabled(text.isEmpty) }
            }
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        if text.hasPrefix("http") {
            let full = await NearbyService.expand(text)
            if GoogleList.listID(in: full) != nil {
                model.toast = await model.importGoogleList(text)
                dismiss()
                return
            }
            if let c = MapsLink.coordinate(in: full) {
                model.addManual(name: MapsLink.placeName(in: full) ?? "Shared place", at: c, note: note.isEmpty ? nil : note)
                dismiss()
                return
            }
        }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        if let h = model.here { req.region = MKCoordinateRegion(center: h.cl, latitudinalMeters: 50_000, longitudinalMeters: 50_000) }
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }
}

struct ListLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var status: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://maps.app.goo.gl/…", text: $link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(ESFont.mono(13))
                    Button("Paste") { link = UIPasteboard.general.string ?? link }
                } footer: {
                    Text("In Google Maps: Saved, open a list, Share, Copy link. The list has to be shared by link. Re-importing a list later adds new places and keeps your notes.")
                }
                if working { ProgressView() }
                if let s = status { Text(s).font(ESFont.small) }
            }
            .navigationTitle("Import a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        Task {
                            working = true
                            status = await model.importGoogleList(link)
                            working = false
                        }
                    }
                    .disabled(link.isEmpty || working)
                }
            }
        }
    }
}
