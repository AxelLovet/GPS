import Foundation
import Observation
import VeloCore

/// Conteneur d'injection de dépendances.
///
/// Rassemble tous les services de l'application derrière leurs protocoles. Les
/// vues et les vues-modèles ne construisent jamais un service elles-mêmes :
/// elles le reçoivent d'ici. C'est ce qui rend le mode démonstration possible
/// sans code conditionnel disséminé partout, et ce qui permettrait de changer de
/// moteur de routage en modifiant un seul fichier.
@Observable
@MainActor
final class AppDependencies {
    private(set) var routingService: RoutingService
    private(set) var loopGenerator: LoopGenerating
    let locationService: LocationService
    let speechService: SpeechInstructionServicing
    let hapticService: HapticFeedbackProviding
    let gpxService: GPXServicing
    let snapshotStore: RideSnapshotStoring
    let settings: AppSettings

    /// Vrai lorsque les circuits proviennent du générateur de démonstration.
    private(set) var isDemoModeActive: Bool

    init(
        routingService: RoutingService,
        locationService: LocationService,
        speechService: SpeechInstructionServicing,
        hapticService: HapticFeedbackProviding,
        gpxService: GPXServicing,
        snapshotStore: RideSnapshotStoring,
        settings: AppSettings,
        isDemoModeActive: Bool
    ) {
        self.routingService = routingService
        self.loopGenerator = LoopGenerationService(routingService: routingService)
        self.locationService = locationService
        self.speechService = speechService
        self.hapticService = hapticService
        self.gpxService = gpxService
        self.snapshotStore = snapshotStore
        self.settings = settings
        self.isDemoModeActive = isDemoModeActive
    }

    /// Construit les dépendances réelles de l'application.
    static func live() -> AppDependencies {
        UITestingSupport.resetPreferencesIfNeeded()
        let settings = AppSettings()
        let apiKey = SecretsProvider.openRouteServiceAPIKey()

        // Le mode démonstration s'active soit par choix explicite dans les
        // Réglages, soit automatiquement lorsqu'aucune clé n'est configurée —
        // sinon l'application serait inutilisable au premier lancement, ce qui
        // est exactement ce qu'il faut éviter pour un débutant. Les tests
        // d'interface l'imposent également, pour ne jamais toucher au réseau.
        let useDemo = settings.demoModeEnabled || apiKey == nil || UITestingSupport.isActive

        let snapshotStore: RideSnapshotStoring
        do {
            snapshotStore = FileRideSnapshotStore(fileURL: try FileRideSnapshotStore.defaultURL())
        } catch {
            AppLog.persistence.error("Instantané de sortie indisponible, reprise désactivée")
            snapshotStore = NoOpRideSnapshotStore()
        }

        return AppDependencies(
            routingService: useDemo
                ? DemoRoutingService()
                : OpenRouteServiceClient(apiKey: apiKey),
            locationService: LocationService(),
            speechService: SpeechInstructionService(),
            hapticService: HapticService(),
            gpxService: GPXService(),
            snapshotStore: snapshotStore,
            settings: settings,
            isDemoModeActive: useDemo
        )
    }

    /// Bascule entre moteur réel et moteur de démonstration.
    ///
    /// Appelé depuis les Réglages. Le générateur de boucles est reconstruit pour
    /// qu'aucune requête ne parte encore vers l'ancien moteur.
    func setDemoMode(_ enabled: Bool) {
        let apiKey = SecretsProvider.openRouteServiceAPIKey()
        let effective = enabled || apiKey == nil

        routingService = effective
            ? DemoRoutingService()
            : OpenRouteServiceClient(apiKey: apiKey)
        loopGenerator = LoopGenerationService(routingService: routingService)
        isDemoModeActive = effective
        settings.demoModeEnabled = enabled
    }

    /// Vrai si une clé API est configurée, indépendamment du mode actif.
    var hasAPIKey: Bool { SecretsProvider.openRouteServiceAPIKey() != nil }
}

/// Instantané inopérant, utilisé lorsque le disque n'est pas accessible.
///
/// Perdre la possibilité de reprendre une sortie interrompue est regrettable ;
/// empêcher l'application de démarrer le serait bien davantage.
struct NoOpRideSnapshotStore: RideSnapshotStoring {
    func write(_ session: RideSession) async throws {}
    func read() async throws -> RideSession? { nil }
    func clear() async throws {}
}
