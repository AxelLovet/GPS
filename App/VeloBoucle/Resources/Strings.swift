import Foundation
import VeloCore

/// Tous les textes visibles par l'utilisateur.
///
/// Les regrouper ici répond à l'exigence du cahier des charges (§10) : aucune
/// chaîne n'est écrite en dur dans une vue, ce qui permet d'ajouter l'anglais et
/// l'allemand en traduisant les seuls fichiers `Localizable.strings`, sans
/// toucher au code.
///
/// La langue de développement est le français ; les clés sont en anglais pour
/// rester lisibles dans les outils de traduction.
enum Strings {
    private static func value(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }

    enum Common {
        static let cancel = value("common.cancel", "Annuler")
        static let validate = value("common.validate", "Valider")
        static let close = value("common.close", "Fermer")
        static let dismiss = value("common.dismiss", "Masquer")
        static let retry = value("common.retry", "Réessayer")
        static let save = value("common.save", "Enregistrer")
        static let delete = value("common.delete", "Supprimer")
        static let rename = value("common.rename", "Renommer")
        static let share = value("common.share", "Partager")
        static let other = value("common.other", "Autre")
        static let back = value("common.back", "Retour")
        static let estimate = value("common.estimate", "estimation")
    }

    enum Detail {
        static let distance = value("detail.distance", "Distance")
        static let duration = value("detail.duration", "Durée")
        static let date = value("detail.date", "Date")
        static let startTime = value("detail.startTime", "Départ")
    }

    enum Map {
        static let start = value("map.start", "Départ")
        static let finish = value("map.finish", "Arrivée")
        static let chosenStart = value("map.chosenStart", "Départ choisi")
        static let currentPosition = value("map.currentPosition", "Votre position")
    }

    enum Tabs {
        static let planner = value("tabs.planner", "Parcours")
        static let ride = value("tabs.ride", "Sortie")
        static let history = value("tabs.history", "Historique")
        static let settings = value("tabs.settings", "Réglages")
    }

    enum Planner {
        static let title = value("planner.title", "Créer une boucle")
        static let distanceTitle = value("planner.distance.title", "Distance souhaitée")
        static let generate = value("planner.generate", "Créer une boucle")
        static let recenter = value("planner.recenter", "Recentrer la carte")
        static let chooseStart = value("planner.chooseStart", "Choisir le départ")
        static let useCurrentLocation = value("planner.useCurrentLocation", "Partir d'ici")
        static let pickStartHint = value(
            "planner.pickStart.hint",
            "Touchez la carte pour placer votre point de départ."
        )
        static let customDistanceTitle = value("planner.customDistance.title", "Distance libre")
        static let customDistanceMessage = value(
            "planner.customDistance.message",
            "Indiquez une distance en kilomètres, entre 2 et 300."
        )
        static let customDistancePlaceholder = value(
            "planner.customDistance.placeholder", "Kilomètres"
        )

        static func distanceAccessibility(_ meters: Double) -> String {
            String(
                format: value("planner.distance.accessibility", "Boucle de %@"),
                InstructionPhrasing.displayDistance(meters)
            )
        }
    }

    enum Generation {
        static let title = value("generation.title", "Recherche de circuits")
        static let explanation = value(
            "generation.explanation",
            "Plusieurs circuits sont calculés puis comparés pour retenir ceux qui approchent le mieux votre distance."
        )
        static let cancel = value("generation.cancel", "Annuler la recherche")

        static func progress(_ completed: Int, _ total: Int) -> String {
            String(
                format: value("generation.progress", "%d circuit(s) analysé(s) sur %d"),
                completed, total
            )
        }
    }

    enum Comparison {
        static let title = value("comparison.title", "Choisissez votre circuit")
        static let recommended = value("comparison.recommended", "Recommandé")
        static func alternative(_ index: Int) -> String {
            String(format: value("comparison.alternative", "Alternatif %d"), index)
        }
        static let select = value("comparison.select", "Choisir ce circuit")
        static let regenerate = value("comparison.regenerate", "Générer d'autres circuits")
        static let cyclePathShare = value("comparison.cyclePathShare", "Pistes cyclables")
        static let surface = value("comparison.surface", "Revêtement")
        static let surfacePaved = value("comparison.surface.paved", "Goudronné")
        static let surfaceMixed = value("comparison.surface.mixed", "Mixte")
    }

