import Foundation

/// Position de l'utilisateur rapportée à l'itinéraire suivi.
public struct RouteMatch: Sendable, Equatable {
    /// Index du premier point du segment sur lequel la position se projette.
    public let segmentIndex: Int
    /// Position projetée sur le tracé.
    public let projectedPoint: GeographicCoordinate
    /// Écart perpendiculaire au tracé, en mètres.
    public let distanceFromRoute: Double
    /// Distance parcourue le long du tracé depuis le départ, en mètres.
    public let distanceAlongRoute: Double
    /// Distance restante jusqu'à l'arrivée, en mètres.
    public let remainingDistance: Double

    public init(
        segmentIndex: Int,
        projectedPoint: GeographicCoordinate,
        distanceFromRoute: Double,
        distanceAlongRoute: Double,
        remainingDistance: Double
    ) {
        self.segmentIndex = segmentIndex
        self.projectedPoint = projectedPoint
        self.distanceFromRoute = distanceFromRoute
        self.distanceAlongRoute = distanceAlongRoute
        self.remainingDistance = remainingDistance
    }

    /// Progression sur le circuit, entre 0 et 1.
    public var fractionCompleted: Double {
        let total = distanceAlongRoute + remainingDistance
        guard total > 0 else { return 0 }
        return min(max(distanceAlongRoute / total, 0), 1)
    }
}

/// Rattache une position GPS à un itinéraire.
public protocol RouteMatching: Sendable {
    func match(
        _ coordinate: GeographicCoordinate,
        on route: CyclingRoute,
        near previousMatch: RouteMatch?
    ) -> RouteMatch?
}

/// Implémentation par projection sur la polyligne, avec fenêtre de recherche.
///
/// Le point délicat est propre aux **circuits en boucle** : le tracé se recoupe
/// près du départ, et parfois ailleurs. Une recherche du point le plus proche sur
/// tout l'itinéraire ferait sauter la progression d'un croisement à l'autre —
/// par exemple en annonçant l'arrivée dès les premiers mètres. La recherche est
/// donc limitée à une fenêtre glissante autour de la position précédente, et
/// n'est élargie que si aucune correspondance plausible n'y est trouvée.
public struct RouteMatchingService: RouteMatching {
    /// Distance explorée en arrière de la position précédente, en mètres.
    ///
    /// Non nulle pour tolérer un léger recul (arrêt, dérive GPS, demi-tour
    /// volontaire), mais courte pour ne pas se raccrocher au passage précédent.
    public let backwardWindow: Double
    /// Distance explorée en avant, en mètres. Doit couvrir la perte du signal
    /// dans un tunnel ou sous un couvert dense.
    public let forwardWindow: Double
    /// Au-delà de cet écart, la correspondance trouvée dans la fenêtre est jugée
    /// douteuse et une recherche globale est tentée.
    public let windowConfidenceThreshold: Double

    public init(
        backwardWindow: Double = 120,
        forwardWindow: Double = 900,
        windowConfidenceThreshold: Double = 150
    ) {
        self.backwardWindow = backwardWindow
        self.forwardWindow = forwardWindow
        self.windowConfidenceThreshold = windowConfidenceThreshold
    }

    public func match(
        _ coordinate: GeographicCoordinate,
        on route: CyclingRoute,
        near previousMatch: RouteMatch?
    ) -> RouteMatch? {
        let coordinates = route.coordinates
        guard coordinates.count >= 2, coordinate.isValid else { return nil }

        let cumulative = route.cumulativeDistances
        let totalDistance = cumulative.last ?? 0

        // Sans position précédente (démarrage de la navigation), la recherche
        // porte sur tout le tracé.
        guard let previousMatch else {
            return search(coordinate, in: 0..<(coordinates.count - 1), route: route)
        }

        let lowerBound = max(previousMatch.distanceAlongRoute - backwardWindow, 0)
        let upperBound = min(previousMatch.distanceAlongRoute + forwardWindow, totalDistance)

        let startIndex = index(forDistance: lowerBound, in: cumulative)
        let endIndex = min(index(forDistance: upperBound, in: cumulative) + 1, coordinates.count - 1)
        guard endIndex > startIndex else {
            return search(coordinate, in: 0..<(coordinates.count - 1), route: route)
        }

        let windowed = search(coordinate, in: startIndex..<endIndex, route: route)

        if let windowed, windowed.distanceFromRoute <= windowConfidenceThreshold {
            return windowed
        }

        // Fenêtre peu concluante : on cherche partout, mais on ne retient le
        // résultat global que s'il est nettement meilleur. Sinon on garde la
        // correspondance locale, quitte à être « hors parcours » — c'est
        // précisément la situation que la détection d'écart doit signaler.
        let global = search(coordinate, in: 0..<(coordinates.count - 1), route: route)
        switch (windowed, global) {
        case (let windowed?, let global?):
            return global.distanceFromRoute < windowed.distanceFromRoute * 0.5 ? global : windowed
        case (nil, let global?):
            return global
        case (let windowed?, nil):
            return windowed
        case (nil, nil):
            return nil
        }
    }

    private func search(
        _ coordinate: GeographicCoordinate,
        in range: Range<Int>,
        route: CyclingRoute
    ) -> RouteMatch? {
        let coordinates = route.coordinates
        let cumulative = route.cumulativeDistances
        let totalDistance = cumulative.last ?? 0
        guard !range.isEmpty else { return nil }

        var best: RouteMatch?
        for index in range {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let projection = Geodesy.project(coordinate, onto: start, end)
            guard best == nil || projection.distance < best!.distanceFromRoute else { continue }

            let segmentLength = cumulative[index + 1] - cumulative[index]
            let along = cumulative[index] + segmentLength * projection.fraction
            best = RouteMatch(
                segmentIndex: index,
                projectedPoint: projection.point,
                distanceFromRoute: projection.distance,
                distanceAlongRoute: along,
                remainingDistance: max(totalDistance - along, 0)
            )
        }
        return best
    }

    /// Index du dernier point situé avant `distance` sur le tracé (recherche
    /// dichotomique sur les distances cumulées, qui sont croissantes).
    private func index(forDistance distance: Double, in cumulative: [Double]) -> Int {
        guard !cumulative.isEmpty else { return 0 }
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if cumulative[middle] <= distance { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
