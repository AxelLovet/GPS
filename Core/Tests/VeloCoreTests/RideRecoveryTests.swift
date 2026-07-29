import XCTest
@testable import VeloCore

/// Couvre le §17 : « reprise d'une sortie interrompue ».
final class RideRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeInterruptedSession(
        distance: Double,
        minutesAgo: Double
    ) -> RideSession {
        let route = TestFixtures.loop(distance: 20_000, seed: 4)
        let startedAt = now.addingTimeInterval(-minutesAgo * 60 - 1_800)
        var tracker = RideTracker.start(
            at: startedAt, name: "Sortie interrompue", plannedRoute: route, profile: .electricRoad
        )
        for sample in TrackSimulator(route: route, speed: 6.5, updateInterval: 2)
            .samples(startingAt: startedAt) {
            tracker.add(sample)
            if tracker.session.statistics.distance >= distance { break }
        }
        var session = tracker.session
        session.lastUpdatedAt = now.addingTimeInterval(-minutesAgo * 60)
        return session
    }

    // MARK: - Décision

    func testRecentInterruptedRideIsOfferedForResume() {
        let session = makeInterruptedSession(distance: 6_000, minutesAgo: 4)
        guard case .offerResume(let recovered) = RideRecovery.decide(for: session, now: now) else {
            return XCTFail("une reprise aurait dû être proposée")
        }
        XCTAssertEqual(recovered.id, session.id)
        XCTAssertGreaterThan(recovered.statistics.distance, 5_000)
    }

    func testOldRideIsOfferedForSavingButNotForResume() {
        let session = makeInterruptedSession(distance: 8_000, minutesAgo: 20 * 60)
        guard case .offerSaveOnly(let recovered) = RideRecovery.decide(for: session, now: now) else {
            return XCTFail("un enregistrement seul aurait dû être proposé")
        }
        XCTAssertGreaterThan(recovered.statistics.distance, 500)
    }

    func testOldAndNearlyEmptyRideIsDiscarded() {
        var session = makeInterruptedSession(distance: 100, minutesAgo: 30 * 60)
        session.statistics.distance = 120
        XCTAssertEqual(RideRecovery.decide(for: session, now: now), .discard)
    }

    func testNoSnapshotMeansNothingToRecover() {
        XCTAssertEqual(RideRecovery.decide(for: nil, now: now), .discard)
    }

    func testFinishedSessionIsNeverOffered() {
        var session = makeInterruptedSession(distance: 5_000, minutesAgo: 2)
        session.state = .finished
        XCTAssertEqual(RideRecovery.decide(for: session, now: now), .discard)
    }

    func testResumedSessionStartsPausedAndDoesNotSwallowTheGap() {
        let session = makeInterruptedSession(distance: 6_000, minutesAgo: 5)
        let elapsedBefore = session.statistics.elapsedTime

        let resumed = RideRecovery.prepareResume(session, now: now)

        XCTAssertEqual(resumed.state, .paused)
        XCTAssertEqual(resumed.lastUpdatedAt, now)
        // Les cinq minutes pendant lesquelles l'application était fermée ne
        // doivent pas être comptées comme du temps de sortie.
        XCTAssertEqualWithTolerance(resumed.statistics.elapsedTime, elapsedBefore, tolerance: 0.01)
        XCTAssertEqual(resumed.statistics.distance, session.statistics.distance)
        XCTAssertEqual(resumed.track.count, session.track.count)
    }

    func testResumedRideCanContinueAccumulatingDistance() {
        let session = RideRecovery.prepareResume(
            makeInterruptedSession(distance: 4_000, minutesAgo: 3),
            now: now
        )
        var tracker = RideTracker(session: session)
        let distanceBefore = tracker.session.statistics.distance

        tracker.resume(at: now)
        let lastPosition = try? XCTUnwrap(session.track.last).coordinate
        guard let lastPosition else { return XCTFail("trace vide") }

        for index in 1...40 {
            let position = Geodesy.destination(
                from: lastPosition, distance: Double(index) * 12, bearing: 45
            )
            tracker.add(
                LocationSample(coordinate: position, timestamp: now.addingTimeInterval(Double(index) * 2))
            )
        }

        XCTAssertGreaterThan(tracker.session.statistics.distance, distanceBefore + 400)
        XCTAssertEqual(tracker.session.state, .running)
    }

    // MARK: - Persistance de l'instantané

    func testSnapshotSurvivesAWriteReadCycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileRideSnapshotStore(
            fileURL: directory.appendingPathComponent("session.json")
        )
        let session = makeInterruptedSession(distance: 3_000, minutesAgo: 1)

        try await store.write(session)
        let restored = try await store.read()

        let recovered = try XCTUnwrap(restored)
        XCTAssertEqual(recovered.id, session.id)
        XCTAssertEqual(recovered.track.count, session.track.count)
        XCTAssertEqualWithTolerance(
            recovered.statistics.distance, session.statistics.distance, tolerance: 0.01
        )
        XCTAssertEqual(recovered.plannedRoute?.coordinates.count,
                       session.plannedRoute?.coordinates.count)

        try await store.clear()
        let cleared = try await store.read()
        XCTAssertNil(cleared)
    }

    func testReadingAbsentSnapshotReturnsNil() async throws {
        let store = FileRideSnapshotStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).json")
        )
        let session = try await store.read()
        XCTAssertNil(session)
    }

    func testCorruptedSnapshotIsReportedRatherThanCrashing() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try Data("ceci n'est pas du json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileRideSnapshotStore(fileURL: url)
        do {
            _ = try await store.read()
            XCTFail("une erreur était attendue")
        } catch {
            guard case .rideRecoveryFailed = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
        }
    }
}
