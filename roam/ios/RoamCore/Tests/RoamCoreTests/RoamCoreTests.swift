import XCTest
@testable import RoamCore

final class GeoTests: XCTestCase {
    let sf = Coordinate(lat: 37.7749, lng: -122.4194)
    let oak = Coordinate(lat: 37.8044, lng: -122.2712)

    func testDistanceSFToOakland() {
        XCTAssertEqual(Geo.distance(sf, oak), 13_400, accuracy: 300)
    }

    func testWalkingMinutes() {
        XCTAssertEqual(Geo.walkingMinutes(800), 13)
        XCTAssertEqual(Geo.walkingMinutes(10), 1)
    }

    func testFormatDistance() {
        XCTAssertEqual(Geo.formatDistance(420, metric: true), "420 m")
        XCTAssertEqual(Geo.formatDistance(2_400, metric: true), "2.4 km")
        XCTAssertEqual(Geo.formatDistance(100, metric: false), "330 ft")
        XCTAssertEqual(Geo.formatDistance(3_219, metric: false), "2.0 mi")
    }

    func testCompass() {
        XCTAssertEqual(Geo.compass(0), "N")
        XCTAssertEqual(Geo.compass(350), "N")
        XCTAssertEqual(Geo.compass(95), "E")
        XCTAssertEqual(Geo.compass(225), "SW")
    }

    func testOffsetRoundTrip() {
        let o = Geo.offset(sf, north: 1000, east: 0)
        XCTAssertEqual(Geo.distance(sf, o), 1000, accuracy: 2)
    }

    func testGridIndexQuery() {
        var g = GridIndex<String>(cellDegrees: 0.05)
        g.insert("near", at: Geo.offset(sf, north: 300, east: 0))
        g.insert("mid", at: Geo.offset(sf, north: 0, east: 4_000))
        g.insert("far", at: oak)
        let r = g.query(near: sf, radius: 5_000)
        XCTAssertEqual(r.map(\.value), ["near", "mid"])
    }

    func testInvalidCoordinates() {
        XCTAssertFalse(Coordinate(lat: 0, lng: 0).isValid)
        XCTAssertFalse(Coordinate(lat: 91, lng: 0).isValid)
        XCTAssertTrue(sf.isValid)
    }
}

