import Foundation

/// État d'une sortie en cours.
public enum RideState: String, Codable, Sendable {
    case idle
    case running
    case paused
    case finished
}

/// Statistiques agrégées d'une sortie.
public struct RideStatistics: Hashable, Codable, Sendable {
    /// Distance parcourue en mètres.
    public var distance: Double
    /// Durée totale écoulée, pauses comprises, en secondes.
    public var elapsedTime: TimeInterval
    /// Temps de déplacement effectif (hors arrêts), en secondes.
    public var movingTime: TimeInterval
    /// Vitesse maximale en m/s.
    public var maximumSpeed: Double
    /// Dénivelé positif cumulé en mètres.
    public var ascent: Double
    /// Dénivelé négatif cumulé en mètres.
    public var descent: Double

    public init(
        distance: Double = 0,
        elapsedTime: TimeInterval = 0,
        movingTime: TimeInterval = 0,
        maximumSpeed: Double = 0,
        ascent: Double = 0,
        descent: Double = 0
    ) {
        self.distance = distance
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.maximumSpeed = maximumSpeed
        self.ascent = ascent
        self.descent = descent
    }

    /// Vitesse moyenne sur le temps de déplacement, en m/s.
    ///
    /// C'est la définition retenue par les compteurs vélo (Garmin, Wahoo) :
    /// les arrêts aux feux ne doivent pas faire chuter la moyenne. La moyenne
    /// sur le temps total est disponible séparément.
    public var averageMovingSpeed: Double {
        guard movingTime > 0 else { return 0 }
        return distance / movingTime
    }

    /// Vitesse moyenne sur la durée totale, en m/s.
    public var averageOverallSpeed: Double {
        guard elapsedTime > 0 else { return 0 }
        return distance / elapsedTime
    }

    /// Estimation des calories brûlées, en kilocalories.
    ///
    /// Formule MET standard : kcal = MET × masse(kg) × heures. C'est une
    /// approximation grossière — elle ignore le vent, la pente réelle, le
    /// matériel et la condition physique — et l'interface doit toujours la
    /// présenter comme une estimation.
    public func estimatedCalories(profile: CyclingProfile, bodyMassKilograms: Double) -> Double {
        guard movingTime > 0, bodyMassKilograms > 0 else { return 0 }
        return profile.metabolicEquivalent * bodyMassKilograms * (movingTime / 3600)
    }
}

/// Une sortie en cours d'enregistrement.
///
/// Ce type est sérialisable : il est écrit périodiquement sur disque pendant la
/// sortie afin de permettre la reprise après une fermeture involontaire de
/// l'application (cahier des charges §15).
public struct RideSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var state: RideState
    public let startedAt: Date
    /// Instant de la dernière mise à jour appliquée.
    public var lastUpdatedAt: Date
    /// Trace GPS enregistrée, après filtrage.
    public var track: [LocationSample]
    public var statistics: RideStatistics
    /// Circuit suivi, s'il y en avait un.
    public var plannedRoute: CyclingRoute?
    public var deviations: [RouteDeviation]
    public var profile: CyclingProfile

    public init(
        id: UUID = UUID(),
        name: String,
        state: RideState = .running,
        startedAt: Date,
        lastUpdatedAt: Date? = nil,
        track: [LocationSample] = [],
        statistics: RideStatistics = RideStatistics(),
        plannedRoute: CyclingRoute? = nil,
        deviations: [RouteDeviation] = [],
        profile: CyclingProfile = .electricRoad
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt ?? startedAt
        self.track = track
        self.statistics = statistics
        self.plannedRoute = plannedRoute
        self.deviations = deviations
        self.profile = profile
    }

    /// Vrai si la session peut être proposée à la reprise après un
    /// redémarrage : elle n'est pas terminée et contient des données utiles.
    public var isResumable: Bool {
        state != .finished && (statistics.distance > 0 || track.count > 1)
    }
}

/// Une sortie terminée et sauvegardée.
public struct RecordedRide: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public let startedAt: Date
    public let finishedAt: Date
    public let statistics: RideStatistics
    public let track: [LocationSample]
    public let plannedRoute: CyclingRoute?
    public let deviations: [RouteDeviation]
    public let profile: CyclingProfile
    /// Masse utilisée pour l'estimation calorique au moment de la sauvegarde.
    public let bodyMassKilograms: Double

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        finishedAt: Date,
        statistics: RideStatistics,
        track: [LocationSample],
        plannedRoute: CyclingRoute?,
        deviations: [RouteDeviation],
        profile: CyclingProfile,
        bodyMassKilograms: Double
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.statistics = statistics
        self.track = track
        self.plannedRoute = plannedRoute
        self.deviations = deviations
        self.profile = profile
        self.bodyMassKilograms = bodyMassKilograms
    }

    public var estimatedCalories: Double {
        statistics.estimatedCalories(profile: profile, bodyMassKilograms: bodyMassKilograms)
    }

    /// Construit une sortie enregistrée à partir d'une session terminée.
    public init(session: RideSession, finishedAt: Date, bodyMassKilograms: Double) {
        self.init(
            id: session.id,
            name: session.name,
            startedAt: session.startedAt,
            finishedAt: finishedAt,
            statistics: session.statistics,
            track: session.track,
            plannedRoute: session.plannedRoute,
            deviations: session.deviations,
            profile: session.profile,
            bodyMassKilograms: bodyMassKilograms
        )
    }
}
