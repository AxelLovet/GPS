import XCTest
@testable import VeloCore

/// Vérifie la génération de boucles de bout en bout, avec un moteur simulé.
final class LoopGenerationTests: XCTestCase {
    private let origin = TestFixtures.lausanne

    // MARK: - Cas nominal

    func testGeneratesAtLeastThreeDistinctProposals() async throws {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let result = try await service.generateLoops(
            from: origin, targetDistance: 20_000, preferences: .default
        )

        XCTAssertEqual(result.candidates.count, 3)
        XCTAssertNotNil(result.recommended)
        XCTAssertEqual(result.alternatives.count, 2)
        XCTAssertGreaterThanOrEqual(result.evaluatedCount, 3)

        // Les propositions doivent être réellement différentes.
        let identifiers = Set(result.candidates.map(\.id))
        XCTAssertEqual(identifiers.count, 3)
    }

    func testEveryProposalIsAClosedLoop() async throws {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let result = try await service.generateLoops(
            from: origin, targetDistance: 15_000, preferences: .default
        )

        for candidate in result.candidates {
            let tolerance = RouteQuality.closureTolerance(for: candidate.route.distance)
            XCTAssertLessThanOrEqual(
                candidate.route.loopClosureDistance, tolerance,
                "le circuit \(candidate.seed) ne se referme pas"
            )
            XCTAssertLessThan(candidate.repeatedSectionRatio, 0.45)
        }
    }

    func testRecommendedProposalIsTheBestScored() async throws {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let result = try await service.generateLoops(
            from: origin, targetDistance: 10_000, preferences: .default
        )
        let recommended = try XCTUnwrap(result.recommended)
        for alternative in result.alternatives {
            XCTAssertLessThanOrEqual(recommended.score, alternative.score)
        }
    }

    func testProgressIsReportedFromZeroToCompletion() async throws {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let collector = ProgressCollector()

        _ = try await service.generateLoops(
            from: origin,
            targetDistance: 12_000,
            preferences: .default,
            onProgress: { progress in collector.append(progress) }
        )

        let reports = collector.reports
        XCTAssertGreaterThan(reports.count, 2)
        XCTAssertEqual(reports.first?.completed, 0)
        XCTAssertEqualWithTolerance(try XCTUnwrap(reports.last?.fraction), 1, tolerance: 0.001)
        // L'avancement ne doit jamais reculer, même quand une seconde passe
        // ajoute des tentatives.
        for index in 1..<reports.count {
            XCTAssertGreaterThanOrEqual(reports[index].completed, reports[index - 1].completed)
        }
    }

    // MARK: - Précision de la distance

    func testCorrectivePassImprovesDistanceAccuracy() async throws {
        // Ce moteur simulé renvoie systématiquement 40 % de trop pour la
        // longueur demandée : c'est le comportement typique de `round_trip`
        // qu'il faut rattraper.
        let overshooting = StubRoutingService(
            roundTripHandler: { origin, requested, seed in
                let inflated = requested * 1.4
                let route = DemoRouteFactory.makeLoop(
                    origin: origin, targetDistance: inflated, seed: seed
                )
                return CyclingRoute(
                    coordinates: route.coordinates,
                    distance: inflated,
                    duration: route.duration,
                    instructions: route.instructions,
                    segments: route.segments,
                    requestedDistance: requested
                )
            },
            routeHandler: { waypoints in
                let route = try DemoLoopFromWaypoints.make(waypoints)
                return route
            }
        )

        let service = LoopGenerationService(routingService: overshooting)
        let result = try await service.generateLoops(
            from: origin, targetDistance: 20_000, preferences: .default
        )

        let best = try XCTUnwrap(result.recommended)
        let deviation = abs(try XCTUnwrap(best.route.distanceDeviationRatio))
        XCTAssertLessThan(
            deviation, 0.25,
            "la passe corrective aurait dû réduire l'écart initial de 40 %"
        )
    }

    func testDeviationIsMeasuredAgainstWhatTheUserAskedFor() async throws {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let result = try await service.generateLoops(
            from: origin, targetDistance: 25_000, preferences: .default
        )
        for candidate in result.candidates {
            XCTAssertEqual(candidate.route.requestedDistance, 25_000)
        }
    }

    // MARK: - Erreurs

    func testMissingAPIKeyStopsGenerationImmediately() async {
        let unconfigured = StubRoutingService(
            isConfigured: false,
            roundTripHandler: { _, _, _ in XCTFail("aucun appel réseau attendu"); throw VeloError.noRouteFound }
        )
        let service = LoopGenerationService(routingService: unconfigured)
        do {
            _ = try await service.generateLoops(
                from: origin, targetDistance: 10_000, preferences: .default
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .missingAPIKey)
        }
    }

    func testInvalidOriginIsRejected() async {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        do {
            _ = try await service.generateLoops(
                from: GeographicCoordinate(latitude: 0, longitude: 0),
                targetDistance: 10_000,
                preferences: .default
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .locationUnavailable)
        }
    }

    func testAbsurdlyShortDistanceIsRejected() async {
        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        do {
            _ = try await service.generateLoops(
                from: origin, targetDistance: 200, preferences: .default
            )
            XCTFail("une erreur était attendue")
        } catch {
            guard case .loopDistanceUnreachable = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
        }
    }

