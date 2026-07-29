import Foundation

/// Avancement d'une génération de circuits, destiné à l'écran de chargement.
public struct LoopGenerationProgress: Sendable, Hashable {
    /// Nombre d'itinéraires déjà calculés.
    public let completed: Int
    /// Nombre total d'itinéraires prévus.
    public let total: Int
    /// Meilleure distance obtenue jusqu'ici, en mètres.
    public let bestDistance: Double?

    public init(completed: Int, total: Int, bestDistance: Double?) {
        self.completed = completed
        self.total = total
        self.bestDistance = bestDistance
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }
}

/// Contrat de génération de boucles, pour pouvoir substituer un générateur de
/// démonstration en tests et dans le simulateur.
public protocol LoopGenerating: Sendable {
    func generateLoops(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        preferences: RoutingPreferences,
        onProgress: (@Sendable (LoopGenerationProgress) -> Void)?
    ) async throws -> LoopGenerationResult
}

extension LoopGenerating {
    public func generateLoops(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        preferences: RoutingPreferences
    ) async throws -> LoopGenerationResult {
        try await generateLoops(
            from: origin,
            targetDistance: targetDistance,
            preferences: preferences,
            onProgress: nil
        )
    }
}

/// Génère plusieurs circuits en boucle et retient les meilleurs.
///
/// Déroulé (cahier des charges §4) :
/// 1. plusieurs tentatives sont préparées, mêlant boucles natives (graines
///    différentes) et boucles polygonales orientées ;
/// 2. elles sont calculées en parallèle, avec une concurrence limitée pour
///    rester dans le quota du moteur ;
/// 3. les résultats hors contraintes sont écartés ;
/// 4. si la meilleure distance sort de la tolérance de ±5 %, une seconde passe
///    corrige la longueur demandée et relance les tentatives les plus proches ;
/// 5. les candidats sont classés, dédoublonnés et les trois meilleurs sont
///    renvoyés.
public struct LoopGenerationService: LoopGenerating {
    private let routingService: RoutingService
    /// Nombre de propositions renvoyées à l'utilisateur.
    private let proposalCount: Int
    /// Requêtes simultanées. Le quota gratuit d'ORS est de 40 requêtes par
    /// minute ; 3 en parallèle laisse une marge confortable tout en divisant le
    /// temps d'attente par trois.
    private let concurrency: Int

    public init(routingService: RoutingService, proposalCount: Int = 3, concurrency: Int = 3) {
        self.routingService = routingService
        self.proposalCount = max(1, proposalCount)
        self.concurrency = max(1, concurrency)
    }

    // MARK: - Tentatives

    private enum Strategy: Sendable, Hashable {
        /// Boucle native du moteur, pilotée par une graine.
        case native(seed: Int, points: Int)
        /// Boucle polygonale construite localement, orientée selon un cap.
        case polygon(bearing: Double, waypointCount: Int)
    }

    private struct Attempt: Sendable, Hashable {
        let strategy: Strategy
        /// Longueur demandée au moteur, qui peut différer de la cible après
        /// correction.
        let requestedLength: Double

        var seed: Int {
            switch strategy {
            case .native(let seed, _): return seed
            case .polygon(let bearing, _): return Int(bearing.rounded())
            }
        }
    }

    private func plan(
        targetDistance: Double,
        preferences: RoutingPreferences
    ) -> [Attempt] {
        let usesNative = routingService.supportsRoundTrips
        let hasDirectionPreference = preferences.preferredDirection.bearing != nil

        var attempts: [Attempt] = []

        if usesNative {
            // Les graines sont fixes et non aléatoires : à distance et point de
            // départ identiques, l'utilisateur retrouve les mêmes propositions,
            // ce qui rend l'application prévisible et les tests reproductibles.
            // « Générer d'autres circuits » décale simplement la série.
            let seeds = hasDirectionPreference ? [1, 7] : [1, 7, 13, 21, 34]
            // Plus la boucle est longue, plus il faut de points de passage pour
            // qu'elle ne dégénère pas en aller-retour.
            let points = targetDistance > 30_000 ? 6 : (targetDistance > 12_000 ? 5 : 4)
            attempts += seeds.map {
                Attempt(strategy: .native(seed: $0, points: points), requestedLength: targetDistance)
            }
        }

        let polygonCount = usesNative ? (hasDirectionPreference ? 4 : 2) : 6
        let bearings = WaypointLoopPlanner.candidateBearings(
            preferred: preferences.preferredDirection,
            count: polygonCount
        )
        let waypointCount = targetDistance > 25_000 ? 5 : 4
        attempts += bearings.map {
            Attempt(
                strategy: .polygon(bearing: $0, waypointCount: waypointCount),
                requestedLength: targetDistance
            )
        }

        return attempts
    }

    // MARK: - Génération

