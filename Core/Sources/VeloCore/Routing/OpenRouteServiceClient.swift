import Foundation

/// Client OpenRouteService.
///
/// Voir `docs/ROUTING_ENGINE.md` pour la justification de ce choix et le détail
/// du protocole. Ce type est la **seule** partie de l'application qui connaît
/// OpenRouteService.
public struct OpenRouteServiceClient: RoutingService {
    /// Base de l'API. Modifiable pour pointer vers une instance auto-hébergée.
    public let baseURL: URL
    private let apiKey: String?
    private let httpClient: HTTPClient
    private let timeout: TimeInterval

    public init(
        apiKey: String?,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = URL(string: "https://api.openrouteservice.org")!,
        timeout: TimeInterval = 40
    ) {
        // Une chaîne vide ou constituée d'espaces équivaut à l'absence de clé :
        // c'est le cas typique d'un `Secrets.xcconfig` créé mais non rempli.
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public var isConfigured: Bool { apiKey != nil }
    public var supportsRoundTrips: Bool { true }

    // MARK: - Requêtes

    public func roundTrip(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        seed: Int,
        points: Int,
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        guard origin.isValid else {
            throw VeloError.invalidRoutingResponse(reason: "point de départ invalide")
        }

        var options: [String: Any] = [
            "round_trip": [
                "length": targetDistance,
                "points": points,
                "seed": seed
            ]
        ]
        if let features = avoidFeatures(for: preferences) {
            options["avoid_features"] = features
        }
        if let profileParams = profileParameters(for: preferences) {
            options["profile_params"] = profileParams
        }

        let body: [String: Any] = [
            "coordinates": [[origin.longitude, origin.latitude]],
            "options": options,
            "instructions": true,
            "instructions_format": "text",
            "language": "fr",
            "elevation": true,
            "extra_info": ["surface", "waytype", "steepness"],
            "units": "m",
            "geometry_simplify": false
        ]

        return try await performRequest(
            body: body,
            preferences: preferences,
            requestedDistance: targetDistance
        )
    }

    public func route(
        through waypoints: [GeographicCoordinate],
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        guard waypoints.count >= 2 else {
            throw VeloError.invalidRoutingResponse(reason: "au moins deux points sont nécessaires")
        }
        guard waypoints.allSatisfy({ $0.isValid }) else {
            throw VeloError.invalidRoutingResponse(reason: "point de passage invalide")
        }

        var options: [String: Any] = [:]
        if let features = avoidFeatures(for: preferences) {
            options["avoid_features"] = features
        }
        if let profileParams = profileParameters(for: preferences) {
            options["profile_params"] = profileParams
        }

        var body: [String: Any] = [
            "coordinates": waypoints.map { [$0.longitude, $0.latitude] },
            "instructions": true,
            "instructions_format": "text",
            "language": "fr",
            "elevation": true,
            "extra_info": ["surface", "waytype", "steepness"],
            "units": "m",
            "geometry_simplify": false
        ]
        if !options.isEmpty {
            body["options"] = options
        }

        return try await performRequest(body: body, preferences: preferences, requestedDistance: nil)
    }

    // MARK: - Construction des options

    /// Éléments de réseau que le moteur doit éviter.
    ///
    /// Les autoroutes n'ont pas besoin d'être listées : les profils vélo d'ORS
    /// s'appuient sur les restrictions d'accès OpenStreetMap et n'empruntent
    /// jamais une voie interdite aux cycles. On écarte en revanche les ferries
    /// (payants, horaires) et, selon les préférences, les routes à fort trafic
    /// et les passages à gué.
    private func avoidFeatures(for preferences: RoutingPreferences) -> [String]? {
        var features = ["ferries"]
        if preferences.avoidHighTrafficRoads {
            features.append("highways")
        }
        if preferences.avoidUnpavedSurfaces || preferences.rejectGravel {
            features.append("fords")
        }
        return features
    }

    /// Paramètres fins du profil : type de revêtement et difficulté acceptés.
    private func profileParameters(for preferences: RoutingPreferences) -> [String: Any]? {
        var restrictions: [String: Any] = [:]

        // `surface_type` retient les revêtements *au moins* aussi bons que la
        // valeur donnée. « asphalt » exclut donc terre, herbe et gravier.
        if preferences.avoidUnpavedSurfaces || preferences.rejectGravel {
            restrictions["surface_type"] = "asphalt"
        }
        if preferences.avoidSteepClimbs {
            restrictions["maximum_incline"] = Int(preferences.maximumComfortableGradient)
        }

        guard !restrictions.isEmpty else { return nil }

        var parameters: [String: Any] = ["restrictions": restrictions]
        if preferences.preferCyclePaths {
            // 0 = itinéraire le plus court, 1 = le plus agréable. 0,8 privilégie
            // nettement les aménagements cyclables sans autoriser de détours
            // absurdes, ce qui casserait la précision de la distance visée.
            parameters["weightings"] = ["green": 0.8]
        }
        return parameters
    }

    // MARK: - Exécution

    private func performRequest(
        body: [String: Any],
        preferences: RoutingPreferences,
        requestedDistance: Double?
    ) async throws -> CyclingRoute {
        guard let apiKey else { throw VeloError.missingAPIKey }

        let url = baseURL
            .appendingPathComponent("v2")
            .appendingPathComponent("directions")
            .appendingPathComponent(preferences.profile.routingProfileIdentifier)
            .appendingPathComponent("geojson")

        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw VeloError.invalidRoutingResponse(reason: "requête non sérialisable")
        }

        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Authorization": apiKey,
                "Content-Type": "application/json; charset=utf-8",
                "Accept": "application/geo+json, application/json"
            ],
            body: payload,
            timeout: timeout
        )

        let response = try await httpClient.send(request)
        try validate(response)
        return try Self.decodeRoute(
            from: response.data,
            preferences: preferences,
            requestedDistance: requestedDistance
        )
    }

    /// Traduit les codes HTTP d'ORS en erreurs compréhensibles par l'utilisateur.
    private func validate(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw VeloError.invalidAPIKey
        case 429:
            throw VeloError.quotaExceeded
        case 404:
            // ORS renvoie 404 avec un corps d'erreur lorsqu'aucun itinéraire
            // n'existe entre les points demandés.
            throw VeloError.noRouteFound
        default:
            // Le corps peut préciser la cause : 2010 = point introuvable sur le
            // réseau routable, 2009 = itinéraire impossible.
            if let decoded = try? JSONDecoder().decode(ORS.ErrorResponse.self, from: response.data) {
                if let code = decoded.error.code, code == 2009 || code == 2010 {
                    throw VeloError.noRouteFound
                }
                throw VeloError.invalidRoutingResponse(reason: decoded.error.message)
            }
            throw VeloError.routingEngineUnavailable(statusCode: response.statusCode)
        }
    }

    // MARK: - Décodage

    /// Convertit une réponse GeoJSON ORS en `CyclingRoute`.
    ///
    /// Exposé au niveau du module (et non privé) pour être exercé directement
    /// par les tests, à partir de réponses figées et sans clé API.
    static func decodeRoute(
        from data: Data,
        preferences: RoutingPreferences,
        requestedDistance: Double?
    ) throws -> CyclingRoute {
        let decoded: ORS.DirectionsResponse
        do {
            decoded = try JSONDecoder().decode(ORS.DirectionsResponse.self, from: data)
        } catch {
            throw VeloError.invalidRoutingResponse(reason: "format GeoJSON inattendu")
        }

        guard let feature = decoded.features.first else {
            throw VeloError.noRouteFound
        }

        let coordinates = feature.geometry.coordinates.compactMap { pair -> GeographicCoordinate? in
            guard pair.count >= 2 else { return nil }
            let coordinate = GeographicCoordinate(
                latitude: pair[1],
                longitude: pair[0],
                altitude: pair.count >= 3 ? pair[2] : nil
            )
            return coordinate.isValid ? coordinate : nil
        }

        guard coordinates.count >= 2 else {
            throw VeloError.invalidRoutingResponse(reason: "tracé vide")
        }

        let properties = feature.properties
        let instructions = decodeInstructions(from: properties.segments ?? [])
        let segments = decodeSegments(
            extras: properties.extras,
            coordinates: coordinates
        )

        // La longueur annoncée par le moteur fait foi, mais un écart massif avec
        // la géométrie reçue signale une réponse corrompue : on préfère alors la
        // mesure faite sur le tracé réellement affiché à l'utilisateur.
        let measured = Geodesy.polylineLength(coordinates)
        let announced = properties.summary?.distance ?? measured
        let distance: Double
        if announced > 0, abs(announced - measured) / max(announced, 1) < 0.25 {
            distance = announced
        } else {
            distance = measured
        }

        let duration = properties.summary?.duration
            ?? distance / (preferences.profile.indicativeSpeedKilometersPerHour * 1000 / 3600)

        return CyclingRoute(
            coordinates: coordinates,
            distance: distance,
            duration: duration,
            ascent: properties.ascent,
            descent: properties.descent,
            instructions: instructions,
            segments: segments,
            profile: preferences.profile,
            requestedDistance: requestedDistance
        )
    }

    private static func decodeInstructions(from segments: [ORS.Segment]) -> [NavigationInstruction] {
        segments.flatMap { segment in
            (segment.steps ?? []).compactMap { step -> NavigationInstruction? in
                guard step.wayPoints.count >= 2 else { return nil }
                let name = step.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                // ORS utilise "-" comme marqueur de voie sans nom.
                let roadName = (name == nil || name == "-" || name?.isEmpty == true) ? nil : name
                return NavigationInstruction(
                    maneuver: ManeuverType(openRouteServiceCode: step.type),
                    roadName: roadName,
                    distance: step.distance,
                    duration: step.duration,
                    startPointIndex: step.wayPoints[0],
                    endPointIndex: step.wayPoints[1],
                    roundaboutExitNumber: step.exitNumber,
                    rawText: step.instruction
                )
            }
        }
    }

    /// Fusionne les blocs `surface` et `waytype` en une liste de tronçons.
    ///
    /// ORS fournit deux découpages indépendants de la polyligne. On les
    /// superpose en découpant sur l'union de leurs frontières, ce qui donne des
    /// tronçons homogènes à la fois en revêtement et en type de voie.
    private static func decodeSegments(
        extras: ORS.Extras?,
        coordinates: [GeographicCoordinate]
    ) -> [RouteSegment] {
        guard let extras else { return [] }

        let surfaceRanges = extras.surface?.values ?? []
        let waytypeRanges = extras.waytype?.values ?? []
        guard !surfaceRanges.isEmpty || !waytypeRanges.isEmpty else { return [] }

        let lastIndex = coordinates.count - 1
        var boundaries = Set<Int>([0, lastIndex])
        for range in surfaceRanges + waytypeRanges where range.count >= 2 {
            boundaries.insert(min(max(range[0], 0), lastIndex))
            boundaries.insert(min(max(range[1], 0), lastIndex))
        }

        let sorted = boundaries.sorted()
        guard sorted.count >= 2 else { return [] }

        func value(at index: Int, in ranges: [[Int]]) -> Int? {
            for range in ranges where range.count >= 3 {
                if index >= range[0] && index < range[1] { return range[2] }
            }
            return nil
        }

        var result: [RouteSegment] = []
        for position in 1..<sorted.count {
            let start = sorted[position - 1]
            let end = sorted[position]
            guard end > start else { continue }

            let surfaceValue = value(at: start, in: surfaceRanges)
            let waytypeValue = value(at: start, in: waytypeRanges)

            let slice = Array(coordinates[start...end])
            result.append(
                RouteSegment(
                    startPointIndex: start,
                    endPointIndex: end,
                    surface: surfaceValue.map(SurfaceKind.init(openRouteServiceValue:)) ?? .unknown,
                    wayKind: waytypeValue.map(WayKind.init(openRouteServiceValue:)) ?? .unknown,
                    distance: Geodesy.polylineLength(slice)
                )
            )
        }
        return result
    }
}
