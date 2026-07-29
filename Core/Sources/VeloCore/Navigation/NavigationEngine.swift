import Foundation

/// Intensité du retour haptique demandé.
public enum HapticCue: String, Sendable, Equatable {
    /// Manœuvre approchant (environ 150 m).
    case upcomingManeuver
    /// Manœuvre imminente (environ 40 m).
    case imminentManeuver
    /// Sortie de parcours.
    case offRoute
    /// Retour sur le parcours.
    case backOnRoute
    /// Arrivée.
    case arrival
}

/// Priorité d'une annonce vocale.
public enum AnnouncementPriority: String, Sendable, Equatable {
    /// Peut être ignorée si une autre annonce est en cours.
    case normal
    /// Doit interrompre l'annonce en cours.
    case urgent
}

/// Événement produit par le moteur de navigation à chaque mise à jour.
public enum NavigationEvent: Sendable, Equatable {
    case announce(text: String, priority: AnnouncementPriority)
    case haptic(HapticCue)
    case offRoute(distance: Double)
    case backOnRoute
    case arrived
    /// Un recalcul est pertinent ; la couche interface décide s'il faut le
    /// déclencher, le proposer ou l'ignorer selon `RecalculationPolicy`.
    case recalculationSuggested(rejoin: GeographicCoordinate)
}

/// Tout ce que l'écran de navigation a besoin d'afficher.
public struct NavigationState: Sendable, Equatable {
    public var match: RouteMatch?
    public var currentInstruction: NavigationInstruction?
    public var nextInstruction: NavigationInstruction?
    /// Distance jusqu'à la prochaine manœuvre, en mètres.
    public var distanceToManeuver: Double
    /// Texte de la consigne en cours, prêt à afficher.
    public var instructionText: String
    /// Distance restante jusqu'à l'arrivée, en mètres.
    public var remainingDistance: Double
    /// Durée restante estimée, en secondes.
    public var remainingDuration: TimeInterval
    /// Heure d'arrivée estimée.
    public var estimatedArrival: Date?
    public var isOffRoute: Bool
    /// Écart au tracé lorsque l'utilisateur est hors parcours, en mètres.
    public var deviationDistance: Double?
    /// Progression sur le circuit, entre 0 et 1.
    public var fractionCompleted: Double
    /// Cap de déplacement, pour orienter la carte.
    public var course: Double?
    public var hasArrived: Bool

    public init(
        match: RouteMatch? = nil,
        currentInstruction: NavigationInstruction? = nil,
        nextInstruction: NavigationInstruction? = nil,
        distanceToManeuver: Double = 0,
        instructionText: String = "",
        remainingDistance: Double = 0,
        remainingDuration: TimeInterval = 0,
        estimatedArrival: Date? = nil,
        isOffRoute: Bool = false,
        deviationDistance: Double? = nil,
        fractionCompleted: Double = 0,
        course: Double? = nil,
        hasArrived: Bool = false
    ) {
        self.match = match
        self.currentInstruction = currentInstruction
        self.nextInstruction = nextInstruction
        self.distanceToManeuver = distanceToManeuver
        self.instructionText = instructionText
        self.remainingDistance = remainingDistance
        self.remainingDuration = remainingDuration
        self.estimatedArrival = estimatedArrival
        self.isOffRoute = isOffRoute
        self.deviationDistance = deviationDistance
        self.fractionCompleted = fractionCompleted
        self.course = course
        self.hasArrived = hasArrived
    }
}

/// Moteur de guidage.
///
/// C'est un type valeur à état mutable : chaque relevé GPS produit un nouvel
/// état et une liste d'événements. Ce choix rend la navigation entièrement
/// reproductible en test — on rejoue une trace et on vérifie les événements —
/// sans dépendre de CoreLocation, d'un simulateur ni d'un minuteur.
public struct NavigationEngine: Sendable {
    /// Paliers d'annonce avant une manœuvre, en mètres, du plus loin au plus près.
    public struct AnnouncementThresholds: Sendable {
        public var far: Double
        public var near: Double
        public var imminent: Double
        /// En dessous de cette longueur, l'annonce lointaine est inutile : la
        /// manœuvre suivante arriverait avant qu'on ait fini de parler.
        public var minimumDistanceForFarAnnouncement: Double

        public init(
            far: Double = 400,
            near: Double = 150,
            imminent: Double = 40,
            minimumDistanceForFarAnnouncement: Double = 700
        ) {
            self.far = far
            self.near = near
            self.imminent = imminent
            self.minimumDistanceForFarAnnouncement = minimumDistanceForFarAnnouncement
        }
    }

