import Foundation

/// Un relevé de position, indépendant de CoreLocation.
///
/// `LocationService` (couche iOS) convertit chaque `CLLocation` en
/// `LocationSample` avant de le transmettre au cœur applicatif. Le suivi de
/// parcours et l'enregistrement de la sortie sont ainsi entièrement testables
/// sans simulateur.
public struct LocationSample: Hashable, Codable, Sendable {
    public let coordinate: GeographicCoordinate
    public let timestamp: Date
    /// Incertitude horizontale en mètres. Négative si indisponible.
    public let horizontalAccuracy: Double
    /// Incertitude verticale en mètres. Négative si indisponible.
    public let verticalAccuracy: Double
    /// Vitesse instantanée en m/s. Négative si indisponible.
    public let speed: Double
    /// Cap de déplacement en degrés. Négatif si indisponible.
    public let course: Double

    public init(
        coordinate: GeographicCoordinate,
        timestamp: Date,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = -1,
        speed: Double = -1,
        course: Double = -1
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
    }

    public var hasValidSpeed: Bool { speed >= 0 }
    public var hasValidCourse: Bool { course >= 0 }
    public var hasValidAltitude: Bool { coordinate.altitude != nil && verticalAccuracy >= 0 }
}

/// Écart constaté entre la position réelle et le circuit suivi.
public struct RouteDeviation: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Début de l'écart.
    public let startedAt: Date
    /// Fin de l'écart, `nil` tant que l'utilisateur n'est pas revenu sur le circuit.
    public var endedAt: Date?
    /// Distance maximale au circuit atteinte pendant l'écart, en mètres.
    public var maximumDistance: Double
    /// Position à laquelle l'écart a été détecté.
    public let detectedAt: GeographicCoordinate

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        maximumDistance: Double,
        detectedAt: GeographicCoordinate
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.maximumDistance = maximumDistance
        self.detectedAt = detectedAt
    }

    public var isResolved: Bool { endedAt != nil }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}
