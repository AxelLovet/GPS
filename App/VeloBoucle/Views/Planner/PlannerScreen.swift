import SwiftUI
import MapKit
import UIKit
import VeloCore

/// Écran d'accueil : carte, distance, création de la boucle.
///
/// Le parcours principal tient en trois gestes — choisir une distance, appuyer
/// sur « Créer une boucle », sélectionner un circuit — conformément au §10 du
/// cahier des charges.
struct PlannerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var model: PlannerViewModel
    /// Démarre la navigation avec le circuit choisi.
    var onStartNavigation: (CyclingRoute) -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnUser = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                map
                overlay
            }
            .navigationTitle(Strings.Planner.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await prepareLocation() }
            .onChange(of: dependencies.locationService.latestSample?.coordinate) { _, coordinate in
                centerOnUserIfNeeded(coordinate)
            }
            .sheet(isPresented: isGenerating) {
                GenerationProgressSheet(
                    progress: model.progress,
                    onCancel: { model.cancelGeneration() }
                )
                .presentationDetents([.height(280)])
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: isComparing) {
                RouteComparisonSheet(model: model)
            }
            .navigationDestination(isPresented: isPreviewing) {
                if let candidate = model.selectedCandidate {
                    RoutePreviewScreen(
                        candidate: candidate,
                        onStart: { onStartNavigation(candidate.route) },
                        onRegenerate: { model.regenerate() }
                    )
                }
            }
        }
    }

    // MARK: - Carte

    private var map: some View {
        RouteMapView(
            route: model.selectedCandidate?.route,
            alternates: alternateRoutes,
            currentPosition: dependencies.locationService.latestSample?.coordinate,
            customStart: model.customStart,
            cameraPosition: $cameraPosition,
            onTapCoordinate: model.isPickingStart ? { model.setCustomStart($0) } : nil,
            onSelectAlternate: { route in
                if let candidate = model.candidates.first(where: { $0.route.id == route.id }) {
                    model.select(candidate)
                }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    private var alternateRoutes: [CyclingRoute] {
        model.candidates
            .filter { $0.id != model.selectedCandidate?.id }
            .map(\.route)
    }

    // MARK: - Superposition

    private var overlay: some View {
        VStack(spacing: 12) {
            HStack {
                LocationStatusBadge(
                    authorization: dependencies.locationService.authorization,
                    hasReducedAccuracy: dependencies.locationService.hasReducedAccuracy,
                    onOpenSettings: openSystemSettings
                )
                Spacer()
                if dependencies.isDemoModeActive { DemoModeBanner() }
            }
            .padding(.horizontal)

            Spacer()

            if model.isPickingStart {
                Text(Strings.Planner.pickStartHint)
                    .font(.subheadline)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            if let error = model.error {
                ErrorBanner(
                    error: error,
                    onAction: handle(action:),
                    onDismiss: { model.dismissError() }
                )
                .padding(.horizontal)
            }

            controls
        }
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            DistanceSelector(distance: $model.targetDistance)

            Button(Strings.Planner.generate) { model.generate() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.isStartAvailable)
                .accessibilityHint(
                    model.isStartAvailable ? "" : Strings.Location.whyMessage
                )
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button(Strings.Planner.useCurrentLocation, systemImage: "location.fill") {
                    model.useCurrentLocationAsStart()
                    hasCenteredOnUser = false
                }
                Button(Strings.Planner.chooseStart, systemImage: "mappin.and.ellipse") {
                    model.isPickingStart = true
                }
            } label: {
                Label(Strings.Planner.chooseStart, systemImage: "flag.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                recenter()
            } label: {
                Label(Strings.Planner.recenter, systemImage: "location.viewfinder")
            }
        }
    }

    // MARK: - Actions

    private func prepareLocation() async {
        dependencies.locationService.requestWhenInUseAuthorization()
        dependencies.locationService.startUpdating(mode: .browsing)
    }

    private func centerOnUserIfNeeded(_ coordinate: GeographicCoordinate?) {
        // On ne recadre automatiquement qu'à la première position reçue : après
        // quoi la carte appartient à l'utilisateur, et la déplacer sous ses
        // doigts serait pénible.
        guard !hasCenteredOnUser, let coordinate else { return }
        hasCenteredOnUser = true
        withAnimation { cameraPosition = .northUp(at: coordinate, distance: 3_000) }
    }

    private func recenter() {
        if let route = model.selectedCandidate?.route {
            withAnimation { cameraPosition = .fitting(coordinates: route.coordinates) }
        } else if let coordinate = model.startCoordinate {
            withAnimation { cameraPosition = .northUp(at: coordinate, distance: 3_000) }
        }
    }

    private func handle(action: RecoveryAction) {
        switch action {
        case .retry:
            model.generate()
        case .changeStartingPoint:
            model.isPickingStart = true
            model.dismissError()
        case .changeDistance, .openSettings:
            model.dismissError()
        case .openAppSettings, .configureAPIKey:
            openSystemSettings()
        case .enableDemoMode:
            dependencies.setDemoMode(true)
            model.dismissError()
        case .useSavedRoute, .none:
            model.dismissError()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Liaisons d'étape

    private var isGenerating: Binding<Bool> {
        Binding(get: { model.stage == .generating }, set: { if !$0 { model.cancelGeneration() } })
    }

    private var isComparing: Binding<Bool> {
        Binding(get: { model.stage == .comparing }, set: { if !$0 { model.reset() } })
    }

    private var isPreviewing: Binding<Bool> {
        Binding(
            get: { model.stage == .previewing },
            set: { if !$0 { model.backToComparison() } }
        )
    }
}

/// Écran de chargement pendant la génération.
struct GenerationProgressSheet: View {
    let progress: LoopGenerationProgress?
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress?.fraction ?? 0)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            VStack(spacing: 8) {
                Text(Strings.Generation.title).font(.headline)
                Text(Strings.Generation.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let progress {
                    Text(Strings.Generation.progress(progress.completed, progress.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button(Strings.Generation.cancel, role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}