    public func generateLoops(
        from origin: GeographicCoordinate,
        targetDistance: Double,
        preferences: RoutingPreferences,
        onProgress: (@Sendable (LoopGenerationProgress) -> Void)?
    ) async throws -> LoopGenerationResult {
        guard origin.isValid else { throw VeloError.locationUnavailable }
        guard targetDistance >= 1_000 else {
            throw VeloError.loopDistanceUnreachable(requested: targetDistance, best: 1_000)
        }
        guard routingService.isConfigured else { throw VeloError.missingAPIKey }

        let scorer = RouteScorer(preferences: preferences)
        let firstPass = plan(targetDistance: targetDistance, preferences: preferences)

        let progressTracker = ProgressTracker(
            total: firstPass.count,
            onProgress: onProgress
        )

        var routes = try await run(
            attempts: firstPass,
            origin: origin,
            preferences: preferences,
            targetDistance: targetDistance,
            tracker: progressTracker
        )

        // Seconde passe : si rien n'est dans la tolérance, on corrige la longueur
        // demandée proportionnellement à l'erreur observée. `round_trip` traite
        // `length` comme un objectif approximatif, et cette correction rattrape
        // l'essentiel de l'écart en une itération.
        let bestDeviation = routes
            .compactMap { $0.route.distanceDeviationRatio.map(abs) }
            .min()

        if let bestDeviation, bestDeviation > RouteScorer.distanceTolerance {
            let corrections = corrective(
                attempts: firstPass,
                routes: routes,
                targetDistance: targetDistance
            )
            if !corrections.isEmpty {
                await progressTracker.extendTotal(by: corrections.count)
                let extra = try await run(
                    attempts: corrections,
                    origin: origin,
                    preferences: preferences,
                    targetDistance: targetDistance,
                    tracker: progressTracker
                )
                routes.append(contentsOf: extra)
            }
        }

        guard !routes.isEmpty else { throw VeloError.noRouteFound }

        let preferredBearing = preferences.preferredDirection.bearing
        var accepted: [RouteCandidate] = []
        var rejectedCount = 0

        for result in routes {
            guard scorer.isAcceptable(result.route) else {
                rejectedCount += 1
                continue
            }
            let penalty = directionPenalty(for: result.route, preferredBearing: preferredBearing)
            accepted.append(
                RouteCandidate(
                    route: result.route,
                    seed: result.seed,
                    warnings: scorer.warnings(for: result.route),
                    score: scorer.score(result.route) + penalty
                )
            )
        }

        guard !accepted.isEmpty else {
            // Tous les itinéraires calculés ont été écartés. On distingue les
            // deux causes possibles, car l'action à proposer n'est pas la même.
            let closest = routes.min {
                abs($0.route.distanceDeviationRatio ?? .infinity)
                    < abs($1.route.distanceDeviationRatio ?? .infinity)
            }
            if let closest,
               let deviation = closest.route.distanceDeviationRatio,
               abs(deviation) > 0.40 {
                throw VeloError.loopDistanceUnreachable(
                    requested: targetDistance,
                    best: closest.route.distance
                )
            }
            throw VeloError.allCandidatesRejected
        }

        return LoopGenerationResult(
            candidates: scorer.rank(accepted, limit: proposalCount),
            evaluatedCount: routes.count,
            rejectedCount: rejectedCount
        )
    }

    // MARK: - Exécution des tentatives

    private struct AttemptResult: Sendable {
        let route: CyclingRoute
        let seed: Int
    }

    /// Compteur d'avancement partagé entre les tâches parallèles.
    private actor ProgressTracker {
        private var completed = 0
        private var total: Int
        private var bestDistance: Double?
        private let onProgress: (@Sendable (LoopGenerationProgress) -> Void)?

        init(total: Int, onProgress: (@Sendable (LoopGenerationProgress) -> Void)?) {
            self.total = total
            self.onProgress = onProgress
            onProgress?(LoopGenerationProgress(completed: 0, total: total, bestDistance: nil))
        }

        func extendTotal(by amount: Int) {
            total += amount
            emit()
        }

        func recordCompletion(distance: Double?) {
            completed += 1
            if let distance { bestDistance = distance }
            emit()
        }

        private func emit() {
            onProgress?(
                LoopGenerationProgress(
                    completed: completed,
                    total: total,
                    bestDistance: bestDistance
                )
            )
        }
    }

    private func run(
        attempts: [Attempt],
        origin: GeographicCoordinate,
        preferences: RoutingPreferences,
        targetDistance: Double,
        tracker: ProgressTracker
    ) async throws -> [AttemptResult] {
        var results: [AttemptResult] = []
        var lastError: Error?

        // Concurrence bornée : on lance au plus `concurrency` requêtes, puis on
        // en relance une à chaque fois qu'une se termine.
        try await withThrowingTaskGroup(of: Result<AttemptResult, Error>.self) { group in
            var iterator = attempts.makeIterator()
            var running = 0

            func addNext() -> Bool {
                guard let attempt = iterator.next() else { return false }
                group.addTask {
                    do {
                        let route = try await execute(
                            attempt,
                            origin: origin,
                            preferences: preferences,
                            targetDistance: targetDistance
                        )
                        return .success(AttemptResult(route: route, seed: attempt.seed))
                    } catch {
                        return .failure(error)
                    }
                }
                running += 1
                return true
            }

            while running < concurrency, addNext() {}

            while let outcome = try await group.next() {
                running -= 1
                switch outcome {
                case .success(let result):
                    results.append(result)
                    await tracker.recordCompletion(distance: result.route.distance)
                case .failure(let error):
                    lastError = error
                    await tracker.recordCompletion(distance: nil)
                }
                try Task.checkCancellation()
                _ = addNext()
            }
        }

        // Une erreur ne fait échouer la génération que si *aucune* tentative
        // n'a abouti : perdre deux candidats sur huit n'a rien de bloquant.
        if results.isEmpty, let lastError {
            throw lastError
        }
        return results
    }

