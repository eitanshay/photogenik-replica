import Foundation
import MapKit

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": "roam/1.0 (personal iOS app; github.com/eitanshay)"]
        return URLSession(configuration: c)
    }()

    static func data(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await session.data(for: request)
        return data
    }

    static func data(_ url: URL) async throws -> Data {
        try await data(URLRequest(url: url))
    }
}

/// The bundled Michelin guide (about 20,000 restaurants), refreshed monthly on Wi-Fi from the open dataset.
actor MichelinStore {
    static let shared = MichelinStore()
    private var index: GridIndex<MichelinRestaurant>?

    private var refreshedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("michelin.tsv")
    }

    func near(_ c: Coordinate, radius: Double) -> [MichelinRestaurant] {
        if index == nil { load() }
        return index?.query(near: c, radius: radius).map(\.value) ?? []
    }

    private func load() {
        let text = (try? String(contentsOf: refreshedURL, encoding: .utf8))
            ?? Bundle.main.url(forResource: "michelin", withExtension: "tsv").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? ""
        index = Michelin.index(Michelin.decodeCompact(text))
    }

    /// Downloads the latest dataset if the local copy is older than 30 days. Call from a background task.
    func refreshIfStale() async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: refreshedURL.path)
        if let m = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 30 * 86_400 { return }
        guard let data = try? await Net.data(Michelin.datasetURL), let text = String(data: data, encoding: .utf8) else { return }
        let items = Michelin.parseDatasetCSV(text)
        guard items.count > 5_000 else { return }
        try? FileManager.default.createDirectory(at: refreshedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Michelin.encodeCompact(items).write(to: refreshedURL, atomically: true, encoding: .utf8)
        index = Michelin.index(items)
    }
}

/// Finds and ranks coffee, food and restrooms; discovers sights; resolves saved places to coordinates.
struct NearbyService {
    var googleKey: String

    // MARK: Coffee

    func coffee(at here: Coordinate) async throws -> [RankedVenue] {
        var venues: [Venue] = []
        if !googleKey.isEmpty {
            async let a = google(GooglePlaces.nearby(types: ["coffee_shop", "cafe"], at: here, radius: 1_600, key: googleKey))
            async let b = google(GooglePlaces.text("specialty coffee", near: here, radius: 1_600, key: googleKey))
            let (x, y) = await (a, b)
            venues = dedupe(x + y)
            if venues.isEmpty {
                // Surface a bad key rather than silently falling back.
                _ = try GooglePlaces.parse(await Net.data(GooglePlaces.nearby(types: ["cafe"], at: here, radius: 1_600, key: googleKey)))
            }
        }
        if venues.isEmpty { venues = await appleSearch(categories: [.cafe], query: "coffee", at: here, radius: 1_600) }
        return Ranker.coffee(venues, from: here)
    }

    // MARK: Food

    func food(at here: Coordinate, budget: Budget, cuisine: Cuisine) async throws -> [RankedVenue] {
        let michelin = await MichelinStore.shared.near(here, radius: 2_500).map(Venue.init(michelin:))
        var found: [Venue] = []
        if !googleKey.isEmpty {
            async let general = google(GooglePlaces.text(cuisine.searchPhrase, near: here, radius: 1_800, key: googleKey, openNow: true))
            async let popular = google(GooglePlaces.nearby(
                types: cuisine == .any ? ["restaurant"] : cuisine.googleTypes, at: here, radius: 1_800, key: googleKey))
            let (g1, g2) = await (general, popular)
            found = dedupe(g1 + g2)
            // Look up open-now for the best Michelin candidates that the area search missed.
            let filtered = michelin.filter { budget.allows($0.priceLevel) && cuisine.matches(text: ($0.cuisine ?? "") + " " + $0.name, types: []) }
            let missing = filtered.filter { m in !found.contains { Ranker.sameName($0.name, m.name) } }
                .sorted { ($0.michelin ?? .selected) > ($1.michelin ?? .selected) }
                .prefix(6)
            await withTaskGroup(of: [Venue].self) { group in
                for m in missing {
                    group.addTask {
                        await google(GooglePlaces.text(m.name, near: m.coordinate, radius: 300, key: googleKey, max: 2))
                    }
                }
                for await r in group { found += r }
            }
        } else {
            found = await appleSearch(categories: [.restaurant], query: cuisine.searchPhrase, at: here, radius: 1_800)
        }
        return Ranker.food(Ranker.merge(michelin: michelin, google: dedupe(found)), from: here, budget: budget, cuisine: cuisine)
    }

    // MARK: Restroom

    func restroom(at here: Coordinate) async -> [RankedVenue] {
        async let osm = osmRestrooms(here)
        async let refuge = refugeRestrooms(here)
        async let apple = appleSearch(categories: [.restroom], query: "public restroom", at: here, radius: 1_000)
        var all = await osm + refuge + apple
        if all.count < 3 {
            // No mapped toilets nearby: places that almost always have one.
            let proxies = await appleSearch(categories: [.library, .publicTransport, .store, .museum, .cafe],
                                            query: nil, at: here, radius: 600)
            all += proxies.map { var v = $0; v.tags["proxy"] = "1"; return v }
        }
        return Ranker.restroom(all, from: here)
    }

