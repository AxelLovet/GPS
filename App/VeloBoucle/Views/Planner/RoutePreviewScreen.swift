import SwiftUI
import MapKit
import VeloCore

/// Aperçu du circuit retenu, dernière étape avant de rouler.
struct RoutePreviewScreen: View {
    let candidate: RouteCandidate
    var onStart: () -> Void
    var onRegenerate: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var exportedFile: ExportedGPXFile?

    private var route: CyclingRoute { candidate.route }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RouteMapView(route: route, showsUserLocation: false, cameraPosition: $cameraPosition)
                    .frame(height: 280)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: VeloMetrics.mapCornerRadius, style: .continuous
                        )
                    )
                    .accessibilityLabel(Strings.Preview.title)

                summary
                if !candidate.warnings.isEmpty {
                    RouteWarningList(warnings: candidate.warnings).veloCard()
                }
                instructionList
                actions
            }
            .padding(16)
        }
        .navigationTitle(Strings.Preview.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cameraPosition = .fitting(coordinates: route.coordinates) }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            StatTile(
                title: Strings.Detail.distance,
                value: InstructionPhrasing.displayDistance(route.distance),
                isProminent: true
            )
            StatTile(
                title: Strings.Detail.duration,
                value: InstructionPhrasing.displayDuration(route.duration)
            )
            if let ascent = route.ascent {
                StatTile(title: Strings.Summary.ascent, value: "\(Int(ascent.rounded()))", unit: "m")
            }
        }
        .veloCard()
    }

    private var instructionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.Preview.instructions)
                .font(.headline)

            // Seules les manœuvres réelles sont listées : afficher trente
            // « continuez tout droit » n'aiderait personne à se représenter le
            // parcours.
            let significant = route.instructions.filter {
                $0.maneuver.requiresAdvanceWarning || $0.maneuver == .depart
            }
            if significant.isEmpty {
                Text(Strings.Preview.noInstructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(significant.prefix(20)) { instruction in
                    HStack(spacing: 12) {
                        ManeuverArrow(maneuver: instruction.maneuver, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                InstructionPhrasing.maneuverText(
                                    instruction.maneuver,
                                    roadName: instruction.roadName,
                                    roundaboutExit: instruction.roundaboutExitNumber
                                )
                            )
                            .font(.subheadline)
                            Text(InstructionPhrasing.displayDistance(instruction.distance))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if significant.count > 20 {
                    Text(Strings.Preview.moreInstructions(significant.count - 20))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .veloCard()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(Strings.Preview.start, action: onStart)
                .buttonStyle(PrimaryButtonStyle())

            Button(Strings.Preview.regenerate, action: onRegenerate)
                .buttonStyle(PrimaryButtonStyle(isProminent: false))

            Button(Strings.Preview.exportGPX) { exportGPX() }
                .buttonStyle(.bordered)
        }
    }

    private func exportGPX() {
        do {
            let data = try dependencies.gpxService.export(route: route, name: Strings.Preview.title)
            exportedFile = try ExportedGPXFile(data: data, fileName: "circuit-veloboucle.gpx")
        } catch {
            AppLog.persistence.error("Export GPX impossible")
        }
    }
}

/// Fichier GPX écrit temporairement pour être partagé.
///
/// `ShareLink` et la feuille de partage d'iOS attendent une URL de fichier ;
/// les données sont donc écrites dans le dossier temporaire, que le système
/// nettoie automatiquement.
struct ExportedGPXFile: Identifiable {
    let id = UUID()
    let url: URL

    init(data: Data, fileName: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        self.url = url
    }
}

/// Pont vers `UIActivityViewController`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
