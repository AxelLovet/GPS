import Foundation

/// Évalue et classe les circuits candidats.
///
/// La note est une somme de pénalités : **plus elle est basse, meilleur est le
/// circuit**. Les poids traduisent l'ordre de priorité du cahier des charges
/// (§24) — la sécurité et la qualité réelle du parcours passent avant la
/// précision de la distance.
public struct RouteScorer: Sendable {
    /// Tolérance relative en deçà de laquelle la distance est jugée conforme.
    public static let distanceTolerance: Double = 0.05

    public var preferences: RoutingPreferences

    public init(preferences: RoutingPreferences) {
        self.preferences = preferences
    }

    // MARK: - Validité

    /// Vrai si le circuit est acceptable, quel que soit son classement.
    ///
    /// Un circuit invalide n'est jamais proposé à l'utilisateur : il vaut mieux
    /// afficher moins de propositions qu'une proposition inutilisable.
    public func isAcceptable(_ route: CyclingRoute) -> Bool {
        rejectionReason(for: route) == nil
    }

    /// Motif de rejet, ou `nil` si le circuit est acceptable.
    public func rejectionReason(for route: CyclingRoute) -> RouteWarning? {
        guard route.coordinates.count >= 2, route.distance > 0 else {
            return .distanceOffTarget
        }
        // Une boucle qui ne se referme pas oblige l'utilisateur à rentrer par
        // ses propres moyens : c'est éliminatoire.
        if !RouteQuality.isClosedLoop(route) {
            return .loopNotClosed
        }
        // Au-delà de 45 % de tracé emprunté deux fois, ce n'est plus une boucle
        // mais un aller-retour déguisé.
        if RouteQuality.repeatedSectionRatio(of: route) > 0.45 {
            return .repeatedSections
        }
        // Un écart de plus de 40 % ne rend pas service : mieux vaut expliquer
        // qu'aucune boucle proche n'existe.
        if let deviation = route.distanceDeviationRatio, abs(deviation) > 0.40 {
            return .distanceOffTarget
        }
        // Refus explicite du gravier : plus de 10 % du parcours suffit à gâcher
        // une sortie sur un vélo de route.
        if preferences.rejectGravel, let ratio = gravelRatio(of: route), ratio > 0.10 {
            return .gravelSections
        }
        return nil
    }

    // MARK: - Avertissements

    /// Avertissements à afficher sur l'écran de comparaison.
    public func warnings(for route: CyclingRoute) -> Set<RouteWarning> {
        var warnings: Set<RouteWarning> = []

        if let deviation = route.distanceDeviationRatio,
           abs(deviation) > Self.distanceTolerance {
            warnings.insert(.distanceOffTarget)
        }
        if !RouteQuality.isClosedLoop(route) {
            warnings.insert(.loopNotClosed)
        }
        if RouteQuality.repeatedSectionRatio(of: route) > 0.15 {
            warnings.insert(.repeatedSections)
        }
        if RouteQuality.containsUTurn(route) {
            warnings.insert(.containsUTurn)
        }
        if preferences.avoidUnpavedSurfaces, let ratio = route.unpavedRatio, ratio > 0.10 {
            warnings.insert(.unpavedSections)
        }
        if let ratio = gravelRatio(of: route), ratio > 0.05 {
            warnings.insert(.gravelSections)
        }
        if let rate = RouteQuality.climbRate(of: route),
           rate > (preferences.avoidSteepClimbs ? 15 : 25) {
            warnings.insert(.steepClimbs)
        }
        return warnings
    }

    // MARK: - Note