    // MARK: Discovery

    func discover(at here: Coordinate, lang: String, includeScenic: Bool) async -> [Place] {
        async let wiki = wikiDiscoveries(here, lang: lang)
        async let scenic: [Place] = includeScenic ? scenicSpots(here) : []
        return await wiki + scenic
    }

    private func wikiDiscoveries(_ here: Coordinate, lang: String) async -> [Place] {
        guard let d = try? await Net.data(Wikipedia.nearbyURL(here, lang: lang)) else { return [] }
        return Wikipedia.discoveries(Wikipedia.parseNearby(d), lang: lang)
    }

    private func scenicSpots(_ here: Coordinate) async -> [Place] {
        guard let d = try? await Net.data(Overpass.request(Overpass.scenicQuery(here))) else { return [] }
        return Overpass.scenicPlaces(Overpass.parse(d))
    }

    // MARK: Resolving saved places to coordinates

    /// Follows a short link (maps.app.goo.gl) to the full Google Maps URL.
    static func expand(_ url: String) async -> String {
        guard MapsLink.isShortLink(url), let u = URL(string: url) else { return url }
        var r = URLRequest(url: u)
        r.httpMethod = "GET"
        guard let (_, resp) = try? await Net.session.data(for: r), let final = resp.url?.absoluteString else { return url }
        return MapsLink.unwrapConsent(final)
    }

    /// Coordinates (and sometimes a better name) for a saved place: link first, then Google, then Apple.
    func resolve(_ p: Place, near: Coordinate?) async -> Place {
        var q = p
        q.resolveAttempts += 1
        if let u = p.url {
            let full = await Self.expand(u)
            if full != u { q.url = full }
            if let c = MapsLink.coordinate(in: full) {
                q.coordinate = c
                if q.name == "Dropped pin", let n = MapsLink.placeName(in: full) { q.name = n }
                return q
            }
            if q.name == "Dropped pin", let n = MapsLink.placeName(in: full) ?? MapsLink.queryText(in: full) { q.name = n }
        }
        let query = [p.name, p.address].compactMap { $0 }.joined(separator: ", ")
        if !googleKey.isEmpty,
           let found = await google(GooglePlaces.text(query, near: near, radius: 50_000, key: googleKey, max: 1)).first {
            q.coordinate = found.coordinate
            q.googlePlaceID = String(found.id.dropFirst(2))
            q.address = q.address ?? found.address
            return q
        }
        if let item = await Self.appleLookup(query, near: near) {
            q.coordinate = Coordinate(lat: item.placemark.coordinate.latitude, lng: item.placemark.coordinate.longitude)
            q.address = q.address ?? item.placemark.title
        }
        return q
    }

    static func appleLookup(_ query: String, near: Coordinate?) async -> MKMapItem? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.resultTypes = [.pointOfInterest, .address]
        if let n = near {
            req.region = MKCoordinateRegion(center: n.cl, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
        }
        return try? await MKLocalSearch(request: req).start().mapItems.first
    }

    // MARK: Helpers

    private func appleSearch(categories: [MKPointOfInterestCategory], query: String?, at here: Coordinate, radius: Double) async -> [Venue] {
        let items: [MKMapItem]
        if let q = query {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            req.resultTypes = .pointOfInterest
            req.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            req.region = MKCoordinateRegion(center: here.cl, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            items = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
        } else {
            let req = MKLocalPointsOfInterestRequest(center: here.cl, radius: radius)
            req.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            items = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
        }
        return items.compactMap { item in
            let c = item.placemark.coordinate
            let coord = Coordinate(lat: c.latitude, lng: c.longitude)
            guard Geo.distance(coord, here) <= radius * 1.3 else { return nil }
            return Venue(id: "apple:\(item.name ?? "")@\(c.latitude),\(c.longitude)", name: item.name ?? "Place",
                         coordinate: coord, source: .apple, address: item.placemark.title,
                         mapsURL: item.url?.absoluteString)
        }
    }

    private func osmRestrooms(_ here: Coordinate) async -> [Venue] {
        guard let d = try? await Net.data(Overpass.request(Overpass.restroomQuery(here))) else { return [] }
        return Overpass.restrooms(Overpass.parse(d))
    }

    private func refugeRestrooms(_ here: Coordinate) async -> [Venue] {
        guard let d = try? await Net.data(Refuge.url(here)) else { return [] }
        return Refuge.parse(d)
    }

    private func google(_ r: URLRequest) async -> [Venue] {
        guard let d = try? await Net.data(r) else { return [] }
        return (try? GooglePlaces.parse(d)) ?? []
    }

    private func dedupe(_ vs: [Venue]) -> [Venue] {
        var seen = Set<String>()
        return vs.filter { seen.insert($0.id).inserted }
    }
}
