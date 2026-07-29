import Foundation

/// Action de récupération proposée à l'utilisateur en réponse à une erreur.
///
/// Le cœur applicatif décide *quelle* action a du sens ; la couche interface
/// décide comment la présenter (bouton, lien vers les Réglages iOS…).
public enum RecoveryAction: String, Sendable, Hashable {
    case retry
    case changeDistance
    case changeStartingPoint
    case openSettings
    case openAppSettings
    case configureAPIKey
    case useSavedRoute
    case enableDemoMode
    case none
}

/// Toutes les erreurs remontées à l'utilisateur par VéloBoucle.
///
/// Les messages sont rédigés en français, sans jargon, et chaque cas propose au
/// moins une action possible. Aucun message ne contient de clé API ni de
/// position précise.
public enum VeloError: Error, Hashable, Sendable {
    // Réseau et moteur de routage
    case noInternetConnection
    case requestTimedOut
    case routingEngineUnavailable(statusCode: Int?)
    case missingAPIKey
    case invalidAPIKey
    case quotaExceeded
    case invalidRoutingResponse(reason: String)

    // Génération de boucles
    case noRouteFound
    case loopDistanceUnreachable(requested: Double, best: Double)
    case allCandidatesRejected

    // Localisation
    case locationPermissionDenied
    case locationPermissionRestricted
    case locationUnavailable
    case locationAccuracyReduced
    case locationTimedOut

    // Navigation et enregistrement
    case navigationInterrupted
    case rideRecoveryFailed(reason: String)
    case persistenceFailure(reason: String)
    case gpxParsingFailed(reason: String)

    /// Titre court, adapté à un en-tête d'alerte.
    public var title: String {
        switch self {
        case .noInternetConnection: return "Pas de connexion"
        case .requestTimedOut: return "Délai dépassé"
        case .routingEngineUnavailable: return "Service de calcul indisponible"
        case .missingAPIKey: return "Clé d'accès manquante"
        case .invalidAPIKey: return "Clé d'accès refusée"
        case .quotaExceeded: return "Limite d'utilisation atteinte"
        case .invalidRoutingResponse: return "Réponse inattendue"
        case .noRouteFound: return "Aucun circuit trouvé"
        case .loopDistanceUnreachable: return "Distance difficile à atteindre"
        case .allCandidatesRejected: return "Aucun circuit satisfaisant"
        case .locationPermissionDenied: return "Localisation refusée"
        case .locationPermissionRestricted: return "Localisation restreinte"
        case .locationUnavailable: return "Position indisponible"
        case .locationAccuracyReduced: return "Position peu précise"
        case .locationTimedOut: return "Position introuvable"
        case .navigationInterrupted: return "Navigation interrompue"
        case .rideRecoveryFailed: return "Sortie non récupérée"
        case .persistenceFailure: return "Enregistrement impossible"
        case .gpxParsingFailed: return "Fichier GPX illisible"
        }
    }

