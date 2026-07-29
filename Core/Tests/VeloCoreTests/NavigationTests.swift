import XCTest
@testable import VeloCore

/// Couvre le §17 : « détection d'une sortie du parcours », « calcul de la
/// distance restante » et « progression sur le parcours ».
final class NavigationTests: XCTestCase {
    private let matcher = RouteMatchingService()

    // MARK: - Correspondance et distance restante

    func testRemainingDistanceAtStartEqualsRouteLength() throws {
        let route = TestFixtures.straightLine(length: 5_000)
        let match = try XCTUnwrap(matcher.match(route.coordinates[0], on: route, near: nil))
        XCTAssertEqualWithTolerance(match.distanceAlongRoute, 0, tolerance: 1)
        XCTAssertEqualWithTolerance(match.remainingDistance, route.measuredDistance, tolerance: 1)
        XCTAssertEqualWithTolerance(match.fractionCompleted, 0, tolerance: 0.001)
    }

    func testRemainingDistanceDecreasesAlongTheRoute() throws {
        let route = TestFixtures.straightLine(length: 5_000)
        let quarter = route.coordinates[route.coordinates.count / 4]
        let match = try XCTUnwrap(matcher.match(quarter, on: route, near: nil))

        XCTAssertEqualWithTolerance(match.distanceAlongRoute, 1_250, tolerance: 60)
        XCTAssertEqualWithTolerance(match.remainingDistance, 3_750, tolerance: 60)
        XCTAssertEqualWithTolerance(match.fractionCompleted, 0.25, tolerance: 0.02)
    }

    func testRemainingDistanceIsZeroAtTheEnd() throws {
        let route = TestFixtures.straightLine(length: 5_000)
        let last = try XCTUnwrap(route.coordinates.last)
        let match = try XCTUnwrap(matcher.match(last, on: route, near: nil))
        XCTAssertEqualWithTolerance(match.remainingDistance, 0, tolerance: 1)
        XCTAssertEqualWithTolerance(match.fractionCompleted, 1, tolerance: 0.001)
    }

    func testProgressAdvancesMonotonicallyAlongASimulatedRide() throws {
        let route = TestFixtures.loop(distance: 8_000, seed: 3)
        let simulator = TrackSimulator(route: route, speed: 6.9, updateInterval: 2)
        let samples = simulator.samples(startingAt: Date(timeIntervalSince1970: 0))
        XCTAssertGreaterThan(samples.count, 50)

        var previous: RouteMatch?
        var maximumRegression: Double = 0

        for sample in samples {
            let match = try XCTUnwrap(matcher.match(sample.coordinate, on: route, near: previous))
            if let previous {
                maximumRegression = max(
                    maximumRegression,
                    previous.distanceAlongRoute - match.distanceAlongRoute
                )
            }
            previous = match
        }

        // La progression ne doit jamais reculer de façon significative, même
        // lorsque la boucle se recoupe près du départ.
        XCTAssertLessThan(maximumRegression, 20)
        let final = try XCTUnwrap(previous)
        XCTAssertGreaterThan(final.fractionCompleted, 0.97)
    }

    func testMatchingStaysOnTheCorrectPassOfASelfCrossingLoop() throws {
        // Une boucle repasse près de son départ à la fin. Sans fenêtre de
        // recherche, la position de départ se rattacherait à la fin du tracé et
        // la navigation annoncerait l'arrivée immédiatement.
        let route = TestFixtures.loop(distance: 6_000, seed: 11)
        let start = try XCTUnwrap(route.coordinates.first)
        let match = try XCTUnwrap(matcher.match(start, on: route, near: nil))
        XCTAssertLessThan(match.distanceAlongRoute, route.measuredDistance / 2)
    }

    // MARK: - Détection de sortie de parcours

    func testSingleOutlierDoesNotTriggerAnAlert() {
        let detector = DeviationDetector()
        var state = DeviationDetector.State()
        let event = detector.evaluate(
            distanceFromRoute: 200, horizontalAccuracy: 5, state: &state
        )
        XCTAssertEqual(event, .onRoute)
        XCTAssertFalse(state.isOffRoute)
    }

    func testSustainedDistanceTriggersDeparture() {
        let detector = DeviationDetector(confirmationCount: 3)
        var state = DeviationDetector.State()
        var events: [DeviationEvent] = []
        for _ in 0..<3 {
            events.append(
                detector.evaluate(distanceFromRoute: 200, horizontalAccuracy: 5, state: &state)
            )
        }
        XCTAssertEqual(events.last, .departed(distance: 200))
        XCTAssertTrue(state.isOffRoute)
    }

