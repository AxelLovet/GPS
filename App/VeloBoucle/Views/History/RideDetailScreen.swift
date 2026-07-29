import SwiftUI
import SwiftData
import MapKit
import VeloCore

/// Fiche détaillée d'une sortie enregistrée.
struct RideDetailScreen: View {
    let stored: StoredRide
    var onRepeat: (CyclingRoute) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var exportedFile: ExportedGPXFile?

    /// Modèle métier décodé une seule fois.
    ///
    /// `toRecordedRide()` désérialise plusieurs milliers de points ; le laisser
    /// dans une propriété calculée le referait à chaque accès, plusieurs fois
    /// par rendu.
    @State private var ride: RecordedRide

    init(stored: StoredRide, onRepeat: @escaping (CyclingRoute) -> Void) {
        self.stored = stored
        self.onRepeat = onRepeat
        _ride = State(initialValue: stored.toRecordedRide())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let coordinates = ride.track.map(\.coordinate)
                if coordinates.count > 1 {
                    RouteMapView(
                        route: ride.plannedRoute,
                        track: coordinates,
                        showsUserLocation: false,
                        cameraPosition: $cameraPosition
                    )
                    .frame(height: 260)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: VeloMetrics.mapCornerRadius, style: .continuous
                        )
                    )
                    .onAppear { cameraPosition = .fitting(coordinates: coordinates) }
                }

                dateBlock
                RideStatisticsGrid(ride: ride)
                actions
            }
            .padding(16)
        }
        .navigationTitle(stored.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(Strings.Common.rename, systemImage: "pencil") {
                        newName = stored.name
                        isRenaming = true
                    }
                    Button(Strings.Common.delete, systemImage: "trash", role: .destructive) {
                        delete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(Strings.Common.rename, isPresented: $isRenaming) {
            TextField(Strings.Summary.nameField, text: $newName)
            Button(Strings.Common.validate) { rename() }
            Button(Strings.Common.cancel, role: .cancel) {}
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var dateBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            StatTile(
                title: Strings.Detail.date,
                value: stored.startedAt.formatted(date: .abbreviated, time: .omitted)
            )
            StatTile(
                title: Strings.Detail.startTime,
                value: stored.startedAt.formatted(date: .omitted, time: .shortened)
            )
            StatTile(
                title: Strings.Settings.profileSection,
                value: Strings.profileName(ride.profile)
            )
        }
        .veloCard()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let planned = ride.plannedRoute {
                Button(Strings.History.repeatRide) {
                    onRepeat(planned)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if ride.track.count > 1 {
                // Sans circuit prévu, la trace parcourue peut tout de même
                // servir d'itinéraire à refaire.
                Button(Strings.History.repeatRide) {
                    onRepeat(routeFromTrack)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button(Strings.Preview.exportGPX) { exportGPX() }
                .buttonStyle(PrimaryButtonStyle(isProminent: false))
        }
    }

    private var routeFromTrack: CyclingRoute {
        let coordinates = ride.track.map(\.coordinate)
        return CyclingRoute(
            coordinates: coordinates,
            distance: Geodesy.polylineLength(coordinates),
            duration: ride.statistics.movingTime,
            profile: ride.profile
        )
    }

    private func rename() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stored.name = trimmed
        ride.name = trimmed
        try? modelContext.save()
    }

    private func delete() {
        modelContext.delete(stored)
        try? modelContext.save()
        dismiss()
    }

    private func exportGPX() {
        do {
            let data = try dependencies.gpxService.export(ride: ride)
            exportedFile = try ExportedGPXFile(
                data: data,
                fileName: "\(stored.name.replacingOccurrences(of: "/", with: "-")).gpx"
            )
        } catch {
            AppLog.persistence.error("Export GPX impossible")
        }
    }
}
