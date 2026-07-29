import SwiftUI
import MapKit
import VeloCore

/// Comparaison des circuits proposés.
///
/// Chaque proposition est présentée avec sa carte, ses chiffres clés et ses
/// éventuels avertissements, pour que le choix se fasse sans avoir à ouvrir
/// chaque circuit un par un.
struct RouteComparisonSheet: View {
    @Bindable var model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                        RouteCandidateCard(
                            candidate: candidate,
                            label: label(for: index),
                            isSelected: candidate.id == model.selectedCandidate?.id,
                            onSelect: {
                                model.select(candidate)
                                model.confirmSelection()
                            }
                        )
                        .onTapGesture { model.select(candidate) }
                    }

                    Button(Strings.Comparison.regenerate) { model.regenerate() }
                        .buttonStyle(PrimaryButtonStyle(isProminent: false))
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle(Strings.Comparison.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.Common.close) { dismiss() }
                }
            }
        }
    }

    private func label(for index: Int) -> String {
        index == 0 ? Strings.Comparison.recommended : Strings.Comparison.alternative(index)
    }
}

/// Fiche d'une proposition de circuit.
struct RouteCandidateCard: View {
    let candidate: RouteCandidate
    let label: String
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var route: CyclingRoute { candidate.route }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            miniMap
            statistics

            if let deviation = InstructionPhrasing.distanceDeviationText(route: route) {
                Label(deviation, systemImage: "ruler")
                    .font(.caption)
                    .foregroundStyle(Color.veloWarning)
            }

            RouteWarningList(warnings: candidate.warnings)

            Button(Strings.Comparison.select, action: onSelect)
                .buttonStyle(PrimaryButtonStyle(isProminent: isSelected))
        }
        .veloCard()
        .overlay(
            RoundedRectangle(cornerRadius: VeloMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onAppear {
            cameraPosition = .fitting(coordinates: route.coordinates, padding: 1.2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var miniMap: some View {
        // La carte miniature est non interactive : elle sert d'aperçu de la
        // forme du circuit, et un geste dessus doit sélectionner la fiche, pas
        // déplacer la vue.
        RouteMapView(
            route: route,
            showsUserLocation: false,
            cameraPosition: $cameraPosition
        )
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: VeloMetrics.mapCornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var statistics: some View {
        HStack(alignment: .top, spacing: 12) {
            StatTile(
                title: Strings.Detail.distance,
                value: InstructionPhrasing.displayDistance(route.distance),
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            StatTile(
                title: Strings.Detail.duration,
                value: InstructionPhrasing.displayDuration(route.duration),
                systemImage: "clock"
            )
            if let ascent = route.ascent {
                StatTile(
                    title: Strings.Summary.ascent,
                    value: "\(Int(ascent.rounded()))",
                    unit: "m",
                    systemImage: "arrow.up.right"
                )
            }
            if let ratio = route.cyclePathRatio {
                StatTile(
                    title: Strings.Comparison.cyclePathShare,
                    value: "\(Int((ratio * 100).rounded()))",
                    unit: "%",
                    systemImage: "bicycle"
                )
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            label,
            InstructionPhrasing.displayDistance(route.distance),
            InstructionPhrasing.displayDuration(route.duration)
        ]
        if let ascent = route.ascent {
            parts.append("\(Int(ascent.rounded())) mètres de dénivelé")
        }
        parts.append(contentsOf: candidate.warnings.map(InstructionPhrasing.warningText))
        return parts.joined(separator: ", ")
    }
}