    enum Preview {
        static let title = value("preview.title", "Votre circuit")
        static let start = value("preview.start", "Démarrer la navigation")
        static let instructions = value("preview.instructions", "Principales indications")
        static let regenerate = value("preview.regenerate", "Générer d'autres circuits")
        static let exportGPX = value("preview.exportGPX", "Exporter en GPX")
        static let noInstructions = value(
            "preview.noInstructions",
            "Ce circuit ne comporte aucun changement de direction notable."
        )

        static func moreInstructions(_ count: Int) -> String {
            String(format: value("preview.moreInstructions", "et %d autre(s) indication(s)"), count)
        }
    }

    enum Ride {
        static let noRideTitle = value("ride.none.title", "Aucune sortie en cours")
        static let noRideMessage = value(
            "ride.none.message",
            "Créez une boucle depuis l'onglet Parcours, puis appuyez sur « Démarrer la navigation »."
        )
        static let freeRide = value("ride.free", "Rouler sans circuit")
        static let pause = value("ride.pause", "Pause")
        static let resume = value("ride.resume", "Reprendre")
        static let finish = value("ride.finish", "Terminer")
        static let recenter = value("ride.recenter", "Recentrer")
        static let showWholeRoute = value("ride.showWholeRoute", "Voir tout le parcours")
        static let northUp = value("ride.northUp", "Nord en haut")
        static let headingUp = value("ride.headingUp", "Sens de marche")

        static let offRouteTitle = value("ride.offRoute.title", "Vous avez quitté le parcours")
        static let recalculate = value("ride.recalculate", "Recalculer")
        static let recalculating = value("ride.recalculating", "Recalcul en cours…")
        static let keepGoing = value("ride.keepGoing", "Continuer sans recalculer")

        static let speed = value("ride.speed", "Vitesse")
        static let averageSpeed = value("ride.averageSpeed", "Moyenne")
        static let distanceCovered = value("ride.distanceCovered", "Parcourus")
        static let remainingDistance = value("ride.remainingDistance", "Restants")
        static let elapsed = value("ride.elapsed", "Temps")
        static let arrivalTime = value("ride.arrivalTime", "Arrivée")
        static let finishConfirmTitle = value("ride.finish.confirm", "Terminer la sortie ?")
        static let finishConfirmMessage = value(
            "ride.finish.message",
            "La sortie sera enregistrée et vous pourrez la retrouver dans l'historique."
        )
        static let offRouteMessage = value(
            "ride.offRoute.message",
            "Voulez-vous calculer un itinéraire pour rejoindre la suite du parcours ?"
        )

        static func offRouteDistance(_ meters: Double) -> String {
            String(
                format: value("ride.offRoute.distance", "à %@ du parcours"),
                InstructionPhrasing.displayDistance(meters)
            )
        }

        static func thenOn(_ roadName: String) -> String {
            String(format: value("ride.thenOn", "puis %@"), roadName)
        }
    }

    enum Summary {
        static let title = value("summary.title", "Sortie terminée")
        static let nameField = value("summary.nameField", "Nom de la sortie")
        static let save = value("summary.save", "Enregistrer la sortie")
        static let discard = value("summary.discard", "Ne pas enregistrer")
        static let calories = value("summary.calories", "Calories")
        static let maxSpeed = value("summary.maxSpeed", "Vitesse max.")
        static let movingTime = value("summary.movingTime", "Temps de déplacement")
        static let ascent = value("summary.ascent", "Dénivelé +")
        static let descent = value("summary.descent", "Dénivelé −")
        static let deviations = value("summary.deviations", "Écarts de parcours")
        static let caloriesDisclaimer = value(
            "summary.calories.disclaimer",
            "Les calories sont une estimation calculée à partir de votre poids et du temps de déplacement. Elles ne remplacent pas une mesure."
        )

        static func deviationCount(_ count: Int) -> String {
            String(format: value("summary.deviationCount", "%d écart(s) par rapport au circuit"), count)
        }
    }

