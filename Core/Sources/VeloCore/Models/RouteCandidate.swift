import Foundation

/// Avertissement attaché à un circuit proposé, affiché sur l'écran de comparaison.
public enum RouteWarning: String, Codable, Sendable, Hashable, CaseIterable {
    /// L'écart à la distance demandée dépasse ±5 %.
    case distanceOffTarget
    /// Le départ et l'arrivée ne coïncident pas suffisamment.
    case loopNotClosed
    /// Une part significative du circuit n'est pas goudronnée.
    case unpavedSections
    /// Le circuit passe par du gravier alors que l'utilisateur l'a refusé.
    case gravelSections
    /// Le circuit repasse plusieurs fois par les mêmes voies.
    case repeatedSections
    /// Le circuit contient au moins un demi-tour.
    case containsUTurn
    /// Dénivelé important au regard de la distance.
    case steepClimbs
}

/// Un itinéraire candidat, produit par la génération de boucles, accompagné de
/// son évaluation.
///
/// Un candidat n'est pas nécessairement proposé à l'utilisateur : il peut être
/// écarté par `LoopGenerationService` s'il est invalide.
public struct RouteCandidate: Identifiable, Hashable, Sendable {
    public let route: CyclingRoute
    /// Graine utilisée pour l'obtenir, conservée pour pouvoir régénérer un
    /// circuit identique ou explicitement différent.
    public let seed: Int
    public let warnings: Set<RouteWarning>
    /// Note globale, plus basse = meilleur. Voir `RouteScorer`.
    public let score: Double

    public var id: UUID { route.id }

    public init(route: CyclingRoute, seed: Int, warnings: Set<RouteWarning>, score: Double) {
        self.route = route
        self.seed = seed
        self.warnings = warnings
        self.score = score
    }

    /// Part du circuit parcourue plus d'une fois, entre 0 et 1.
    public var repeatedSectionRatio: Double {
        RouteQuality.repeatedSectionRatio(of: route)
    }
}

/// Résultat complet d'une génération de boucles.
public struct LoopGenerationResult: Sendable {
    /// Candidats retenus, triés du meilleur au moins bon. Le premier est le
    /// circuit recommandé.
    public let candidates: [RouteCandidate]
    /// Nombre d'itinéraires effectivement calculés, y compris ceux écartés.
    public let evaluatedCount: Int
    /// Nombre d'itinéraires écartés parce qu'ils ne respectaient pas les
    /// contraintes.
    public let rejectedCount: Int

    public init(candidates: [RouteCandidate], evaluatedCount: Int, rejectedCount: Int) {
        self.candidates = candidates
        self.evaluatedCount = evaluatedCount
        self.rejectedCount = rejectedCount
    }

    public var recommended: RouteCandidate? { candidates.first }
    public var alternatives: [RouteCandidate] { Array(candidates.dropFirst()) }
}
