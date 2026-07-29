import Foundation

/// Mesures de qualité d'un circuit, indépendantes du moteur qui l'a produit.
///
/// Ces mesures sont ce qui permet d'éliminer les « fausses boucles » : un
/// aller-retour sur la même route est un itinéraire parfaitement valide pour un
/// moteur de routage, mais c'est exactement ce que l'utilisateur ne veut pas.
public enum RouteQuality {
    /// Côté de la grille d'analyse, en mètres.
    ///
    /// 25 m est un compromis : assez large pour que les deux sens d'une même
    /// route (séparés par quelques mètres) tombent dans la même cellule, assez
    /// fin pour que deux routes parallèles distinctes n'y soient pas confondues.
    static let gridCellSize: Double = 25

    /// Part du circuit empruntée plus d'une fois, entre 0 et 1.
    ///
    /// Le tracé est projeté sur une grille régulière ; toute cellule visitée
    /// lors de deux passages distincts est comptée comme répétée. Un aller-retour
    /// pur tend vers 1, une boucle propre reste sous 0,1 (seule la jonction
    /// départ/arrivée se recoupe).
    public static func repeatedSectionRatio(of route: CyclingRoute) -> Double {
        repeatedSectionRatio(of: route.coordinates)
    }

    public static func repeatedSectionRatio(of coordinates: [GeographicCoordinate]) -> Double {
        guard coordinates.count > 2 else { return 0 }
        guard let center = Geodesy.centroid(of: coordinates) else { return 0 }

        let latitudeStep = gridCellSize / 111_320.0
        let longitudeStep = gridCellSize
            / (111_320.0 * max(cos(center.latitude * .pi / 180), 0.01))

        func cell(for coordinate: GeographicCoordinate) -> Int64 {
            let row = Int64((coordinate.latitude / latitudeStep).rounded(.down))
            let column = Int64((coordinate.longitude / longitudeStep).rounded(.down))
            // Combinaison injective en pratique aux latitudes habitées.
            return row &* 4_000_000 &+ column
        }

        let cells = coordinates.map(cell(for:))

        // Compresse les répétitions consécutives : rester dans une cellule
        // pendant plusieurs points n'est pas un second passage.
        var visitCounts: [Int64: Int] = [:]
        var previous: Int64?
        for value in cells where value != previous {
            visitCounts[value, default: 0] += 1
            previous = value
        }

        let repeatedCells = Set(visitCounts.filter { $0.value > 1 }.keys)
        guard !repeatedCells.isEmpty else { return 0 }

        var repeatedLength: Double = 0
        var totalLength: Double = 0
        for index in 1..<coordinates.count {
            let length = Geodesy.distance(from: coordinates[index - 1], to: coordinates[index])
            totalLength += length
            if repeatedCells.contains(cells[index - 1]) && repeatedCells.contains(cells[index]) {
                repeatedLength += length
            }
        }

        guard totalLength > 0 else { return 0 }
        return min(repeatedLength / totalLength, 1)
    }

    /// Vrai si le moteur a inséré au moins un demi-tour dans les consignes.
    public static func containsUTurn(_ route: CyclingRoute) -> Bool {
        route.instructions.contains { $0.maneuver == .uTurn }
    }

    /// Dénivelé positif rapporté à la distance, en m/km.
    ///
    /// Repère utile : moins de 10 m/km est plat, au-delà de 20 m/km le parcours
    /// est vallonné, au-delà de 35 m/km il est montagneux.
    public static func climbRate(of route: CyclingRoute) -> Double? {
        guard let ascent = route.ascent, route.distance > 0 else { return nil }
        return ascent / (route.distance / 1000)
    }

    /// Vrai si le circuit revient suffisamment près de son point de départ.
    ///
    /// La tolérance dépend de la longueur : sur 50 km, finir 150 m plus loin est
    /// sans conséquence, alors que sur 5 km c'est visible.
    public static func isClosedLoop(_ route: CyclingRoute) -> Bool {
        route.loopClosureDistance <= closureTolerance(for: route.distance)
    }

    public static func closureTolerance(for distance: Double) -> Double {
        min(max(distance * 0.005, 50), 200)
    }
}
