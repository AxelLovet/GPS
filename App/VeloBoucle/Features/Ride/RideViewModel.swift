import Foundation
import Observation
import UIKit
import VeloCore

/// Pilote une sortie : navigation, enregistrement, recalcul, sauvegarde.
///
/// Toute la logique de guidage réside dans `NavigationEngine` et `RideTracker`
/// (paquet `VeloCore`, testés unitairement). Cette classe se limite à
/// l'orchestration : consommer le flux de positions, relayer les événements vers
/// la voix et l'haptique, décider d'un recalcul, écrire les instantanés.
@Observable
@MainActor
final class RideViewModel {
    private let dependencies: AppDependencies

    private(set) var navigationState = NavigationState()
    private(set) var statistics = RideStatistics()
    private(set) var rideState: RideState = .idle
    private(set) var route: CyclingRoute?
    private(set) var track: [GeographicCoordinate] = []
    private(set) var currentCoordinate: GeographicCoordinate?
    private(set) var currentSpeed: Double = 0
    private(set) var error: VeloError?
    private(set) var isRecalculating = false
    /// Proposition de recalcul en attente de réponse de l'utilisateur.
    private(set) var pendingRecalculation: GeographicCoordinate?
    /// Sortie terminée en attente d'enregistrement, présentée par l'écran de fin.
    private(set) var finishedRide: RecordedRide?
    /// Sortie interrompue retrouvée au lancement.
    private(set) var recoverableSession: RideSession?

    private var engine: NavigationEngine?
    private var tracker: RideTracker?
    private var simulator: DemoRideSimulator?
    private var streamTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var lastSnapshotDate = Date.distantPast

    /// Intervalle minimal entre deux écritures d'instantané.
    ///
    /// Écrire à chaque relevé GPS solliciterait le disque une à deux fois par
    /// seconde pendant des heures. Dix secondes suffisent : c'est le maximum que
    /// l'on peut perdre si l'application est tuée.
    private let snapshotInterval: TimeInterval = 10

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var isActive: Bool { rideState == .running || rideState == .paused }
    var hasRoute: Bool { route != nil }

    // MARK: - Cycle de vie de la sortie

    /// Démarre une sortie, guidée si un circuit est fourni.
    func start(route: CyclingRoute?, name: String? = nil) {
        let now = Date()
        self.route = route
        self.error = nil
        self.finishedRide = nil
        self.track = []

        engine = route.map { NavigationEngine(route: $0) }
        tracker = RideTracker.start(
            at: now,
            name: name ?? Self.defaultRideName(at: now),
            plannedRoute: route,
            profile: dependencies.settings.profile
        )
        rideState = .running
        navigationState = NavigationState(
            remainingDistance: route?.distance ?? 0,
            remainingDuration: route?.duration ?? 0
        )

        dependencies.locationService.startUpdating(mode: .navigating)
        dependencies.hapticService.prepare()
        applyScreenAwakePreference()
        observeLocationUpdates()

        AppLog.ride.info("Sortie démarrée\(route == nil ? " sans circuit" : " avec circuit")")
    }

    func pause() {
        guard rideState == .running else { return }
        let now = Date()
        tracker?.pause(at: now)
        rideState = .paused
        dependencies.speechService.stop()
        // La précision maximale n'a plus d'intérêt à l'arrêt : on relâche le GPS
        // pour économiser la batterie pendant la pause.
        dependencies.locationService.startUpdating(mode: .browsing)
        writeSnapshot(force: true)
    }

    func resume() {
        guard rideState == .paused else { return }
        tracker?.resume(at: Date())
        rideState = .running
        dependencies.locationService.startUpdating(mode: .navigating)
    }

    /// Termine la sortie et prépare l'écran de résumé.
    @discardableResult
    func finish() -> RecordedRide? {
        guard var tracker = self.tracker else { return nil }
        let now = Date()
        let session = tracker.finish(at: now)
        self.tracker = tracker

        let ride = RecordedRide(
            session: session,
            finishedAt: now,
            bodyMassKilograms: dependencies.settings.bodyMassKilograms
        )
        finishedRide = ride
        rideState = .finished
        statistics = session.statistics

        stopEverything()
        Task { try? await dependencies.snapshotStore.clear() }

        AppLog.ride.info("Sortie terminée")
        return ride
    }

    /// Abandonne la sortie sans l'enregistrer.
    func discard() {
        stopEverything()
        engine = nil
        tracker = nil
        route = nil
        track = []
        rideState = .idle
        navigationState = NavigationState()
        statistics = RideStatistics()
        finishedRide = nil
        Task { try? await dependencies.snapshotStore.clear() }
    }

    /// Efface l'écran de fin après enregistrement ou refus.
    func clearFinishedRide() {
        finishedRide = nil
        route = nil
        track = []
        rideState = .idle
        navigationState = NavigationState()
        statistics = RideStatistics()
    }

    // MARK: - Mode démonstration

    /// Vrai lorsqu'un déplacement simulé est en cours.
    var isSimulating: Bool { simulator?.isRunning ?? false }

