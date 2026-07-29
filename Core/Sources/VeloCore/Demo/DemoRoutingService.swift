import Foundation

/// Moteur de routage simulé, entièrement hors ligne.
///
/// Utilisé dans deux cas seulement :
/// - le **mode démonstration**, activable dans les Réglages, qui permet
///   d'essayer l'application dans le simulateur iOS sans clé API ;
/// - les **tests**, qui doivent produire des résultats identiques à chaque
///   exécution sans dépendre du réseau.
///
/// Il n'est jamais substitué au moteur réel sans que l'utilisateur l'ait
/// explicitement demandé, et l'interface affiche en permanence un bandeau
/// « Mode démonstration » lorsqu'il est actif.
public struct DemoRoutingService: RoutingService {
    /// Latence simulée, en secondes, pour que l'écran de chargement soit
    /// réellement visible et testable.
    public var simulatedLatency: TimeInterval

    public init(simulatedLatency: TimeInterval = 0.25) {
        self.simulatedLatency = simulatedLatency
    }

    public var isConfigured: Bool { true }
    public var supportsRoundTrips: Bool { true }

    public func roundTrip(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        seed: Int,
        points: Int,
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        try await simulateWork()
        return DemoRouteFactory.makeLoop(
            origin: origin,
            targetDistance: targetDistance,
            seed: seed &* 31 &+ points,
            profile: preferences.profile
        )
    }

    public func route(
        through waypoints: [GeographicCoordinate],
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute {
        guard waypoints.count >= 2 else {
            throw VeloError.invalidRoutingResponse(reason: "au moins deux points sont nécessaires")
        }
        try await simulateWork()

        // Les points de passage sont reliés par un tracé sinueux plutôt que par
        // des segments rectilignes : un vrai réseau routier impose un détour, et
        // le mode démonstration doit reproduire cette contrainte pour que la
        // génération de boucles soit réellement mise à l'épreuve.
        let coordinates = DemoRouteFactory
            .connect(waypoints: waypoints)
            .map {
                GeographicCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: 500)
            }
        guard coordinates.count >= 2 else { throw VeloError.noRouteFound }

        let distance = Geodesy.polylineLength(coordinates)
        let speed = preferences.profile.indicativeSpeedKilometersPerHour * 1000 / 3600

        return CyclingRoute(
            coordinates: coordinates,
            distance: distance,
            duration: distance / speed,
            ascent: 0,
            descent: 0,
            instructions: DemoRouteFactory.makeInstructions(for: coordinates),
            segments: [],
            profile: preferences.profile,
            requestedDistance: nil
        )
    }

    private func simulateWork() async throws {
        guard simulatedLatency > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(simulatedLatency * 1_000_000_000))
    }
}
