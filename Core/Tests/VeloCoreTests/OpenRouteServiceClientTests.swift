import XCTest
@testable import VeloCore

/// Vérifie le client OpenRouteService sans réseau et **sans clé API réelle**.
final class OpenRouteServiceClientTests: XCTestCase {
    private let preferences = RoutingPreferences.default

    // MARK: - Décodage

    func testDecodesGeometryInstructionsAndElevation() throws {
        let route = try OpenRouteServiceClient.decodeRoute(
            from: Data(TestFixtures.openRouteServiceGeoJSON.utf8),
            preferences: preferences,
            requestedDistance: 1_200
        )

        XCTAssertEqual(route.coordinates.count, 6)
        // GeoJSON stocke [longitude, latitude] : l'inversion doit être faite.
        XCTAssertEqualWithTolerance(route.coordinates[0].latitude, 46.5197, tolerance: 1e-6)
        XCTAssertEqualWithTolerance(route.coordinates[0].longitude, 6.6323, tolerance: 1e-6)
        XCTAssertEqualWithTolerance(try XCTUnwrap(route.coordinates[0].altitude), 495, tolerance: 0.01)

        XCTAssertEqualWithTolerance(route.distance, 1_180.4, tolerance: 0.1)
        XCTAssertEqualWithTolerance(route.duration, 262, tolerance: 0.1)
        XCTAssertEqualWithTolerance(try XCTUnwrap(route.ascent), 21, tolerance: 0.1)
        XCTAssertEqual(route.instructions.count, 5)
        XCTAssertEqual(route.requestedDistance, 1_200)
    }

    func testTranslatesManeuverCodes() throws {
        let route = try OpenRouteServiceClient.decodeRoute(
            from: Data(TestFixtures.openRouteServiceGeoJSON.utf8),
            preferences: preferences,
            requestedDistance: nil
        )
        XCTAssertEqual(
            route.instructions.map(\.maneuver),
            [.depart, .right, .roundaboutEnter, .left, .arrive]
        )
        XCTAssertEqual(route.instructions[2].roundaboutExitNumber, 2)
    }

    func testUnnamedRoadsAreNotExposedAsDash() throws {
        // ORS utilise "-" pour une voie sans nom ; l'afficher tel quel donnerait
        // « Tournez à droite sur - ».
        let route = try OpenRouteServiceClient.decodeRoute(
            from: Data(TestFixtures.openRouteServiceGeoJSON.utf8),
            preferences: preferences,
            requestedDistance: nil
        )
        XCTAssertNil(route.instructions[2].roadName)
        XCTAssertEqual(route.instructions[1].roadName, "Avenue du Théâtre")
    }

    func testDecodesSurfaceAndWayTypeSegments() throws {
        let route = try OpenRouteServiceClient.decodeRoute(
            from: Data(TestFixtures.openRouteServiceGeoJSON.utf8),
            preferences: preferences,
            requestedDistance: nil
        )
        XCTAssertFalse(route.segments.isEmpty)
        XCTAssertTrue(route.segments.contains { $0.surface == .gravel })
        XCTAssertTrue(route.segments.contains { $0.wayKind == .cyclePath })
        XCTAssertNotNil(route.cyclePathRatio)
    }

    func testRejectsResponseWithoutFeatures() {
        let json = #"{"type":"FeatureCollection","features":[]}"#
        XCTAssertThrowsError(
            try OpenRouteServiceClient.decodeRoute(
                from: Data(json.utf8), preferences: preferences, requestedDistance: nil
            )
        ) { error in
            XCTAssertEqual(error as? VeloError, .noRouteFound)
        }
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(
            try OpenRouteServiceClient.decodeRoute(
                from: Data("pas du json".utf8), preferences: preferences, requestedDistance: nil
            )
        ) { error in
            guard case .invalidRoutingResponse = error as? VeloError else {
                return XCTFail("erreur inattendue : \(error)")
            }
        }
    }

    func testFallsBackToMeasuredDistanceWhenSummaryIsInconsistent() throws {
        // Une longueur annoncée absurde ne doit pas être affichée à
        // l'utilisateur : la géométrie réellement dessinée fait foi.
        let json = TestFixtures.openRouteServiceGeoJSON
            .replacingOccurrences(of: "\"distance\": 1180.4", with: "\"distance\": 99999.0")
        let route = try OpenRouteServiceClient.decodeRoute(
            from: Data(json.utf8), preferences: preferences, requestedDistance: nil
        )
        XCTAssertEqualWithTolerance(route.distance, route.measuredDistance, tolerance: 1)
        XCTAssertLessThan(route.distance, 5_000)
    }

    // MARK: - Requêtes et erreurs

    func testMissingAPIKeyIsReportedBeforeAnyNetworkCall() async {
        let client = OpenRouteServiceClient(
            apiKey: "   ",
            httpClient: MockHTTPClient.returning(json: TestFixtures.openRouteServiceGeoJSON)
        )
        XCTAssertFalse(client.isConfigured)
        do {
            _ = try await client.roundTrip(
                from: TestFixtures.lausanne, targetDistance: 10_000,
                seed: 1, points: 4, preferences: preferences
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .missingAPIKey)
        }
    }