    enum History {
        static let title = value("history.title", "Historique")
        static let empty = value("history.empty", "Aucune sortie enregistrée")
        static let emptyMessage = value(
            "history.empty.message",
            "Vos sorties apparaîtront ici une fois terminées et enregistrées."
        )
        static let search = value("history.search", "Rechercher une sortie")
        static let repeatRide = value("history.repeat", "Refaire ce parcours")
        static let importGPX = value("history.importGPX", "Importer un fichier GPX")
        static let deleteConfirm = value("history.delete.confirm", "Supprimer cette sortie ?")
        static let deleteMessage = value(
            "history.delete.message",
            "Cette action est définitive. Pensez à exporter le fichier GPX si vous souhaitez le conserver."
        )
    }

    enum Settings {
        static let title = value("settings.title", "Réglages")
        static let profileSection = value("settings.profile.section", "Profil de vélo")
        static let routeSection = value("settings.route.section", "Préférences de parcours")
        static let navigationSection = value("settings.navigation.section", "Navigation")
        static let locationSection = value("settings.location.section", "Localisation")
        static let dataSection = value("settings.data.section", "Cartes et données")
        static let aboutSection = value("settings.about.section", "À propos")

        static let avoidUnpaved = value("settings.avoidUnpaved", "Éviter les chemins non goudronnés")
        static let rejectGravel = value("settings.rejectGravel", "Refuser le gravier")
        static let preferCyclePaths = value("settings.preferCyclePaths", "Privilégier les pistes cyclables")
        static let avoidHighTraffic = value("settings.avoidHighTraffic", "Éviter les routes à fort trafic")
        static let avoidSteepClimbs = value("settings.avoidSteepClimbs", "Éviter les fortes montées")
        static let preferredDirection = value("settings.preferredDirection", "Direction préférée")
        static let preferredDirectionFooter = value(
            "settings.preferredDirection.footer",
            "Indique de quel côté la boucle doit se dérouler par rapport à votre départ."
        )

        static let voiceInstructions = value("settings.voiceInstructions", "Instructions vocales")
        static let hapticFeedback = value("settings.hapticFeedback", "Retours haptiques")
        static let keepScreenAwake = value("settings.keepScreenAwake", "Garder l'écran allumé")
        static let keepScreenAwakeFooter = value(
            "settings.keepScreenAwake.footer",
            "Pratique sur un guidon, mais consomme nettement plus de batterie. L'enregistrement de la sortie continue même écran éteint."
        )
        static let recalculation = value("settings.recalculation", "Recalcul hors parcours")
        static let bodyMass = value("settings.bodyMass", "Poids")
        static let bodyMassFooter = value(
            "settings.bodyMass.footer",
            "Sert uniquement à estimer les calories. Cette information ne quitte jamais votre iPhone."
        )

        static let demoMode = value("settings.demoMode", "Mode démonstration")
        static let demoModeFooter = value(
            "settings.demoMode.footer",
            "Génère des circuits fictifs sans connexion ni clé d'accès. Utile pour découvrir l'application ou la tester dans le simulateur."
        )
        static let apiKeyConfigured = value("settings.apiKey.configured", "Clé d'accès configurée")
        static let apiKeyMissing = value("settings.apiKey.missing", "Aucune clé d'accès")
        static let apiKeyFooter = value(
            "settings.apiKey.footer",
            "La clé OpenRouteService s'ajoute dans le fichier Secrets.xcconfig, jamais dans le code. Voir le fichier README du projet."
        )

        static let openSystemSettings = value("settings.openSystem", "Ouvrir les Réglages d'iOS")
        static let dataAttribution = value(
            "settings.dataAttribution",
            "Fonds de carte : Apple Plans. Calcul d'itinéraires : OpenRouteService, à partir des données OpenStreetMap (ODbL)."
        )
        static let version = value("settings.version", "Version")
        static let locationWhenInUse = value(
            "settings.location.whenInUse", "Pendant l'utilisation"
        )
        static let locationAlways = value("settings.location.always", "Toujours")
        static let privacy = value("settings.privacy", "Confidentialité")
        static let privacySummary = value(
            "settings.privacy.summary",
            "Vos sorties, vos traces GPS et vos réglages restent sur votre iPhone. Seul le point de départ et la distance souhaitée sont envoyés au service de calcul d'itinéraires, le temps d'une requête."
        )
    }

