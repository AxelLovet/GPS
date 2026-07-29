import SwiftUI
import SwiftData
import VeloCore

/// Onglets de l'application et coordination entre eux.
///
/// Les quatre onglets exigés par le cahier des charges (§10) : Parcours,
/// Sortie, Historique, Réglages. `RootView` porte les deux vues-modèles
/// partagées et gère les transitions qui les relient — démarrer une navigation
/// depuis un circuit, refaire un parcours de l'historique, reprendre une sortie
/// interrompue.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .planner
    @State private var planner: PlannerViewModel?
    @State private var ride: RideViewModel?

    enum Tab: Hashable {
        case planner, ride, history, settings
    }

    var body: some View {
        Group {
            if let planner, let ride {
                tabs(planner: planner, ride: ride)
            } else {
                // Les vues-modèles ont besoin du conteneur de dépendances, qui
                // n'est disponible qu'une fois l'environnement installé.
                ProgressView().task { makeViewModels() }
            }
        }
    }

    private func makeViewModels() {
        guard planner == nil else { return }
        planner = PlannerViewModel(dependencies: dependencies)
        let rideModel = RideViewModel(dependencies: dependencies)
        ride = rideModel
        Task { await rideModel.lookForInterruptedRide() }
    }

    private func tabs(planner: PlannerViewModel, ride: RideViewModel) -> some View {
        TabView(selection: $selectedTab) {
            PlannerScreen(model: planner) { route in
                ride.start(route: route)
                planner.reset()
                selectedTab = .ride
            }
            .tabItem { Label(Strings.Tabs.planner, systemImage: "map") }
            .tag(Tab.planner)

            RideNavigationScreen(model: ride) { selectedTab = .planner }
                .tabItem { Label(Strings.Tabs.ride, systemImage: "bicycle") }
                .tag(Tab.ride)
                .badge(ride.isActive ? "•" : nil)

            HistoryScreen { route in
                planner.load(route: route)
                selectedTab = .planner
            }
            .tabItem { Label(Strings.Tabs.history, systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            SettingsScreen(settings: dependencies.settings)
                .tabItem { Label(Strings.Tabs.settings, systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .sheet(item: finishedRideBinding(ride)) { finished in
            RideSummaryScreen(
                ride: finished,
                onSave: { save($0, ride: ride) },
                onDiscard: { ride.clearFinishedRide() }
            )
        }
        .alert(
            Strings.Recovery.title,
            isPresented: recoveryBinding(ride)
        ) {
            Button(Strings.Recovery.resume) {
                ride.resumeRecoveredRide()
                selectedTab = .ride
            }
            Button(Strings.Recovery.saveOnly) {
                _ = ride.saveRecoveredRideWithoutResuming()
            }
            Button(Strings.Recovery.discard, role: .destructive) {
                ride.discardRecoveredRide()
            }
        } message: {
            Text(Strings.Recovery.message)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase, ride: ride)
        }
    }

    // MARK: - Transitions

    private func save(_ finished: RecordedRide, ride: RideViewModel) {
        let service = PersistenceService(context: modelContext)
        Task {
            try? await service.save(finished)
            ride.clearFinishedRide()
        }
    }

    /// Réduit la consommation quand l'application passe en arrière-plan.
    ///
    /// Le suivi n'est **pas** interrompu : une sortie doit continuer à être
    /// enregistrée écran verrouillé (§8). En revanche, si aucune sortie n'est en
    /// cours, plus rien ne justifie de solliciter le GPS.
    private func handleScenePhase(_ phase: ScenePhase, ride: RideViewModel) {
        switch phase {
        case .background where !ride.isActive:
            dependencies.locationService.stopUpdating()
        case .active where !ride.isActive && selectedTab == .planner:
            dependencies.locationService.startUpdating(mode: .browsing)
        default:
            break
        }
    }

    private func finishedRideBinding(_ ride: RideViewModel) -> Binding<RecordedRide?> {
        Binding(
            get: { ride.finishedRide },
            set: { if $0 == nil { ride.clearFinishedRide() } }
        )
    }

    private func recoveryBinding(_ ride: RideViewModel) -> Binding<Bool> {
        Binding(
            get: { ride.recoverableSession != nil },
            set: { if !$0 { ride.discardRecoveredRide() } }
        )
    }
}
