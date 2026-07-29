import XCTest
@testable import VeloCore

/// Couvre le §17 : « création d'un fichier GPX », ainsi que la relecture.
final class GPXServiceTests: XCTestCase {
    private let service = GPXService()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRide(name: String = "Sortie du dimanche") -> RecordedRide {
        let route = TestFixtures.loop(distance: 5_000, seed: 3)
        var tracker = RideTracker.start(
            at: start, name: name, plannedRoute: route, profile: .electricRoad
        )
        for sample in TrackSimulator(route: route, speed: 6.5, updateInterval: 2)
            .samples(startingAt: start) {
            tracker.add(sample)
        }
        let session = tracker.finish(at: start.addingTimeInterval(800))
        return RecordedRide(
            session: session,
            finishedAt: start.addingTimeInterval(800),
            bodyMassKilograms: 75
        )
    }

    func testExportProducesValidGPXStructure() throws {
        let data = try service.export(ride: makeRide())
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<gpx version=\"1.1\""))
        XCTAssertTrue(xml.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""))
        XCTAssertTrue(xml.contains("<trk>"))
        XCTAssertTrue(xml.contains("<trkseg>"))
        XCTAssertTrue(xml.contains("<trkpt lat="))
        XCTAssertTrue(xml.contains("<ele>"))
        XCTAssertTrue(xml.contains("<time>"))
        XCTAssertTrue(xml.hasSuffix("</gpx>\n"))
    }

    func testExportIncludesThePlannedRouteAlongsideTheTrack() throws {
        let data = try service.export(ride: makeRide())
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("<rte>"))
        XCTAssertTrue(xml.contains("Circuit prévu"))
    }

    func testExportEscapesSpecialCharactersInNames() throws {
        let data = try service.export(ride: makeRide(name: "Tour <Jura> & \"Lac\""))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("Tour &lt;Jura&gt; &amp; &quot;Lac&quot;"))
        XCTAssertFalse(xml.contains("<Jura>"))
    }

    func testTimestampsAreISO8601InUTC() throws {
        let data = try service.export(ride: makeRide())
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("<time>2023-11-14T22:13:20Z</time>"))
    }

    func testExportedFileCanBeParsedBack() throws {
        let ride = makeRide()
        let data = try service.export(ride: ride)
        let document = try service.parse(data: data)

        XCTAssertEqual(document.name, ride.name)
        XCTAssertEqual(document.trackPoints.count, ride.track.count)
        XCTAssertFalse(document.routePoints.isEmpty)

        let originalFirst = try XCTUnwrap(ride.track.first)
        let parsedFirst = try XCTUnwrap(document.trackPoints.first)
        XCTAssertEqualWithTolerance(
            parsedFirst.coordinate.latitude, originalFirst.coordinate.latitude, tolerance: 1e-6
        )
        XCTAssertEqualWithTolerance(
            parsedFirst.coordinate.longitude, originalFirst.coordinate.longitude, tolerance: 1e-6
        )
        XCTAssertEqual(parsedFirst.timestamp, originalFirst.timestamp)
    }

    func testDistanceIsPreservedThroughAnExportImportCycle() throws {
        let ride = makeRide()
        let document = try service.parse(data: try service.export(ride: ride))
        let reimported = Geodesy.polylineLength(document.trackPoints.map(\.coordinate))
        XCTAssertEqualWithTolerance(reimported, ride.statistics.distance, tolerance: 5)
    }

    func testRouteOnlyExportContainsRoutePointsWithoutTrack() throws {
        let route = TestFixtures.loop(distance: 8_000, seed: 2)
        let data = try service.export(route: route, name: "Boucle du Léman")
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("<rtept lat="))
        XCTAssertFalse(xml.contains("<trkpt"))

        let document = try service.parse(data: data)
        XCTAssertEqual(document.routePoints.count, route.coordinates.count)
        XCTAssertTrue(document.trackPoints.isEmpty)
    }

    func testParsesExternalGPXWithFractionalSeconds() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Garmin" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Col du Marchairuz</name><trkseg>
            <trkpt lat="46.5450" lon="6.2450"><ele>1447.0</ele>
              <time>2024-06-01T08:30:00.000Z</time></trkpt>
            <trkpt lat="46.5460" lon="6.2470"><ele>1450.5</ele>
              <time>2024-06-01T08:30:05.000Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let document = try service.parse(data: Data(gpx.utf8))
        XCTAssertEqual(document.name, "Col du Marchairuz")
        XCTAssertEqual(document.trackPoints.count, 2)
        XCTAssertEqualWithTolerance(
            try XCTUnwrap(document.trackPoints[0].coordinate.altitude), 1_447, tolerance: 0.01
        )
        XCTAssertEqualWithTolerance(
            document.trackPoints[1].timestamp
                .timeIntervalSince(document.trackPoints[0].timestamp),
            5, tolerance: 0.01
        )
    }

    func testEmptyDataIsRejectedWithAFrenchExplanation() {
        XCTAssertThrowsError(try service.parse(data: Data())) { error in
            guard case .gpxParsingFailed(let reason) = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
            XCTAssertEqual(reason, "fichier vide")
        }
    }

    func testMalformedXMLIsRejected() {
        let broken = "<gpx><trk><trkseg><trkpt lat=\"46.5\""
        XCTAssertThrowsError(try service.parse(data: Data(broken.utf8))) { error in
            guard case .gpxParsingFailed = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
        }
    }

    func testWellFormedButEmptyGPXIsRejected() {
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"></gpx>
        """
        XCTAssertThrowsError(try service.parse(data: Data(empty.utf8))) { error in
            guard case .gpxParsingFailed(let reason) = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
            XCTAssertEqual(reason, "aucun point trouvé")
        }
    }

    func testInvalidCoordinatesInImportedFileAreDropped() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="46.5450" lon="6.2450"></trkpt>
            <trkpt lat="999" lon="6.2470"></trkpt>
            <trkpt lat="0" lon="0"></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let document = try service.parse(data: Data(gpx.utf8))
        XCTAssertEqual(document.trackPoints.count, 1)
    }
}
