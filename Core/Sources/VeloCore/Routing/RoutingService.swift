import Foundation

/// Contrat que doit remplir tout moteur de calcul d'itinéraire.
///
/// Aucune autre partie de l'application ne connaît OpenRouteService : changer de
/// moteur consiste à fournir une nouvelle implémentation de ce protocole.
public protocol RoutingService: Sendable {
    /// Vrai lorsque le service dispose de tout ce qu'il lui faut pour répondre
    /// (typiquement : une clé API). Permet à l'interface d'expliquer la
    /// situation *avant* que l'utilisateur ne lance une génération.
    var isConfigured: Bool { get }

    /// Vrai si le moteur sait générer nativement une boucle.
    var supportsRoundTrips: Bool { get }

    /// Demande une boucle partant et revenant au même point.
    ///
    /// - Parameters:
    ///   - origin: point de départ et d'arrivée.
    ///   - targetDistance: longueur souhaitée en mètres.
    ///   - seed: graine de génération. Deux graines différentes produisent des
    ///     circuits différents pour un même point et une même distance.
    ///   - points: nombre de points de passage intermédiaires que le moteur doit
    ///     placer. Plus la valeur est élevée, plus la boucle est sinueuse.
    func roundTrip(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        seed: Int,
        points: Int,
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute

    /// Calcule un itinéraire passant par les points fournis, dans l'ordre.
    ///
    /// Utilisé pour le recalcul hors parcours et comme repli lorsque la
    /// génération native de boucle n'aboutit pas.
    func route(
        through waypoints: [GeographicCoordinate],
        preferences: RoutingPreferences
    ) async throws -> CyclingRoute
}