    private enum AnnouncementStage: Int, Comparable {
        case none = 0, far, near, imminent
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public private(set) var route: CyclingRoute
    public private(set) var state: NavigationState
    public var thresholds: AnnouncementThresholds
    public var arrivalRadius: Double

    private let matcher: RouteMatching
    private let detector: DeviationDetector
    private var detectorState = DeviationDetector.State()
    private var announcedStage: [UUID: AnnouncementStage] = [:]
    private var hapticStage: [UUID: AnnouncementStage] = [:]
    private var hasAnnouncedArrival = false
    private var smoothedSpeed: Double?

    public init(
        route: CyclingRoute,
        matcher: RouteMatching = RouteMatchingService(),
        detector: DeviationDetector = DeviationDetector(),
        thresholds: AnnouncementThresholds = AnnouncementThresholds(),
        arrivalRadius: Double = 35
    ) {
        self.route = route
        self.matcher = matcher
        self.detector = detector
        self.thresholds = thresholds
        self.arrivalRadius = arrivalRadius
        self.state = NavigationState(
            remainingDistance: route.distance,
            remainingDuration: route.duration
        )
    }

    /// Remplace le circuit suivi, après un recalcul.
    ///
    /// L'état d'annonce est réinitialisé : les consignes du nouvel itinéraire
    /// n'ont rien à voir avec les précédentes.
    public mutating func replaceRoute(with newRoute: CyclingRoute) {
        route = newRoute
        detectorState = DeviationDetector.State()
        announcedStage.removeAll()
        hapticStage.removeAll()
        hasAnnouncedArrival = false
        state.match = nil
        state.isOffRoute = false
        state.deviationDistance = nil
        state.remainingDistance = newRoute.distance
        state.remainingDuration = newRoute.duration
    }

    /// Traite un relevé de position et renvoie les événements à déclencher.
    @discardableResult
    public mutating func update(with sample: LocationSample, now: Date? = nil) -> [NavigationEvent] {
        let referenceDate = now ?? sample.timestamp
        var events: [NavigationEvent] = []

        guard let match = matcher.match(
            sample.coordinate,
            on: route,
            near: state.match
        ) else {
            return events
        }

        state.match = match
        state.remainingDistance = match.remainingDistance
        state.fractionCompleted = match.fractionCompleted
        state.course = sample.hasValidCourse ? sample.course : state.course

        updateSmoothedSpeed(with: sample)

        // Écart au parcours
        let deviationEvent = detector.evaluate(
            distanceFromRoute: match.distanceFromRoute,
            horizontalAccuracy: sample.horizontalAccuracy,
            state: &detectorState
        )
        switch deviationEvent {
        case .onRoute:
            state.isOffRoute = false
            state.deviationDistance = nil
        case .departed(let distance):
            state.isOffRoute = true
            state.deviationDistance = distance
            events.append(.offRoute(distance: distance))
            events.append(.haptic(.offRoute))
            events.append(
                .announce(text: "Vous avez quitté le parcours", priority: .urgent)
            )
            if let rejoin = RejoinPointSelector.rejoinPoint(
                on: route,
                from: sample.coordinate,
                lastMatch: match
            ) {
                events.append(.recalculationSuggested(rejoin: rejoin.coordinate))
            }
        case .stillOff(let distance):
            state.isOffRoute = true
            state.deviationDistance = distance
        case .returned:
            state.isOffRoute = false
            state.deviationDistance = nil
            events.append(.backOnRoute)
            events.append(.haptic(.backOnRoute))
            events.append(
                .announce(text: "Vous êtes de retour sur le parcours", priority: .normal)
            )
        }

        // Consignes
        let instructionIndex = currentInstructionIndex(for: match)
        let current = instructionIndex.map { route.instructions[$0] }
        let next = instructionIndex
            .flatMap { $0 + 1 < route.instructions.count ? route.instructions[$0 + 1] : nil }

        state.currentInstruction = current
        state.nextInstruction = next

        if let current {
            let maneuverDistance = distanceToEnd(of: current, from: match)
            state.distanceToManeuver = maneuverDistance
            state.instructionText = InstructionPhrasing.instructionText(
                current,
                distanceToManeuver: maneuverDistance
            )
            if !state.isOffRoute {
                events += announcementEvents(for: current, distance: maneuverDistance)
            }
        } else {
            state.distanceToManeuver = match.remainingDistance
            state.instructionText = InstructionPhrasing.maneuverText(.straight)
        }

        // Durée restante et heure d'arrivée
        state.remainingDuration = estimatedRemainingDuration(match: match)
        state.estimatedArrival = referenceDate.addingTimeInterval(state.remainingDuration)

        // Arrivée
        if !hasAnnouncedArrival,
           match.remainingDistance <= arrivalRadius,
           match.fractionCompleted > 0.8 {
            hasAnnouncedArrival = true
            state.hasArrived = true
            events.append(.arrived)
            events.append(.haptic(.arrival))
            events.append(.announce(text: "Vous êtes arrivé", priority: .urgent))
        }

        return events
    }

