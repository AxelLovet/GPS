import Foundation

/// Filtre les relevés GPS manifestement faux avant qu'ils ne polluent la trace.
///
/// Le GPS d'un iPhone produit régulièrement des points aberrants : au démarrage
/// (avant la convergence), à l'ombre d'un bâtiment, à la sortie d'un tunnel. Les
/// laisser passer gonfle artificiellement la distance et la vitesse maximale, et
/// dessine des zigzags sur la carte.
///
/// Le filtre est délibérément **conservateur** : il ne lisse pas la trace, il
/// se contente d'écarter l'impossible. Un lissage agressif raccourcirait la
/// distance réelle du cycliste, ce qui serait une erreur plus grave que de
/// laisser passer un peu de bruit.
public struct LocationFilter: Sendable {
    /// Incertitude horizontale au-delà de laquelle un relevé est rejeté.
    ///
    /// 65 m correspond à une position calculée sur les seuls réseaux Wi-Fi ou
    /// cellulaire : inutilisable pour une trace, mais encore acceptable pour
    /// centrer une carte.
    public var maximumHorizontalAccuracy: Double
    /// Vitesse au-delà de laquelle un déplacement est jugé impossible à vélo, en m/s.
    /// 25 m/s = 90 km/h : au-dessus, c'est un saut GPS ou un trajet en voiture.
    public var maximumPlausibleSpeed: Double
    /// Déplacement minimal pour être comptabilisé, en mètres.
    /// En dessous, c'est le bruit du récepteur à l'arrêt.
    public var minimumDisplacement: Double
    /// Écart d'altitude minimal pris en compte pour le dénivelé, en mètres.
    /// L'altitude GPS est bruitée de ±10 m ; un seuil de 3 m évite d'accumuler
    /// des centaines de mètres de dénivelé sur un parcours plat.
    public var minimumAltitudeChange: Double

    public init(
        maximumHorizontalAccuracy: Double = 65,
        maximumPlausibleSpeed: Double = 25,
        minimumDisplacement: Double = 3,
        minimumAltitudeChange: Double = 3
    ) {
        self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
        self.maximumPlausibleSpeed = maximumPlausibleSpeed
        self.minimumDisplacement = minimumDisplacement
        self.minimumAltitudeChange = minimumAltitudeChange
    }

    /// Raison pour laquelle un relevé a été écarté.
    public enum Rejection: String, Sendable, Equatable {
        case invalidCoordinate
        case poorAccuracy
        case implausibleSpeed
        case notMoving
        case outOfOrder
    }

    /// Décide si un relevé peut rejoindre la trace.
    ///
    /// - Parameters:
    ///   - sample: relevé à examiner.
    ///   - previous: dernier relevé accepté, s'il y en a un.
    /// - Returns: `nil` si le relevé est accepté, sinon le motif du rejet.
    public func rejectionReason(
        for sample: LocationSample,
        previous: LocationSample?
    ) -> Rejection? {
        guard sample.coordinate.isValid else { return .invalidCoordinate }
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return .poorAccuracy
        }

        guard let previous else { return nil }

        let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
        // Un relevé antérieur au précédent arrive lorsque CoreLocation vide un
        // tampon accumulé en arrière-plan ; il ne doit pas être intercalé.
        guard interval > 0 else { return .outOfOrder }

        let displacement = Geodesy.distance(from: previous.coordinate, to: sample.coordinate)

        // Un saut est jugé sur la vitesse qu'il impliquerait, mais on tolère
        // l'imprécision annoncée : deux relevés à ±30 m peuvent sembler éloignés
        // de 60 m sans que le cycliste ait bougé.
        let tolerance = max(sample.horizontalAccuracy, previous.horizontalAccuracy)
        let correctedDisplacement = max(displacement - tolerance, 0)
        if correctedDisplacement / interval > maximumPlausibleSpeed {
            return .implausibleSpeed
        }

        if displacement < minimumDisplacement { return .notMoving }

        return nil
    }
}
