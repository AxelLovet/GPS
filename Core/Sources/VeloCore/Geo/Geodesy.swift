import Foundation

/// Calculs géodésiques sur la sphère terrestre.
///
/// Toutes les fonctions utilisent une approximation sphérique (rayon moyen
/// 6 371 008,8 m). Pour un usage cycliste — des segments de quelques dizaines de
/// mètres à quelques kilomètres — l'écart avec un calcul ellipsoïdal (Vincenty)
/// reste inférieur à 0,5 %, très en deçà de l'incertitude du GPS lui-même. Le
/// gain de simplicité et de coût de calcul justifie ce compromis, d'autant que
/// ces fonctions sont appelées à chaque mise à jour de position pendant la
/// navigation.
public enum Geodesy {
    /// Rayon moyen de la Terre en mètres (IUGG).
    public static let earthRadius: Double = 6_371_008.8

    @inline(__always)
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    @inline(__always)
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Distance orthodromique entre deux points, en mètres.
    ///
    /// Utilise la formule de haversine, numériquement stable pour les très
    /// petites distances — contrairement à la loi des cosinus sphériques, qui
    /// perd toute précision en dessous de quelques mètres et produirait un bruit
    /// inacceptable sur une trace GPS échantillonnée à la seconde.
    public static func distance(from a: GeographicCoordinate, to b: GeographicCoordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(b.longitude - a.longitude)

        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Cap initial de `a` vers `b`, en degrés dans [0, 360), 0 = nord géographique.
    public static func bearing(from a: GeographicCoordinate, to b: GeographicCoordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizedBearing(degrees(atan2(y, x)))
    }

    /// Ramène un cap quelconque dans [0, 360).
    public static func normalizedBearing(_ bearing: Double) -> Double {
        let value = bearing.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Écart angulaire signé le plus court entre deux caps, dans (-180, 180].
    ///
    /// Positif = il faut tourner à droite pour passer de `from` à `to`.
    public static func bearingDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Point situé à `distance` mètres de `origin` dans la direction `bearing`.
    public static func destination(
        from origin: GeographicCoordinate,
        distance: Double,
        bearing: Double
    ) -> GeographicCoordinate {
        let angular = distance / earthRadius
        let lat1 = radians(origin.latitude)
        let lon1 = radians(origin.longitude)
        let theta = radians(bearing)

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(
            sin(theta) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        // Ramène la longitude dans [-180, 180].
        let normalizedLon = (degrees(lon2) + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeographicCoordinate(latitude: degrees(lat2), longitude: normalizedLon)
    }

    /// Longueur cumulée d'une polyligne, en mètres.
    public static func polylineLength(_ coordinates: [GeographicCoordinate]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<coordinates.count {
            total += distance(from: coordinates[index - 1], to: coordinates[index])
        }
        return total
    }

    /// Résultat de la projection d'un point sur un segment.
    public struct SegmentProjection: Equatable, Sendable {
        /// Point du segment le plus proche du point projeté.
        public let point: GeographicCoordinate
        /// Distance perpendiculaire au segment, en mètres.
        public let distance: Double
        /// Position le long du segment, de 0 (début) à 1 (fin).
        public let fraction: Double
    }

    /// Projette `point` sur le segment [`start`, `end`].
    ///
    /// Le calcul est fait dans un plan local équirectangulaire centré sur
    /// `start` : sur des segments d'itinéraire (rarement plus de 200 m), la
    /// déformation est négligeable et cela évite une projection sphérique
    /// coûteuse à chaque mise à jour GPS.
    public static func project(
        _ point: GeographicCoordinate,
        onto start: GeographicCoordinate,
        _ end: GeographicCoordinate
    ) -> SegmentProjection {
        let latScale = radians(1) * earthRadius
        let lonScale = latScale * cos(radians(start.latitude))

        let sx = 0.0, sy = 0.0
        let ex = (end.longitude - start.longitude) * lonScale
        let ey = (end.latitude - start.latitude) * latScale
        let px = (point.longitude - start.longitude) * lonScale
        let py = (point.latitude - start.latitude) * latScale

        let dx = ex - sx, dy = ey - sy
        let lengthSquared = dx * dx + dy * dy

        // Segment dégénéré (deux points confondus) : la projection est le point lui-même.
        guard lengthSquared > 1e-9 else {
            return SegmentProjection(
                point: start,
                distance: distance(from: point, to: start),
                fraction: 0
            )
        }

        let rawFraction = ((px - sx) * dx + (py - sy) * dy) / lengthSquared
        let fraction = min(max(rawFraction, 0), 1)

        let projected = GeographicCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )

        return SegmentProjection(
            point: projected,
            distance: distance(from: point, to: projected),
            fraction: fraction
        )
    }

    /// Barycentre d'un ensemble de coordonnées, pondéré uniformément.
    ///
    /// Passe par les vecteurs cartésiens afin de rester correct de part et
    /// d'autre de l'antiméridien.
    public static func centroid(of coordinates: [GeographicCoordinate]) -> GeographicCoordinate? {
        guard !coordinates.isEmpty else { return nil }
        var x = 0.0, y = 0.0, z = 0.0
        for coordinate in coordinates {
            let lat = radians(coordinate.latitude)
            let lon = radians(coordinate.longitude)
            x += cos(lat) * cos(lon)
            y += cos(lat) * sin(lon)
            z += sin(lat)
        }
        let count = Double(coordinates.count)
        x /= count; y /= count; z /= count

        let hypotenuse = sqrt(x * x + y * y)
        guard hypotenuse > 1e-12 || abs(z) > 1e-12 else { return coordinates.first }
        return GeographicCoordinate(
            latitude: degrees(atan2(z, hypotenuse)),
            longitude: degrees(atan2(y, x))
        )
    }
}
