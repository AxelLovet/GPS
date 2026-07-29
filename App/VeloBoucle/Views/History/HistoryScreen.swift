import SwiftUI
import SwiftData
import MapKit
import UniformTypeIdentifiers
import VeloCore

/// Historique des sorties enregistrées.
struct HistoryScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredRide.startedAt, order: .reverse) private var rides: [StoredRide]

    /// Recharge un circuit dans le planificateur pour le refaire.
    var onRepeat: (CyclingRoute) -> Void

    @State private var searchText = ""
    @State private var rideToDelete: StoredRide?
    @State private var isImporting = false
    @State private var importError: VeloError?

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView {
                        Label(Strings.History.empty, systemImage: "list.bullet.rectangle")
                    } description: {
                        Text(Strings.History.emptyMessage)
                    }
                } else {
                    list
                }
            }
            .navigationTitle(Strings.History.title)
            .searchable(text: $searchText, prompt: Strings.History.search)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Label(Strings.History.importGPX, systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                importError?.title ?? "",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button(Strings.Common.close, role: .cancel) { importError = nil }
            } message: {
                Text(importError?.message ?? "")
            }
            .confirmationDialog(
                Strings.History.deleteConfirm,
                isPresented: Binding(
                    get: { rideToDelete != nil },
                    set: { if !$0 { rideToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(Strings.Common.delete, role: .destructive) { confirmDelete() }
                Button(Strings.Common.cancel, role: .cancel) { rideToDelete = nil }
            } message: {
                Text(Strings.History.deleteMessage)
            }
        }
    }

    private var filteredRides: [StoredRide] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rides }
        return rides.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var list: some View {
        List {
            ForEach(filteredRides) { stored in
                NavigationLink {
                    RideDetailScreen(stored: stored, onRepeat: onRepeat)
                } label: {
                    HistoryRow(stored: stored)
                }
                .swipeActions(edge: .trailing) {
                    Button(Strings.Common.delete, role: .destructive) {
                        rideToDelete = stored
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func confirmDelete() {
        guard let rideToDelete else { return }
        modelContext.delete(rideToDelete)
        try? modelContext.save()
        self.rideToDelete = nil
    }

    /// Importe un fichier GPX et le propose comme circuit à suivre.
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        // Un fichier choisi hors du bac à sable de l'application n'est
        // accessible qu'entre ces deux appels.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let document = try dependencies.gpxService.parse(data: try Data(contentsOf: url))
            let coordinates = document.routePoints.isEmpty
                ? document.trackPoints.map(\.coordinate)
                : document.routePoints
            guard coordinates.count >= 2 else {
                importError = .gpxParsingFailed(reason: "trace trop courte")
                return
            }

            let distance = Geodesy.polylineLength(coordinates)
            let profile = dependencies.settings.profile
            onRepeat(
                CyclingRoute(
                    coordinates: coordinates,
                    distance: distance,
                    duration: distance / (profile.indicativeSpeedKilometersPerHour * 1000 / 3600),
                    profile: profile
                )
            )
        } catch let error as VeloError {
            importError = error
        } catch {
            importError = .gpxParsingFailed(reason: "fichier illisible")
        }
    }
}

/// Ligne de l'historique : vignette, nom, chiffres clés.
struct HistoryRow: View {
    let stored: StoredRide

    var body: some View {
        HStack(spacing: 12) {
            TrackThumbnail(coordinates: stored.trackPreview())
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(stored.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(stored.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(
                        InstructionPhrasing.displayDistance(stored.distance),
                        systemImage: "arrow.left.and.right"
                    )
                    Label(
                        InstructionPhrasing.displayDuration(stored.movingTime),
                        systemImage: "clock"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Vignette dessinant le tracé d'une sortie sans charger de carte.
///
/// Instancier une vraie carte MapKit par ligne de liste serait très coûteux ;
/// un simple chemin normalisé suffit à reconnaître la forme d'un parcours.
struct TrackThumbnail: View {
    let coordinates: [GeographicCoordinate]

    var body: some View {
        GeometryReader { geometry in
            let path = normalisedPath(in: geometry.size)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                if !coordinates.isEmpty {
                    path.stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    Image(systemName: "map")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalisedPath(in size: CGSize) -> Path {
        var path = Path()
        guard coordinates.count > 1 else { return path }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max()
        else { return path }

        let inset: CGFloat = 6
        // Un degré de longitude est plus court qu'un degré de latitude, d'un
        // facteur cos(latitude). Sans cette correction, un parcours nord-sud
        // paraîtrait deux fois plus large qu'il ne l'est sous nos latitudes.
        let longitudeScale = cos((minLatitude + maxLatitude) / 2 * .pi / 180)
        let width = max((maxLongitude - minLongitude) * longitudeScale, 1e-6)
        let height = max(maxLatitude - minLatitude, 1e-6)

        let scale = min(
            (size.width - inset * 2) / width,
            (size.height - inset * 2) / height
        )
        let offsetX = (size.width - width * scale) / 2
        let offsetY = (size.height - height * scale) / 2

        for (index, coordinate) in coordinates.enumerated() {
            let point = CGPoint(
                x: offsetX + (coordinate.longitude - minLongitude) * longitudeScale * scale,
                // L'axe des ordonnées de l'écran est inversé par rapport à la latitude.
                y: offsetY + (maxLatitude - coordinate.latitude) * scale
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
