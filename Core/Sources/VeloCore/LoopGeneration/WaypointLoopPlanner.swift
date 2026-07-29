import Foundation

/// Construit des points de passage formant une boucle autour d'un départ.
///
/// Deux usages :
/// 1. honorer une **direction de départ préférée**, ce que la génération native
///    de boucle d'OpenRouteService ne permet pas (elle n'expose qu'une graine) ;
/// 2. servir de **repli** quand `round_trip` échoue ou quand le moteur choisi ne
///    sait pas générer de boucle.
public enum WaypointLoopPlanner {
    /// Rapport entre la distance réellement roulée et la distance à vol d'oiseau.
    ///
    /// Sur un réseau routier européen ordinaire, un itinéraire mesure environ
    /// 20 à 30 % de plus que le polygone qui le sous-tend. 1,25 place la
    /// première tentative dans la bonne fourchette ; l'affinage se fait ensuite
    /// par correction de la longueur demandée.
    public static let detourFactor: Double = 1.25

    /// Points de passage d'une boucle polygonale.
    ///
    /// - Parameters:
    ///   - origin: départ et arrivée.
    ///   - targetDistance: distance visée en mètres.
    ///   - bearing: direction générale de la boucle, en degrés.
    ///   - waypointCount: nombre de points intermédiaires (3 à 6 sont utiles ;
    ///     en dessous la boucle est triangulaire et anguleuse, au-dessus elle
    ///     devient sinueuse et le moteur peine à la respecter).
    /// - Returns: `[origine, p1, …, pn, origine]`, prêt pour `RoutingService.route(through:)`.
    public static func waypoints(
        around origin: GeographicCoordinate,
        targetDistance: Double,
        bearing: Double,
        waypointCount: Int
    ) -> [GeographicCoordinate] {
        let count = max(2, min(waypointCount, 8))
        let vertexCount = count + 1  // les points intermédiaires plus le départ

        // Périmètre d'un polygone régulier à `vertexCount` sommets inscrit dans
        // un cercle de rayon r : 2·n·r·sin(π/n). On inverse la relation pour
        // obtenir le rayon donnant la distance visée une fois le détour pris en
        // compte.
        let perimeterFactor = 2 * Double(vertexCount) * sin(.pi / Double(vertexCount))
        let radius = targetDistance / (detourFactor * perimeterFactor)

        // Le cercle est centré dans la direction demandée : le cycliste part
        // bien vers ce cap, et le départ se trouve sur le cercle.
        let center = Geodesy.destination(from: origin, distance: radius, bearing: bearing)
        let originAngle = Geodesy.bearing(from: center, to: origin)

        var result: [GeographicCoordinate] = [origin]
        for index in 1...count {
            let angle = Geodesy.normalizedBearing(
                originAngle + 360 * Double(index) / Double(vertexCount)
            )
            result.append(Geodesy.destination(from: center, distance: radius, bearing: angle))
        }
        result.append(origin)
        return result
    }

    /// Répartit `count` caps de départ autour d'une direction préférée.
    ///
    /// Sans préférence, les caps couvrent toute la rose des vents pour maximiser
    /// la diversité des propositions. Avec préférence, ils restent groupés dans
    /// un secteur de ±50° autour du cap demandé.
    public static func candidateBearings(
        preferred: PreferredDirection,
        count: Int
    ) -> [Double] {
        guard count > 0 else { return [] }
        guard let preferredBearing = preferred.bearing else {
            return (0..<count).map { Geodesy.normalizedBearing(360 * Double($0) / Double(count)) }
        }
        guard count > 1 else { return [preferredBearing] }

        let spread: Double = 50
        return (0..<count).map { index in
            let offset = -spread + 2 * spread * Double(index) / Double(count - 1)
            return Geodesy.normalizedBearing(preferredBearing + offset)
        }
    }
}
