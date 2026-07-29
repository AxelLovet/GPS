import Foundation

/// Simule un déplacement le long d'un circuit et produit des relevés GPS.
///
/// C'est ce qui permet de tester la navigation complète — progression,
/// consignes, sortie de parcours, recalcul — dans le simulateur iOS et dans les
/// tests unitaires, sans bouger et sans capteur.
public struct TrackSimulator: Sendable {
    /// Écart volontaire par rapport au circuit, pour éprouver la détection.
    public struct DetourPlan: Sendable, Hashable {
        /// Distance sur le circuit à laquelle l'écart commence, en mètres.
        public let startDistance: Double
        /// Longueur de l'écart, en mètres.
        public let length: Double
        /// Écart latéral maximal atteint, en mètres.
        public let lateralOffset: Double

        public init(startDistance: Double, length: Double, lateralOffset: Double) {
            self.startDistance = startDistance
            self.length = length
            self.lateralOffset = lateralOffset
        }
    }

    public let route: CyclingRoute
    /// Vitesse de déplacement simulée, en m/s (6,9 m/s ≈ 25 km/h).
    public let speed: Double
    /// Intervalle entre deux relevés, en secondes.
    public let updateInterval: TimeInterval
    /// Incertitude horizontale annoncée sur chaque relevé.
    public let horizontalAccuracy: Double
    public let detour: DetourPlan?

    public init(
        route: CyclingRoute,
        speed: Double = 6.9,
        updateInterval: TimeInterval = 1,
        horizontalAccuracy: Double = 5,
        detour: DetourPlan? = nil
    ) {
        self.route = route
        self.speed = speed
        self.updateInterval = updateInterval
        self.horizontalAccuracy = horizontalAccuracy
        self.detour = detour
    }

    /// Produit toute la série de relevés du départ à l'arrivée.
    public func samples(startingAt startDate: Date) -> [LocationSample] {
        let total = route.cumulativeDistances.last ?? 0
        guard total > 0, speed > 0, updateInterval > 0 else { return [] }

        var samples: [LocationSample] = []
        var travelled: Double = 0
        var elapsed: TimeInterval = 0

        while travelled <= total {
            if let position = position(atDistance: travelled) {
                samples.append(
                    LocationSample(
                        coordinate: position.coordinate,
                        timestamp: startDate.addingTimeInterval(elapsed),
                        horizontalAccuracy: horizontalAccuracy,
                        verticalAccuracy: position.coordinate.altitude != nil ? 8 : -1,
                        speed: speed,
                        course: position.course
                    )
                )
            }
            travelled += speed * updateInterval
            elapsed += updateInterval
        }
        return samples
    }

    /// Position et cap à une distance donnée le long du circuit, écart compris.
    public func position(
        atDistance distance: Double
    ) -> (coordinate: GeographicCoordinate, course: Double)? {
        let coordinates = route.coordinates
        let cumulative = route.cumulativeDistances
        guard coordinates.count >= 2, let total = cumulative.last, total > 0 else { return nil }

        let clamped = min(max(distance, 0), total)
        var index = 0
        while index < cumulative.count - 2 && cumulative[index + 1] < clamped {
            index += 1
        }

        let segmentLength = cumulative[index + 1] - cumulative[index]
        let fraction = segmentLength > 0 ? (clamped - cumulative[index]) / segmentLength : 0
        let start = coordinates[index]
        let end = coordinates[index + 1]

        var point = GeographicCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction,
            altitude: interpolatedAltitude(start.altitude, end.altitude, fraction)
        )
        let course = Geodesy.bearing(from: start, to: end)

        if let offset = lateralOffset(atDistance: clamped) {
            // L'écart est appliqué perpendiculairement au sens de marche : le
            // cycliste s'éloigne progressivement puis revient, comme s'il avait
            // pris une rue parallèle.
            point = Geodesy.destination(
                from: point,
                distance: offset,
                bearing: Geodesy.normalizedBearing(course + 90)
            )
        }
        return (point, course)
    }

    private func lateralOffset(atDistance distance: Double) -> Double? {
        guard let detour else { return nil }
        let relative = distance - detour.startDistance
        guard relative >= 0, relative <= detour.length, detour.length > 0 else { return nil }
        // Profil sinusoïdal : départ et retour progressifs, sans saut brutal qui
        // serait rejeté comme une aberration par le filtre de position.
        return detour.lateralOffset * sin(.pi * relative / detour.length)
    }

    private func interpolatedAltitude(_ a: Double?, _ b: Double?, _ fraction: Double) -> Double? {
        guard let a else { return b }
        guard let b else { return a }
        return a + (b - a) * fraction
    }
}
