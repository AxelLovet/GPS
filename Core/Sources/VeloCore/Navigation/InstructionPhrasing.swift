import Foundation

/// Met en français les consignes de navigation.
///
/// Les formulations sont produites ici, et non reprises telles quelles du moteur
/// de routage, pour trois raisons :
/// - garantir une langue homogène même si le moteur répond partiellement en
///   anglais ;
/// - contrôler la distance annoncée (arrondie à une valeur prononçable) ;
/// - disposer de deux variantes, écrite et vocale, adaptées à chaque support.
///
/// Les chaînes sont regroupées dans ce fichier afin de pouvoir être extraites
/// vers des catalogues de traduction (anglais, allemand) sans toucher aux vues.
public enum InstructionPhrasing {
    // MARK: - Manœuvres

    /// Consigne seule, sans distance : « Tournez à droite ».
    public static func maneuverText(
        _ maneuver: ManeuverType,
        roadName: String? = nil,
        roundaboutExit: Int? = nil
    ) -> String {
        let base: String
        switch maneuver {
        case .depart:
            base = "Départ"
        case .straight:
            base = "Continuez tout droit"
        case .slightLeft:
            base = "Serrez à gauche"
        case .left:
            base = "Tournez à gauche"
        case .sharpLeft:
            base = "Tournez franchement à gauche"
        case .slightRight:
            base = "Serrez à droite"
        case .right:
            base = "Tournez à droite"
        case .sharpRight:
            base = "Tournez franchement à droite"
        case .uTurn:
            base = "Faites demi-tour"
        case .roundaboutEnter:
            if let exit = roundaboutExit, exit > 0 {
                base = "Au rond-point, prenez la \(ordinal(exit)) sortie"
            } else {
                base = "Engagez-vous dans le rond-point"
            }
        case .roundaboutExit:
            base = "Quittez le rond-point"
        case .keepLeft:
            base = "Restez à gauche"
        case .keepRight:
            base = "Restez à droite"
        case .arrive:
            return "Vous êtes arrivé"
        }

        guard let roadName, !roadName.isEmpty, maneuver != .depart else { return base }

        switch maneuver {
        case .straight, .keepLeft, .keepRight:
            return "\(base) sur \(roadName)"
        case .roundaboutEnter, .roundaboutExit:
            return "\(base) vers \(roadName)"
        default:
            return "\(base) sur \(roadName)"
        }
    }

    /// Consigne complète avec distance : « Dans 100 mètres, tournez à droite ».
    public static func instructionText(
        _ instruction: NavigationInstruction,
        distanceToManeuver: Double
    ) -> String {
        let maneuver = maneuverText(
            instruction.maneuver,
            roadName: instruction.roadName,
            roundaboutExit: instruction.roundaboutExitNumber
        )

        if instruction.maneuver == .arrive {
            return distanceToManeuver <= 30
                ? "Vous êtes arrivé"
                : "Arrivée dans \(spokenDistance(distanceToManeuver))"
        }
        if instruction.maneuver == .depart {
            return maneuver
        }
        if distanceToManeuver <= 25 {
            return maneuver
        }
        return "Dans \(spokenDistance(distanceToManeuver)), \(lowercasedFirst(maneuver))"
    }

    /// Variante destinée à la synthèse vocale.
    ///
    /// Identique au texte affiché à une nuance près : les noms de voie sont
    /// omis en dessous de 60 m, car à cette distance la manœuvre est imminente
    /// et une phrase courte est plus utile qu'une phrase complète.
    public static func spokenText(
        _ instruction: NavigationInstruction,
        distanceToManeuver: Double
    ) -> String {
        if distanceToManeuver <= 60, instruction.maneuver != .arrive {
            return maneuverText(
                instruction.maneuver,
                roadName: nil,
                roundaboutExit: instruction.roundaboutExitNumber
            )
        }
        return instructionText(instruction, distanceToManeuver: distanceToManeuver)
    }

    // MARK: - Distances

    /// Distance arrondie à une valeur naturelle à prononcer.
    ///
    /// Personne ne dit « dans 187 mètres » : on annonce 150 ou 200. Les paliers
    /// suivent ce que font les GPS routiers.
    public static func spokenDistance(_ meters: Double) -> String {
        switch meters {
        case ..<20:
            return "quelques mètres"
        case ..<100:
            return "\(Int((meters / 10).rounded()) * 10) mètres"
        case ..<1_000:
            return "\(Int((meters / 50).rounded()) * 50) mètres"
        case ..<10_000:
            let kilometers = (meters / 100).rounded() / 10
            let formatted = String(format: "%.1f", kilometers).replacingOccurrences(of: ".", with: ",")
            return "\(formatted) kilomètres"
        default:
            return "\(Int((meters / 1_000).rounded())) kilomètres"
        }
    }

    /// Distance affichée à l'écran, plus précise que la version parlée.
    public static func displayDistance(_ meters: Double) -> String {
        if meters < 1_000 {
            return "\(Int(meters.rounded())) m"
        }
        let kilometers = meters / 1_000
        if kilometers < 100 {
            return String(format: "%.1f km", kilometers).replacingOccurrences(of: ".", with: ",")
        }
        return String(format: "%.0f km", kilometers)
    }

    /// Durée affichée : « 1 h 25 » ou « 42 min ».
    public static func displayDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, minutes)
    }

    /// Vitesse affichée en km/h à partir d'une vitesse en m/s.
    public static func displaySpeed(metersPerSecond: Double) -> String {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "—" }
        let kilometersPerHour = metersPerSecond * 3.6
        return String(format: "%.1f", kilometersPerHour).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Écarts et avertissements

    /// Phrase décrivant l'écart entre distance obtenue et distance demandée.
    public static func distanceDeviationText(route: CyclingRoute) -> String? {
        guard let requested = route.requestedDistance, requested > 0 else { return nil }
        let deviation = (route.distance - requested) / requested
        guard abs(deviation) > RouteScorer.distanceTolerance else { return nil }
        let percentage = Int((abs(deviation) * 100).rounded())
        let direction = deviation > 0 ? "de plus" : "de moins"
        return "\(percentage) % \(direction) que les \(displayDistance(requested)) demandés"
    }

    /// Libellé d'un avertissement de circuit.
    public static func warningText(_ warning: RouteWarning) -> String {
        switch warning {
        case .distanceOffTarget: return "Distance éloignée de votre demande"
        case .loopNotClosed: return "L'arrivée n'est pas exactement au départ"
        case .unpavedSections: return "Portions non goudronnées"
        case .gravelSections: return "Portions en gravier"
        case .repeatedSections: return "Certaines routes sont empruntées deux fois"
        case .containsUTurn: return "Contient un demi-tour"
        case .steepClimbs: return "Montées soutenues"
        }
    }

    // MARK: - Utilitaires

    static func ordinal(_ value: Int) -> String {
        value == 1 ? "1re" : "\(value)e"
    }

    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).lowercased() + text.dropFirst()
    }
}
