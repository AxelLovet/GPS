import Foundation

/// Enregistre une sortie : trace filtrée, distance, vitesses, dénivelé, écarts.
///
/// Type valeur à état mutable, comme `NavigationEngine` : une trace complète
/// peut être rejouée en test et les statistiques vérifiées exactement, sans
/// horloge ni capteur réel.
public struct RideTracker: Sendable {
    public private(set) var session: RideSession
    private let filter: LocationFilter
    /// Vitesse en dessous de laquelle le cycliste est considéré à l'arrêt, en m/s.
    /// 0,8 m/s ≈ 3 km/h : en dessous, on marche ou on attend à un feu.
    private let movingSpeedThreshold: Double

    /// Dernier relevé accepté, y compris ceux ignorés pour cause d'immobilité —
    /// nécessaire pour calculer correctement l'intervalle de temps suivant.
    private var lastAcceptedSample: LocationSample?
    /// Altitude de référence pour le calcul du dénivelé, mise à jour par paliers.
    private var referenceAltitude: Double?
    /// Écart en cours, s'il y en a un.
    private var openDeviationIndex: Int?

    public init(
        session: RideSession,
        filter: LocationFilter = LocationFilter(),
        movingSpeedThreshold: Double = 0.8
    ) {
        self.session = session
        self.filter = filter
        self.movingSpeedThreshold = movingSpeedThreshold
        self.lastAcceptedSample = session.track.last
        self.referenceAltitude = session.track.last?.coordinate.altitude
    }

    /// Démarre une nouvelle sortie.
    public static func start(
        at date: Date,
        name: String,
        plannedRoute: CyclingRoute?,
        profile: CyclingProfile,
        filter: LocationFilter = LocationFilter()
    ) -> RideTracker {
        RideTracker(
            session: RideSession(
                name: name,
                state: .running,
                startedAt: date,
                plannedRoute: plannedRoute,
                profile: profile
            ),
            filter: filter
        )
    }

    // MARK: - Cycle de vie

    public mutating func pause(at date: Date) {
        guard session.state == .running else { return }
        session.state = .paused
        session.lastUpdatedAt = date
    }

    public mutating func resume(at date: Date) {
        guard session.state == .paused else { return }
        session.state = .running
        session.lastUpdatedAt = date
        // Le relevé de référence est oublié : l'intervalle passé en pause ne
        // doit compter ni en distance ni en temps de déplacement.
        lastAcceptedSample = nil
    }

    public mutating func finish(at date: Date) -> RideSession {
        session.state = .finished
        session.lastUpdatedAt = date
        session.statistics.elapsedTime = date.timeIntervalSince(session.startedAt)
        closeOpenDeviation(at: date)
        return session
    }

    public mutating func rename(_ name: String) {
        session.name = name
    }

    // MARK: - Relevés

    /// Résultat de l'ajout d'un relevé.
    @discardableResult
    public mutating func add(_ sample: LocationSample) -> LocationFilter.Rejection? {
        guard session.state == .running else { return .notMoving }

        if let rejection = filter.rejectionReason(for: sample, previous: lastAcceptedSample) {
            // « Immobile » n'est pas une erreur : le relevé n'enrichit pas la
            // trace mais fait bien avancer le temps écoulé.
            if rejection == .notMoving {
                session.statistics.elapsedTime = sample.timestamp
                    .timeIntervalSince(session.startedAt)
                session.lastUpdatedAt = sample.timestamp
            }
            return rejection
        }

        if let previous = lastAcceptedSample {
            let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
            let displacement = Geodesy.distance(from: previous.coordinate, to: sample.coordinate)

            session.statistics.distance += displacement

            let effectiveSpeed = interval > 0 ? displacement / interval : 0
            if effectiveSpeed >= movingSpeedThreshold {
                session.statistics.movingTime += interval
            }

            // La vitesse maximale s'appuie sur le déplacement mesuré plutôt que
            // sur la vitesse instantanée du GPS, plus sujette aux pics.
            let candidateSpeed = sample.hasValidSpeed
                ? min(sample.speed, effectiveSpeed * 1.5)
                : effectiveSpeed
            if candidateSpeed <= filter.maximumPlausibleSpeed {
                session.statistics.maximumSpeed = max(
                    session.statistics.maximumSpeed,
                    candidateSpeed
                )
            }
        }

        updateElevation(with: sample)

        session.track.append(sample)
        lastAcceptedSample = sample
        session.lastUpdatedAt = sample.timestamp
        session.statistics.elapsedTime = sample.timestamp.timeIntervalSince(session.startedAt)

        return nil
    }

    /// Cumule le dénivelé par paliers.
    ///
    /// L'altitude GPS oscille de plusieurs mètres même à l'arrêt. On ne
    /// comptabilise donc un dénivelé que lorsque l'écart avec l'altitude de
    /// référence dépasse le seuil, puis on déplace la référence. Sans cela, une
    /// sortie plate afficherait plusieurs centaines de mètres de dénivelé.
    private mutating func updateElevation(with sample: LocationSample) {
        guard let altitude = sample.coordinate.altitude else { return }
        // Une altitude n'est retenue que si la précision verticale est connue et
        // raisonnable ; sinon elle n'a aucune valeur.
        guard sample.verticalAccuracy >= 0, sample.verticalAccuracy <= 20 else { return }

        guard let reference = referenceAltitude else {
            referenceAltitude = altitude
            return
        }

        let change = altitude - reference
        guard abs(change) >= filter.minimumAltitudeChange else { return }

        if change > 0 {
            session.statistics.ascent += change
        } else {
            session.statistics.descent += -change
        }
        referenceAltitude = altitude
    }

    // MARK: - Écarts de parcours

    /// Enregistre le début d'un écart au circuit.
    public mutating func beginDeviation(at date: Date, distance: Double, position: GeographicCoordinate) {
        guard openDeviationIndex == nil else { return }
        session.deviations.append(
            RouteDeviation(startedAt: date, maximumDistance: distance, detectedAt: position)
        )
        openDeviationIndex = session.deviations.count - 1
    }

    /// Met à jour l'écart maximal atteint pendant l'écart en cours.
    public mutating func updateDeviation(distance: Double) {
        guard let index = openDeviationIndex else { return }
        session.deviations[index].maximumDistance = max(
            session.deviations[index].maximumDistance,
            distance
        )
    }

    /// Clôt l'écart en cours, l'utilisateur étant revenu sur le circuit.
    public mutating func endDeviation(at date: Date) {
        closeOpenDeviation(at: date)
    }

    private mutating func closeOpenDeviation(at date: Date) {
        guard let index = openDeviationIndex else { return }
        session.deviations[index].endedAt = date
        openDeviationIndex = nil
    }
}
