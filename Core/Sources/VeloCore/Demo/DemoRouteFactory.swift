import Foundation

/// Fabrique de circuits synthétiques pour le mode démonstration.
///
/// **Ce code ne sert jamais en production.** Il permet de faire fonctionner
/// l'application entière — génération, comparaison, navigation, enregistrement,
/// export — dans le simulateur iOS et dans les tests, sans réseau et sans clé
/// API. Tout ce qui relève de la démonstration est regroupé dans ce dossier
/// pour qu'aucune donnée simulée ne puisse se glisser dans un parcours réel.
public enum DemoRouteFactory {
    /// Place Saint-François, Lausanne — point de départ des données de démonstration.
    public static let lausanne = GeographicCoordinate(latitude: 46.5197, longitude: 6.6323)

    /// Construit une boucle fermée d'une longueur approximative donnée.
    ///
    /// La forme est un polygone irrégulier — les sommets sont perturbés par un
    /// générateur pseudo-aléatoire déterministe — puis interpolé et lissé afin
    /// de ressembler à un tracé routier plutôt qu'à une figure géométrique.
    ///
    /// - Parameters:
    ///   - origin: départ et arrivée.
    ///   - targetDistance: longueur visée en mètres.
    ///   - seed: graine ; deux graines différentes donnent deux circuits différents.
    ///   - profile: profil, qui détermine la durée estimée.
    public static func makeLoop(
        origin: GeographicCoordinate,
        targetDistance: Double,
        seed: Int,
        profile: CyclingProfile = .electricRoad
    ) -> CyclingRoute {
        var generator = DeterministicGenerator(seed: UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9)

        let vertexCount = 6 + Int(generator.next(upperBound: 4))
        // Rayon donnant approximativement la longueur voulue une fois le
        // polygone interpolé (voir WaypointLoopPlanner pour la relation).
        let perimeterFactor = 2 * Double(vertexCount) * sin(.pi / Double(vertexCount))
        let baseRadius = targetDistance / perimeterFactor

        let startAngle = generator.nextDouble() * 360
        var vertices: [GeographicCoordinate] = []
        for index in 0..<vertexCount {
            let angle = Geodesy.normalizedBearing(
                startAngle + 360 * Double(index) / Double(vertexCount)
            )
            // Rayon perturbé de ±25 % : le circuit n'est pas un cercle parfait.
            let radius = baseRadius * (0.75 + 0.5 * generator.nextDouble())
            vertices.append(Geodesy.destination(from: origin, distance: radius, bearing: angle))
        }

        // Le départ est inséré comme premier et dernier sommet : la boucle se
        // ferme exactement, comme l'exige le cahier des charges.
        var polygon = [origin] + vertices + [origin]
        polygon = smooth(polygon, passes: 2)

        let coordinates = interpolate(polygon, spacing: 25)
        let withAltitude = addSyntheticAltitude(to: coordinates, generator: &generator)
        let instructions = makeInstructions(for: withAltitude, polygonSize: polygon.count)

        let distance = Geodesy.polylineLength(withAltitude)
        let duration = distance / (profile.indicativeSpeedKilometersPerHour * 1000 / 3600)
        let (ascent, descent) = elevationTotals(of: withAltitude)

        return CyclingRoute(
            coordinates: withAltitude,
            distance: distance,
            duration: duration,
            ascent: ascent,
            descent: descent,
            instructions: instructions,
            segments: makeSegments(for: withAltitude),
            profile: profile,
            requestedDistance: targetDistance
        )
    }

    // MARK: - Géométrie

    /// Lissage de Chaikin : arrondit les angles du polygone.
    private static func smooth(
        _ points: [GeographicCoordinate],
        passes: Int
    ) -> [GeographicCoordinate] {
        var current = points
        for _ in 0..<passes {
            guard current.count >= 3 else { break }
            var result: [GeographicCoordinate] = [current[0]]
            for index in 0..<(current.count - 1) {
                let a = current[index]
                let b = current[index + 1]
                result.append(interpolated(a, b, 0.25))
                result.append(interpolated(a, b, 0.75))
            }
            result.append(current[current.count - 1])
            current = result
        }
        return current
    }

