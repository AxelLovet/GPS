import Foundation

/// Nature du revêtement d'un tronçon.
public enum SurfaceKind: String, Codable, Sendable, CaseIterable {
    case paved
    case unpaved
    case gravel
    case unknown

    /// Traduction des valeurs `extra_info.surface` d'OpenRouteService.
    ///
    /// Table ORS : 0 inconnu, 1 pavé (générique), 2 asphalte, 3 béton,
    /// 4 chaussée pavée, 5 pavés, 6 non pavé (générique), 7 gravier fin,
    /// 8 compacté, 9 terre, 10 gravier, 11 empierré, 12 herbe, …
    public init(openRouteServiceValue value: Int) {
        switch value {
        case 1...5: self = .paved
        case 7, 10, 11: self = .gravel
        case 6, 8, 9, 12...20: self = .unpaved
        default: self = .unknown
        }
    }
}

/// Nature de la voie empruntée.
public enum WayKind: String, Codable, Sendable, CaseIterable {
    case cyclePath
    case road
    case path
    case unknown

    /// Traduction des valeurs `extra_info.waytype` d'OpenRouteService.
    ///
    /// Table ORS : 0 inconnu, 1 route nationale, 2 route, 3 rue,
    /// 4 chemin (track), 5 piste cyclable, 6 sentier, 7 chemin piéton,
    /// 8 escalier, 9 ferry, 10 construction.
    public init(openRouteServiceValue value: Int) {
        switch value {
        case 5: self = .cyclePath
        case 1, 2, 3: self = .road
        case 4, 6, 7: self = .path
        default: self = .unknown
        }
    }
}

/// Tronçon homogène d'un itinéraire (même revêtement, même type de voie).
public struct RouteSegment: Hashable, Codable, Sendable {
    /// Index du premier point du tronçon dans la polyligne du circuit.
    public let startPointIndex: Int
    /// Index du dernier point du tronçon dans la polyligne du circuit.
    public let endPointIndex: Int
    public let surface: SurfaceKind
    public let wayKind: WayKind
    /// Longueur du tronçon en mètres.
    public let distance: Double

    public init(
        startPointIndex: Int,
        endPointIndex: Int,
        surface: SurfaceKind = .unknown,
        wayKind: WayKind = .unknown,
        distance: Double
    ) {
        self.startPointIndex = startPointIndex
        self.endPointIndex = endPointIndex
        self.surface = surface
        self.wayKind = wayKind
        self.distance = distance
    }
}

/// Un circuit cyclable calculé, prêt à être affiché ou navigué.
public struct CyclingRoute: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Polyligne complète du circuit, du départ à l'arrivée.
    public let coordinates: [GeographicCoordinate]
    /// Distance totale en mètres, telle que fournie par le moteur.
    public let distance: Double
    /// Durée estimée en secondes.
    public let duration: TimeInterval
    /// Dénivelé positif cumulé en mètres, si disponible.
    public let ascent: Double?
    /// Dénivelé négatif cumulé en mètres, si disponible.
    public let descent: Double?
    public let instructions: [NavigationInstruction]
    public let segments: [RouteSegment]
    /// Profil utilisé pour le calcul.
    public let profile: CyclingProfile
    /// Distance demandée par l'utilisateur, en mètres, si le circuit provient
    /// d'une génération de boucle.
    public let requestedDistance: Double?
    /// Distances cumulées depuis le départ, une valeur par point de `coordinates`.
    ///
    /// Précalculé une fois à la construction : la navigation interroge cette
    /// table à chaque mise à jour GPS, et la recalculer coûterait O(n) par point.
    public let cumulativeDistances: [Double]

    public init(
        id: UUID = UUID(),
        coordinates: [GeographicCoordinate],
        distance: Double,
        duration: TimeInterval,
        ascent: Double? = nil,
        descent: Double? = nil,
        instructions: [NavigationInstruction] = [],
        segments: [RouteSegment] = [],
        profile: CyclingProfile = .electricRoad,
        requestedDistance: Double? = nil
    ) {
        self.id = id
        self.coordinates = coordinates
        self.distance = distance
        self.duration = duration
        self.ascent = ascent
        self.descent = descent
        self.instructions = instructions
        self.segments = segments
        self.profile = profile
        self.requestedDistance = requestedDistance
        self.cumulativeDistances = Self.computeCumulativeDistances(coordinates)
    }

    private static func computeCumulativeDistances(
        _ coordinates: [GeographicCoordinate]
    ) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: coordinates.count)
        for index in 1..<coordinates.count {
            result[index] = result[index - 1]
                + Geodesy.distance(from: coordinates[index - 1], to: coordinates[index])
        }
        return result
    }

    public var start: GeographicCoordinate? { coordinates.first }
    public var end: GeographicCoordinate? { coordinates.last }

    /// Distance entre le départ et l'arrivée, en mètres. Doit rester faible
    /// pour qu'un circuit mérite le nom de boucle.
    public var loopClosureDistance: Double {
        guard let start, let end else { return .infinity }
        return Geodesy.distance(from: start, to: end)
    }

    /// Longueur mesurée sur la polyligne, indépendante de la valeur annoncée
    /// par le moteur. Sert à détecter une réponse incohérente.
    public var measuredDistance: Double { cumulativeDistances.last ?? 0 }

    /// Part du circuit empruntant une piste cyclable, entre 0 et 1.
    public var cyclePathRatio: Double? {
        guard !segments.isEmpty, distance > 0 else { return nil }
        let known = segments.filter { $0.wayKind != .unknown }
        guard !known.isEmpty else { return nil }
        let onCyclePath = known.filter { $0.wayKind == .cyclePath }
            .reduce(0) { $0 + $1.distance }
        let total = known.reduce(0) { $0 + $1.distance }
        guard total > 0 else { return nil }
        return onCyclePath / total
    }

    /// Part du circuit sur revêtement non goudronné, entre 0 et 1.
    public var unpavedRatio: Double? {
        guard !segments.isEmpty else { return nil }
        let known = segments.filter { $0.surface != .unknown }
        guard !known.isEmpty else { return nil }
        let unpaved = known.filter { $0.surface == .unpaved || $0.surface == .gravel }
            .reduce(0) { $0 + $1.distance }
        let total = known.reduce(0) { $0 + $1.distance }
        guard total > 0 else { return nil }
        return unpaved / total
    }

    /// Écart relatif signé à la distance demandée (0,05 = 5 % de trop).
    public var distanceDeviationRatio: Double? {
        guard let requestedDistance, requestedDistance > 0 else { return nil }
        return (distance - requestedDistance) / requestedDistance
    }
}
