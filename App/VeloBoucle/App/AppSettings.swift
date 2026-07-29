import Foundation
import Observation
import VeloCore

/// Réglages de l'utilisateur, conservés dans `UserDefaults`.
///
/// Aucune donnée de localisation n'est stockée ici : uniquement des préférences.
@Observable
@MainActor
final class AppSettings {
    private enum Key {
        static let profile = "profile"
        static let avoidUnpaved = "avoidUnpavedSurfaces"
        static let rejectGravel = "rejectGravel"
        static let preferCyclePaths = "preferCyclePaths"
        static let avoidHighTraffic = "avoidHighTrafficRoads"
        static let avoidSteepClimbs = "avoidSteepClimbs"
        static let preferredDirection = "preferredDirection"
        static let voiceEnabled = "voiceInstructionsEnabled"
        static let hapticsEnabled = "hapticFeedbackEnabled"
        static let recalculationPolicy = "recalculationPolicy"
        static let bodyMass = "bodyMassKilograms"
        static let lastDistance = "lastRequestedDistance"
        static let demoMode = "demoModeEnabled"
        static let keepScreenAwake = "keepScreenAwake"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.profile: CyclingProfile.electricRoad.rawValue,
            Key.avoidUnpaved: true,
            Key.rejectGravel: false,
            Key.preferCyclePaths: true,
            Key.avoidHighTraffic: true,
            Key.avoidSteepClimbs: false,
            Key.preferredDirection: PreferredDirection.any.rawValue,
            Key.voiceEnabled: true,
            Key.hapticsEnabled: true,
            Key.recalculationPolicy: RecalculationPolicy.ask.rawValue,
            Key.bodyMass: 75.0,
            Key.lastDistance: 20_000.0,
            Key.demoMode: false,
            Key.keepScreenAwake: true
        ])
    }

    // MARK: - Préférences de parcours

    var profile: CyclingProfile {
        get { CyclingProfile(rawValue: defaults.string(forKey: Key.profile) ?? "") ?? .electricRoad }
        set { defaults.set(newValue.rawValue, forKey: Key.profile) }
    }

    var avoidUnpavedSurfaces: Bool {
        get { defaults.bool(forKey: Key.avoidUnpaved) }
        set { defaults.set(newValue, forKey: Key.avoidUnpaved) }
    }

    var rejectGravel: Bool {
        get { defaults.bool(forKey: Key.rejectGravel) }
        set { defaults.set(newValue, forKey: Key.rejectGravel) }
    }

    var preferCyclePaths: Bool {
        get { defaults.bool(forKey: Key.preferCyclePaths) }
        set { defaults.set(newValue, forKey: Key.preferCyclePaths) }
    }

    var avoidHighTrafficRoads: Bool {
        get { defaults.bool(forKey: Key.avoidHighTraffic) }
        set { defaults.set(newValue, forKey: Key.avoidHighTraffic) }
    }

    var avoidSteepClimbs: Bool {
        get { defaults.bool(forKey: Key.avoidSteepClimbs) }
        set { defaults.set(newValue, forKey: Key.avoidSteepClimbs) }
    }

    var preferredDirection: PreferredDirection {
        get {
            PreferredDirection(rawValue: defaults.string(forKey: Key.preferredDirection) ?? "") ?? .any
        }
        set { defaults.set(newValue.rawValue, forKey: Key.preferredDirection) }
    }

    /// Agrégat consommé par le moteur de génération.
    var routingPreferences: RoutingPreferences {
        RoutingPreferences(
            profile: profile,
            avoidUnpavedSurfaces: avoidUnpavedSurfaces,
            rejectGravel: rejectGravel,
            preferCyclePaths: preferCyclePaths,
            avoidHighTrafficRoads: avoidHighTrafficRoads,
            avoidSteepClimbs: avoidSteepClimbs,
            preferredDirection: preferredDirection
        )
    }

    // MARK: - Navigation

    var voiceInstructionsEnabled: Bool {
        get { defaults.bool(forKey: Key.voiceEnabled) }
        set { defaults.set(newValue, forKey: Key.voiceEnabled) }
    }

    var hapticFeedbackEnabled: Bool {
        get { defaults.bool(forKey: Key.hapticsEnabled) }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }

    var recalculationPolicy: RecalculationPolicy {
        get {
            RecalculationPolicy(rawValue: defaults.string(forKey: Key.recalculationPolicy) ?? "")
                ?? .ask
        }
        set { defaults.set(newValue.rawValue, forKey: Key.recalculationPolicy) }
    }

    /// Empêche la mise en veille pendant la navigation.
    ///
    /// Coûteux en batterie, donc désactivable. Le suivi de la sortie continue de
    /// toute façon écran éteint : ce réglage ne concerne que le confort de
    /// lecture sur un guidon.
    var keepScreenAwake: Bool {
        get { defaults.bool(forKey: Key.keepScreenAwake) }
        set { defaults.set(newValue, forKey: Key.keepScreenAwake) }
    }

    // MARK: - Divers

    /// Masse corporelle utilisée pour l'estimation calorique.
    var bodyMassKilograms: Double {
        get { defaults.double(forKey: Key.bodyMass) }
        set { defaults.set(min(max(newValue, 30), 200), forKey: Key.bodyMass) }
    }

    /// Dernière distance demandée, réutilisée au lancement suivant.
    var lastRequestedDistance: Double {
        get { defaults.double(forKey: Key.lastDistance) }
        set { defaults.set(newValue, forKey: Key.lastDistance) }
    }

    var demoModeEnabled: Bool {
        get { defaults.bool(forKey: Key.demoMode) }
        set { defaults.set(newValue, forKey: Key.demoMode) }
    }
}