    private func execute(
        _ attempt: Attempt,
        origin: GeographicCoordinate,
        preferences: RoutingPreferences,
        targetDistance: Double
    ) async throws -> CyclingRoute {
        switch attempt.strategy {
        case .native(let seed, let points):
            let route = try await routingService.roundTrip(
                from: origin,
                targetDistance: attempt.requestedLength,
                seed: seed,
                points: points,
                preferences: preferences
            )
            return retarget(route, to: targetDistance)

        case .polygon(let bearing, let waypointCount):
            let waypoints = WaypointLoopPlanner.waypoints(
                around: origin,
                targetDistance: attempt.requestedLength,
                bearing: bearing,
                waypointCount: waypointCount
            )
            let route = try await routingService.route(
                through: waypoints,
                preferences: preferences
            )
            return retarget(route, to: targetDistance)
        }
    }

    /// Réattache la distance **demandée par l'utilisateur** au circuit obtenu.
    ///
    /// Nécessaire parce qu'une tentative corrective interroge le moteur avec une
    /// longueur ajustée : sans cela, l'écart affiché serait calculé par rapport
    /// à la valeur corrigée et non à ce que l'utilisateur a demandé.
    private func retarget(_ route: CyclingRoute, to targetDistance: Double) -> CyclingRoute {
        CyclingRoute(
            id: route.id,
            coordinates: route.coordinates,
            distance: route.distance,
            duration: route.duration,
            ascent: route.ascent,
            descent: route.descent,
            instructions: route.instructions,
            segments: route.segments,
            profile: route.profile,
            requestedDistance: targetDistance
        )
    }

    /// Prépare une seconde passe avec une longueur corrigée.
    private func corrective(
        attempts: [Attempt],
        routes: [AttemptResult],
        targetDistance: Double
    ) -> [Attempt] {
        // On repart des deux tentatives les plus proches de la cible : ce sont
        // celles dont la forme convient déjà, il ne manque que l'échelle.
        let ranked = routes.sorted {
            abs($0.route.distance - targetDistance) < abs($1.route.distance - targetDistance)
        }
        var corrections: [Attempt] = []

        for result in ranked.prefix(2) {
            guard result.route.distance > 0 else { continue }
            guard let original = attempts.first(where: { $0.seed == result.seed }) else { continue }

            let ratio = targetDistance / result.route.distance
            // Une correction est bornée : au-delà, le moteur produirait une
            // boucle sans rapport avec celle qu'on cherche à ajuster.
            let bounded = min(max(ratio, 0.5), 2.0)
            let corrected = original.requestedLength * bounded

            // Inutile de relancer pour une correction insignifiante.
            guard abs(corrected - original.requestedLength) / original.requestedLength > 0.03 else {
                continue
            }
            corrections.append(
                Attempt(strategy: original.strategy, requestedLength: corrected)
            )
        }
        return corrections
    }

    /// Pénalité appliquée à un circuit qui ne va pas dans la direction voulue.
    ///
    /// La direction est mesurée sur le **centre de gravité du circuit** vu
    /// depuis le départ, et non sur le cap des premiers mètres. C'est ce que
    /// l'utilisateur veut dire quand il choisit « vers le nord » : que la boucle
    /// se déroule au nord, pas qu'il quitte sa rue en direction du nord — sur
    /// une boucle, le cap de départ est de toute façon tangent et dépend d'un
    /// sens de parcours arbitraire.
    ///
    /// La pénalité reste volontairement douce : une excellente boucle décalée de
    /// 60° vaut mieux qu'une mauvaise boucle pile dans l'axe.
    private func directionPenalty(
        for route: CyclingRoute,
        preferredBearing: Double?
    ) -> Double {
        guard let preferredBearing,
              let start = route.coordinates.first,
              let centroid = Geodesy.centroid(of: route.coordinates) else { return 0 }

        // Un circuit dont le centre de gravité coïncide avec le départ n'a pas
        // d'orientation exploitable ; le pénaliser n'aurait pas de sens.
        guard Geodesy.distance(from: start, to: centroid) > 100 else { return 0 }

        let actual = Geodesy.bearing(from: start, to: centroid)
        let delta = abs(Geodesy.bearingDelta(from: preferredBearing, to: actual))
        return delta / 180 * 45
    }
}