final class ImportTests: XCTestCase {
    func testCSVQuotesAndNewlines() {
        let rows = CSV.parse("a,b,c\r\n\"x, y\",\"he said \"\"hi\"\"\",\"line1\nline2\"\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], ["x, y", "he said \"hi\"", "line1\nline2"])
    }

    func testCSVBOMAndBlankRows() {
        let recs = CSV.records("\u{FEFF}Title,Note,URL\n,,\nCafe,,https://x\n")
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0]["title"], "Cafe")
    }

    func testCoordinateFromPinData() {
        let u = "https://www.google.com/maps/place/Tartine+Bakery/@37.7614,-122.4241,17z/data=!3m1!4b1!4m6!3m5!1s0x808f7e3dadc07a37:0xc86b0ff2d6537d5!8m2!3d37.761426!4d-122.42405!16s"
        let c = MapsLink.coordinate(in: u)
        XCTAssertEqual(c?.lat ?? 0, 37.761426, accuracy: 1e-6)
        XCTAssertEqual(c?.lng ?? 0, -122.42405, accuracy: 1e-6)
        XCTAssertEqual(MapsLink.placeName(in: u), "Tartine Bakery")
    }

    func testCoordinateFromViewportAndQuery() {
        XCTAssertEqual(MapsLink.coordinate(in: "https://www.google.com/maps/@38.7139,-9.1334,15z")?.lat ?? 0, 38.7139, accuracy: 1e-6)
        XCTAssertEqual(MapsLink.coordinate(in: "https://maps.google.com/?q=48.8584,2.2945")?.lng ?? 0, 2.2945, accuracy: 1e-6)
        XCTAssertEqual(MapsLink.coordinate(in: "https://www.google.com/maps/search/41.40363,+2.17436")?.lat ?? 0, 41.40363, accuracy: 1e-6)
        XCTAssertNil(MapsLink.coordinate(in: "https://www.google.com/maps/place/Somewhere"))
        XCTAssertNil(MapsLink.coordinate(in: "https://www.google.com/maps/search/?api=1&query=Blue+Bottle&query_place_id=ChIJ"))
    }

    func testQueryTextAndConsent() {
        XCTAssertEqual(MapsLink.queryText(in: "https://www.google.com/search?q=Bar+Tomate+Madrid"), "Bar Tomate Madrid")
        let consent = "https://consent.google.com/m?continue=https://www.google.com/maps/place/X/@1.5,2.5,17z&gl=DE"
        XCTAssertTrue(MapsLink.unwrapConsent(consent).hasPrefix("https://www.google.com/maps/place/X"))
        XCTAssertTrue(MapsLink.isShortLink("https://maps.app.goo.gl/AbC123"))
    }

    func testShareText() {
        let s = MapsLink.parseShareText("Time Out Market Lisboa\nAv. 24 de Julho 49, 1200-479 Lisboa, Portugal\nhttps://maps.app.goo.gl/q8Yh2")
        XCTAssertEqual(s.name, "Time Out Market Lisboa")
        XCTAssertEqual(s.address, "Av. 24 de Julho 49, 1200-479 Lisboa, Portugal")
        XCTAssertEqual(s.url, "https://maps.app.goo.gl/q8Yh2")
        XCTAssertNil(MapsLink.parseShareText("https://maps.app.goo.gl/q8Yh2").name)
    }

    func testTakeoutListCSV() {
        let csv = """
        Title,Note,URL,Tags,Comment
        ,,,,
        Pastéis de Belém,Get 6,https://www.google.com/maps/place/Past%C3%A9is+de+Bel%C3%A9m/data=!4m2!3m1!1s0xd1ecb!8m2!3d38.6975!4d-9.2032,,
        Cervejaria Ramiro,,https://www.google.com/search?q=Cervejaria+Ramiro,,"order the clams"
        """
        let ps = Takeout.parseListCSV(csv, listName: "Lisbon")
        XCTAssertEqual(ps.count, 2)
        XCTAssertEqual(ps[0].name, "Pastéis de Belém")
        XCTAssertEqual(ps[0].note, "Get 6")
        XCTAssertEqual(ps[0].coordinate?.lat ?? 0, 38.6975, accuracy: 1e-6)
        XCTAssertNil(ps[1].coordinate)
        XCTAssertEqual(ps[1].note, "order the clams")
        XCTAssertEqual(ps[1].lists, ["Lisbon"])
    }

    func testTakeoutCSVTitleFromURL() {
        let ps = Takeout.parseListCSV("Title,Note,URL,Comment\n,,https://www.google.com/maps/place/Blue+Bottle+Coffee/data=!4m2,\n", listName: "x")
        XCTAssertEqual(ps.first?.name, "Blue Bottle Coffee")
    }

    func testSavedPlacesGeoJSONNewAndOld() throws {
        let json = """
        {"type":"FeatureCollection","features":[
         {"geometry":{"coordinates":[-122.4241,37.7614],"type":"Point"},"properties":{"date":"2023-01-01T00:00:00Z","google_maps_url":"http://maps.google.com/?cid=123","location":{"address":"600 Guerrero St","name":"Tartine Bakery"}},"type":"Feature"},
         {"geometry":{"coordinates":[0,0],"type":"Point"},"properties":{"google_maps_url":"http://maps.google.com/?q=Sightglass","location":{"name":"Sightglass"}},"type":"Feature"},
         {"geometry":{"coordinates":[2.2945,48.8584],"type":"Point"},"properties":{"Title":"Eiffel Tower","Location":{"Address":"Paris"}},"type":"Feature"}
        ]}
        """
        let ps = Takeout.parseSavedPlacesJSON(Data(json.utf8))
        XCTAssertEqual(ps.map(\.name), ["Tartine Bakery", "Sightglass", "Eiffel Tower"])
        XCTAssertTrue(ps[0].isResolved)
        XCTAssertFalse(ps[1].isResolved)
        XCTAssertEqual(ps[2].address, "Paris")
    }

    func testListName() {
        XCTAssertEqual(Takeout.listName(fromFileName: "Want to go.csv"), "Want to go")
    }
}

final class LibraryTests: XCTestCase {
    func testUpsertMergesSameNameNearby() {
        var lib = PlaceLibrary()
        let c = Coordinate(lat: 38.7, lng: -9.14)
        lib.upsert(Place(name: "Café A Brasileira", coordinate: c, lists: ["Lisbon"]))
        lib.upsert(Place(name: "Cafe a Brasileira", coordinate: Geo.offset(c, north: 40, east: 0), lists: ["Coffee"], note: "go early"))
        XCTAssertEqual(lib.places.count, 1)
        XCTAssertEqual(lib.places[0].lists, ["Lisbon", "Coffee"])
        XCTAssertEqual(lib.places[0].note, "go early")
    }

