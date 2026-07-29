import SwiftUI
import VeloCore

// MARK: - Sélecteur de distance

/// Choix de la distance visée : raccourcis usuels plus une valeur libre.
struct DistanceSelector: View {
    @Binding var distance: Double
    @State private var isEditingCustomValue = false
    @State private var customText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Planner.distanceTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PlannerViewModel.presetDistances, id: \.self) { preset in
                        presetButton(preset)
                    }
                    customButton
                }
                .padding(.horizontal, 1)
            }
        }
        .alert(Strings.Planner.customDistanceTitle, isPresented: $isEditingCustomValue) {
            TextField(Strings.Planner.customDistancePlaceholder, text: $customText)
                .keyboardType(.numberPad)
            Button(Strings.Common.validate) { applyCustomValue() }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Planner.customDistanceMessage)
        }
    }

    private func presetButton(_ preset: Double) -> some View {
        let isSelected = abs(distance - preset) < 1
        return Button {
            distance = preset
        } label: {
            Text(InstructionPhrasing.displayDistance(preset))
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(
                        isSelected ? Color.accentColor : Color(.tertiarySystemFill)
                    )
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Planner.distanceAccessibility(preset))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var customButton: some View {
        let isCustom = !PlannerViewModel.presetDistances.contains { abs($0 - distance) < 1 }
        return Button {
            customText = String(Int((distance / 1000).rounded()))
            isEditingCustomValue = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text(isCustom ? InstructionPhrasing.displayDistance(distance) : Strings.Common.other)
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(isCustom ? Color.accentColor : Color(.tertiarySystemFill)))
            .foregroundStyle(isCustom ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func applyCustomValue() {
        guard let kilometers = Double(customText.filter(\.isNumber)), kilometers > 0 else { return }
        // Bornes volontairement larges mais finies : en deçà de 2 km une boucle
        // n'a pas de sens, au-delà de 300 km le moteur de routage refuse.
        distance = min(max(kilometers, 2), 300) * 1000
    }
}

// MARK: - Tuile de statistique

/// Valeur chiffrée avec son libellé, lisible d'un coup d'œil.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String?
    var systemImage: String?
    var isProminent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(isProminent ? .system(size: 40, weight: .bold, design: .rounded)
                                      : .title3.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(isProminent ? .title3.weight(.medium) : .caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) : \(value) \(unit ?? "")")
    }
}

// MARK: - Flèche de manœuvre

/// Grande flèche indiquant la prochaine manœuvre.
///
/// C'est l'élément le plus important de l'écran de navigation : il doit être
/// interprétable en une fraction de seconde, sans lire le texte.
struct ManeuverArrow: View {
    let maneuver: ManeuverType
    var size: CGFloat = VeloMetrics.maneuverArrowSize

    var body: some View {
        Image(systemName: maneuver.symbolName)
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accentColor))
            .accessibilityLabel(InstructionPhrasing.maneuverText(maneuver))
    }
}

// MARK: - Erreurs

/// Présentation d'une erreur avec ses actions de récupération.
struct ErrorBanner: View {
    let error: VeloError
    var onAction: (RecoveryAction) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.veloWarning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title).font(.headline)
                    Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel(Strings.Common.dismiss)
            }

            if !error.recoveryActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(error.recoveryActions.filter { $0 != .none }, id: \.self) { action in
                            Button(Strings.recoveryActionTitle(action)) { onAction(action) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .veloCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Avertissements de circuit

/// Liste compacte des avertissements attachés à un circuit.
struct RouteWarningList: View {
    let warnings: Set<RouteWarning>

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warnings.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { warning in
                    Label(
                        InstructionPhrasing.warningText(warning),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.veloWarning)
                }
            }
        }
    }
}

// MARK: - État de la localisation

/// Pastille indiquant l'état de l'autorisation de localisation.
struct LocationStatusBadge: View {
    let authorization: LocationAuthorizationState
    let hasReducedAccuracy: Bool
    var onOpenSettings: () -> Void

    var body: some View {
        if let description {
            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(description).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.thinMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Strings.Location.openSettingsHint)
        }
    }

    private var description: String? {
        switch authorization {
        case .notDetermined: return Strings.Location.notDetermined
        case .denied: return Strings.Location.denied
        case .restricted: return Strings.Location.restricted
        case .whenInUse, .always:
            return hasReducedAccuracy ? Strings.Location.reducedAccuracy : nil
        }
    }

    private var icon: String {
        switch authorization {
        case .denied, .restricted: return "location.slash.fill"
        default: return "location.fill"
        }
    }
}

// MARK: - Bandeau du mode démonstration

/// Rappelle en permanence que les circuits affichés sont simulés.
struct DemoModeBanner: View {
    var body: some View {
        Label(Strings.Demo.banner, systemImage: "testtube.2")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.veloWarning.opacity(0.9)))
            .foregroundStyle(.white)
            .accessibilityLabel(Strings.Demo.bannerAccessibility)
    }
}
