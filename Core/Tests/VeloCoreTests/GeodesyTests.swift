import XCTest
@testable import VeloCore

final class GeodesyTests: XCTestCase {
    func testDistanceBetweenKnownCities() {
        // Lausanne → Genève : environ 51,5 km à vol d'oiseau.
        let lausanne = GeographicCoordinate(latitude: 46.5197, longitude: 6.6323)
        let geneva = GeographicCoordinate(latitude: 46.2044, longitude: 6.1432)
        let distance = Geodesy.distance(from: lausanne, to: geneva)
        XCTAssertEqualWithTolerance(distance, 51_500, tolerance: 800)
    }

    func testDistanceIsSymmetricAndZeroForSamePoint() {
        let a = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let b = GeographicCoordinate(latitude: 46.6, longitude: 6.7)
        XCTAssertEqual(Geodesy.distance(from: a, to: a), 0, accuracy: 1e-6)
        XCTAssertEqualWithTolerance(
            Geodesy.distance(from: a, to: b),
            Geodesy.distance(from: b, to: a),
            tolerance: 1e-6
        )
    }

    func testBearingCardinalDirections() {
        let origin = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let north = Geodesy.destination(from: origin, distance: 1_000, bearing: 0)
        let east = Geodesy.destination(from: origin, distance: 1_000, bearing: 90)

        XCTAssertEqualWithTolerance(Geodesy.bearing(from: origin, to: north), 0, tolerance: 0.5)
        XCTAssertEqualWithTolerance(Geodesy.bearing(from: origin, to: east), 90, tolerance: 0.5)
    }

    func testDestinationRoundTripsThroughDistance() {
        let origin = GeographicCoordinate(latitude: 46.5197, longitude: 6.6323)
        for bearing in stride(from: 0.0, to: 360.0, by: 45) {
            let target = Geodesy.destination(from: origin, distance: 2_500, bearing: bearing)
            XCTAssertEqualWithTolerance(
                Geodesy.distance(from: origin, to: target),
                2_500,
                tolerance: 1
            )
        }
    }

    func testBearingDeltaTakesShortestPath() {
        XCTAssertEqualWithTolerance(Geodesy.bearingDelta(from: 350, to: 10), 20, tolerance: 1e-9)
        XCTAssertEqualWithTolerance(Geodesy.bearingDelta(from: 10, to: 350), -20, tolerance: 1e-9)
        XCTAssertEqualWithTolerance(Geodesy.bearingDelta(from: 0, to: 180), 180, tolerance: 1e-9)
    }

    func testProjectionOntoSegmentMeasuresPerpendicularDistance() {
        let start = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let end = Geodesy.destination(from: start, distance: 1_000, bearing: 90)
        // Point situé 100 m au nord du milieu du segment.
        let middle = Geodesy.destination(from: start, distance: 500, bearing: 90)
        let offset = Geodesy.destination(from: middle, distance: 100, bearing: 0)

        let projection = Geodesy.project(offset, onto: start, end)
        XCTAssertEqualWithTolerance(projection.distance, 100, tolerance: 2)
        XCTAssertEqualWithTolerance(projection.fraction, 0.5, tolerance: 0.02)
    }

    func testProjectionClampsBeyondSegmentEnds() {
        let start = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let end = Geodesy.destination(from: start, distance: 500, bearing: 90)
        let beyond = Geodesy.destination(from: end, distance: 200, bearing: 90)

        let projection = Geodesy.project(beyond, onto: start, end)
        XCTAssertEqual(projection.fraction, 1)
        XCTAssertEqualWithTolerance(projection.distance, 200, tolerance: 2)
    }

    func testProjectionOnDegenerateSegment() {
        let point = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let projection = Geodesy.project(point, onto: point, point)
        XCTAssertEqual(projection.fraction, 0)
        XCTAssertEqualWithTolerance(projection.distance, 0, tolerance: 1e-6)
    }

    func testPolylineLengthAccumulatesSegments() {
        let origin = GeographicCoordinate(latitude: 46.5, longitude: 6.6)
        let coordinates = (0...4).map {
            Geodesy.destination(from: origin, distance: Double($0) * 250, bearing: 45)
        }
        XCTAssertEqualWithTolerance(Geodesy.polylineLength(coordinates), 1_000, tolerance: 2)
    }

    func testCoordinateValidation() {
        XCTAssertTrue(GeographicCoordinate(latitude: 46.5, longitude: 6.6).isValid)
        XCTAssertFalse(GeographicCoordinate(latitude: 0, longitude: 0).isValid)
        XCTAssertFalse(GeographicCoordinate(latitude: 95, longitude: 6.6).isValid)
        XCTAssertFalse(GeographicCoordinate(latitude: .nan, longitude: 6.6).isValid)
    }

    func testCoordinateDescriptionDoesNotLeakPrecisePosition() {
        // Le cahier des charges interdit de journaliser la position exacte :
        // la description est volontairement arrondie à quatre décimales.
        let coordinate = GeographicCoordinate(latitude: 46.519712345, longitude: 6.632398765)
        XCTAssertEqual(coordinate.description, "(46.5197, 6.6324)")
    }
}
