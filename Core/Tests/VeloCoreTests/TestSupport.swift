import Foundation
import XCTest
@testable import VeloCore

// MARK: - Doubles de test réseau

/// Client HTTP qui rejoue des réponses figées.
///
/// Aucun test n'utilise de clé API réelle ni n'atteint le réseau : le client
/// renvoie ce qu'on lui a donné, y compris les cas d'erreur.
struct MockHTTPClient: HTTPClient {
    enum Behaviour: Sendable {
        case respond(statusCode: Int, data: Data)
        case fail(VeloError)
    }

    let behaviour: Behaviour
    /// Capture des requêtes émises, pour vérifier le corps envoyé.
    let recorder: RequestRecorder

    init(behaviour: Behaviour, recorder: RequestRecorder = RequestRecorder()) {
        self.behaviour = behaviour
        self.recorder = recorder
    }

    static func returning(json: String, statusCode: Int = 200) -> MockHTTPClient {
        MockHTTPClient(behaviour: .respond(statusCode: statusCode, data: Data(json.utf8)))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        await recorder.record(request)
        switch behaviour {
        case .respond(let statusCode, let data):
            return HTTPResponse(statusCode: statusCode, data: data)
        case .fail(let error):
            throw error
        }
    }
}

actor RequestRecorder {
    private(set) var requests: [HTTPRequest] = []
    func record(_ request: HTTPRequest) { requests.append(request) }
    var lastBody: [String: Any]? {
        guard let body = requests.last?.body,
              let object = try? JSONSerialization.jsonObject(with: body) else { return nil }
        return object as? [String: Any]
    }
}

// MARK: - Doubles de test routage

/// Moteur de routage contrôlé : renvoie les circuits qu'on lui indique.
struct StubRoutingService: RoutingService {
    var isConfigured: Bool = true
    var supportsRoundTrips: Bool = true
    /// Renvoie un circuit en fonction de la graine demandée.
    var roundTripHandler: @Sendable (GeographicCoordinate, Double, Int) throws -> CyclingRoute
    var routeHandler: (@Sendable ([GeographicCoordinate]) throws -> CyclingRoute)?

    func roundTrip(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        seed: Int,
        points: Int,
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        try roundTripHandler(origin, targetDistance, seed)
    }

    func route(
        through waypoints: [GeographicCoordinate],
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        if let routeHandler { return try routeHandler(waypoints) }
        throw VeloError.noRouteFound
    }
}

// MARK: - Fabriques

enum TestFixtures {
    static let lausanne = GeographicCoordinate(latitude: 46.5197, longitude: 6.6323)

    /// Boucle de démonstration déterministe.
    static func loop(
        distance: Double = 10_000,
        seed: Int = 1,
        origin: GeographicCoordinate = lausanne
    ) -> CyclingRoute {
        DemoRouteFactory.makeLoop(origin: origin, targetDistance: distance, seed: seed)
    }

    /// Circuit rectiligne d'est en ouest, pratique pour vérifier des distances
    /// exactes sans dépendre de la géométrie d'une boucle.
    static func straightLine(
        from origin: GeographicCoordinate = lausanne,
        length: Double,
        bearing: Double = 90,
        spacing: Double = 50,
        requestedDistance: Double? = nil
    ) -> CyclingRoute {
        var coordinates: [GeographicCoordinate] = [origin]
        var travelled = 0.0
        while travelled < length {
            travelled = min(travelled + spacing, length)
            coordinates.append(
                Geodesy.destination(from: origin, distance: travelled, bearing: bearing)
            )
        }
        let measured = Geodesy.polylineLength(coordinates)
        let lastIndex = coordinates.count - 1
        return CyclingRoute(
            coordinates: coordinates,
            distance: measured,
            duration: measured / 6.5,
            instructions: [
                NavigationInstruction(
                    maneuver: .depart,
                    roadName: "Avenue d'Ouchy",
                    distance: measured / 2,
                    duration: measured / 2 / 6.5,
                    startPointIndex: 0,
                    endPointIndex: lastIndex / 2
                ),
                NavigationInstruction(
                    maneuver: .right,
                    roadName: "Chemin du Lac",
                    distance: measured / 2,
                    duration: measured / 2 / 6.5,
                    startPointIndex: lastIndex / 2,
                    endPointIndex: lastIndex
                ),
                NavigationInstruction(
                    maneuver: .arrive,
                    roadName: nil,
                    distance: 0,
                    duration: 0,
                    startPointIndex: lastIndex,
                    endPointIndex: lastIndex
                )
            ],
            requestedDistance: requestedDistance
        )
    }

    /// Aller-retour sur la même ligne : la « fausse boucle » type que la
    /// génération doit refuser.
    static func outAndBack(length: Double, origin: GeographicCoordinate = lausanne) -> CyclingRoute {
        let outbound = straightLine(from: origin, length: length / 2).coordinates
        let coordinates = outbound + outbound.dropLast().reversed()
        let measured = Geodesy.polylineLength(coordinates)
        return CyclingRoute(
            coordinates: coordinates,
            distance: measured,
            duration: measured / 6.5,
            requestedDistance: length
        )
    }

    /// Réponse GeoJSON minimale mais réaliste d'OpenRouteService.
    static let openRouteServiceGeoJSON = """
    {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": [
              [6.6323, 46.5197, 495.0],
              [6.6340, 46.5205, 498.0],
              [6.6362, 46.5211, 505.0],
              [6.6350, 46.5225, 511.0],
              [6.6330, 46.5218, 502.0],
              [6.6323, 46.5197, 495.0]
            ]
          },
          "properties": {
            "ascent": 21.0,
            "descent": 21.0,
            "summary": { "distance": 1180.4, "duration": 262.0 },
            "segments": [
              {
                "distance": 1180.4,
                "duration": 262.0,
                "steps": [
                  { "distance": 210.0, "duration": 46.0, "type": 11,
                    "instruction": "Head north", "name": "Rue de Bourg",
                    "way_points": [0, 1] },
                  { "distance": 190.0, "duration": 42.0, "type": 1,
                    "instruction": "Turn right", "name": "Avenue du Théâtre",
                    "way_points": [1, 2] },
                  { "distance": 300.0, "duration": 66.0, "type": 7,
                    "instruction": "Enter roundabout", "name": "-",
                    "exit_number": 2, "way_points": [2, 3] },
                  { "distance": 280.0, "duration": 62.0, "type": 0,
                    "instruction": "Turn left", "name": "Chemin des Vignes",
                    "way_points": [3, 4] },
                  { "distance": 200.4, "duration": 46.0, "type": 10,
                    "instruction": "Arrive at destination", "name": "-",
                    "way_points": [4, 5] }
                ]
              }
            ],
            "extras": {
              "surface": { "values": [[0, 3, 2], [3, 5, 10]] },
              "waytype": { "values": [[0, 2, 3], [2, 5, 5]] }
            }
          }
        }
      ]
    }
    """
}

// MARK: - Assertions

func XCTAssertEqualWithTolerance(
    _ value: Double,
    _ expected: Double,
    tolerance: Double,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        value, expected, accuracy: tolerance,
        message.isEmpty ? "attendu \(expected) ± \(tolerance), obtenu \(value)" : message,
        file: file, line: line
    )
}
