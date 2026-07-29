import Foundation

/// Manœuvre à effectuer, indépendante du moteur de routage.
///
/// Les valeurs brutes d'OpenRouteService sont traduites vers ce type par
/// `ManeuverType.init(openRouteServiceCode:)`, de sorte que le reste de
/// l'application ignore totalement le format du fournisseur.
public enum ManeuverType: String, Codable, Sendable, CaseIterable {
    case depart
    case straight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn
    case roundaboutEnter
    case roundaboutExit
    case keepLeft
    case keepRight
    case arrive

    /// Traduction des codes numériques d'OpenRouteService.
    /// Voir `docs/ROUTING_ENGINE.md` pour la table complète.
    public init(openRouteServiceCode code: Int) {
        switch code {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .sharpLeft
        case 3: self = .sharpRight
        case 4: self = .slightLeft
        case 5: self = .slightRight
        case 6: self = .straight
        case 7: self = .roundaboutEnter
        case 8: self = .roundaboutExit
        case 9: self = .uTurn
        case 10: self = .arrive
        case 11: self = .depart
        case 12: self = .keepLeft
        case 13: self = .keepRight
        default: self = .straight
        }
    }

    /// Nom du symbole SF Symbols utilisé pour la grande flèche de navigation.
    ///
    /// Défini ici plutôt que dans la couche vue afin que la correspondance
    /// manœuvre → flèche soit couverte par les tests unitaires : une flèche
    /// erronée pendant une navigation à vélo est un problème de sécurité.
    public var symbolName: String {
        switch self {
        case .depart: return "flag.circle.fill"
        case .straight: return "arrow.up"
        case .slightLeft: return "arrow.up.left"
        case .left: return "arrow.turn.up.left"
        case .sharpLeft: return "arrow.uturn.left"
        case .slightRight: return "arrow.up.right"
        case .right: return "arrow.turn.up.right"
        case .sharpRight: return "arrow.uturn.right"
        case .uTurn: return "arrow.uturn.down"
        case .roundaboutEnter: return "arrow.triangle.turn.up.right.circle"
        case .roundaboutExit: return "arrow.triangle.turn.up.right.diamond"
        case .keepLeft: return "arrow.up.left"
        case .keepRight: return "arrow.up.right"
        case .arrive: return "flag.checkered"
        }
    }

    /// Vrai si la manœuvre exige un changement de direction franc.
    ///
    /// Sert à décider d'un retour haptique et d'une annonce vocale anticipée :
    /// on n'annonce pas « continuez tout droit ».
    public var requiresAdvanceWarning: Bool {
        switch self {
        case .straight, .depart, .keepLeft, .keepRight: return false
        default: return true
        }
    }
}

/// Une consigne de navigation rattachée à une portion précise de l'itinéraire.
public struct NavigationInstruction: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Manœuvre à effectuer à la fin de la portion couverte par l'instruction.
    public let maneuver: ManeuverType
    /// Nom de la voie empruntée pendant cette portion, si le moteur le connaît.
    public let roadName: String?
    /// Longueur de la portion couverte, en mètres.
    public let distance: Double
    /// Durée estimée de la portion, en secondes.
    public let duration: TimeInterval
    /// Index, dans la polyligne du circuit, du premier point de la portion.
    public let startPointIndex: Int
    /// Index, dans la polyligne du circuit, du dernier point de la portion.
    public let endPointIndex: Int
    /// Numéro de sortie, pour les ronds-points uniquement.
    public let roundaboutExitNumber: Int?
    /// Texte fourni tel quel par le moteur, conservé pour diagnostic.
    public let rawText: String?

    public init(
        id: UUID = UUID(),
        maneuver: ManeuverType,
        roadName: String?,
        distance: Double,
        duration: TimeInterval,
        startPointIndex: Int,
        endPointIndex: Int,
        roundaboutExitNumber: Int? = nil,
        rawText: String? = nil
    ) {
        self.id = id
        self.maneuver = maneuver
        self.roadName = roadName
        self.distance = distance
        self.duration = duration
        self.startPointIndex = startPointIndex
        self.endPointIndex = endPointIndex
        self.roundaboutExitNumber = roundaboutExitNumber
        self.rawText = rawText
    }
}