    /// Rejoue un déplacement le long du circuit, sans capteur GPS.
    ///
    /// Réservé au mode démonstration : la simulation ne remplace jamais les
    /// positions réelles, elle vient s'y substituer uniquement à la demande
    /// explicite de l'utilisateur.
    func startSimulation(withDetour: Bool) {
        guard dependencies.isDemoModeActive, let route else { return }
        if rideState == .idle || rideState == .finished {
            start(route: route)
        }
        // Le GPS réel n'a plus rien à apporter pendant une simulation, et le
        // laisser tourner ferait alterner deux positions incompatibles.
        dependencies.locationService.stopUpdating()

        let simulator = self.simulator ?? DemoRideSimulator()
        self.simulator = simulator
        simulator.start(on: route, withDetour: withDetour) { [weak self] sample in
            self?.handle(sample)
        }
    }

    func stopSimulation() {
        simulator?.stop()
        simulator = nil
        if rideState == .running {
            dependencies.locationService.startUpdating(mode: .navigating)
        }
    }

    private func stopEverything() {
        simulator?.stop(); simulator = nil
        streamTask?.cancel(); streamTask = nil
        snapshotTask?.cancel(); snapshotTask = nil
        dependencies.speechService.stop()
        dependencies.locationService.stopUpdating()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func applyScreenAwakePreference() {
        UIApplication.shared.isIdleTimerDisabled = dependencies.settings.keepScreenAwake
    }

    private static func defaultRideName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return "Sortie du \(formatter.string(from: date))"
    }

    // MARK: - Flux de positions

    private func observeLocationUpdates() {
        streamTask?.cancel()
        let stream = dependencies.locationService.sampleStream()
        streamTask = Task { [weak self] in
            for await sample in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(sample)
            }
        }
    }

    private func handle(_ sample: LocationSample) {
        currentCoordinate = sample.coordinate
        if sample.hasValidSpeed { currentSpeed = sample.speed }

        guard rideState == .running else { return }

        tracker?.add(sample)
        if let tracker {
            statistics = tracker.session.statistics
            // La trace affichée est reconstruite depuis la session : elle ne
            // contient donc que les points réellement retenus après filtrage.
            track = tracker.session.track.map(\.coordinate)
        }

        if engine != nil {
            let events = engine!.update(with: sample)
            navigationState = engine!.state
            for event in events { react(to: event, at: sample) }
        }

        writeSnapshot(force: false)
    }

    private func react(to event: NavigationEvent, at sample: LocationSample) {
        switch event {
        case .announce(let text, let priority):
            guard dependencies.settings.voiceInstructionsEnabled else { return }
            dependencies.speechService.announce(text, priority: priority)

        case .haptic(let cue):
            guard dependencies.settings.hapticFeedbackEnabled else { return }
            dependencies.hapticService.play(cue)

        case .offRoute(let distance):
            tracker?.beginDeviation(
                at: sample.timestamp, distance: distance, position: sample.coordinate
            )
            AppLog.navigation.notice("Sortie de parcours détectée")

        case .backOnRoute:
            tracker?.endDeviation(at: sample.timestamp)

        case .arrived:
            // On ne termine pas la sortie d'autorité : l'utilisateur peut
            // vouloir continuer à rouler au-delà de la boucle.
            AppLog.navigation.info("Arrivée atteinte")

        case .recalculationSuggested(let rejoin):
            handleRecalculationSuggestion(rejoin: rejoin)
        }

        if navigationState.isOffRoute, let distance = navigationState.deviationDistance {
            tracker?.updateDeviation(distance: distance)
        }
    }

    // MARK: - Recalcul

    private func handleRecalculationSuggestion(rejoin: GeographicCoordinate) {
        guard !isRecalculating else { return }
        switch dependencies.settings.recalculationPolicy {
        case .automatic:
            recalculate(towards: rejoin)
        case .ask:
            pendingRecalculation = rejoin
        case .never:
            break
        }
    }

    func acceptPendingRecalculation() {
        guard let rejoin = pendingRecalculation else { return }
        pendingRecalculation = nil
        recalculate(towards: rejoin)
    }

    func declinePendingRecalculation() {
        pendingRecalculation = nil
    }

    /// Calcule un itinéraire de la position actuelle vers un point du circuit,
    /// puis le raccorde au reste du parcours.
    func recalculate(towards rejoin: GeographicCoordinate) {
        guard let current = currentCoordinate, let existing = route else { return }
        isRecalculating = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRecalculating = false }
            do {
                let connector = try await dependencies.routingService.route(
                    through: [current, rejoin],
                    preferences: dependencies.settings.routingPreferences
                )
                let merged = RouteSplicer.splice(
                    connector: connector,
                    into: existing,
                    rejoiningAt: rejoin,
                    profile: dependencies.settings.profile
                )
                route = merged
                engine?.replaceRoute(with: merged)
                navigationState = engine?.state ?? navigationState
                tracker?.endDeviation(at: Date())

                if dependencies.settings.voiceInstructionsEnabled {
                    dependencies.speechService.announce(
                        "Nouvel itinéraire calculé", priority: .urgent
                    )
                }
                AppLog.navigation.info("Itinéraire recalculé")
            } catch {
                self.error = (error as? VeloError) ?? .routingEngineUnavailable(statusCode: nil)
            }
        }
    }

    // MARK: - Instantané et reprise

    private func writeSnapshot(force: Bool) {
        guard let session = tracker?.session else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshotDate) >= snapshotInterval else { return }
        lastSnapshotDate = now

        snapshotTask?.cancel()
        snapshotTask = Task { [dependencies] in
            try? await dependencies.snapshotStore.write(session)
        }
    }

    /// Cherche une sortie interrompue au lancement de l'application.
    func lookForInterruptedRide() async {
        guard rideState == .idle else { return }
        let stored = try? await dependencies.snapshotStore.read()
        switch RideRecovery.decide(for: stored, now: Date()) {
        case .offerResume(let session), .offerSaveOnly(let session):
            recoverableSession = session
        case .discard:
            recoverableSession = nil
            try? await dependencies.snapshotStore.clear()
        }
    }

    /// Reprend la sortie retrouvée. Elle redémarre en pause.
    func resumeRecoveredRide() {
        guard let session = recoverableSession else { return }
        let prepared = RideRecovery.prepareResume(session, now: Date())

        tracker = RideTracker(session: prepared)
        route = prepared.plannedRoute
        engine = prepared.plannedRoute.map { NavigationEngine(route: $0) }
        statistics = prepared.statistics
        track = prepared.track.map(\.coordinate)
        rideState = .paused
        recoverableSession = nil

        dependencies.locationService.startUpdating(mode: .browsing)
        observeLocationUpdates()
        applyScreenAwakePreference()
        AppLog.ride.info("Sortie interrompue reprise")
    }

    /// Enregistre la sortie retrouvée sans la reprendre.
    func saveRecoveredRideWithoutResuming() -> RecordedRide? {
        guard let session = recoverableSession else { return nil }
        recoverableSession = nil
        let ride = RecordedRide(
            session: session,
            finishedAt: session.lastUpdatedAt,
            bodyMassKilograms: dependencies.settings.bodyMassKilograms
        )
        finishedRide = ride
        Task { try? await dependencies.snapshotStore.clear() }
        return ride
    }

    func discardRecoveredRide() {
        recoverableSession = nil
        Task { try? await dependencies.snapshotStore.clear() }
    }

    func dismissError() { error = nil }

    /// Renomme la sortie en attente d'enregistrement.
    func renameFinishedRide(to name: String) {
        guard var ride = finishedRide else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ride.name = trimmed
        finishedRide = ride
    }
}