    // MARK: - Consignes

    /// Index de la consigne en cours.
    ///
    /// Une consigne couvre les points `[startPointIndex, endPointIndex]` du
    /// tracé ; on cherche celle dont l'intervalle contient le segment courant.
    func currentInstructionIndex(for match: RouteMatch) -> Int? {
        guard !route.instructions.isEmpty else { return nil }
        let segment = match.segmentIndex

        for (index, instruction) in route.instructions.enumerated()
        where segment >= instruction.startPointIndex && segment < instruction.endPointIndex {
            return index
        }

        // Le segment courant est au-delà de la dernière consigne bornée : on
        // renvoie la consigne finale (arrivée).
        if let last = route.instructions.indices.last,
           segment >= route.instructions[last].startPointIndex {
            return last
        }
        return route.instructions.indices.first
    }

    private func distanceToEnd(of instruction: NavigationInstruction, from match: RouteMatch) -> Double {
        let cumulative = route.cumulativeDistances
        guard instruction.endPointIndex < cumulative.count else {
            return match.remainingDistance
        }
        return max(cumulative[instruction.endPointIndex] - match.distanceAlongRoute, 0)
    }

    private mutating func announcementEvents(
        for instruction: NavigationInstruction,
        distance: Double
    ) -> [NavigationEvent] {
        guard instruction.maneuver != .depart else { return [] }

        let stage: AnnouncementStage
        if distance <= thresholds.imminent {
            stage = .imminent
        } else if distance <= thresholds.near {
            stage = .near
        } else if distance <= thresholds.far,
                  instruction.distance >= thresholds.minimumDistanceForFarAnnouncement {
            stage = .far
        } else {
            return []
        }

        var events: [NavigationEvent] = []
        let previousAnnouncement = announcedStage[instruction.id] ?? .none

        // Une consigne « tout droit » n'a pas besoin d'être répétée : on
        // n'annonce et ne vibre que pour les vrais changements de direction.
        if stage > previousAnnouncement, instruction.maneuver.requiresAdvanceWarning {
            announcedStage[instruction.id] = stage
            events.append(
                .announce(
                    text: InstructionPhrasing.spokenText(instruction, distanceToManeuver: distance),
                    priority: stage == .imminent ? .urgent : .normal
                )
            )
        } else if stage > previousAnnouncement {
            announcedStage[instruction.id] = stage
        }

        let previousHaptic = hapticStage[instruction.id] ?? .none
        if instruction.maneuver.requiresAdvanceWarning, stage > previousHaptic, stage >= .near {
            hapticStage[instruction.id] = stage
            events.append(.haptic(stage == .imminent ? .imminentManeuver : .upcomingManeuver))
        }

        return events
    }

    // MARK: - Estimations

    /// Lissage exponentiel de la vitesse.
    ///
    /// La vitesse instantanée du GPS est bruitée ; l'utiliser telle quelle ferait
    /// osciller l'heure d'arrivée de plusieurs minutes à chaque seconde. Un
    /// facteur de 0,25 amortit le bruit tout en réagissant en une dizaine de
    /// secondes à un vrai changement d'allure.
    private mutating func updateSmoothedSpeed(with sample: LocationSample) {
        guard sample.hasValidSpeed, sample.speed >= 0 else { return }
        if let previous = smoothedSpeed {
            smoothedSpeed = previous * 0.75 + sample.speed * 0.25
        } else {
            smoothedSpeed = sample.speed
        }
    }

    /// Durée restante, combinant l'estimation du moteur et l'allure réelle.
    ///
    /// Le moteur connaît le profil du terrain mais ignore la forme du cycliste ;
    /// la vitesse mesurée est l'inverse. La moyenne des deux donne une heure
    /// d'arrivée sensiblement plus juste que l'une ou l'autre isolément.
    private func estimatedRemainingDuration(match: RouteMatch) -> TimeInterval {
        let total = route.distance
        guard total > 0 else { return 0 }

        let plannedRemaining = route.duration * (match.remainingDistance / total)

        guard let speed = smoothedSpeed, speed > 1.0 else { return plannedRemaining }
        let measuredRemaining = match.remainingDistance / speed
        return plannedRemaining * 0.5 + measuredRemaining * 0.5
    }
}
