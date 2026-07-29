import XCTest
import SwiftData
@testable import VeloBoucle
import VeloCore

/// Tests de la couche application, exécutés dans le simulateur iOS.
///
/// Le cœur métier est couvert par `Core/Tests/VeloCoreTests`, exécutable sur
/// n'importe quelle plateforme. Ce fichier ne teste que ce qui dépend
/// réellement des frameworks Apple : lecture des secrets, persistance
/// SwiftData, recollement d'itinéraire après recalcul.
final class SecretsProviderTests: XCTestCase {
    func testEnvironmentVariableTakesPrecedence() {
        let key = SecretsProvider.openRouteServiceAPIKey(
            bundle: .main,
            environment: [SecretsProvider.environmentVariableName: "cle-environnement"]
        )
        XCTAssertEqual(key, "cle-environnement")
    }

    func testPlaceholderFromTheExampleFileIsNotTreatedAsAKey() {
        // Un Secrets.xcconfig copié mais non rempli ne doit pas produire une
        // erreur d'authentification incompréhensible.
        XCTAssertNil(
            SecretsProvider.openRouteServiceAPIKey(
                environment: [SecretsProvider.environmentVariableName: "VOTRE_CLE_ICI"]
            )
        )
    }

    func testUnexpandedBuildVariableIsNotTreatedAsAKey() {
        XCTAssertNil(
            SecretsProvider.openRouteServiceAPIKey(
                environment: [SecretsProvider.environmentVariableName: "$(ORS_API_KEY)"]
            )
        )
    }

    func testBlankValueIsIgnored() {
        XCTAssertNil(
            SecretsProvider.openRouteServiceAPIKey(
                environment: [SecretsProvider.environmentVariableName: "   "]
            )
        )
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(
            SecretsProvider.openRouteServiceAPIKey(
                environment: [SecretsProvider.environmentVariableName: "  cle-valide \n"]
            ),
            "cle-valide"
        )
    }
}

final class RouteSplicerTests: XCTestCase {
    private let origin = GeographicCoordinate(latitude: 46.5197, longitude: 6.6323)

    private func makeRoute(length: Double) -> CyclingRoute {
        var coordinates: [GeographicCoordinate] = []
        var travelled = 0.0
        while travelled <= length {
            coordinates.append(
                Geodesy.destination(from: origin, distance: travelled, bearing: 90)
            )
            travelled += 50
        }
        let measured = Geodesy.polylineLength(coordinates)
        let lastIndex = coordinates.count - 1
        return CyclingRoute(
            coordinates: coordinates,
            distance: measured,
            duration: measured / 6.5,
            instructions: [
                NavigationInstruction(
                    maneuver: .depart, roadName: "Départ", distance: measured / 2,
                    duration: 100, startPointIndex: 0, endPointIndex: lastIndex / 2
                ),
                NavigationInstruction(
                    maneuver: .right, roadName: "Virage", distance: measured / 2,
                    duration: 100, startPointIndex: lastIndex / 2, endPointIndex: lastIndex
                ),
                NavigationInstruction(
                    maneuver: .arrive, roadName: nil, distance: 0,
                    duration: 0, startPointIndex: lastIndex, endPointIndex: lastIndex
                )
            ],
            requestedDistance: length
        )
    }

    private func makeConnector(from: GeographicCoordinate, to: GeographicCoordinate) -> CyclingRoute {
        let length = Geodesy.distance(from: from, to: to)
        let steps = max(Int(length / 25), 2)
        let coordinates = (0...steps).map { step -> GeographicCoordinate in
            let fraction = Double(step) / Double(steps)
            return GeographicCoordinate(
                latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * fraction
            )
        }
        let measured = Geodesy.polylineLength(coordinates)
        return CyclingRoute(
            coordinates: coordinates,
            distance: measured,
            duration: measured / 6.5,
            instructions: [
                NavigationInstruction(
                    maneuver: .depart, roadName: "Rattrapage", distance: measured,
                    duration: measured / 6.5, startPointIndex: 0,
                    endPointIndex: coordinates.count - 1
                )
            ]
        )
    }

    func testSplicedRouteKeepsTheRemainderOfTheOriginal() throws {
        let original = makeRoute(length: 5_000)
        let rejoin = original.coordinates[original.coordinates.count / 2]
        let strayed = Geodesy.destination(from: rejoin, distance: 300, bearing: 0)
        let connector = makeConnector(from: strayed, to: rejoin)

        let merged = RouteSplicer.splice(
            connector: connector, into: original, rejoiningAt: rejoin, profile: .electricRoad
        )

        // Le nouveau circuit doit couvrir le rattrapage plus la moitié restante
        // du circuit initial : perdre la fin du parcours serait le pire défaut
        // possible d'un recalcul.
        XCTAssertGreaterThan(merged.distance, 2_400)
        XCTAssertEqual(merged.coordinates.first, strayed)
        XCTAssertEqual(merged.coordinates.last, original.coordinates.last)
    }