    /// Explication en français, orientée vers ce que l'utilisateur peut faire.
    public var message: String {
        switch self {
        case .noInternetConnection:
            return "Votre iPhone n'est pas connecté à Internet. Une connexion est nécessaire pour calculer un nouveau circuit, mais pas pour suivre un circuit déjà chargé ni pour consulter votre historique."
        case .requestTimedOut:
            return "Le calcul du circuit a pris trop de temps. La connexion est peut-être lente ou le service momentanément surchargé."
        case .routingEngineUnavailable(let statusCode):
            if let statusCode {
                return "Le service de calcul d'itinéraires ne répond pas correctement (code \(statusCode)). Réessayez dans quelques instants."
            }
            return "Le service de calcul d'itinéraires ne répond pas. Réessayez dans quelques instants."
        case .missingAPIKey:
            return "Aucune clé d'accès OpenRouteService n'est configurée. Sans elle, l'application ne peut pas calculer de nouveaux circuits. Vous pouvez tout de même essayer le mode démonstration."
        case .invalidAPIKey:
            return "La clé d'accès configurée a été refusée par OpenRouteService. Vérifiez qu'elle a été copiée en entier, sans espace."
        case .quotaExceeded:
            return "Le nombre de calculs autorisés pour aujourd'hui est atteint. La limite se réinitialise chaque jour. En attendant, vous pouvez refaire un circuit déjà enregistré."
        case .invalidRoutingResponse(let reason):
            return "La réponse du service de calcul n'a pas pu être lue (\(reason))."
        case .noRouteFound:
            return "Aucun itinéraire cyclable n'a pu être calculé depuis ce point de départ. Essayez de partir d'un endroit plus proche d'une route ouverte aux vélos."
        case .loopDistanceUnreachable(let requested, let best):
            // Virgule décimale : les nombres affichés doivent respecter la
            // convention francophone, ce que `String(format:)` ne fait pas seul.
            let requestedKm = String(format: "%.0f", requested / 1000)
            let bestKm = String(format: "%.1f", best / 1000)
                .replacingOccurrences(of: ".", with: ",")
            return "Aucune boucle de \(requestedKm) km n'a pu être trouvée ici. Le circuit le plus proche fait \(bestKm) km. Vous pouvez l'accepter, modifier la distance ou changer de point de départ."
        case .allCandidatesRejected:
            return "Les circuits calculés ne respectaient pas vos préférences (revêtement, pistes cyclables, dénivelé). Assouplissez vos réglages ou changez de distance."
        case .locationPermissionDenied:
            return "VéloBoucle a besoin de votre position pour placer le départ de la boucle et vous guider. Vous pouvez l'autoriser dans les Réglages d'iOS, ou choisir un point de départ manuellement sur la carte."
        case .locationPermissionRestricted:
            return "L'accès à la localisation est bloqué sur cet iPhone, probablement par un réglage de temps d'écran ou une restriction d'entreprise. Vous pouvez choisir un point de départ manuellement sur la carte."
        case .locationUnavailable:
            return "Votre position n'a pas pu être déterminée. Placez-vous à l'extérieur, à l'écart des bâtiments, puis réessayez."
        case .locationAccuracyReduced:
            return "La position précise est désactivée pour VéloBoucle. Le guidage risque d'être imprécis. Activez « Position exacte » dans les Réglages pour une navigation fiable."
        case .locationTimedOut:
            return "Aucune position n'a été reçue à temps. Le signal GPS est peut-être trop faible à cet endroit."
        case .navigationInterrupted:
            return "La navigation s'est interrompue. Votre sortie a été conservée et peut être reprise."
        case .rideRecoveryFailed(let reason):
            return "La sortie précédente n'a pas pu être récupérée (\(reason))."
        case .persistenceFailure(let reason):
            return "L'enregistrement sur l'iPhone a échoué (\(reason)). Exportez votre sortie en GPX pour ne pas la perdre."
        case .gpxParsingFailed(let reason):
            return "Ce fichier GPX n'a pas pu être lu (\(reason)). Vérifiez qu'il contient bien une trace ou un itinéraire."
        }
    }

    /// Actions proposées, dans l'ordre de pertinence.
    public var recoveryActions: [RecoveryAction] {
        switch self {
        case .noInternetConnection, .requestTimedOut, .routingEngineUnavailable:
            return [.retry, .useSavedRoute]
        case .missingAPIKey:
            return [.configureAPIKey, .enableDemoMode]
        case .invalidAPIKey:
            return [.configureAPIKey]
        case .quotaExceeded:
            return [.useSavedRoute]
        case .invalidRoutingResponse, .noRouteFound:
            return [.retry, .changeStartingPoint]
        case .loopDistanceUnreachable:
            return [.changeDistance, .changeStartingPoint, .retry]
        case .allCandidatesRejected:
            return [.openSettings, .changeDistance, .retry]
        case .locationPermissionDenied, .locationAccuracyReduced:
            return [.openAppSettings, .changeStartingPoint]
        case .locationPermissionRestricted:
            return [.changeStartingPoint]
        case .locationUnavailable, .locationTimedOut:
            return [.retry, .changeStartingPoint]
        case .navigationInterrupted:
            return [.retry]
        case .rideRecoveryFailed, .persistenceFailure, .gpxParsingFailed:
            return [.none]
        }
    }

    /// Vrai si réessayer immédiatement a une chance d'aboutir.
    public var isTransient: Bool {
        switch self {
        case .requestTimedOut, .routingEngineUnavailable, .locationUnavailable,
             .locationTimedOut, .noInternetConnection:
            return true
        default:
            return false
        }
    }
}

extension VeloError: LocalizedError {
    public var errorDescription: String? { title }
    public var failureReason: String? { message }
}