/// Raccorde un itinéraire de rattrapage au circuit d'origine.
enum RouteSplicer {
    /// Construit un circuit continu : trajet de rattrapage, puis suite du
    /// circuit initial à partir du point de reprise.
    ///
    /// Sans ce recollement, un recalcul ferait perdre la fin du parcours :
    /// l'utilisateur serait guidé jusqu'au point de reprise puis abandonné.
    static func splice(
        connector: CyclingRoute,
        into original: CyclingRoute,
        rejoiningAt rejoin: GeographicCoordinate,
        profile: CyclingProfile
    ) -> CyclingRoute {
        // Point du circuit d'origine le plus proche du point de reprise.
        var rejoinIndex = 0
        var bestDistance = Double.infinity
        for (index, coordinate) in original.coordinates.enumerated() {
            let distance = Geodesy.distance(from: coordinate, to: rejoin)
            if distance < bestDistance {
                bestDistance = distance
                rejoinIndex = index
            }
        }

        let remainder = Array(original.coordinates[rejoinIndex...])
        let coordinates = connector.coordinates + remainder.dropFirst()
        guard coordinates.count >= 2 else { return original }

        let offset = connector.coordinates.count - 1
        // Les consignes du circuit d'origine sont réindexées sur la nouvelle
        // polyligne ; celles déjà passées sont écartées.
        let shiftedInstructions = original.instructions
            .filter { $0.endPointIndex > rejoinIndex }
            .map { instruction in
                NavigationInstruction(
                    maneuver: instruction.maneuver,
                    roadName: instruction.roadName,
                    distance: instruction.distance,
                    duration: instruction.duration,
                    startPointIndex: max(instruction.startPointIndex - rejoinIndex, 0) + offset,
                    endPointIndex: max(instruction.endPointIndex - rejoinIndex, 0) + offset,
                    roundaboutExitNumber: instruction.roundaboutExitNumber,
                    rawText: instruction.rawText
                )
            }

        let remainingDistance = Geodesy.polylineLength(remainder)
        let remainingDuration = original.distance > 0
            ? original.duration * (remainingDistance / original.distance)
            : 0

        return CyclingRoute(
            coordinates: coordinates,
            distance: connector.distance + remainingDistance,
            duration: connector.duration + remainingDuration,
            ascent: original.ascent,
            descent: original.descent,
            instructions: connector.instructions.filter { $0.maneuver != .arrive }
                + shiftedInstructions,
            segments: [],
            profile: profile,
            requestedDistance: original.requestedDistance
        )
    }
}
