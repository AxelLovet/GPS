import SwiftUI
import MapKit
import VeloCore

/// Écran de navigation, conçu pour être lu sur un guidon.
///
/// Contraintes qui gouvernent cette mise en page (§6) : la consigne et sa flèche
/// occupent le haut de l'écran et sont visibles d'un coup d'œil ; les chiffres
/// utiles sont en gros et monospacés pour ne pas sautiller ; les seules actions
/// disponibles en roulant sont Pause, Terminer, Recentrer et le changement
/// d'orientation, tous avec de très grandes cibles.
struct RideNavigationScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var model: RideViewModel
    /// Ouvre l'onglet Parcours quand aucune sortie n'est en cours.
    var onRequestPlanner: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isHeadingUp = true
    @State private var followsUser = true
    @State private var isConfirmingFinish = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isActive {
                    activeRide
                } else {
                    idleState
                }
            }
            .navigationTitle(Strings.Tabs.ride)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(model.isActive ? .hidden : .visible, for: .navigationBar)
        }
        .alert(Strings.Ride.finishConfirmTitle, isPresented: $isConfirmingFinish) {
            Button(Strings.Ride.finish, role: .destructive) { model.finish() }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Ride.finishConfirmMessage)
        }
        .alert(
            Strings.Ride.offRouteTitle,
            isPresented: Binding(
                get: { model.pendingRecalculation != nil },
                set: { if !$0 { model.declinePendingRecalculation() } }
            )
        ) {
            Button(Strings.Ride.recalculate) { model.acceptPendingRecalculation() }
            Button(Strings.Ride.keepGoing, role: .cancel) { model.declinePendingRecalculation() }
        } message: {
            Text(Strings.Ride.offRouteMessage)
        }
    }

    // MARK: - Sortie en cours

    private var activeRide: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()

            VStack(spacing: 0) {
                if model.hasRoute {
                    instructionBanner
                }
                if model.navigationState.isOffRoute {
                    offRouteBanner
                }
                Spacer()
                if dependencies.isDemoModeActive { demoControls }
                statisticsPanel
                controls
            }
            .padding(.bottom, 6)
        }
        .onChange(of: model.currentCoordinate) { _, coordinate in
            updateCamera(for: coordinate)
        }
        .onChange(of: isHeadingUp) { _, _ in
            updateCamera(for: model.currentCoordinate)
        }
    }

    private var map: some View {
        RouteMapView(
            route: model.route,
            track: model.track,
            currentPosition: model.currentCoordinate,
            currentCourse: model.navigationState.course,
            cameraPosition: $cameraPosition
        )
    }

    /// Grande consigne : flèche, texte, distance à la manœuvre.
    private var instructionBanner: some View {
        HStack(spacing: 16) {
            ManeuverArrow(
                maneuver: model.navigationState.currentInstruction?.maneuver ?? .straight
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(InstructionPhrasing.displayDistance(model.navigationState.distanceToManeuver))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(instructionText)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let roadName = model.navigationState.nextInstruction?.roadName {
                    Text(Strings.Ride.thenOn(roadName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.navigationState.instructionText)
    }

    private var instructionText: String {
        let text = model.navigationState.instructionText
        return text.isEmpty ? InstructionPhrasing.maneuverText(.straight) : text
    }

    private var offRouteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.Ride.offRouteTitle).font(.subheadline.weight(.bold))
                if let distance = model.navigationState.deviationDistance {
                    Text(Strings.Ride.offRouteDistance(distance)).font(.caption)
                }
            }
            Spacer(minLength: 0)
            if model.isRecalculating {
                ProgressView()
            } else if dependencies.settings.recalculationPolicy != .never {
                Button(Strings.Ride.recalculate) {
                    if let rejoin = rejoinPoint { model.recalculate(towards: rejoin) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.veloWarning.opacity(0.95))
        .foregroundStyle(.white)
    }

    private var rejoinPoint: GeographicCoordinate? {
        guard let route = model.route, let position = model.currentCoordinate else { return nil }
        return RejoinPointSelector.rejoinPoint(
            on: route, from: position, lastMatch: model.navigationState.match
        )?.coordinate
    }

    /// Commandes de démonstration, visibles uniquement dans ce mode.
    ///
    /// Elles permettent d'observer la navigation complète dans le simulateur
    /// iOS : progression, consignes, sortie de parcours et recalcul.
    private var demoControls: some View {
        HStack(spacing: 8) {
            DemoModeBanner()
            Spacer(minLength: 0)
            if model.isSimulating {
                Button(Strings.Demo.stopSimulation) { model.stopSimulation() }
                    .buttonStyle(.bordered)
            } else {
                Button(Strings.Demo.simulateRide) { model.startSimulation(withDetour: false) }
                    .buttonStyle(.bordered)
                Button(Strings.Demo.simulateDetour) { model.startSimulation(withDetour: true) }
                    .buttonStyle(.bordered)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// Chiffres essentiels, toujours à la même place.
    private var statisticsPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StatTile(
                    title: Strings.Ride.speed,
                    value: InstructionPhrasing.displaySpeed(metersPerSecond: model.currentSpeed),
                    unit: "km/h",
                    isProminent: true
                )
                VStack(spacing: 10) {
                    StatTile(
                        title: Strings.Ride.distanceCovered,
                        value: InstructionPhrasing.displayDistance(model.statistics.distance)
                    )
                    StatTile(
                        title: Strings.Ride.averageSpeed,
                        value: InstructionPhrasing.displaySpeed(
                            metersPerSecond: model.statistics.averageMovingSpeed
                        ),
                        unit: "km/h"
                    )
                }
            }

            if model.hasRoute {
                HStack(alignment: .top, spacing: 12) {
                    StatTile(
                        title: Strings.Ride.remainingDistance,
                        value: InstructionPhrasing.displayDistance(
                            model.navigationState.remainingDistance
                        )
                    )
                    StatTile(
                        title: Strings.Ride.arrivalTime,
                        value: arrivalText
                    )
                    StatTile(
                        title: Strings.Ride.elapsed,
                        value: InstructionPhrasing.displayDuration(model.statistics.elapsedTime)
                    )
                }
            } else {
                StatTile(
                    title: Strings.Ride.elapsed,
                    value: InstructionPhrasing.displayDuration(model.statistics.elapsedTime)
                )
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var arrivalText: String {
        guard let arrival = model.navigationState.estimatedArrival else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: arrival)
    }

    /// Quatre actions maximum, toutes atteignables sans regarder longtemps.
    private var controls: some View {
        HStack(spacing: 10) {
            if model.rideState == .running {
                controlButton(Strings.Ride.pause, systemImage: "pause.fill") { model.pause() }
            } else {
                controlButton(Strings.Ride.resume, systemImage: "play.fill") { model.resume() }
            }

            controlButton(
                followsUser ? Strings.Ride.showWholeRoute : Strings.Ride.recenter,
                systemImage: followsUser ? "map" : "location.fill"
            ) {
                followsUser.toggle()
                followsUser ? updateCamera(for: model.currentCoordinate) : showWholeRoute()
            }

            controlButton(
                isHeadingUp ? Strings.Ride.northUp : Strings.Ride.headingUp,
                systemImage: isHeadingUp ? "location.north.line" : "location.north.fill"
            ) {
                isHeadingUp.toggle()
            }

            controlButton(Strings.Ride.finish, systemImage: "stop.fill", role: .destructive) {
                isConfirmingFinish = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : .accentColor)
        .accessibilityLabel(title)
    }

    // MARK: - Caméra

    private func updateCamera(for coordinate: GeographicCoordinate?) {
        guard followsUser, let coordinate else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            if isHeadingUp {
                cameraPosition = .navigating(
                    at: coordinate,
                    heading: model.navigationState.course
                        ?? dependencies.locationService.heading
                        ?? 0
                )
            } else {
                cameraPosition = .northUp(at: coordinate)
            }
        }
    }

    private func showWholeRoute() {
        let coordinates = model.route?.coordinates ?? model.track
        guard !coordinates.isEmpty else { return }
        withAnimation { cameraPosition = .fitting(coordinates: coordinates) }
    }

    // MARK: - Aucune sortie

    private var idleState: some View {
        ContentUnavailableView {
            Label(Strings.Ride.noRideTitle, systemImage: "bicycle")
        } description: {
            Text(Strings.Ride.noRideMessage)
        } actions: {
            VStack(spacing: 12) {
                Button(Strings.Planner.title, action: onRequestPlanner)
                    .buttonStyle(.borderedProminent)
                Button(Strings.Ride.freeRide) { model.start(route: nil) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