    private static func interpolated(
        _ a: GeographicCoordinate,
        _ b: GeographicCoordinate,
        _ fraction: Double
    ) -> GeographicCoordinate {
        GeographicCoordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    /// Rééchantillonne la polyligne à pas régulier.
    private static func interpolate(
        _ points: [GeographicCoordinate],
        spacing: Double
    ) -> [GeographicCoordinate] {
        guard points.count >= 2, spacing > 0 else { return points }
        var result: [GeographicCoordinate] = [points[0]]

        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let segmentLength = Geodesy.distance(from: start, to: end)
            let steps = max(Int(segmentLength / spacing), 1)
            for step in 1...steps {
                result.append(interpolated(start, end, Double(step) / Double(steps)))
            }
        }
        return result
    }

    private static func addSyntheticAltitude(
        to coordinates: [GeographicCoordinate],
        generator: inout DeterministicGenerator
    ) -> [GeographicCoordinate] {
        let baseAltitude = 495.0  // altitude approximative de Lausanne
        let amplitude = 40 + generator.nextDouble() * 60
        let phase = generator.nextDouble() * 2 * .pi
        let count = Double(coordinates.count)

        return coordinates.enumerated().map { index, coordinate in
            let position = Double(index) / max(count - 1, 1)
            // Deux harmoniques : une montée franche et une ondulation, ce qui
            // donne un profil crédible et un dénivelé non nul.
            let altitude = baseAltitude
                + amplitude * sin(position * 2 * .pi + phase)
                + amplitude * 0.4 * sin(position * 6 * .pi)
            return GeographicCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitude: altitude
            )
        }
    }

    private static func elevationTotals(
        of coordinates: [GeographicCoordinate]
    ) -> (ascent: Double, descent: Double) {
        var ascent = 0.0
        var descent = 0.0
        for index in 1..<max(coordinates.count, 1) {
            guard let previous = coordinates[index - 1].altitude,
                  let current = coordinates[index].altitude else { continue }
            let delta = current - previous
            if delta > 0 { ascent += delta } else { descent += -delta }
        }
        return (ascent, descent)
    }

    /// Relie des points de passage par un tracé sinueux, comme le ferait un
    /// vrai réseau routier.
    ///
    /// Un moteur de routage réel ne relie jamais deux points en ligne droite :
    /// l'itinéraire suit les routes existantes et mesure typiquement 20 à 30 %
    /// de plus que la distance à vol d'oiseau. Reproduire ce détour est
    /// indispensable pour que le mode démonstration exerce réellement la
    /// génération de boucles — avec des segments rectilignes, tous les circuits
    /// polygonaux seraient systématiquement trop courts et donc écartés.
    ///
    /// L'amplitude des méandres est ajustée par dichotomie pour atteindre le
    /// facteur de détour visé.
    public static func connect(
        waypoints: [GeographicCoordinate],
        detourFactor: Double = WaypointLoopPlanner.detourFactor,
        spacing: Double = 25
    ) -> [GeographicCoordinate] {
        guard waypoints.count >= 2 else { return waypoints }

        let straightLength = Geodesy.polylineLength(waypoints)
        guard straightLength > 0, detourFactor > 1 else {
            return interpolate(waypoints, spacing: spacing)
        }
        let targetLength = straightLength * detourFactor

        var low = 0.0
        var high = 0.5
        var best = meander(waypoints, amplitudeRatio: high, spacing: spacing)

        for _ in 0..<14 {
            let middle = (low + high) / 2
            let candidate = meander(waypoints, amplitudeRatio: middle, spacing: spacing)
            let length = Geodesy.polylineLength(candidate)
            best = candidate
            if length < targetLength { low = middle } else { high = middle }
        }
        return best
    }

    /// Trace un chemin ondulant entre les points de passage.
    private static func meander(
        _ waypoints: [GeographicCoordinate],
        amplitudeRatio: Double,
        spacing: Double
    ) -> [GeographicCoordinate] {
        var result: [GeographicCoordinate] = []

        for index in 1..<waypoints.count {
            let start = waypoints[index - 1]
            let end = waypoints[index]
            let segmentLength = Geodesy.distance(from: start, to: end)
            guard segmentLength > 0 else { continue }

            let bearing = Geodesy.bearing(from: start, to: end)
            let perpendicular = Geodesy.normalizedBearing(bearing + 90)
            let amplitude = segmentLength * amplitudeRatio
            let steps = max(Int(segmentLength / spacing), 2)
            // Le sens de l'ondulation alterne d'un segment à l'autre, ce qui
            // évite un tracé en spirale.
            let sign: Double = index.isMultiple(of: 2) ? 1 : -1

            let range = index == 1 ? 0...steps : 1...steps
            for step in range {
                let fraction = Double(step) / Double(steps)
                let base = interpolated(start, end, fraction)
                // Deux périodes complètes, nulles aux extrémités : les points de
                // passage restent exactement sur le tracé.
                let offset = sign * amplitude * sin(fraction * 2 * .pi * 2)
                result.append(
                    offset == 0
                        ? base
                        : Geodesy.destination(
                            from: base, distance: abs(offset),
                            bearing: offset > 0 ? perpendicular : perpendicular + 180
                        )
                )
            }
        }
        return result
    }

    // MARK: - Consignes

    /// Déduit des consignes de navigation de la géométrie du tracé.
    ///
    /// À chaque point, on mesure le changement de cap sur une fenêtre de
    /// quelques dizaines de mètres ; au-delà d'un seuil, une manœuvre est
    /// insérée. C'est exactement ce que fait un moteur de routage à partir de la
    /// topologie du réseau, en plus fruste.
    static func makeInstructions(
        for coordinates: [GeographicCoordinate],
        polygonSize: Int = 0
    ) -> [NavigationInstruction] {
        guard coordinates.count > 8 else { return [] }

        let window = 3
        var turnIndices: [(index: Int, delta: Double)] = []
        var lastTurnIndex = 0

        for index in window..<(coordinates.count - window) {
            let incoming = Geodesy.bearing(
                from: coordinates[index - window],
                to: coordinates[index]
            )
            let outgoing = Geodesy.bearing(
                from: coordinates[index],
                to: coordinates[index + window]
            )
            let delta = Geodesy.bearingDelta(from: incoming, to: outgoing)

            // Un seuil de 30° et un espacement minimal évitent d'émettre une
            // consigne à chaque léger virage.
            guard abs(delta) > 30, index - lastTurnIndex > 12 else { continue }
            turnIndices.append((index, delta))
            lastTurnIndex = index
        }

        var instructions: [NavigationInstruction] = []
        var previousIndex = 0
        let names = ["Route de Berne", "Chemin des Vignes", "Avenue du Lac",
                     "Route de la Vallée", "Piste cyclable du Léman", "Chemin de Praz"]

        func append(maneuver: ManeuverType, to index: Int) {
            let slice = Array(coordinates[previousIndex...index])
            let distance = Geodesy.polylineLength(slice)
            instructions.append(
                NavigationInstruction(
                    maneuver: maneuver,
                    roadName: names[instructions.count % names.count],
                    distance: distance,
                    duration: distance / 6.5,
                    startPointIndex: previousIndex,
                    endPointIndex: index
                )
            )
            previousIndex = index
        }

        append(maneuver: .depart, to: min(turnIndices.first?.index ?? 5, coordinates.count - 1))

        for turn in turnIndices.dropFirst() {
            append(maneuver: maneuver(forDelta: turn.delta), to: turn.index)
        }
        append(maneuver: .arrive, to: coordinates.count - 1)

        return instructions
    }

    private static func maneuver(forDelta delta: Double) -> ManeuverType {
        switch delta {
        case ..<(-110): return .sharpLeft
        case ..<(-50): return .left
        case ..<(-25): return .slightLeft
        case 25..<50: return .slightRight
        case 50..<110: return .right
        case 110...: return .sharpRight
        default: return .straight
        }
    }

    private static func makeSegments(
        for coordinates: [GeographicCoordinate]
    ) -> [RouteSegment] {
        guard coordinates.count > 4 else { return [] }
        // Trois tronçons : bitume, piste cyclable, bitume. Suffisant pour que
        // l'écran de comparaison affiche des pourcentages plausibles.
        let third = coordinates.count / 3
        func length(_ range: ClosedRange<Int>) -> Double {
            Geodesy.polylineLength(Array(coordinates[range]))
        }
        return [
            RouteSegment(
                startPointIndex: 0, endPointIndex: third,
                surface: .paved, wayKind: .road, distance: length(0...third)
            ),
            RouteSegment(
                startPointIndex: third, endPointIndex: third * 2,
                surface: .paved, wayKind: .cyclePath, distance: length(third...(third * 2))
            ),
            RouteSegment(
                startPointIndex: third * 2, endPointIndex: coordinates.count - 1,
                surface: .paved, wayKind: .road,
                distance: length((third * 2)...(coordinates.count - 1))
            )
        ]
    }
}

/// Générateur pseudo-aléatoire déterministe (SplitMix64).
///
/// Un générateur reproductible est indispensable : les tests doivent produire
/// exactement les mêmes circuits d'une exécution à l'autre, et l'utilisateur du
/// mode démonstration doit retrouver le même parcours.
struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else { return 0 }
        return next() % upperBound
    }

    /// Valeur dans [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