    enum Location {
        static let notDetermined = value("location.notDetermined", "Localisation non autorisée")
        static let denied = value("location.denied", "Localisation refusée")
        static let restricted = value("location.restricted", "Localisation bloquée")
        static let reducedAccuracy = value("location.reducedAccuracy", "Position peu précise")
        static let openSettingsHint = value(
            "location.openSettings.hint", "Ouvre les réglages de l'application"
        )
        static let whyTitle = value("location.why.title", "Pourquoi la localisation ?")
        static let whyMessage = value(
            "location.why.message",
            "VéloBoucle a besoin de votre position pour placer le départ de votre boucle, vous guider en temps réel et enregistrer votre sortie. Sans elle, vous pouvez encore choisir un départ à la main sur la carte."
        )
        static let alwaysExplanation = value(
            "location.always.explanation",
            "Pour continuer à enregistrer votre sortie écran verrouillé, autorisez la localisation « Toujours »."
        )
    }

    enum Recovery {
        static let title = value("recovery.title", "Sortie interrompue")
        static let message = value(
            "recovery.message",
            "Une sortie n'a pas été terminée correctement. Voulez-vous la reprendre ?"
        )
        static let resume = value("recovery.resume", "Reprendre")
        static let saveOnly = value("recovery.saveOnly", "Enregistrer sans reprendre")
        static let discard = value("recovery.discard", "Abandonner")
    }

    enum Demo {
        static let banner = value("demo.banner", "Mode démonstration")
        static let bannerAccessibility = value(
            "demo.banner.accessibility",
            "Mode démonstration actif : les circuits affichés sont fictifs"
        )
        static let simulateRide = value("demo.simulateRide", "Simuler un déplacement")
        static let simulateDetour = value("demo.simulateDetour", "Simuler une sortie de parcours")
        static let stopSimulation = value("demo.stopSimulation", "Arrêter la simulation")
    }

    /// Libellé d'une action de récupération proposée après une erreur.
    static func recoveryActionTitle(_ action: RecoveryAction) -> String {
        switch action {
        case .retry: return Common.retry
        case .changeDistance: return value("recovery.changeDistance", "Modifier la distance")
        case .changeStartingPoint: return value("recovery.changeStart", "Changer de départ")
        case .openSettings: return value("recovery.openSettings", "Ouvrir les réglages")
        case .openAppSettings: return Settings.openSystemSettings
        case .configureAPIKey: return value("recovery.configureKey", "Configurer la clé d'accès")
        case .useSavedRoute: return value("recovery.useSaved", "Utiliser un parcours enregistré")
        case .enableDemoMode: return value("recovery.enableDemo", "Passer en démonstration")
        case .none: return Common.close
        }
    }

    /// Nom lisible d'un profil de vélo.
    static func profileName(_ profile: CyclingProfile) -> String {
        switch profile {
        case .electricRoad: return value("profile.electricRoad", "Vélo de route électrique")
        case .road: return value("profile.road", "Vélo de route")
        case .regular: return value("profile.regular", "Vélo de ville")
        case .mountain: return value("profile.mountain", "VTT")
        }
    }

    /// Nom lisible d'une direction préférée.
    static func directionName(_ direction: PreferredDirection) -> String {
        switch direction {
        case .any: return value("direction.any", "Indifférente")
        case .north: return value("direction.north", "Nord")
        case .east: return value("direction.east", "Est")
        case .south: return value("direction.south", "Sud")
        case .west: return value("direction.west", "Ouest")
        }
    }

    /// Nom lisible d'une politique de recalcul.
    static func recalculationName(_ policy: RecalculationPolicy) -> String {
        switch policy {
        case .automatic: return value("recalculation.automatic", "Automatique")
        case .ask: return value("recalculation.ask", "Demander d'abord")
        case .never: return value("recalculation.never", "Ne pas recalculer")
        }
    }
}