    func testSamePlaceNameFarApartStaysSeparate() {
        var lib = PlaceLibrary()
        lib.upsert(Place(name: "Blue Bottle", coordinate: Coordinate(lat: 37.78, lng: -122.4)))
        lib.upsert(Place(name: "Blue Bottle", coordinate: Coordinate(lat: 40.7, lng: -74.0)))
        XCTAssertEqual(lib.places.count, 2)
    }

    func testSavedWinsOverDiscovered() {
        var lib = PlaceLibrary()
        let c = Coordinate(lat: 48.8584, lng: 2.2945)
        lib.upsert(Place(name: "Eiffel Tower", coordinate: c, kind: .attraction, source: .wikipedia, wikipediaTitle: "Eiffel Tower", wikipediaLang: "en", score: 0.9))
        lib.upsert(Place(name: "Eiffel Tower", coordinate: c, kind: .saved, source: .takeout, lists: ["Paris"]))
        XCTAssertEqual(lib.places.count, 1)
        XCTAssertEqual(lib.places[0].kind, .saved)
        XCTAssertEqual(lib.places[0].wikipediaTitle, "Eiffel Tower")
    }

    func testUnresolvedGetsCoordinateFromLaterImport() {
        var lib = PlaceLibrary()
        lib.upsert(Place(name: "Sightglass"))
        lib.upsert(Place(name: "Sightglass", coordinate: Coordinate(lat: 37.77, lng: -122.41)))
        XCTAssertEqual(lib.places.count, 1)
        XCTAssertTrue(lib.places[0].isResolved)
    }

    func testUpsertManyMergesAndCounts() {
        var lib = PlaceLibrary(places: [Place(id: "gmap:1", name: "Cafe A", coordinate: Coordinate(lat: 19.43, lng: -99.19), lists: ["Want to go"])])
        let incoming = [
            Place(id: "gmap:1", name: "Cafe A", coordinate: Coordinate(lat: 19.43, lng: -99.19), lists: ["Favorites"]),
            Place(id: "gmap:2", name: "Taqueria", coordinate: Coordinate(lat: 19.41, lng: -99.18), lists: ["Favorites"]),
            Place(name: "cafe a", coordinate: Coordinate(lat: 19.4301, lng: -99.19), lists: ["Coffee"])
        ]
        XCTAssertEqual(lib.upsertMany(incoming), 1)
        XCTAssertEqual(lib.places.count, 2)
        XCTAssertEqual(lib.places[0].lists, ["Want to go", "Favorites", "Coffee"])
        XCTAssertEqual(lib.upsertMany(incoming), 0)
    }

    func testPruneKeepsSavedAndMuted() {
        let home = Coordinate(lat: 37.44, lng: -122.14)
        let far = Coordinate(lat: 38.72, lng: -9.14)
        var lib = PlaceLibrary(places: [
            Place(name: "A", coordinate: far, kind: .attraction),
            Place(name: "B", coordinate: far, kind: .saved),
            Place(name: "C", coordinate: far, kind: .scenic, muted: true),
            Place(name: "D", coordinate: home, kind: .attraction)
        ])
        lib.pruneDiscovered(around: home)
        XCTAssertEqual(Set(lib.places.map(\.name)), ["B", "C", "D"])
    }

    func testFileStoreInbox() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PlaceFileStore(directory: dir)
        store.appendToInbox(Place(name: "From share", source: .share))
        store.appendToInbox(Place(name: "Second", source: .share))
        var lib = store.loadLibrary()
        XCTAssertEqual(store.drainInbox(into: &lib).count, 2)
        store.save(lib)
        XCTAssertEqual(store.loadLibrary().places.count, 2)
        XCTAssertTrue(store.readInbox().isEmpty)
    }
}

final class MichelinTests: XCTestCase {
    func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "michelin_sample", withExtension: "csv", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParseDataset() throws {
        let items = Michelin.parseDatasetCSV(try fixture())
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[1].name, "ABaC")
        XCTAssertEqual(items[1].award, .star3)
        XCTAssertEqual(items[1].price, 4)
    }

    func testCompactRoundTrip() throws {
        let items = Michelin.parseDatasetCSV(try fixture())
        let back = Michelin.decodeCompact(Michelin.encodeCompact(items))
        XCTAssertEqual(back.count, items.count)
        XCTAssertEqual(back[0].name, items[0].name)
        XCTAssertEqual(back[0].coordinate.lat, items[0].coordinate.lat, accuracy: 1e-5)
    }

    func testAwardAndPrice() {
        XCTAssertEqual(MichelinAward(text: "Bib Gourmand"), .bib)
        XCTAssertEqual(MichelinAward(text: "2 Stars"), .star2)
        XCTAssertNil(MichelinAward(text: ""))
        XCTAssertEqual(Michelin.priceLevel("€€€"), 3)
        XCTAssertEqual(Michelin.priceLevel(""), 2)
    }
}

