import Foundation

/// Décision prise par le détecteur à chaque mise à jour de position.
public enum DeviationEvent: Sendable, Equatable {
    /// Rien à signaler.
    case onRoute
    /// L'utilisateur vient de quitter le parcours.
    case departed(distance: Double)
    /// L'écart se poursuit.
    case stillOff(distance: Double)
    /// L'utilisateur vient de revenir sur le parcours.
    case returned
}

/// Détecte les sorties de parcours avec hystérésis.
///
/// Trois précautions évitent les fausses alertes, qui sont le principal défaut
/// des applications de navigation à vélo :
///
/// 1. **Seuil adaptatif** — la tolérance tient compte de l'incertitude annoncée
///    par le GPS. En ville, entre les immeubles, l'erreur horizontale dépasse
///    couramment 30 m sans que le cycliste ait quitté sa route.
/// 2. **Confirmation dans la durée** — un seul relevé aberrant ne déclenche
///    rien ; il faut plusieurs relevés consécutifs au-delà du seuil.
/// 3. **Hystérésis** — le retour sur le parcours est déclaré à un seuil plus bas
///    que le départ, ce qui évite l'oscillation quand on longe le tracé.
public struct DeviationDetector: Sendable {
    /// Tolérance de base, en mètres. Généreuse à dessein : les tracés OSM sont
    /// tracés au centre de la chaussée et une piste cyclable parallèle peut se
    /// trouver à 15 m de la route.
    public var baseThreshold: Double
    /// Part de l'incertitude GPS ajoutée à la tolérance.
    public var accuracyFactor: Double
    /// Plafond de tolérance, en mètres.
    public var maximumThreshold: Double
    /// Nombre de relevés consécutifs hors tolérance avant de déclarer l'écart.
    public var confirmationCount: Int
    /// Rapport entre le seuil de retour et le seuil de sortie.
    public var returnRatio: Double

    public init(
        baseThreshold: Double = 40,
        accuracyFactor: Double = 1.5,
        maximumThreshold: Double = 120,
        confirmationCount: Int = 3,
        returnRatio: Double = 0.6
    ) {
        self.baseThreshold = baseThreshold
        self.accuracyFactor = accuracyFactor
        self.maximumThreshold = maximumThreshold
        self.confirmationCount = max(1, confirmationCount)
        self.returnRatio = returnRatio
    }

    /// État interne du détecteur, extrait du détecteur lui-même pour que la
    /// configuration reste immuable et copiable.
    public struct State: Sendable, Equatable {
        public private(set) var consecutiveOutside = 0
        public private(set) var isOffRoute = false

        public init() {}

        mutating func registerOutside() { consecutiveOutside += 1 }
        mutating func resetOutside() { consecutiveOutside = 0 }
        mutating func setOffRoute(_ value: Bool) {
            isOffRoute = value
            consecutiveOutside = 0
        }
    }

    /// Tolérance applicable à un relevé donné.
    public func threshold(forAccuracy horizontalAccuracy: Double) -> Double {
        let accuracy = horizontalAccuracy > 0 ? horizontalAccuracy : 0
        return min(baseThreshold + accuracy * accuracyFactor, maximumThreshold)
    }

    /// Met à jour l'état et renvoie l'événement correspondant.
    public func evaluate(
        distanceFromRoute: Double,
        horizontalAccuracy: Double,
        state: inout State
    ) -> DeviationEvent {
        let departureThreshold = threshold(forAccuracy: horizontalAccuracy)
        let returnThreshold = departureThreshold * returnRatio

        if state.isOffRoute {
            if distanceFromRoute <= returnThreshold {
                state.setOffRoute(false)
                return .returned
            }
            return .stillOff(distance: distanceFromRoute)
        }

        if distanceFromRoute > departureThreshold {
            state.registerOutside()
            if state.consecutiveOutside >= confirmationCount {
                state.setOffRoute(true)
                return .departed(distance: distanceFromRoute)
            }
            return .onRoute
        }

        state.resetOutside()
        return .onRoute
    }
}

/// Politique de recalcul choisie par l'utilisateur.
public enum RecalculationPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Recalculer sans rien demander.
    case automatic
    /// Proposer le recalcul et attendre la réponse.
    case ask
    /// Ne jamais recalculer ; l'utilisateur revient par ses propres moyens.
    case never

    public var id: String { rawValue }
}

/// Choisit le point du circuit vers lequel ramener un cycliste hors parcours.
public enum RejoinPointSelector {
    /// Point de reprise sur le circuit.
    ///
    /// La règle est simple mais importante pour la sécurité : on ne renvoie
    /// **jamais** l'utilisateur en arrière si un point de reprise raisonnable
    /// existe devant lui. Faire faire demi-tour à un cycliste sur une route
    /// ouverte est à la fois désagréable et risqué (cahier des charges §7).
    ///
    /// - Parameters:
    ///   - route: circuit suivi.
    ///   - position: position actuelle.
    ///   - lastMatch: dernière correspondance connue sur le circuit.
    ///   - lookahead: distance devant soi à explorer, en mètres.
    /// - Returns: point du circuit à rejoindre et distance parcourue à ce point.
    public static func rejoinPoint(
        on route: CyclingRoute,
        from position: GeographicCoordinate,
        lastMatch: RouteMatch?,
        lookahead: Double = 2_500
    ) -> (coordinate: GeographicCoordinate, distanceAlongRoute: Double)? {
        let coordinates = route.coordinates
        let cumulative = route.cumulativeDistances
        guard coordinates.count >= 2, !cumulative.isEmpty else { return nil }

        let startDistance = lastMatch?.distanceAlongRoute ?? 0
        let endDistance = min(startDistance + lookahead, cumulative.last ?? 0)

        var best: (coordinate: GeographicCoordinate, distanceAlongRoute: Double)?
        var bestCost = Double.infinity

        for index in coordinates.indices {
            let along = cumulative[index]
            guard along >= startDistance, along <= endDistance else { continue }

            let straightLine = Geodesy.distance(from: position, to: coordinates[index])
            // Coût = trajet à faire pour rejoindre le point, moins un crédit
            // proportionnel à l'avancement gagné sur le circuit. Rejoindre plus
            // loin devant est donc récompensé, mais pas au prix d'un détour
            // disproportionné.
            let progressCredit = (along - startDistance) * 0.35
            let cost = straightLine - progressCredit

            if cost < bestCost {
                bestCost = cost
                best = (coordinates[index], along)
            }
        }

        // Aucun point devant : le circuit est presque terminé, on vise l'arrivée.
        if best == nil, let last = coordinates.last {
            best = (last, cumulative.last ?? 0)
        }
        return best
    }
}