    func testRoundTripRequestCarriesLoopParameters() async throws {
        let recorder = RequestRecorder()
        let client = OpenRouteServiceClient(
            apiKey: "cle-de-test",
            httpClient: MockHTTPClient(
                behaviour: .respond(
                    statusCode: 200,
                    data: Data(TestFixtures.openRouteServiceGeoJSON.utf8)
                ),
                recorder: recorder
            )
        )

        _ = try await client.roundTrip(
            from: TestFixtures.lausanne, targetDistance: 15_000,
            seed: 7, points: 5, preferences: preferences
        )

        let capturedBody = await recorder.lastBody
        let body = try XCTUnwrap(capturedBody)
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        let roundTrip = try XCTUnwrap(options["round_trip"] as? [String: Any])
        XCTAssertEqual(roundTrip["length"] as? Double, 15_000)
        XCTAssertEqual(roundTrip["seed"] as? Int, 7)
        XCTAssertEqual(roundTrip["points"] as? Int, 5)
        XCTAssertEqual(body["language"] as? String, "fr")
        XCTAssertEqual(body["elevation"] as? Bool, true)

        // Une requête de boucle ne porte qu'une seule coordonnée : c'est le
        // minimum d'information envoyé au service (voir PRIVACY.md).
        let coordinates = try XCTUnwrap(body["coordinates"] as? [[Double]])
        XCTAssertEqual(coordinates.count, 1)
    }

    func testProfileIdentifierFollowsUserPreference() async throws {
        let recorder = RequestRecorder()
        var electric = RoutingPreferences.default
        electric.profile = .electricRoad
        let client = OpenRouteServiceClient(
            apiKey: "cle-de-test",
            httpClient: MockHTTPClient(
                behaviour: .respond(
                    statusCode: 200,
                    data: Data(TestFixtures.openRouteServiceGeoJSON.utf8)
                ),
                recorder: recorder
            )
        )
        _ = try await client.roundTrip(
            from: TestFixtures.lausanne, targetDistance: 10_000,
            seed: 1, points: 4, preferences: electric
        )
        let capturedRequests = await recorder.requests
        let url = try XCTUnwrap(capturedRequests.last?.url.absoluteString)
        XCTAssertTrue(url.hasSuffix("/v2/directions/cycling-electric/geojson"), url)
    }

    func testHTTPStatusCodesMapToActionableErrors() async {
        let cases: [(Int, VeloError)] = [
            (401, .invalidAPIKey),
            (403, .invalidAPIKey),
            (429, .quotaExceeded),
            (404, .noRouteFound),
            (500, .routingEngineUnavailable(statusCode: 500))
        ]

        for (statusCode, expected) in cases {
            let client = OpenRouteServiceClient(
                apiKey: "cle-de-test",
                httpClient: MockHTTPClient(behaviour: .respond(statusCode: statusCode, data: Data()))
            )
            do {
                _ = try await client.roundTrip(
                    from: TestFixtures.lausanne, targetDistance: 10_000,
                    seed: 1, points: 4, preferences: preferences
                )
                XCTFail("une erreur était attendue pour le code \(statusCode)")
            } catch {
                XCTAssertEqual(error as? VeloError, expected, "code \(statusCode)")
            }
        }
    }

    func testEngineErrorPayloadForUnroutablePointIsRecognised() async {
        let payload = #"{"error":{"code":2010,"message":"Could not find routable point"}}"#
        let client = OpenRouteServiceClient(
            apiKey: "cle-de-test",
            httpClient: MockHTTPClient(
                behaviour: .respond(statusCode: 400, data: Data(payload.utf8))
            )
        )
        do {
            _ = try await client.roundTrip(
                from: TestFixtures.lausanne, targetDistance: 10_000,
                seed: 1, points: 4, preferences: preferences
            )
            XCTFail("une erreur était attendue")
        } catch {
            XCTAssertEqual(error as? VeloError, .noRouteFound)
        }
    }

    func testEveryErrorOffersAFrenchExplanationAndAnAction() {
        let errors: [VeloError] = [
            .noInternetConnection, .requestTimedOut, .routingEngineUnavailable(statusCode: 503),
            .missingAPIKey, .invalidAPIKey, .quotaExceeded,
            .invalidRoutingResponse(reason: "test"), .noRouteFound,
            .loopDistanceUnreachable(requested: 20_000, best: 12_400), .allCandidatesRejected,
            .locationPermissionDenied, .locationPermissionRestricted, .locationUnavailable,
            .locationAccuracyReduced, .locationTimedOut, .navigationInterrupted,
            .rideRecoveryFailed(reason: "test"), .persistenceFailure(reason: "test"),
            .gpxParsingFailed(reason: "test")
        ]

        for error in errors {
            XCTAssertFalse(error.title.isEmpty, "\(error)")
            XCTAssertGreaterThan(error.message.count, 20, "\(error)")
            XCTAssertFalse(error.recoveryActions.isEmpty, "\(error)")
        }
    }

    func testUnreachableDistanceErrorQuotesBothDistances() {
        let error = VeloError.loopDistanceUnreachable(requested: 20_000, best: 12_400)
        XCTAssertTrue(error.message.contains("20 km"), error.message)
        XCTAssertTrue(error.message.contains("12,4 km"), error.message)
    }
}