final class RankingTests: XCTestCase {
    let here = Coordinate(lat: 38.7100, lng: -9.1400)

    func venue(_ name: String, north: Double, rating: Double? = nil, count: Int? = nil, price: Int? = nil,
               types: [String] = [], open: Bool? = true, michelin: MichelinAward? = nil, cuisine: String? = nil,
               source: VenueSource = .google, tags: [String: String] = [:]) -> Venue {
        Venue(id: name, name: name, coordinate: Geo.offset(here, north: north, east: 0), source: source, rating: rating,
              ratingCount: count, priceLevel: price, types: types, openNow: open, michelin: michelin, cuisine: cuisine, tags: tags)
    }

    func testBayesPullsSmallCounts() {
        XCTAssertLessThan(Ranker.bayes(rating: 5.0, count: 3, priorMean: 4.3, priorWeight: 60), 4.4)
        XCTAssertGreaterThan(Ranker.bayes(rating: 4.8, count: 2_000, priorMean: 4.3, priorWeight: 60), 4.78)
    }

    func testCoffeePrefersBestOverNearest() {
        let list = [
            venue("Starbucks", north: 50, rating: 4.1, count: 900),
            venue("Fábrica Coffee Roasters", north: 700, rating: 4.7, count: 2_100),
            venue("Tiny Perfect Cafe", north: 100, rating: 5.0, count: 4),
            venue("Closed Gem", north: 100, rating: 4.9, count: 900, open: false)
        ]
        let r = Ranker.coffee(list, from: here)
        XCTAssertEqual(r.first?.venue.name, "Fábrica Coffee Roasters")
        XCTAssertFalse(r.contains { $0.venue.name == "Closed Gem" })
        XCTAssertFalse(r.contains { $0.venue.name == "Tiny Perfect Cafe" })
        XCTAssertEqual(r.last?.venue.name, "Starbucks")
    }

    func testCoffeeDropsTooFar() {
        let r = Ranker.coffee([venue("Far", north: 3_000, rating: 4.9, count: 500)], from: here)
        XCTAssertTrue(r.isEmpty)
    }

    func testFoodBibFirstForMidBudget() {
        let list = [
            venue("Belcanto", north: 400, price: 4, open: nil, michelin: .star2, cuisine: "Creative", source: .michelin),
            venue("Taberna da Rua das Flores", north: 600, price: 2, open: nil, michelin: .bib, cuisine: "Portuguese", source: .michelin),
            venue("Popular Spot", north: 100, rating: 4.6, count: 3_000, price: 2, types: ["restaurant"])
        ]
        let mid = Ranker.food(list, from: here, budget: .mid, cuisine: .any)
        XCTAssertEqual(mid.first?.venue.name, "Taberna da Rua das Flores")
        XCTAssertFalse(mid.contains { $0.venue.name == "Belcanto" })
        let high = Ranker.food(list, from: here, budget: .high, cuisine: .any)
        XCTAssertEqual(high.first?.venue.name, "Belcanto")
    }

    func testFoodCuisineFilter() {
        let list = [
            venue("Sushi Bar", north: 200, rating: 4.5, count: 400, price: 2, types: ["japanese_restaurant"]),
            venue("Kanazawa", north: 300, price: 3, open: nil, michelin: .selected, cuisine: "Japanese", source: .michelin),
            venue("Pizza Place", north: 100, rating: 4.7, count: 900, price: 1, types: ["pizza_restaurant"])
        ]
        let r = Ranker.food(list, from: here, budget: .any, cuisine: .japanese)
        XCTAssertEqual(Set(r.map(\.venue.name)), ["Sushi Bar", "Kanazawa"])
    }

    func testRestroomNearestWithProxyPenalty() {
        let list = [
            venue("Station toilets", north: 300, source: .osm),
            venue("Cafe (proxy)", north: 150, source: .apple, tags: ["proxy": "1"]),
            venue("Private", north: 50, source: .osm, tags: ["access": "private"]),
            venue("Dup of station", north: 310, source: .apple)
        ]
        let r = Ranker.restroom(list, from: here)
        XCTAssertEqual(r.first?.venue.name, "Station toilets")
        XCTAssertFalse(r.contains { $0.venue.name == "Private" })
        XCTAssertEqual(r.count, 2)
    }

