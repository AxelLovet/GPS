import SwiftUI
import SwiftData

/// Point d'entrée de VéloBoucle.
///
/// L'application est volontairement construite autour d'un unique conteneur de
/// dépendances (`AppDependencies`) injecté dans l'environnement SwiftUI. Aucun
/// singleton n'est utilisé : chaque service est un objet remplaçable, ce qui
/// permet de lancer l'application en mode démonstration ou en test avec des
/// doubles, sans modifier une seule vue.
@main
struct VeloBoucleApp: App {
    @State private var dependencies = AppDependencies.live()

    /// Conteneur SwiftData de l'historique des sorties.
    ///
    /// Créé une seule fois au lancement. En cas d'échec — schéma corrompu,
    /// disque plein — l'application bascule sur un conteneur en mémoire plutôt
    /// que de refuser de démarrer : l'utilisateur doit toujours pouvoir rouler,
    /// quitte à ne pas conserver la sortie.
    private let modelContainer: ModelContainer = {
        let schema = Schema([StoredRide.self])
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
        } catch {
            AppLog.persistence.error("Conteneur SwiftData indisponible, repli en mémoire")
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.settings)
                .tint(.veloAccent)
        }
        .modelContainer(modelContainer)
    }
}
