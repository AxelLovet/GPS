import Foundation

/// Résolution de la clé d'accès au moteur de routage.
///
/// **Aucune clé n'est écrite dans le code source.** Elles sont recherchées, dans
/// l'ordre :
///
/// 1. la variable d'environnement `ORS_API_KEY` — utilisée par l'intégration
///    continue et par les schémas de test, jamais en production ;
/// 2. la clé `ORSAPIKey` de l'`Info.plist`, alimentée par `Secrets.xcconfig`,
///    fichier local exclu du dépôt (voir `Secrets.example.xcconfig`).
///
/// Si aucune n'est trouvée, la fonction renvoie `nil` et l'application démarre
/// en mode démonstration avec une explication, plutôt que d'échouer.
enum SecretsProvider {
    static let environmentVariableName = "ORS_API_KEY"
    static let infoPlistKey = "ORSAPIKey"

    static func openRouteServiceAPIKey(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let fromEnvironment = normalise(environment[environmentVariableName]) {
            return fromEnvironment
        }
        return normalise(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Élimine les valeurs vides et le contenu du fichier d'exemple.
    ///
    /// Un `Secrets.xcconfig` copié depuis l'exemple mais non rempli contient
    /// encore le texte substitutif ; le traiter comme une clé valide
    /// produirait une erreur d'authentification incompréhensible plutôt qu'un
    /// message clair « clé manquante ».
    private static func normalise(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "VOTRE_CLE_ICI",
              !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }
}