    func testMergeMichelinWithGoogle() {
        let m = venue("Taberna da Rua das Flores", north: 600, price: 2, open: nil, michelin: .bib, source: .michelin)
        let g = venue("Taberna da Rua das Flores", north: 620, rating: 4.6, count: 2_000, open: true)
        let other = venue("Other", north: 10, rating: 4.0, count: 50)
        let merged = Ranker.merge(michelin: [m], google: [g, other])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].openNow, true)
        XCTAssertEqual(merged[0].michelin, .bib)
    }

    func testSameName() {
        XCTAssertTrue(Ranker.sameName("Café de Flore", "Cafe de Flore"))
        XCTAssertTrue(Ranker.sameName("Tasca do Chico", "A Tasca do Chico Fado"))
        XCTAssertFalse(Ranker.sameName("Nobu", "Zuma"))
    }

    func testBudgetBands() {
        XCTAssertTrue(Budget.low.allows(2))
        XCTAssertFalse(Budget.low.allows(3))
        XCTAssertTrue(Budget.high.allows(nil))
    }
}

final class ProximityTests: XCTestCase {
    let here = Coordinate(lat: 41.3870, lng: 2.1700)

    func place(_ name: String, east: Double, kind: PlaceKind = .saved, score: Double = 1, muted: Bool = false) -> Place {
        Place(id: name, name: name, coordinate: Geo.offset(here, north: 0, east: east), kind: kind, score: score, muted: muted)
    }

    func testPlannerCapsAtNineteenAndPrefersSaved() {
        var ps = (1...40).map { place("d\($0)", east: Double($0) * 100, kind: .attraction, score: 0.5) }
        ps.append(place("savedFar", east: 2_500))
        ps.append(place("muted", east: 300, muted: true))
        let plan = GeofencePlanner.plan(from: here, places: ps)
        XCTAssertEqual(plan.regions.count, 19)
        XCTAssertTrue(plan.regions.contains { $0.id == GeofencePlanner.regionID(for: "savedFar") })
        XCTAssertFalse(plan.regions.contains { $0.id.hasSuffix("muted") })
        XCTAssertGreaterThanOrEqual(plan.refresh.radius, 400)
        XCTAssertLessThanOrEqual(plan.refresh.radius, 5_000)
    }

    func testPlannerReportsAlreadyInside() {
        let plan = GeofencePlanner.plan(from: here, places: [place("here", east: 50), place("there", east: 800)])
        XCTAssertEqual(plan.alreadyInside, ["here"])
        XCTAssertEqual(plan.regions.count, 1)
    }

    func testRegionIDRoundTrip() {
        XCTAssertEqual(GeofencePlanner.placeID(from: GeofencePlanner.regionID(for: "abc")), "abc")
        XCTAssertNil(GeofencePlanner.placeID(from: GeofencePlanner.refreshID))
    }

    func testPolicy() {
        let s = AlertSettings()
        let now = Date()
        let saved = place("s", east: 0)
        let disc = place("d", east: 0, kind: .attraction)
        XCTAssertEqual(AlertPolicy.decide(place: saved, now: now, hour: 14, tripMode: false, speed: 1, log: [], settings: s), .allow)
        XCTAssertEqual(AlertPolicy.decide(place: disc, now: now, hour: 14, tripMode: false, speed: 1, log: [], settings: s), .deny("not on a trip"))
        XCTAssertEqual(AlertPolicy.decide(place: disc, now: now, hour: 14, tripMode: true, speed: 1, log: [], settings: s), .allow)
        XCTAssertEqual(AlertPolicy.decide(place: disc, now: now, hour: 23, tripMode: true, speed: 1, log: [], settings: s), .deny("quiet hours"))
        XCTAssertEqual(AlertPolicy.decide(place: disc, now: now, hour: 14, tripMode: true, speed: 15, log: [], settings: s), .deny("moving too fast"))
        let log = (1...3).map { AlertLogEntry(placeID: "x\($0)", date: now.addingTimeInterval(Double(-$0) * 3_600), discovery: true) }
        XCTAssertEqual(AlertPolicy.decide(place: disc, now: now, hour: 14, tripMode: true, speed: 1, log: log, settings: s), .deny("daily cap"))
        var recent = saved
        recent.lastAlertAt = now.addingTimeInterval(-86_400)
        XCTAssertEqual(AlertPolicy.decide(place: recent, now: now, hour: 14, tripMode: false, speed: nil, log: [], settings: s), .deny("alerted recently"))
        XCTAssertEqual(AlertPolicy.decide(place: recent, now: now, hour: 14, tripMode: true, speed: nil, log: [], settings: s), .allow)
    }

