import Foundation

/// Coordonnée géographique WGS 84, indépendante de CoreLocation.
///
/// L'altitude est optionnelle : les traces GPS en fournissent une, les
/// itinéraires calculés seulement lorsque le moteur de routage a été interrogé
/// avec `elevation: true`.
public struct GeographicCoordinate: Hashable, Codable, Sendable {
    /// Latitude en degrés décimaux, entre -90 et 90.
    public var latitude: Double
    /// Longitude en degrés décimaux, entre -180 et 180.
    public var longitude: Double
    /// Altitude en mètres au-dessus du niveau de la mer, si connue.
    public var altitude: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    /// Vrai si la coordonnée est dans les bornes valides et n'est pas le point nul.
    ///
    /// Le point (0, 0) est rejeté volontairement : il se situe dans le golfe de
    /// Guinée et, en pratique, signale presque toujours une valeur non initialisée
    /// renvoyée par une API ou un capteur.
    public var isValid: Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return !(latitude == 0 && longitude == 0)
    }
}

extension GeographicCoordinate: CustomStringConvertible {
    /// Description volontairement arrondie à ~11 m.
    ///
    /// Les journaux de développement ne doivent jamais contenir la position
    /// précise de l'utilisateur (cahier des charges §20). Quatre décimales
    /// suffisent au diagnostic sans identifier une adresse.
    public var description: String {
        String(format: "(%.4f, %.4f)", latitude, longitude)
    }
}
