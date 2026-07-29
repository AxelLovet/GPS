import SwiftUI
import MapKit
import SwiftData
import VeloCore

/// Écran de fin de sortie : résumé, carte, enregistrement, export.
struct RideSummaryScreen: View {
    let ride: RecordedRide
    var onSave: (RecordedRide) -> Void
    var onDiscard: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var exportedFile: ExportedGPXFile?

    init(
        ride: RecordedRide,
        onSave: @escaping (RecordedRide) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.ride = ride
        self.onSave = onSave
        self.onDiscard = onDiscard
        _name = State(initialValue: ride.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if trackCoordinates.count > 1 {
                        RouteMapView(
                            route: ride.plannedRoute,
                            track: trackCoordinates,
                            showsUserLocation: false,
                            cameraPosition: $cameraPosition
                        )
                        .frame(height: 240)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: VeloMetrics.mapCornerRadius, style: .continuous
                            )
                        )
                        .allowsHitTesting(false)
                    }

                    TextField(Strings.Summary.nameField, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)

                    RideStatisticsGrid(ride: ride)

                    if !ride.deviations.isEmpty {
                        Label(
                            Strings.Summary.deviationCount(ride.deviations.count),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .veloCard()
                    }

                    actions
                }
                .padding(16)
            }
            .navigationTitle(Strings.Summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                cameraPosition = .fitting(coordinates: trackCoordinates)
            }
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
            }
        }
    }

    private var trackCoordinates: [GeographicCoordinate] {
        ride.track.map(\.coordinate)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(Strings.Summary.save) {
                var named = ride
                named.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ride.name
                    : name
                onSave(named)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(Strings.Preview.exportGPX) { exportGPX() }
                .buttonStyle(PrimaryButtonStyle(isProminent: false))

            Button(Strings.Summary.discard, role: .destructive) {
                onDiscard()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    private func exportGPX() {
        do {
            let data = try dependencies.gpxService.export(ride: ride)
            exportedFile = try ExportedGPXFile(
                data: data,
                fileName: "\(ride.name.replacingOccurrences(of: "/", with: "-")).gpx"
            )
        } catch {
            AppLog.persistence.error("Export GPX impossible")
        }
    }
}

/// Grille des statistiques d'une sortie.
struct RideStatisticsGrid: View {
    let ride: RecordedRide

    private var statistics: RideStatistics { ride.statistics }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                StatTile(
                    title: Strings.Detail.distance,
                    value: InstructionPhrasing.displayDistance(statistics.distance),
                    isProminent: true
                )
                StatTile(
                    title: Strings.Summary.movingTime,
                    value: InstructionPhrasing.displayDuration(statistics.movingTime)
                )
            }
            HStack(alignment: .top, spacing: 12) {
                StatTile(
                    title: Strings.Ride.averageSpeed,
                    value: InstructionPhrasing.displaySpeed(
                        metersPerSecond: statistics.averageMovingSpeed
                    ),
                    unit: "km/h"
                )
                StatTile(
                    title: Strings.Summary.maxSpeed,
                    value: InstructionPhrasing.displaySpeed(
                        metersPerSecond: statistics.maximumSpeed
                    ),
                    unit: "km/h"
                )
                StatTile(
                    title: Strings.Ride.elapsed,
                    value: InstructionPhrasing.displayDuration(statistics.elapsedTime)
                )
            }
            HStack(alignment: .top, spacing: 12) {
                StatTile(
                    title: Strings.Summary.ascent,
                    value: "\(Int(statistics.ascent.rounded()))",
                    unit: "m"
                )
                StatTile(
                    title: Strings.Summary.descent,
                    value: "\(Int(statistics.descent.rounded()))",
                    unit: "m"
                )
                StatTile(
                    title: Strings.Summary.calories,
                    value: "\(Int(ride.estimatedCalories.rounded()))",
                    unit: "kcal"
                )
            }
            // Les calories sont un ordre de grandeur, jamais une mesure : le
            // cahier des charges impose de le dire explicitement.
            Text(Strings.Summary.caloriesDisclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .veloCard()
    }
}