    func testThresholdGrowsWithPoorGPSAccuracy() {
        let detector = DeviationDetector()
        XCTAssertLessThan(
            detector.threshold(forAccuracy: 5),
            detector.threshold(forAccuracy: 40)
        )
        // Le seuil reste plafonné pour ne pas devenir inopérant.
        XCTAssertLessThanOrEqual(detector.threshold(forAccuracy: 500), 120)
    }

    func testPoorAccuracyPreventsFalseAlarmAtModerateDistance() {
        let detector = DeviationDetector()
        var state = DeviationDetector.State()
        for _ in 0..<6 {
            _ = detector.evaluate(distanceFromRoute: 55, horizontalAccuracy: 35, state: &state)
        }
        XCTAssertFalse(state.isOffRoute, "55 m avec ±35 m d'incertitude n'est pas une sortie")
    }

    func testHysteresisPreventsOscillationWhenReturning() {
        let detector = DeviationDetector(baseThreshold: 40, confirmationCount: 2, returnRatio: 0.6)
        var state = DeviationDetector.State()

        for _ in 0..<2 {
            _ = detector.evaluate(distanceFromRoute: 100, horizontalAccuracy: 0, state: &state)
        }
        XCTAssertTrue(state.isOffRoute)

        // Juste sous le seuil de sortie mais au-dessus du seuil de retour :
        // on reste considéré hors parcours.
        let stillOff = detector.evaluate(
            distanceFromRoute: 35, horizontalAccuracy: 0, state: &state
        )
        XCTAssertEqual(stillOff, .stillOff(distance: 35))

        let returned = detector.evaluate(
            distanceFromRoute: 20, horizontalAccuracy: 0, state: &state
        )
        XCTAssertEqual(returned, .returned)
        XCTAssertFalse(state.isOffRoute)
    }

