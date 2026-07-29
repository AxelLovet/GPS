import Foundation

/// Type de vélo, qui détermine le profil de routage demandé au moteur.
public enum CyclingProfile: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Vélo de route électrique — profil par défaut de la première version.
    case electricRoad
    /// Vélo de route musculaire.
    case road
    /// Vélo de ville / polyvalent.
    case regular
    /// VTT, accepte les chemins.
    case mountain

    public var id: String { rawValue }

    /// Identifiant de profil attendu par OpenRouteService.
    ///
    /// `cycling-electric` modélise l'assistance électrique : les durées en
    /// montée y sont sensiblement plus réalistes que celles de `cycling-road`
    /// pour un vélo à assistance, ce qui améliore directement l'heure d'arrivée
    /// estimée affichée pendant la navigation.
    public var routingProfileIdentifier: String {
        switch self {
        case .electricRoad: return "cycling-electric"
        case .road: return "cycling-road"
        case .regular: return "cycling-regular"
        case .mountain: return "cycling-mountain"
        }
    }

    /// Vitesse moyenne indicative en km/h, utilisée uniquement comme repli
    /// lorsque le moteur ne fournit pas de durée.
    public var indicativeSpeedKilometersPerHour: Double {
        switch self {
        case .electricRoad: return 25
        case .road: return 22
        case .regular: return 16
        case .mountain: return 14
        }
    }

    /// Coefficient MET moyen, pour l'estimation des calories.
    public var metabolicEquivalent: Double {
        switch self {
        case .electricRoad: return 5.0
        case .road: return 8.0
        case .regular: return 6.0
        case .mountain: return 8.5
        }
    }
}

/// Orientation de départ souhaitée pour la boucle.
public enum PreferredDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    case any, north, east, south, west

    public var id: String { rawValue }

    /// Cap central en degrés, ou `nil` si l'utilisateur est indifférent.
    public var bearing: Double? {
        switch self {
        case .any: return nil
        case .north: return 0
        case .east: return 90
        case .south: return 180
        case .west: return 270
        }
    }
}

/// Préférences de calcul d'itinéraire choisies par l'utilisateur.
public struct RoutingPreferences: Codable, Hashable, Sendable {
    public var profile: CyclingProfile
    /// Éviter les revêtements non goudronnés.
    public var avoidUnpavedSurfaces: Bool
    /// Refuser explicitement le gravier (plus strict que `avoidUnpavedSurfaces`).
    public var rejectGravel: Bool
    /// Privilégier les pistes et bandes cyclables.
    public var preferCyclePaths: Bool
    /// Éviter les routes à fort trafic.
    public var avoidHighTrafficRoads: Bool
    /// Éviter les fortes montées.
    public var avoidSteepClimbs: Bool
    /// Direction de départ préférée.
    public var preferredDirection: PreferredDirection

    public init(
        profile: CyclingProfile = .electricRoad,
        avoidUnpavedSurfaces: Bool = true,
        rejectGravel: Bool = false,
        preferCyclePaths: Bool = true,
        avoidHighTrafficRoads: Bool = true,
        avoidSteepClimbs: Bool = false,
        preferredDirection: PreferredDirection = .any
    ) {
        self.profile = profile
        self.avoidUnpavedSurfaces = avoidUnpavedSurfaces
        self.rejectGravel = rejectGravel
        self.preferCyclePaths = preferCyclePaths
        self.avoidHighTrafficRoads = avoidHighTrafficRoads
        self.avoidSteepClimbs = avoidSteepClimbs
        self.preferredDirection = preferredDirection
    }

    /// Préférences par défaut : vélo de route électrique, routes goudronnées,
    /// pistes cyclables privilégiées.
    public static let `default` = RoutingPreferences()

    /// Pente maximale tolérée en pourcentage avant qu'un itinéraire soit signalé.
    public var maximumComfortableGradient: Double { avoidSteepClimbs ? 8 : 14 }
}
