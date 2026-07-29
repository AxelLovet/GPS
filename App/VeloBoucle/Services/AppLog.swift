import Foundation
import OSLog

/// Journalisation de l'application.
///
/// Règle absolue (cahier des charges §20) : **aucune trace ne contient de clé
/// API, de position précise ni de donnée personnelle.** Les journaux servent au
/// diagnostic technique, pas au suivi de l'utilisateur.
///
/// `OSLog` traite par défaut toute valeur interpolée comme privée et la remplace
/// par `<private>` dans les journaux collectés hors du poste de développement.
/// Les rares valeurs marquées `.public` sont des libellés fixes, jamais des
/// données.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ch.veloboucle.app"

    static let location = Logger(subsystem: subsystem, category: "localisation")
    static let routing = Logger(subsystem: subsystem, category: "routage")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let persistence = Logger(subsystem: subsystem, category: "persistance")
    static let ride = Logger(subsystem: subsystem, category: "sortie")
}