    func testSimulatedDetourIsDetectedThenResolved() throws {
        let route = TestFixtures.loop(distance: 10_000, seed: 4)
        let simulator = TrackSimulator(
            route: route,
            updateInterval: 2,
            detour: TrackSimulator.DetourPlan(
                startDistance: 2_000, length: 900, lateralOffset: 180
            )
        )
        var engine = NavigationEngine(route: route)
        var sawDeparture = false
        var sawReturn = false
        var suggestedRejoin: GeographicCoordinate?

        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)) {
            for event in engine.update(with: sample) {
                switch event {
                case .offRoute: sawDeparture = true
                case .backOnRoute: sawReturn = true
                case .recalculationSuggested(let rejoin): suggestedRejoin = rejoin
                default: break
                }
            }
        }

        XCTAssertTrue(sawDeparture, "l'écart de 180 m aurait dû être détecté")
        XCTAssertTrue(sawReturn, "le retour sur le parcours aurait dû être détecté")
        XCTAssertNotNil(suggestedRejoin, "un point de reprise aurait dû être proposé")
    }

    func testNoFalseAlarmOnAFaithfullyFollowedRoute() {
        let route = TestFixtures.loop(distance: 12_000, seed: 8)
        let simulator = TrackSimulator(route: route, updateInterval: 2, horizontalAccuracy: 12)
        var engine = NavigationEngine(route: route)
        var falseAlarms = 0

        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)) {
            for event in engine.update(with: sample) {
                if case .offRoute = event { falseAlarms += 1 }
            }
        }
        XCTAssertEqual(falseAlarms, 0)
    }

    // MARK: - Point de reprise

    func testRejoinPointIsAheadRatherThanBehind() throws {
        let route = TestFixtures.loop(distance: 10_000, seed: 5)
        let cumulative = route.cumulativeDistances
        let index = try XCTUnwrap(cumulative.firstIndex { $0 >= 3_000 })
        let onRoute = route.coordinates[index]
        let strayed = Geodesy.destination(from: onRoute, distance: 250, bearing: 0)

        let lastMatch = try XCTUnwrap(matcher.match(onRoute, on: route, near: nil))
        let rejoin = try XCTUnwrap(
            RejoinPointSelector.rejoinPoint(on: route, from: strayed, lastMatch: lastMatch)
        )

        XCTAssertGreaterThanOrEqual(
            rejoin.distanceAlongRoute,
            lastMatch.distanceAlongRoute - 1,
            "le point de reprise ne doit pas imposer de revenir en arrière"
        )
    }

    func testRejoinPointFallsBackToTheFinishNearTheEnd() throws {
        let route = TestFixtures.loop(distance: 5_000, seed: 2)
        let total = try XCTUnwrap(route.cumulativeDistances.last)
        let lastMatch = RouteMatch(
            segmentIndex: route.coordinates.count - 2,
            projectedPoint: try XCTUnwrap(route.coordinates.last),
            distanceFromRoute: 0,
            distanceAlongRoute: total,
            remainingDistance: 0
        )
        let rejoin = try XCTUnwrap(
            RejoinPointSelector.rejoinPoint(
                on: route,
                from: Geodesy.destination(
                    from: try XCTUnwrap(route.coordinates.last), distance: 300, bearing: 180
                ),
                lastMatch: lastMatch
            )
        )
        XCTAssertEqualWithTolerance(rejoin.distanceAlongRoute, total, tolerance: 1)
    }

    // MARK: - Moteur de navigation

    func testEngineAnnouncesManeuversOnceAtEachThreshold() {
        let route = TestFixtures.loop(distance: 6_000, seed: 6)
        var engine = NavigationEngine(route: route)
        let simulator = TrackSimulator(route: route, updateInterval: 1)

        var announcements: [String] = []
        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)) {
            for event in engine.update(with: sample) {
                if case .announce(let text, _) = event { announcements.append(text) }
            }
        }

        XCTAssertFalse(announcements.isEmpty)
        XCTAssertTrue(
            announcements.contains { $0.contains("Tournez") || $0.contains("Serrez") },
            "au moins une consigne de changement de direction était attendue"
        )
        XCTAssertTrue(announcements.contains("Vous êtes arrivé"))

        // Aucune annonce ne doit être répétée à l'identique deux fois de suite.
        for index in 1..<announcements.count {
            XCTAssertNotEqual(announcements[index], announcements[index - 1])
        }
    }

    func testEngineProducesHapticCuesBeforeTurns() {
        let route = TestFixtures.loop(distance: 6_000, seed: 6)
        var engine = NavigationEngine(route: route)
        let simulator = TrackSimulator(route: route, updateInterval: 1)

        var cues: [HapticCue] = []
        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)) {
            for event in engine.update(with: sample) {
                if case .haptic(let cue) = event { cues.append(cue) }
            }
        }
        XCTAssertTrue(cues.contains(.upcomingManeuver))
        XCTAssertTrue(cues.contains(.imminentManeuver))
        XCTAssertTrue(cues.contains(.arrival))
    }

    func testArrivalIsAnnouncedExactlyOnce() {
        let route = TestFixtures.loop(distance: 4_000, seed: 12)
        var engine = NavigationEngine(route: route)
        let simulator = TrackSimulator(route: route, updateInterval: 1)

        var arrivals = 0
        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)) {
            for event in engine.update(with: sample) where event == .arrived {
                arrivals += 1
            }
        }
        XCTAssertEqual(arrivals, 1)
        XCTAssertTrue(engine.state.hasArrived)
    }

    func testEstimatedArrivalIsConsistentWithRemainingDistance() throws {
        let route = TestFixtures.loop(distance: 10_000, seed: 7)
        var engine = NavigationEngine(route: route)
        let start = Date(timeIntervalSince1970: 0)
        let simulator = TrackSimulator(route: route, speed: 6.9, updateInterval: 1)

        for sample in simulator.samples(startingAt: start).prefix(120) {
            engine.update(with: sample)
        }

        let state = engine.state
        let arrival = try XCTUnwrap(state.estimatedArrival)
        XCTAssertGreaterThan(state.remainingDuration, 0)
        // À 25 km/h, il reste environ 9 km : entre 15 et 45 minutes.
        XCTAssertGreaterThan(arrival.timeIntervalSince(start), 900)
        XCTAssertLessThan(arrival.timeIntervalSince(start), 2_700)
    }

    func testReplacingRouteResetsNavigationState() {
        let route = TestFixtures.loop(distance: 5_000, seed: 1)
        var engine = NavigationEngine(route: route)
        let simulator = TrackSimulator(route: route, updateInterval: 1)
        for sample in simulator.samples(startingAt: Date(timeIntervalSince1970: 0)).prefix(30) {
            engine.update(with: sample)
        }
        XCTAssertNotNil(engine.state.match)

        let replacement = TestFixtures.loop(distance: 7_000, seed: 2)
        engine.replaceRoute(with: replacement)

        XCTAssertNil(engine.state.match)
        XCTAssertFalse(engine.state.isOffRoute)
        XCTAssertEqualWithTolerance(
            engine.state.remainingDistance, replacement.distance, tolerance: 1
        )
    }
}