    func testQuietHoursWrap() {
        XCTAssertTrue(AlertPolicy.inQuietHours(hour: 23, start: 22, end: 8))
        XCTAssertTrue(AlertPolicy.inQuietHours(hour: 3, start: 22, end: 8))
        XCTAssertFalse(AlertPolicy.inQuietHours(hour: 12, start: 22, end: 8))
        XCTAssertTrue(AlertPolicy.inQuietHours(hour: 13, start: 12, end: 14))
    }

    func testTripMode() {
        let home = Coordinate(lat: 37.44, lng: -122.14)
        XCTAssertTrue(AlertPolicy.isTripMode(here: here, home: home))
        XCTAssertFalse(AlertPolicy.isTripMode(here: home, home: home))
        XCTAssertFalse(AlertPolicy.isTripMode(here: here, home: nil))
    }

    func testComposer() {
        var p = place("Sagrada Família", east: 0, kind: .attraction)
        p.blurb = "basilica in Barcelona"
        let t = AlertComposer.compose(place: p, distance: 200, metric: true, goldenStartsIn: nil)
        XCTAssertEqual(t.title, "Worth a look: Sagrada Família")
        XCTAssertTrue(t.body.hasPrefix("Basilica in Barcelona. 3 min walk."))
        var s = place("Bunkers del Carmel", east: 0, kind: .scenic)
        s.scenic = true
        XCTAssertTrue(AlertComposer.compose(place: s, distance: 50, metric: true, goldenStartsIn: 30).body.contains("Golden hour in 30 min"))
    }
}

final class SourceTests: XCTestCase {
    func testWikipediaNearbyAndFilter() {
        let json = """
        {"batchcomplete":true,"query":{"pages":[
          {"pageid":1,"title":"Belém Tower","length":45000,"description":"fortified tower in Lisbon, Portugal","coordinates":[{"lat":38.6916,"lon":-9.216,"primary":true,"globe":"earth"}]},
          {"pageid":2,"title":"Rua Augusta","length":9000,"description":"street in Lisbon","coordinates":[{"lat":38.71,"lon":-9.137}]},
          {"pageid":3,"title":"Tiny stub","length":1200,"description":"church","coordinates":[{"lat":38.71,"lon":-9.13}]},
          {"pageid":4,"title":"No coords","length":50000}
        ]}}
        """
        let pages = Wikipedia.parseNearby(Data(json.utf8))
        XCTAssertEqual(pages.count, 3)
        let d = Wikipedia.discoveries(pages)
        XCTAssertEqual(d.map(\.name), ["Belém Tower"])
        XCTAssertEqual(d[0].id, "wiki:en:Belém Tower")
        XCTAssertGreaterThan(d[0].score, 0.5)
    }

    func testWikipediaExtractCutsReferences() {
        let json = #"{"query":{"pages":[{"title":"X","extract":"Intro text.\n\n== History ==\nOld.\n\n== References ==\nRefs"}]}}"#
        let t = Wikipedia.parseExtract(Data(json.utf8))
        XCTAssertEqual(t, "Intro text.\n\n== History ==\nOld.")
    }

    func testURLsEncode() {
        XCTAssertTrue(Wikipedia.nearbyURL(Coordinate(lat: 1, lng: 2)).absoluteString.contains("ggscoord=1.000000%7C2.000000"))
        XCTAssertTrue(Drive.searchURL("Lisbon's best").absoluteString.contains("fullText"))
    }

