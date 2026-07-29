import Foundation
import Observation
import VeloCore

/// Étape courante du parcours de création d'un circuit.
enum PlannerStage: Equatable {
    /// Carte et choix de la distance.
    case idle
    /// Calcul en cours.
    case generating
    /// Comparaison des propositions.
    case comparing
    /// Aperçu du circuit choisi, prêt à démarrer.
    case previewing
}

/// Pilote l'écran d'accueil : point de départ, distance, génération, choix.
@Observable
@MainActor
final class PlannerViewModel {
    /// Distances proposées en accès direct, en mètres.
    static let presetDistances: [Double] = [5_000, 10_000, 20_000, 30_000, 50_000]

    private let dependencies: AppDependencies

    private(set) var stage: PlannerStage = .idle
    private(set) var progress: LoopGenerationProgress?
    private(set) var candidates: [RouteCandidate] = []
    private(set) var error: VeloError?

    var selectedCandidate: RouteCandidate?
    /// Distance visée, en mètres.
    var targetDistance: Double

    /// Point de départ choisi manuellement sur la carte. `nil` = position actuelle.
    var customStart: GeographicCoordinate?
    /// Vrai quand l'utilisateur est en train de désigner un départ sur la carte.
    var isPickingStart = false

    /// Décalage appliqué aux graines par « Générer d'autres circuits », afin
    /// d'obtenir des propositions différentes sans changer la distance.
    private var regenerationOffset = 0
    private var generationTask: Task<Void, Never>?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.targetDistance = dependencies.settings.lastRequestedDistance
    }

    // MARK: - Point de départ

    /// Point de départ effectif : celui choisi sur la carte, sinon la position.
    var startCoordinate: GeographicCoordinate? {
        customStart ?? dependencies.locationService.latestSample?.coordinate
    }

    var isStartAvailable: Bool { startCoordinate != nil }

    func useCurrentLocationAsStart() {
        customStart = nil
        dependencies.locationService.requestOneShotLocation()
    }

    func setCustomStart(_ coordinate: GeographicCoordinate) {
        guard coordinate.isValid else { return }
        customStart = coordinate
        isPickingStart = false
    }

    // MARK: - Génération

    func generate() {
        guard let origin = startCoordinate else {
            error = dependencies.locationService.authorization.isUsable
                ? .locationUnavailable
                : .locationPermissionDenied
            return
        }

        dependencies.settings.lastRequestedDistance = targetDistance
        error = nil
        candidates = []
        selectedCandidate = nil
        stage = .generating
        progress = LoopGenerationProgress(completed: 0, total: 1, bestDistance: nil)

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await run(origin: origin)
        }
    }

    /// Relance une génération en cherchant des circuits différents.
    func regenerate() {
        regenerationOffset += 1
        generate()
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        stage = .idle
        progress = nil
    }

    private func run(origin: GeographicCoordinate) async {
        var preferences = dependencies.settings.routingPreferences
        // Le décalage de régénération est reporté sur la direction préférée
        // lorsqu'elle est indifférente : c'est le levier le plus simple pour
        // obtenir des circuits franchement différents.
        if regenerationOffset > 0, preferences.preferredDirection == .any {
            let directions = PreferredDirection.allCases.filter { $0 != .any }
            preferences.preferredDirection = directions[
                (regenerationOffset - 1) % directions.count
            ]
        }

        do {
            let result = try await dependencies.loopGenerator.generateLoops(
                from: origin,
                targetDistance: targetDistance,
                preferences: preferences,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.progress = progress }
                }
            )
            guard !Task.isCancelled else { return }

            candidates = result.candidates
            selectedCandidate = result.recommended
            stage = result.candidates.isEmpty ? .idle : .comparing
            progress = nil

            if result.candidates.isEmpty { error = .noRouteFound }
            AppLog.routing.info(
                "Génération terminée : \(result.candidates.count) propositions retenues sur \(result.evaluatedCount) calculées"
            )
        } catch is CancellationError {
            stage = .idle
            progress = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? VeloError) ?? .routingEngineUnavailable(statusCode: nil)
            stage = .idle
            progress = nil
        }
    }

    // MARK: - Sélection

    func select(_ candidate: RouteCandidate) {
        selectedCandidate = candidate
    }

    func confirmSelection() {
        guard selectedCandidate != nil else { return }
        stage = .previewing
    }

    func backToComparison() {
        stage = candidates.isEmpty ? .idle : .comparing
    }

    func reset() {
        generationTask?.cancel()
        stage = .idle
        candidates = []
        selectedCandidate = nil
        progress = nil
        error = nil
    }

    func dismissError() { error = nil }

    /// Charge un circuit venu d'ailleurs — historique ou fichier GPX — pour le
    /// refaire.
    func load(route: CyclingRoute) {
        candidates = []
        selectedCandidate = RouteCandidate(route: route, seed: 0, warnings: [], score: 0)
        stage = .previewing
    }
}
