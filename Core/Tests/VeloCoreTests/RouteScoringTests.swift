import XCTest
@testable import VeloCore

/// Couvre le §17 du cahier des charges : « calcul de l'écart entre distance
/// souhaitée et distance obtenue », « sélection du meilleur circuit » et
/// « élimination des circuits invalides ».
final class RouteScoringTests: XCTestCase {
    private let scorer = RouteScorer(preferences: .default)

    // MARK: - Écart de distance

    func testDistanceDeviationRatioIsSignedAndRelative() throws {
        let route = TestFixtures.straightLine(length: 10_500, requestedDistance: 10_000)
        let deviation = try XCTUnwrap(route.distanceDeviationRatio)
        XCTAssertEqualWithTolerance(deviation, 0.05, tolerance: 0.005)

        let short = TestFixtures.straightLine(length: 9_000, requestedDistance: 10_000)
        let shortDeviation = try XCTUnwrap(short.distanceDeviationRatio)
        XCTAssertEqualWithTolerance(shortDeviation, -0.10, tolerance: 0.005)
    }

    func testDistanceDeviationIsNilWithoutRequestedDistance() {
        let route = TestFixtures.straightLine(length: 10_000)
        XCTAssertNil(route.distanceDeviationRatio)
    }

    func testDeviationWithinToleranceProducesNoWarning() {
        let route = TestFixtures.loop(distance: 10_000, seed: 3)
        let onTarget = CyclingRoute(
            coordinates: route.coordinates,
            distance: 10_200,
            duration: route.duration,
            requestedDistance: 10_000
        )
        XCTAssertFalse(scorer.warnings(for: onTarget).contains(.distanceOffTarget))
    }

    func testDeviationBeyondToleranceProducesWarning() {
        let route = TestFixtures.loop(distance: 10_000, seed: 3)
        let offTarget = CyclingRoute(
            coordinates: route.coordinates,
            distance: 13_000,
            duration: route.duration,
            requestedDistance: 10_000
        )
        XCTAssertTrue(scorer.warnings(for: offTarget).contains(.distanceOffTarget))
    }

    func testDeviationTextExplainsGapInFrench() throws {
        let route = TestFixtures.loop(distance: 10_000, seed: 3)
        let offTarget = CyclingRoute(
            coordinates: route.coordinates,
            distance: 12_000,
            duration: route.duration,
            requestedDistance: 10_000
        )
        let text = try XCTUnwrap(InstructionPhrasing.distanceDeviationText(route: offTarget))
        XCTAssertTrue(text.contains("20 %"), text)
        XCTAssertTrue(text.contains("de plus"), text)
    }

    // MARK: - Élimination des circuits invalides

    func testOutAndBackIsRejectedAsRepeatedSections() {
        let route = TestFixtures.outAndBack(length: 10_000)
        XCTAssertEqual(scorer.rejectionReason(for: route), .repeatedSections)
        XCTAssertFalse(scorer.isAcceptable(route))
    }

    func testUnclosedLoopIsRejected() {
        // Une ligne droite de 10 km finit à 10 km du départ : ce n'est pas une boucle.
        let route = TestFixtures.straightLine(length: 10_000, requestedDistance: 10_000)
        XCTAssertEqual(scorer.rejectionReason(for: route), .loopNotClosed)
    }

    func testGrosslyWrongDistanceIsRejected() {
        let loop = TestFixtures.loop(distance: 10_000, seed: 5)
        let wrong = CyclingRoute(
            coordinates: loop.coordinates,
            distance: loop.distance,
            duration: loop.duration,
            requestedDistance: loop.distance * 3
        )
        XCTAssertEqual(scorer.rejectionReason(for: wrong), .distanceOffTarget)
    }

    func testGravelIsRejectedOnlyWhenUserRefusesIt() {
        let loop = TestFixtures.loop(distance: 10_000, seed: 5)
        let half = loop.coordinates.count / 2
        let gravelRoute = CyclingRoute(
            coordinates: loop.coordinates,
            distance: loop.distance,
            duration: loop.duration,
            segments: [
                RouteSegment(startPointIndex: 0, endPointIndex: half,
                             surface: .gravel, wayKind: .path, distance: loop.distance / 2),
                RouteSegment(startPointIndex: half, endPointIndex: loop.coordinates.count - 1,
                             surface: .paved, wayKind: .road, distance: loop.distance / 2)
            ],
            requestedDistance: loop.distance
        )

        var strict = RoutingPreferences.default
        strict.rejectGravel = true
        XCTAssertEqual(
            RouteScorer(preferences: strict).rejectionReason(for: gravelRoute),
            .gravelSections
        )

        var tolerant = RoutingPreferences.default
        tolerant.rejectGravel = false
        XCTAssertNil(RouteScorer(preferences: tolerant).rejectionReason(for: gravelRoute))
    }