    /// Note du circuit. Plus basse = meilleure.
    public func score(_ route: CyclingRoute) -> Double {
        var score: Double = 0

        // Écart de distance : pénalité nulle dans la tolérance de ±5 %, puis
        // croissance quadratique. Une boucle à +6 % reste très bien classée,
        // une boucle à +30 % est fortement dépréciée.
        if let deviation = route.distanceDeviationRatio {
            let excess = max(abs(deviation) - Self.distanceTolerance, 0)
            score += 120 * excess * excess / (Self.distanceTolerance * Self.distanceTolerance)
        }

        // Répétitions : c'est le principal défaut des boucles générées
        // automatiquement, donc le poids le plus lourd.
        let repeated = RouteQuality.repeatedSectionRatio(of: route)
        score += 220 * repeated * repeated

        // Demi-tours : dangereux et désagréables à vélo.
        let uTurnCount = route.instructions.filter { $0.maneuver == .uTurn }.count
        score += 40 * Double(uTurnCount)

        // Fermeture de la boucle : quelques dizaines de mètres sont sans
        // importance, un kilomètre ne l'est pas.
        let closure = route.loopClosureDistance
        if closure.isFinite {
            score += min(closure / 10, 60)
        }

        // Revêtement.
        if preferences.avoidUnpavedSurfaces, let unpaved = route.unpavedRatio {
            score += 90 * unpaved
        }
        if let gravel = gravelRatio(of: route) {
            score += (preferences.rejectGravel ? 200 : 45) * gravel
        }

        // Pistes cyclables : bonus, pas pénalité — on récompense sans jamais
        // pousser à un détour absurde.
        if preferences.preferCyclePaths, let cyclePath = route.cyclePathRatio {
            score -= 35 * cyclePath
        }

        // Dénivelé.
        if let rate = RouteQuality.climbRate(of: route) {
            let ceiling = preferences.avoidSteepClimbs ? 12.0 : 22.0
            score += max(rate - ceiling, 0) * (preferences.avoidSteepClimbs ? 2.5 : 1.0)
        }

        // Nombre de manœuvres rapporté à la distance : un circuit qui enchaîne
        // les changements de direction tous les 100 m est pénible à suivre.
        if route.distance > 0 {
            let maneuversPerKilometer = Double(route.instructions.count)
                / (route.distance / 1000)
            score += max(maneuversPerKilometer - 6, 0) * 3
        }

        return score
    }

    /// Construit le candidat complet à partir d'un itinéraire.
    public func makeCandidate(route: CyclingRoute, seed: Int) -> RouteCandidate {
        RouteCandidate(
            route: route,
            seed: seed,
            warnings: warnings(for: route),
            score: score(route)
        )
    }

    /// Classe les candidats du meilleur au moins bon et écarte les doublons.
    ///
    /// Deux circuits produits par des graines différentes peuvent être presque
    /// identiques ; les proposer tous les deux n'apporte rien. Un candidat est
    /// considéré comme un doublon s'il partage plus de 70 % de son tracé avec un
    /// candidat déjà retenu.
    public func rank(_ candidates: [RouteCandidate], limit: Int) -> [RouteCandidate] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.route.distance < rhs.route.distance }
            return lhs.score < rhs.score
        }

        var selected: [RouteCandidate] = []
        for candidate in sorted {
            guard selected.count < limit else { break }
            let isDuplicate = selected.contains { existing in
                RouteSimilarity.overlapRatio(
                    candidate.route.coordinates,
                    existing.route.coordinates
                ) > 0.70
            }
            if !isDuplicate { selected.append(candidate) }
        }

        // Si le filtrage anti-doublon a trop réduit la liste, on complète avec
        // les meilleurs restants : proposer trois circuits proches vaut mieux
        // que n'en proposer qu'un seul.
        if selected.count < limit {
            for candidate in sorted where !selected.contains(where: { $0.id == candidate.id }) {
                guard selected.count < limit else { break }
                selected.append(candidate)
            }
        }
        return selected
    }

    private func gravelRatio(of route: CyclingRoute) -> Double? {
        guard !route.segments.isEmpty else { return nil }
        let known = route.segments.filter { $0.surface != .unknown }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(0) { $0 + $1.distance }
        guard total > 0 else { return nil }
        let gravel = known.filter { $0.surface == .gravel }.reduce(0) { $0 + $1.distance }
        return gravel / total
    }
}

/// Comparaison géométrique de deux tracés.
public enum RouteSimilarity {
    /// Part du premier tracé qui se superpose au second, entre 0 et 1.
    public static func overlapRatio(
        _ first: [GeographicCoordinate],
        _ second: [GeographicCoordinate]
    ) -> Double {
        guard first.count > 1, second.count > 1 else { return 0 }

        let latitudeStep = RouteQuality.gridCellSize / 111_320.0
        let referenceLatitude = first[0].latitude
        let longitudeStep = RouteQuality.gridCellSize
            / (111_320.0 * max(cos(referenceLatitude * .pi / 180), 0.01))

        func cell(_ coordinate: GeographicCoordinate) -> Int64 {
            let row = Int64((coordinate.latitude / latitudeStep).rounded(.down))
            let column = Int64((coordinate.longitude / longitudeStep).rounded(.down))
            return row &* 4_000_000 &+ column
        }

        let secondCells = Set(second.map(cell))

        var shared: Double = 0
        var total: Double = 0
        for index in 1..<first.count {
            let length = Geodesy.distance(from: first[index - 1], to: first[index])
            total += length
            if secondCells.contains(cell(first[index])) { shared += length }
        }
        guard total > 0 else { return 0 }
        return shared / total
    }
}
