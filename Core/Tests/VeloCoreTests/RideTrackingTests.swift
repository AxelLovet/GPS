import XCTest
@testable import VeloCore

/// Couvre le §17 : « calcul de la vitesse moyenne » et le filtrage des positions
/// aberrantes exigé au §14.
final class RideTrackingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Vitesse moyenne

    func testAverageMovingSpeedIgnoresStops() {
        var statistics = RideStatistics()
        statistics.distance = 20_000      // 20 km
        statistics.movingTime = 3_600     // 1 h de roulage
        statistics.elapsedTime = 4_500    // 1 h 15 avec les arrêts

        // 20 km en 1 h = 5,56 m/s, soit 20 km/h.
        XCTAssertEqualWithTolerance(statistics.averageMovingSpeed, 5.556, tolerance: 0.01)
        XCTAssertEqualWithTolerance(statistics.averageOverallSpeed, 4.444, tolerance: 0.01)
        XCTAssertGreaterThan(statistics.averageMovingSpeed, statistics.averageOverallSpeed)
    }

    func testAverageSpeedIsZeroWithoutMovement() {
        let statistics = RideStatistics()
        XCTAssertEqual(statistics.averageMovingSpeed, 0)
        XCTAssertEqual(statistics.averageOverallSpeed, 0)
    }

    func testAverageSpeedOverARecordedRide() {
        let route = TestFixtures.straightLine(length: 6_000)
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: route, profile: .electricRoad
        )
        // 6 km parcourus à exactement 6 m/s.
        let simulator = TrackSimulator(route: route, speed: 6, updateInterval: 1)
        for sample in simulator.samples(startingAt: start) {
            tracker.add(sample)
        }
        let session = tracker.finish(at: start.addingTimeInterval(1_000))

        XCTAssertEqualWithTolerance(session.statistics.distance, 6_000, tolerance: 60)
        XCTAssertEqualWithTolerance(session.statistics.averageMovingSpeed, 6, tolerance: 0.2)
    }

    // MARK: - Filtrage

    func testPoorAccuracySamplesAreRejected() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        let rejection = tracker.add(
            LocationSample(
                coordinate: TestFixtures.lausanne,
                timestamp: start,
                horizontalAccuracy: 300
            )
        )
        XCTAssertEqual(rejection, .poorAccuracy)
        XCTAssertTrue(tracker.session.track.isEmpty)
    }

    func testTeleportingSampleIsRejected() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        tracker.add(LocationSample(coordinate: TestFixtures.lausanne, timestamp: start))

        // 5 km en une seconde : impossible à vélo.
        let jump = Geodesy.destination(from: TestFixtures.lausanne, distance: 5_000, bearing: 90)
        let rejection = tracker.add(
            LocationSample(coordinate: jump, timestamp: start.addingTimeInterval(1))
        )
        XCTAssertEqual(rejection, .implausibleSpeed)
        XCTAssertEqual(tracker.session.track.count, 1)
        XCTAssertEqual(tracker.session.statistics.distance, 0)
    }

    func testStationaryNoiseDoesNotInflateDistance() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        tracker.add(LocationSample(coordinate: TestFixtures.lausanne, timestamp: start))

        // Trente relevés à l'arrêt, avec un bruit de 1 m.
        for index in 1...30 {
            let jitter = Geodesy.destination(
                from: TestFixtures.lausanne,
                distance: 1,
                bearing: Double(index) * 37
            )
            tracker.add(
                LocationSample(coordinate: jitter, timestamp: start.addingTimeInterval(Double(index)))
            )
        }
        XCTAssertEqual(tracker.session.statistics.distance, 0)
        XCTAssertEqual(tracker.session.statistics.movingTime, 0)
        // Le temps écoulé, lui, avance : le cycliste attend à un feu.
        XCTAssertEqualWithTolerance(tracker.session.statistics.elapsedTime, 30, tolerance: 0.5)
    }

    func testOutOfOrderSampleIsRejected() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        tracker.add(
            LocationSample(
                coordinate: TestFixtures.lausanne,
                timestamp: start.addingTimeInterval(10)
            )
        )
        let older = Geodesy.destination(from: TestFixtures.lausanne, distance: 50, bearing: 90)
        let rejection = tracker.add(
            LocationSample(coordinate: older, timestamp: start.addingTimeInterval(5))
        )
        XCTAssertEqual(rejection, .outOfOrder)
    }

    func testFlatRideDoesNotAccumulatePhantomElevation() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        // Parcours parfaitement plat, avec le bruit d'altitude habituel du GPS.
        for index in 0..<60 {
            let position = Geodesy.destination(
                from: TestFixtures.lausanne, distance: Double(index) * 10, bearing: 90
            )
            let noisyAltitude = 500 + sin(Double(index)) * 1.5
            tracker.add(
                LocationSample(
                    coordinate: GeographicCoordinate(
                        latitude: position.latitude,
                        longitude: position.longitude,
                        altitude: noisyAltitude
                    ),
                    timestamp: start.addingTimeInterval(Double(index) * 2),
                    verticalAccuracy: 8
                )
            )
        }
        XCTAssertEqual(tracker.session.statistics.ascent, 0)
        XCTAssertEqual(tracker.session.statistics.descent, 0)
    }

    func testRealClimbIsCounted() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        for index in 0..<50 {
            let position = Geodesy.destination(
                from: TestFixtures.lausanne, distance: Double(index) * 20, bearing: 90
            )
            tracker.add(
                LocationSample(
                    coordinate: GeographicCoordinate(
                        latitude: position.latitude,
                        longitude: position.longitude,
                        altitude: 500 + Double(index) * 4
                    ),
                    timestamp: start.addingTimeInterval(Double(index) * 3),
                    verticalAccuracy: 6
                )
            )
        }
        // 49 paliers de 4 m ≈ 196 m de dénivelé positif.
        XCTAssertEqualWithTolerance(tracker.session.statistics.ascent, 196, tolerance: 10)
        XCTAssertEqual(tracker.session.statistics.descent, 0)
    }

    // MARK: - Pause

    func testPausedRideIgnoresSamplesAndTheGapIsNotCounted() {
        let route = TestFixtures.straightLine(length: 4_000)
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: route, profile: .electricRoad
        )
        let samples = TrackSimulator(route: route, speed: 6, updateInterval: 1)
            .samples(startingAt: start)

        for sample in samples.prefix(100) { tracker.add(sample) }
        let distanceBeforePause = tracker.session.statistics.distance
        let movingTimeBeforePause = tracker.session.statistics.movingTime

        tracker.pause(at: start.addingTimeInterval(100))
        for sample in samples.dropFirst(100).prefix(100) { tracker.add(sample) }

        XCTAssertEqual(tracker.session.statistics.distance, distanceBeforePause)
        XCTAssertEqual(tracker.session.statistics.movingTime, movingTimeBeforePause)

        tracker.resume(at: start.addingTimeInterval(200))
        for sample in samples.dropFirst(200).prefix(50) { tracker.add(sample) }
        XCTAssertGreaterThan(tracker.session.statistics.distance, distanceBeforePause)
    }

    // MARK: - Écarts

    func testDeviationsAreRecordedAndClosed() throws {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        tracker.beginDeviation(at: start, distance: 60, position: TestFixtures.lausanne)
        tracker.updateDeviation(distance: 140)
        tracker.updateDeviation(distance: 90)
        tracker.endDeviation(at: start.addingTimeInterval(180))

        XCTAssertEqual(tracker.session.deviations.count, 1)
        let deviation = tracker.session.deviations[0]
        XCTAssertEqualWithTolerance(deviation.maximumDistance, 140, tolerance: 0.01)
        XCTAssertTrue(deviation.isResolved)
        XCTAssertEqualWithTolerance(try XCTUnwrap(deviation.duration), 180, tolerance: 0.01)
    }

    func testOpenDeviationIsClosedWhenTheRideEnds() {
        var tracker = RideTracker.start(
            at: start, name: "Test", plannedRoute: nil, profile: .road
        )
        tracker.beginDeviation(at: start, distance: 80, position: TestFixtures.lausanne)
        let session = tracker.finish(at: start.addingTimeInterval(600))
        XCTAssertTrue(session.deviations[0].isResolved)
    }

    // MARK: - Calories

    func testCalorieEstimateScalesWithTimeAndProfile() {
        var statistics = RideStatistics()
        statistics.movingTime = 3_600

        let electric = statistics.estimatedCalories(profile: .electricRoad, bodyMassKilograms: 75)
        let road = statistics.estimatedCalories(profile: .road, bodyMassKilograms: 75)

        XCTAssertEqualWithTolerance(electric, 375, tolerance: 1)   // 5,0 MET × 75 kg × 1 h
        XCTAssertEqualWithTolerance(road, 600, tolerance: 1)       // 8,0 MET × 75 kg × 1 h
        XCTAssertGreaterThan(road, electric, "un vélo musculaire demande plus d'effort")
    }
}