    func testGeneratedDemoLoopIsAccepted() {
        for seed in 1...8 {
            let route = TestFixtures.loop(distance: 15_000, seed: seed)
            XCTAssertNil(
                scorer.rejectionReason(for: route),
                "la boucle de démonstration \(seed) devrait être acceptée"
            )
        }
    }

    // MARK: - Répétition de tronçons

    func testRepeatedSectionRatioIsHighForOutAndBack() {
        let ratio = RouteQuality.repeatedSectionRatio(of: TestFixtures.outAndBack(length: 8_000))
        XCTAssertGreaterThan(ratio, 0.8)
    }

    func testRepeatedSectionRatioIsLowForRealLoop() {
        let ratio = RouteQuality.repeatedSectionRatio(of: TestFixtures.loop(distance: 20_000, seed: 2))
        XCTAssertLessThan(ratio, 0.1)
    }

    // MARK: - Sélection du meilleur circuit

    func testBestCandidateIsTheOneClosestToTarget() {
        let target = 20_000.0
        let candidates = [
            makeCandidate(distance: 26_000, target: target, seed: 1),
            makeCandidate(distance: 20_300, target: target, seed: 2),
            makeCandidate(distance: 15_500, target: target, seed: 3)
        ]
        let ranked = scorer.rank(candidates, limit: 3)
        XCTAssertEqual(ranked.first?.seed, 2)
    }

    func testRankingReturnsAtMostTheRequestedNumber() {
        let candidates = (1...7).map { makeCandidate(distance: 10_000, target: 10_000, seed: $0) }
        XCTAssertEqual(scorer.rank(candidates, limit: 3).count, 3)
    }

    func testRankingPrefersDistinctRoutesButStillFillsTheList() {
        // Deux candidats géométriquement identiques et un troisième différent :
        // le dédoublonnage doit privilégier la variété, sans renvoyer moins de
        // propositions que demandé.
        let shared = TestFixtures.loop(distance: 12_000, seed: 4)
        let duplicateA = scorer.makeCandidate(route: retarget(shared, to: 12_000), seed: 1)
        let duplicateB = scorer.makeCandidate(route: retarget(shared, to: 12_000), seed: 2)
        let distinct = scorer.makeCandidate(
            route: retarget(TestFixtures.loop(distance: 12_000, seed: 9), to: 12_000),
            seed: 3
        )

        let ranked = scorer.rank([duplicateA, duplicateB, distinct], limit: 3)
        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(Set(ranked.prefix(2).map(\.seed)).count, 2)
    }

    func testUTurnsArePenalised() {
        let base = TestFixtures.loop(distance: 10_000, seed: 6)
        let withUTurn = CyclingRoute(
            coordinates: base.coordinates,
            distance: base.distance,
            duration: base.duration,
            instructions: base.instructions + [
                NavigationInstruction(
                    maneuver: .uTurn, roadName: nil, distance: 10, duration: 5,
                    startPointIndex: 0, endPointIndex: 1
                )
            ],
            requestedDistance: base.distance
        )
        XCTAssertGreaterThan(scorer.score(withUTurn), scorer.score(retarget(base, to: base.distance)))
        XCTAssertTrue(scorer.warnings(for: withUTurn).contains(.containsUTurn))
    }

    func testCyclePathRatioAndUnpavedRatio() throws {
        let loop = TestFixtures.loop(distance: 9_000, seed: 7)
        XCTAssertNotNil(loop.cyclePathRatio)
        let ratio = try XCTUnwrap(loop.cyclePathRatio)
        XCTAssertGreaterThan(ratio, 0.2)
        XCTAssertLessThan(ratio, 0.5)
        XCTAssertEqualWithTolerance(try XCTUnwrap(loop.unpavedRatio), 0, tolerance: 0.001)
    }

    // MARK: - Utilitaires

    private func makeCandidate(distance: Double, target: Double, seed: Int) -> RouteCandidate {
        let base = TestFixtures.loop(distance: distance, seed: seed)
        let route = CyclingRoute(
            coordinates: base.coordinates,
            distance: distance,
            duration: base.duration,
            instructions: base.instructions,
            segments: base.segments,
            requestedDistance: target
        )
        return scorer.makeCandidate(route: route, seed: seed)
    }

    private func retarget(_ route: CyclingRoute, to target: Double) -> CyclingRoute {
        CyclingRoute(
            coordinates: route.coordinates,
            distance: route.distance,
            duration: route.duration,
            ascent: route.ascent,
            descent: route.descent,
            instructions: route.instructions,
            segments: route.segments,
            requestedDistance: target
        )
    }
}