    func testSplicedInstructionsAreReindexedOntoTheNewPolyline() {
        let original = makeRoute(length: 4_000)
        let rejoinIndex = original.coordinates.count / 3
        let rejoin = original.coordinates[rejoinIndex]
        let strayed = Geodesy.destination(from: rejoin, distance: 200, bearing: 180)
        let connector = makeConnector(from: strayed, to: rejoin)

        let merged = RouteSplicer.splice(
            connector: connector, into: original, rejoiningAt: rejoin, profile: .road
        )

        XCTAssertFalse(merged.instructions.isEmpty)
        for instruction in merged.instructions {
            XCTAssertLessThan(
                instruction.endPointIndex, merged.coordinates.count,
                "une consigne pointe hors du nouveau tracé"
            )
            XCTAssertLessThanOrEqual(instruction.startPointIndex, instruction.endPointIndex)
        }
        // La consigne d'arrivée du circuit initial doit être conservée.
        XCTAssertTrue(merged.instructions.contains { $0.maneuver == .arrive })
    }

    func testSplicingDegenerateConnectorLeavesTheRouteUntouched() {
        let original = makeRoute(length: 3_000)
        let empty = CyclingRoute(coordinates: [], distance: 0, duration: 0)
        let merged = RouteSplicer.splice(
            connector: empty,
            into: original,
            rejoiningAt: original.coordinates[0],
            profile: .road
        )
        XCTAssertEqual(merged.coordinates.count, original.coordinates.count)
    }
}

@MainActor
final class PersistenceServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: PersistenceService!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: StoredRide.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = PersistenceService(context: ModelContext(container))
    }

    private func makeRide(name: String = "Sortie de test") -> RecordedRide {
        let route = DemoRouteFactory.makeLoop(
            origin: GeographicCoordinate(latitude: 46.5197, longitude: 6.6323),
            targetDistance: 8_000,
            seed: 3
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var tracker = RideTracker.start(
            at: start, name: name, plannedRoute: route, profile: .electricRoad
        )
        for sample in TrackSimulator(route: route, updateInterval: 4).samples(startingAt: start) {
            tracker.add(sample)
        }
        let session = tracker.finish(at: start.addingTimeInterval(1_200))
        return RecordedRide(
            session: session, finishedAt: start.addingTimeInterval(1_200), bodyMassKilograms: 75
        )
    }

    func testSaveThenLoadPreservesStatisticsAndTrack() async throws {
        let ride = makeRide()
        try await service.save(ride)

        let loaded = try await service.loadAll()
        XCTAssertEqual(loaded.count, 1)
        let restored = try XCTUnwrap(loaded.first)

        XCTAssertEqual(restored.id, ride.id)
        XCTAssertEqual(restored.name, ride.name)
        XCTAssertEqual(restored.track.count, ride.track.count)
        XCTAssertEqual(restored.statistics.distance, ride.statistics.distance, accuracy: 0.01)
        XCTAssertEqual(restored.plannedRoute?.coordinates.count, ride.plannedRoute?.coordinates.count)
    }

    func testSavingTheSameIdentifierReplacesRatherThanDuplicates() async throws {
        // Une sortie reprise après interruption garde son identifiant : elle ne
        // doit pas apparaître deux fois dans l'historique.
        let ride = makeRide()
        try await service.save(ride)
        try await service.save(ride)
        let loaded = try await service.loadAll()
        XCTAssertEqual(loaded.count, 1)
    }

    func testRenameAndDelete() async throws {
        let ride = makeRide()
        try await service.save(ride)

        try await service.rename(id: ride.id, to: "Tour du Léman")
        var loaded = try await service.loadAll()
        XCTAssertEqual(loaded.first?.name, "Tour du Léman")

        // Un nom vide ne doit pas écraser un nom existant.
        try await service.rename(id: ride.id, to: "   ")
        loaded = try await service.loadAll()
        XCTAssertEqual(loaded.first?.name, "Tour du Léman")

        try await service.delete(id: ride.id)
        loaded = try await service.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testHistoryIsSortedNewestFirst() async throws {
        var older = makeRide(name: "Ancienne")
        older = RecordedRide(
            id: UUID(), name: older.name,
            startedAt: Date(timeIntervalSince1970: 1_600_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_600_003_600),
            statistics: older.statistics, track: older.track,
            plannedRoute: nil, deviations: [], profile: .road, bodyMassKilograms: 75
        )
        try await service.save(older)
        try await service.save(makeRide(name: "Récente"))

        let loaded = try await service.loadAll()
        XCTAssertEqual(loaded.map(\.name), ["Récente", "Ancienne"])
    }

    func testThumbnailPreviewIsDownsampled() throws {
        let stored = try StoredRide(ride: makeRide())
        let preview = stored.trackPreview(maximumPoints: 40)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertLessThanOrEqual(preview.count, 42)
    }
}
