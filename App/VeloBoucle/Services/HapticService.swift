import Foundation
import UIKit
import VeloCore

/// Retours haptiques de la navigation.
protocol HapticFeedbackProviding: AnyObject, Sendable {
    func play(_ cue: HapticCue)
    /// Prépare le moteur haptique avant une manœuvre, pour supprimer la latence
    /// de première activation.
    func prepare()
}

/// Implémentation `UIFeedbackGenerator`.
///
/// Les intensités sont choisies pour être perceptibles à travers une poche ou
/// un support de guidon, sans être désagréables : un signal léger pour prévenir,
/// un signal net à l'approche immédiate, un motif d'avertissement pour une
/// sortie de parcours.
@MainActor
final class HapticService: HapticFeedbackProviding {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    nonisolated func prepare() {
        Task { @MainActor in
            light.prepare()
            heavy.prepare()
            notification.prepare()
        }
    }

    nonisolated func play(_ cue: HapticCue) {
        Task { @MainActor in perform(cue) }
    }

    private func perform(_ cue: HapticCue) {
        switch cue {
        case .upcomingManeuver:
            light.impactOccurred(intensity: 0.7)
        case .imminentManeuver:
            heavy.impactOccurred(intensity: 1.0)
        case .offRoute:
            notification.notificationOccurred(.warning)
        case .backOnRoute:
            notification.notificationOccurred(.success)
        case .arrival:
            notification.notificationOccurred(.success)
        }
    }
}

/// Double inactif, utilisé quand l'utilisateur désactive les vibrations.
final class SilentHapticService: HapticFeedbackProviding {
    func play(_ cue: HapticCue) {}
    func prepare() {}
}
