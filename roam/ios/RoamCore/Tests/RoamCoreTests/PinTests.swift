import XCTest
@testable import RoamCore

final class PinTests: XCTestCase {
    func venue(_ name: String, rating: Double? = 4.6, count: Int? = 1234, michelin: MichelinAward? = nil) -> Venue {
        Venue(id: name, name: name, coordinate: Coordinate(lat: 38.71, lng: -9.14), source: .google,
              rating: rating, ratingCount: count, priceLevel: 2, michelin: michelin, cuisine: "portuguese")
    }

    func testCategoriesFromPlaces() {
        XCTAssertEqual(PinCategory.of(Place(name: "a", kind: .saved)), .saved)
        XCTAssertEqual(PinCategory.of(Place(name: "b", kind: .attraction)), .sight)
        XCTAssertEqual(PinCategory.of(Place(name: "c", kind: .attraction, scenic: true)), .scenic)
        XCTAssertEqual(PinCategory.of(Place(name: "d", kind: .scenic)), .scenic)
        XCTAssertTrue(PinCategory.coffee.isSearch)
        XCTAssertFalse(PinCategory.saved.isSearch)
    }

    func testRatingAndRankText() {
        XCTAssertEqual(PinText.rating(venue("x")), "★ 4.6 (1.2k)")
        XCTAssertEqual(PinText.rating(venue("x", count: 23000)), "★ 4.6 (23k)")
        XCTAssertNil(PinText.rating(venue("x", rating: nil)))
        XCTAssertEqual(PinText.compactCount(1000), "1k")
        XCTAssertEqual(PinText.price(venue("x")), "$$")
        let r = RankedVenue(venue: venue("Cafe"), distance: 300, walkMinutes: 4, score: 1, reason: "4.6 from 1.2k reviews")
        let best = Pin(ranked: r, category: .coffee, rank: 1, of: 6)
        XCTAssertEqual(PinText.rank(best), "Best coffee nearby")
        XCTAssertEqual(PinText.rank(Pin(ranked: r, category: .coffee, rank: 3, of: 6)), "#3 of 6")
        XCTAssertEqual(PinText.rank(Pin(ranked: r, category: .restroom, rank: 1, of: 2)), "Nearest restroom")
    }

    func testWords() {
        let p = Place(name: "Miradouro", kind: .attraction,
                      blurb: "viewpoint over the old town with a long view of the river and the bridge at sunset")
        XCTAssertEqual(PinText.words(for: p), "Viewpoint over the old town with a long view…")
        XCTAssertEqual(PinText.words(for: Place(name: "x", lists: ["Lisbon"])), "From Lisbon")
        XCTAssertNil(PinText.words(for: Place(name: "x")))
        let m = venue("Taberna", michelin: .bib)
        XCTAssertEqual(PinText.words(for: m, reason: "Bib Gourmand · Portuguese"), "Bib Gourmand · Portuguese")
    }

    func testOrdering() {
        let here = Coordinate(lat: 0, lng: 0)
        let far = Pin(place: Place(name: "far", coordinate: Coordinate(lat: 0.02, lng: 0), kind: .attraction))
        let near = Pin(place: Place(name: "near", coordinate: Coordinate(lat: 0.001, lng: 0), kind: .attraction))
        XCTAssertEqual(PinText.ordered([far, near], category: .sight, from: here).map(\.name), ["near", "far"])
        let r = RankedVenue(venue: venue("a"), distance: 1, walkMinutes: 1, score: 1, reason: "")
        let r2 = RankedVenue(venue: venue("b"), distance: 1, walkMinutes: 1, score: 1, reason: "")
        let pins = [Pin(ranked: r2, category: .food, rank: 2, of: 2), Pin(ranked: r, category: .food, rank: 1, of: 2)]
        XCTAssertEqual(PinText.ordered(pins, category: .food, from: here).map(\.name), ["a", "b"])
    }
}
