import SwiftUI
import UIKit
import VeloCore

/// Réglages de l'application.
struct SettingsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                routePreferencesSection
                navigationSection
                locationSection
                demoSection
                dataSection
                aboutSection
            }
            .navigationTitle(Strings.Settings.title)
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section(Strings.Settings.profileSection) {
            Picker(Strings.Settings.profileSection, selection: $settings.profile) {
                ForEach(CyclingProfile.allCases) { profile in
                    Text(Strings.profileName(profile)).tag(profile)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var routePreferencesSection: some View {
        Section {
            Toggle(Strings.Settings.preferCyclePaths, isOn: $settings.preferCyclePaths)
            Toggle(Strings.Settings.avoidHighTraffic, isOn: $settings.avoidHighTrafficRoads)
            Toggle(Strings.Settings.avoidUnpaved, isOn: $settings.avoidUnpavedSurfaces)
            Toggle(Strings.Settings.rejectGravel, isOn: $settings.rejectGravel)
            Toggle(Strings.Settings.avoidSteepClimbs, isOn: $settings.avoidSteepClimbs)

            Picker(Strings.Settings.preferredDirection, selection: $settings.preferredDirection) {
                ForEach(PreferredDirection.allCases) { direction in
                    Text(Strings.directionName(direction)).tag(direction)
                }
            }
        } header: {
            Text(Strings.Settings.routeSection)
        } footer: {
            Text(Strings.Settings.preferredDirectionFooter)
        }
    }

    private var navigationSection: some View {
        Section {
            Toggle(Strings.Settings.voiceInstructions, isOn: $settings.voiceInstructionsEnabled)
            Toggle(Strings.Settings.hapticFeedback, isOn: $settings.hapticFeedbackEnabled)
            Toggle(Strings.Settings.keepScreenAwake, isOn: $settings.keepScreenAwake)

            Picker(Strings.Settings.recalculation, selection: $settings.recalculationPolicy) {
                ForEach(RecalculationPolicy.allCases) { policy in
                    Text(Strings.recalculationName(policy)).tag(policy)
                }
            }
        } header: {
            Text(Strings.Settings.navigationSection)
        } footer: {
            Text(Strings.Settings.keepScreenAwakeFooter)
        }
    }

    private var locationSection: some View {
        Section {
            LabeledContent(Strings.Location.whyTitle) {
                Text(authorizationDescription).foregroundStyle(.secondary)
            }
            Button(Strings.Settings.openSystemSettings) { openSystemSettings() }

            if dependencies.locationService.authorization == .whenInUse {
                Text(Strings.Location.alwaysExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(Strings.Settings.locationSection)
        } footer: {
            Text(Strings.Location.whyMessage)
        }
    }

    private var authorizationDescription: String {
        switch dependencies.locationService.authorization {
        case .notDetermined: return Strings.Location.notDetermined
        case .denied: return Strings.Location.denied
        case .restricted: return Strings.Location.restricted
        case .whenInUse: return Strings.Settings.locationWhenInUse
        case .always: return Strings.Settings.locationAlways
        }
    }

    private var demoSection: some View {
        Section {
            Toggle(
                Strings.Settings.demoMode,
                isOn: Binding(
                    get: { dependencies.isDemoModeActive },
                    set: { dependencies.setDemoMode($0) }
                )
            )
            // Sans clé d'accès, le mode démonstration est le seul mode
            // fonctionnel : le désactiver n'aurait aucun effet, autant le dire.
            .disabled(!dependencies.hasAPIKey)

            LabeledContent(Strings.Settings.apiKeyConfigured) {
                Label(
                    dependencies.hasAPIKey
                        ? Strings.Settings.apiKeyConfigured
                        : Strings.Settings.apiKeyMissing,
                    systemImage: dependencies.hasAPIKey ? "checkmark.seal.fill" : "xmark.seal"
                )
                .labelStyle(.titleAndIcon)
                .foregroundStyle(dependencies.hasAPIKey ? Color.green : Color.veloWarning)
            }
        } header: {
            Text(Strings.Demo.banner)
        } footer: {
            Text("\(Strings.Settings.demoModeFooter)\n\n\(Strings.Settings.apiKeyFooter)")
        }
    }

    private var dataSection: some View {
        Section {
            Stepper(
                value: $settings.bodyMassKilograms, in: 30...200, step: 1
            ) {
                LabeledContent(Strings.Settings.bodyMass) {
                    Text("\(Int(settings.bodyMassKilograms)) kg")
                }
            }
        } header: {
            Text(Strings.Settings.dataSection)
        } footer: {
            Text(Strings.Settings.bodyMassFooter)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(Strings.Settings.version) {
                Text(Self.versionString).foregroundStyle(.secondary)
            }
            Text(Strings.Settings.dataAttribution)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Strings.Settings.privacySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(Strings.Settings.aboutSection)
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