    func testOverpassParseAndScenic() {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":38.7139,"lon":-9.1295,"tags":{"tourism":"viewpoint","name":"Miradouro da Graça","wikidata":"Q1"}},
          {"type":"way","id":2,"center":{"lat":38.7,"lon":-9.2},"tags":{"man_made":"lighthouse"}},
          {"type":"node","id":3,"lat":38.71391,"lon":-9.12951,"tags":{"tourism":"viewpoint"}},
          {"type":"node","id":4,"lat":38.70,"lon":-9.10,"tags":{"amenity":"bench"}}
        ]}
        """
        let els = Overpass.parse(Data(json.utf8))
        XCTAssertEqual(els.count, 4)
        let s = Overpass.scenicPlaces(els)
        XCTAssertEqual(s.map(\.name), ["Miradouro da Graça", "Lighthouse"])
        XCTAssertGreaterThan(s[0].score, s[1].score)
        XCTAssertEqual(s[0].kind, .scenic)
        XCTAssertTrue(Overpass.restroomQuery(Coordinate(lat: 1, lng: 2)).contains("amenity"))
    }

    func testRefugeParse() {
        let json = #"[{"id":5,"name":"Library","street":"1 Main","latitude":37.4,"longitude":-122.1,"accessible":true,"unisex":false}]"#
        let v = Refuge.parse(Data(json.utf8))
        XCTAssertEqual(v.first?.name, "Library")
        XCTAssertEqual(v.first?.tags["wheelchair"], "yes")
    }

    func testGooglePlacesParse() throws {
        let json = """
        {"places":[
          {"id":"abc","displayName":{"text":"Fábrica Coffee Roasters","languageCode":"en"},"location":{"latitude":38.72,"longitude":-9.14},
           "rating":4.7,"userRatingCount":2100,"priceLevel":"PRICE_LEVEL_INEXPENSIVE","types":["coffee_shop","cafe"],
           "currentOpeningHours":{"openNow":true},"formattedAddress":"R. das Portas de Santo Antão","googleMapsUri":"https://maps.google.com/?cid=1","businessStatus":"OPERATIONAL"},
          {"id":"gone","displayName":{"text":"Closed"},"location":{"latitude":38.7,"longitude":-9.1},"businessStatus":"CLOSED_PERMANENTLY"}
        ]}
        """
        let v = try GooglePlaces.parse(Data(json.utf8))
        XCTAssertEqual(v.count, 1)
        XCTAssertEqual(v[0].priceLevel, 1)
        XCTAssertEqual(v[0].openNow, true)
        XCTAssertEqual(v[0].id, "g:abc")
        XCTAssertThrowsError(try GooglePlaces.parse(Data(#"{"error":{"code":403,"message":"API key not valid"}}"#.utf8)))
        XCTAssertEqual(try GooglePlaces.parse(Data("{}".utf8)).count, 0)
    }

    func testClaudeParse() throws {
        let ok = #"{"content":[{"type":"text","text":"Hello there."}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try Claude.parseText(Data(ok.utf8)), "Hello there.")
        XCTAssertThrowsError(try Claude.parseText(Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)))
    }

    func testOAuthHelpers() throws {
        XCTAssertEqual(GoogleOAuth.redirectScheme(clientID: "123-abc.apps.googleusercontent.com"), "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(GoogleOAuth.redirectURI(clientID: "123-abc.apps.googleusercontent.com"), "com.googleusercontent.apps.123-abc:/oauth2redirect")
        let cb = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=4/xyz&scope=drive")!
        XCTAssertEqual(GoogleOAuth.code(fromCallback: cb), "4/xyz")
        let t = try GoogleOAuth.parseTokens(Data(#"{"access_token":"a","expires_in":3599,"refresh_token":"r","token_type":"Bearer"}"#.utf8))
        XCTAssertEqual(t.refresh, "r")
        XCTAssertThrowsError(try GoogleOAuth.parseTokens(Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)))
        XCTAssertEqual(GoogleOAuth.base64url(Data([0xfb, 0xff])), "-_8")
        let body = String(data: GoogleOAuth.tokenRequest(["code": "4/a b", "grant_type": "authorization_code"]).httpBody!, encoding: .utf8)
        XCTAssertEqual(body, "code=4%2Fa%20b&grant_type=authorization_code")
    }

    func testDriveParse() throws {
        let f = try Drive.parseFiles(Data(#"{"files":[{"id":"1","name":"Lisbon plan","modifiedTime":"2026-10-01T00:00:00Z"}]}"#.utf8))
        XCTAssertEqual(f.first?.name, "Lisbon plan")
    }
}

final class GuideTests: XCTestCase {
    func testTrimStaysUnderBudgetAtSentence() {
        let sentence = "The tower was built in the sixteenth century to guard the river mouth."
        let text = Array(repeating: sentence, count: 40).joined(separator: " ")
        let t = Guide.trim(text)
        XCTAssertLessThanOrEqual(Guide.wordCount(t), Guide.maxWords)
        XCTAssertTrue(t.hasSuffix("mouth."))
        XCTAssertLessThanOrEqual(Guide.estimatedSeconds(t), 120)
    }

    func testTrimRemovesParentheticals() {
        XCTAssertEqual(Guide.trim("Lisbon (Portuguese: Lisboa) is old."), "Lisbon is old.")
    }

    func testTidyDropsHeadings() {
        XCTAssertEqual(Guide.tidy("# Belém Tower\n\nIt stands **in** the river."), "It stands in the river.")
    }

    func testPromptMentionsNoteAndSource() {
        let p = Guide.prompt(place: Place(name: "Ramiro", note: "order clams"), source: nil, city: "Lisbon")
        XCTAssertTrue(p.contains("order clams"))
        XCTAssertTrue(p.contains("No source text"))
    }

    func testTripsGroupByCity() {
        let home = Coordinate(lat: 37.44, lng: -122.14)
        let lis = Coordinate(lat: 38.72, lng: -9.14)
        let d = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            TripEvent(title: "Flight", start: d, end: d.addingTimeInterval(3_600), coordinate: lis, city: "Lisbon"),
            TripEvent(title: "Dinner", start: d.addingTimeInterval(86_400), end: d.addingTimeInterval(90_000), coordinate: lis, city: "Lisbon"),
            TripEvent(title: "Dentist", start: d, end: d.addingTimeInterval(3_600), coordinate: home, city: "Palo Alto"),
            TripEvent(title: "Later Lisbon", start: d.addingTimeInterval(30 * 86_400), end: d.addingTimeInterval(30 * 86_400 + 3_600), coordinate: lis, city: "Lisbon")
        ]
        let trips = TripPlanner.trips(from: events, home: home)
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].events.count, 2)
        XCTAssertEqual(TripPlanner.current(trips, now: d.addingTimeInterval(3_600), here: nil)?.city, "Lisbon")
    }

    func testDocExtractionParse() {
        let reply = "Here you go:\n```json\n{\"places\":[{\"name\":\"Cervejaria Ramiro\",\"city\":\"Lisbon\",\"note\":\"clams, book 8pm\",\"type\":\"food\"},{\"name\":\" \"}]}\n```"
        let ps = DocExtraction.parse(reply)
        XCTAssertEqual(ps.map(\.name), ["Cervejaria Ramiro"])
        XCTAssertTrue(DocExtraction.parse("not json").isEmpty)
    }

    func testSunGoldenWindowExists() {
        let w = Sun.goldenWindow(from: Date(timeIntervalSince1970: 1_800_000_000), latitude: 38.7, longitude: -9.1)
        XCTAssertNotNil(w)
    }
}

final class GoogleListTests: XCTestCase {
    func testListIDFromBothURLForms() {
        XCTAssertEqual(GoogleList.listID(in: "https://www.google.com/maps/placelists/list/11J2JiXPiaV0oQ2PdQ_evBLqMris?shh=CAE"), "11J2JiXPiaV0oQ2PdQ_evBLqMris")
        XCTAssertEqual(GoogleList.listID(in: "https://www.google.com/maps/@/data=!3m1!4b1!4m2!11m1!2s1ZFTlgHwjRppM8Himf0_ZKXt4nsk!18m1!1e1?g_ep=x"), "1ZFTlgHwjRppM8Himf0_ZKXt4nsk")
        XCTAssertNil(GoogleList.listID(in: "https://www.google.com/maps/place/Cafe/@1.5,2.5,17z"))
    }

    func testParseSyntheticResponse() {
        let body = """
        )]}'
        [[["LISTID",3,[[1],[9]],1,1],4,[2,1,"u"],["Owner","p","1"],"Want to go","",null,null,[
         [null,[null,null,"Cafe A, 1 Main St",null,"1 Main St, Mexico City",[null,null,19.43,-99.19],["-8803970307559093503","-1970343289966187788"],"/g/x"],"Cafe A","great flat white",null,null,null,[]],
         [null,[null,null,"",null,"2 Side St",[null,null,19.41,-99.18],["1","42"]],"Taqueria B","",null],
         [null,[null,null,"",null,"",null,null],"No Pin",""],
         [null,null,"Broken"]
        ]]]
        """
        let list = GoogleList.parse(Data(body.utf8))
        XCTAssertEqual(list?.name, "Want to go")
        XCTAssertEqual(list?.places.map(\.name), ["Cafe A", "Taqueria B", "No Pin"])
        XCTAssertEqual(list?.places[0].note, "great flat white")
        XCTAssertEqual(list?.places[0].coordinate?.lat ?? 0, 19.43, accuracy: 1e-9)
        XCTAssertEqual(list?.places[0].url, "https://maps.google.com/?cid=16476400783743363828")
        XCTAssertEqual(list?.places[1].id, "gmap:42")
        XCTAssertNil(list?.places[2].coordinate)
        XCTAssertEqual(list?.places[0].lists, ["Want to go"])
        XCTAssertNil(GoogleList.parse(Data("<html>".utf8)))
    }
}