    func testTotalEngineFailureSurfacesTheUnderlyingError() async {
        let failing = StubRoutingService(
            roundTripHandler: { _, _, _ in throw VeloError.quotaExceeded },
            routeHandler: { _ in throw VeloError.quotaExceeded }
        )
        let service = LoopGenerationService(routingService: failing)
        do {
            _ = try await service.generateLoops(
                from: origin, targetDistance: 10_000, preferences: .default
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .quotaExceeded)
        }
    }

    func testPartialEngineFailureStillProducesProposals() async throws {
        // Une tentative sur deux échoue : la génération doit aboutir malgré tout.
        let counter = CallCounter()
        let flaky = StubRoutingService(
            roundTripHandler: { origin, requested, seed in
                guard counter.increment() % 2 == 0 else { throw VeloError.requestTimedOut }
                return DemoRouteFactory.makeLoop(
                    origin: origin, targetDistance: requested, seed: seed
                )
            },
            routeHandler: { waypoints in try DemoLoopFromWaypoints.make(waypoints) }
        )
        let service = LoopGenerationService(routingService: flaky)
        let result = try await service.generateLoops(
            from: origin, targetDistance: 15_000, preferences: .default
        )
        XCTAssertFalse(result.candidates.isEmpty)
    }

    func testEveryRouteRejectedProducesAnActionableError() async {
        // Le moteur ne renvoie que des allers-retours : rien n'est acceptable.
        let outAndBackOnly = StubRoutingService(
            roundTripHandler: { _, requested, _ in TestFixtures.outAndBack(length: requested) },
            routeHandler: { _ in TestFixtures.outAndBack(length: 10_000) }
        )
        let service = LoopGenerationService(routingService: outAndBackOnly)
        do {
            _ = try await service.generateLoops(
                from: origin, targetDistance: 10_000, preferences: .default
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .allCandidatesRejected)
            XCTAssertTrue(
                (error as? VeloError)?.recoveryActions.contains(.changeDistance) ?? false
            )
        }
    }

    func testCancellationStopsGeneration() async {
        let service = LoopGenerationService(
            routingService: DemoRoutingService(simulatedLatency: 0.4)
        )
        let task = Task {
            try await service.generateLoops(
                from: origin, targetDistance: 20_000, preferences: .default
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            // Une génération très rapide peut aboutir avant l'annulation ; ce
            // n'est pas un échec, seul un blocage le serait.
        } catch {
            XCTAssertTrue(error is CancellationError || error is VeloError)
        }
    }

    // MARK: - Direction préférée

    func testPreferredDirectionInfluencesTheChosenLoop() async throws {
        var north = RoutingPreferences.default
        north.preferredDirection = .north
        var south = RoutingPreferences.default
        south.preferredDirection = .south

        let service = LoopGenerationService(routingService: DemoRoutingService(simulatedLatency: 0))
        let northResult = try await service.generateLoops(
            from: origin, targetDistance: 12_000, preferences: north
        )
        let southResult = try await service.generateLoops(
            from: origin, targetDistance: 12_000, preferences: south
        )

        let northCentroid = try XCTUnwrap(
            Geodesy.centroid(of: XCTUnwrap(northResult.recommended).route.coordinates)
        )
        let southCentroid = try XCTUnwrap(
            Geodesy.centroid(of: XCTUnwrap(southResult.recommended).route.coordinates)
        )
        XCTAssertGreaterThan(
            northCentroid.latitude, southCentroid.latitude,
            "la boucle « nord » devrait se situer plus au nord que la boucle « sud »"
        )
    }

    // MARK: - Points de passage

    func testPolygonWaypointsFormAClosedRingOfTheRightScale() {
        let waypoints = WaypointLoopPlanner.waypoints(
            around: origin, targetDistance: 20_000, bearing: 90, waypointCount: 4
        )
        XCTAssertEqual(waypoints.first, origin)
        XCTAssertEqual(waypoints.last, origin)
        XCTAssertEqual(waypoints.count, 6)

        // Le périmètre du polygone, majoré du facteur de détour, doit approcher
        // la distance visée.
        let perimeter = Geodesy.polylineLength(waypoints)
        let expected = 20_000 / WaypointLoopPlanner.detourFactor
        XCTAssertEqualWithTolerance(perimeter, expected, tolerance: expected * 0.15)
    }

    func testCandidateBearingsSpreadAroundThePreferredDirection() {
        let any = WaypointLoopPlanner.candidateBearings(preferred: .any, count: 4)
        XCTAssertEqual(any, [0, 90, 180, 270])

        let east = WaypointLoopPlanner.candidateBearings(preferred: .east, count: 3)
        XCTAssertEqual(east.count, 3)
        for bearing in east {
            XCTAssertLessThanOrEqual(abs(Geodesy.bearingDelta(from: 90, to: bearing)), 50)
        }
    }
}

// MARK: - Utilitaires de test

/// Collecteur d'avancement sûr à traverser les tâches concurrentes.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LoopGenerationProgress] = []

    func append(_ progress: LoopGenerationProgress) {
        lock.lock(); defer { lock.unlock() }
        storage.append(progress)
    }

    var reports: [LoopGenerationProgress] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Construit une boucle de test à partir de points de passage.
private enum DemoLoopFromWaypoints {
    static func make(_ waypoints: [GeographicCoordinate]) throws -> CyclingRoute {
        guard let origin = waypoints.first else { throw VeloError.noRouteFound }
        let perimeter = Geodesy.polylineLength(waypoints)
        return DemoRouteFactory.makeLoop(
            origin: origin,
            targetDistance: perimeter * WaypointLoopPlanner.detourFactor,
            seed: Int(perimeter.rounded())
        )
    }
}
