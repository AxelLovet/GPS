import Foundation
import VeloCore

/// Rejoue un déplacement simulé le long d'un circuit.
///
/// Destiné au **mode démonstration** et au simulateur iOS, où aucun capteur GPS
/// réel n'est disponible. Il produit exactement le même type de relevés que
/// `LocationService` (`LocationSample`), de sorte que la navigation, la
/// détection de sortie de parcours, le recalcul et l'enregistrement s'exécutent
/// sans la moindre différence de code.
///
/// Ce fichier appartient au dossier `Demo/` : rien ici ne s'active sans que
/// l'utilisateur ait explicitement demandé le mode démonstration.
@MainActor
final class DemoRideSimulator {
    /// Accélération par rapport au temps réel.
    ///
    /// Une boucle de 20 km à 25 km/h dure 48 minutes ; à ×20 la démonstration
    /// se déroule en un peu plus de deux minutes, ce qui reste observable tout
    /// en restant supportable.
    private let timeScale: Double
    private let updateInterval: TimeInterval

    private var task: Task<Void, Never>?

    init(timeScale: Double = 20, updateInterval: TimeInterval = 1) {
        self.timeScale = timeScale
        self.updateInterval = updateInterval
    }

    var isRunning: Bool { task != nil && !(task?.isCancelled ?? true) }

    /// Démarre la simulation et transmet chaque relevé à `handler`.
    ///
    /// - Parameters:
    ///   - route: circuit à parcourir.
    ///   - withDetour: insère un écart volontaire d'environ 180 m au tiers du
    ///     parcours, pour éprouver la détection de sortie et le recalcul.
    ///   - handler: reçoit les relevés, dans l'ordre.
    func start(
        on route: CyclingRoute,
        withDetour: Bool,
        handler: @escaping @MainActor (LocationSample) -> Void
    ) {
        stop()

        let detour = withDetour
            ? TrackSimulator.DetourPlan(
                startDistance: route.distance / 3,
                length: min(1_000, route.distance / 8),
                lateralOffset: 180
            )
            : nil

        let simulator = TrackSimulator(
            route: route,
            speed: 6.9,
            updateInterval: updateInterval,
            horizontalAccuracy: 6,
            detour: detour
        )

        // Les relevés portent des horodatages réalistes — un par seconde de
        // temps simulé — pour que les statistiques de vitesse et de temps de
        // déplacement restent cohérentes malgré l'accélération de la lecture.
        let samples = simulator.samples(startingAt: Date())
        let delay = UInt64(updateInterval / timeScale * 1_000_000_000)

        task = Task { @MainActor in
            for sample in samples {
                guard !Task.isCancelled else { return }
                handler(sample)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
