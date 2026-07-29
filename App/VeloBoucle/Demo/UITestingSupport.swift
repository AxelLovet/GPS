import Foundation
import VeloCore

/// Configuration appliquée lorsque l'application est lancée par les tests
/// d'interface.
///
/// Les tests XCUITest doivent s'exécuter sans réseau, sans clé API et sans
/// dépendre d'une position réelle — un simulateur n'en a pas toujours une. Ce
/// petit module centralise ces adaptations, plutôt que de disséminer des
/// conditions de test dans le code de production.
///
/// Rien ici ne s'active en usage normal : l'unique déclencheur est l'argument
/// de lancement `-VeloBoucleUITesting`, que seule la cible de tests transmet.
enum UITestingSupport {
    static let launchArgument = "-VeloBoucleUITesting"

    /// Vrai si l'application tourne sous test d'interface.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Position à utiliser en l'absence de GPS, lue dans l'environnement de
    /// lancement. Par défaut : place Saint-François, Lausanne.
    static var simulatedCoordinate: GeographicCoordinate? {
        guard isActive else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let latitude = Double(environment["VELO_SIMULATED_LATITUDE"] ?? "")
            ?? DemoRouteFactory.lausanne.latitude
        let longitude = Double(environment["VELO_SIMULATED_LONGITUDE"] ?? "")
            ?? DemoRouteFactory.lausanne.longitude

        let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }

    /// Relevé synthétique correspondant à la position simulée.
    static var simulatedSample: LocationSample? {
        simulatedCoordinate.map {
            LocationSample(coordinate: $0, timestamp: Date(), horizontalAccuracy: 5)
        }
    }

    /// Réinitialise les préférences afin que chaque test parte d'un état connu.
    ///
    /// Sans cela, la distance choisie par un test précédent serait réutilisée et
    /// les scénarios deviendraient dépendants de leur ordre d'exécution.
    static func resetPreferencesIfNeeded(_ defaults: UserDefaults = .standard) {
        guard isActive else { return }
        for key in ["lastRequestedDistance", "demoModeEnabled", "preferredDirection"] {
            defaults.removeObject(forKey: key)
        }
    }
}
