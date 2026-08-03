import Foundation
import SwiftData
import VeloCore

/// Représentation SwiftData d'une sortie enregistrée.
///
/// Les données volumineuses et structurées — trace GPS, circuit prévu, écarts —
/// sont conservées sous forme de JSON encodé dans un `Data`. Ce choix est
/// délibéré : une trace de sortie compte plusieurs milliers de points, et les
/// modéliser en entités SwiftData liées multiplierait les objets gérés par le
/// contexte sans aucun bénéfice, puisqu'on ne les interroge jamais
/// individuellement. Les champs sur lesquels on trie ou recherche — date, nom,
/// distance — restent en revanche de vrais attributs.
@Model
final class StoredRide {
    // Pas de `#Index` : cette macro SwiftData n'existe qu'à partir d'iOS 18, et
    // l'application cible iOS 17. Le tri par date se fait donc sans index, ce
    // qui est sans conséquence à l'échelle d'un historique personnel.
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var finishedAt: Date

    var distance: Double
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var maximumSpeed: Double
    var ascent: Double
    var descent: Double

    var profileIdentifier: String
    var bodyMassKilograms: Double

    /// Trace GPS encodée (`[LocationSample]`).
    @Attribute(.externalStorage) var trackData: Data
    /// Circuit prévu encodé (`CyclingRoute`), absent pour une sortie libre.
    @Attribute(.externalStorage) var plannedRouteData: Data?
    /// Écarts de parcours encodés (`[RouteDeviation]`).
    var deviationsData: Data?

    init(ride: RecordedRide) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        id = ride.id
        name = ride.name
        startedAt = ride.startedAt
        finishedAt = ride.finishedAt
        distance = ride.statistics.distance
        elapsedTime = ride.statistics.elapsedTime
        movingTime = ride.statistics.movingTime
        maximumSpeed = ride.statistics.maximumSpeed
        ascent = ride.statistics.ascent
        descent = ride.statistics.descent
        profileIdentifier = ride.profile.rawValue
        bodyMassKilograms = ride.bodyMassKilograms
        trackData = try encoder.encode(ride.track)
        plannedRouteData = try ride.plannedRoute.map { try encoder.encode($0) }
        deviationsData = ride.deviations.isEmpty ? nil : try encoder.encode(ride.deviations)
    }

    /// Reconstitue le modèle métier.
    ///
    /// La décodage des données volumineuses est tolérant : si la trace est
    /// illisible — schéma d'une version antérieure, fichier tronqué — la sortie
    /// reste consultable avec ses statistiques, sans sa carte. Perdre le tracé
    /// est préférable à faire disparaître la sortie de l'historique.
    func toRecordedRide() -> RecordedRide {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let track = (try? decoder.decode([LocationSample].self, from: trackData)) ?? []
        let plannedRoute = plannedRouteData.flatMap {
            try? decoder.decode(CyclingRoute.self, from: $0)
        }
        let deviations = deviationsData.flatMap {
            try? decoder.decode([RouteDeviation].self, from: $0)
        } ?? []

        return RecordedRide(
            id: id,
            name: name,
            startedAt: startedAt,
            finishedAt: finishedAt,
            statistics: RideStatistics(
                distance: distance,
                elapsedTime: elapsedTime,
                movingTime: movingTime,
                maximumSpeed: maximumSpeed,
                ascent: ascent,
                descent: descent
            ),
            track: track,
            plannedRoute: plannedRoute,
            deviations: deviations,
            profile: CyclingProfile(rawValue: profileIdentifier) ?? .electricRoad,
            bodyMassKilograms: bodyMassKilograms
        )
    }

    /// Aperçu léger du tracé pour la carte miniature de l'historique.
    ///
    /// Décoder plusieurs milliers de points pour dessiner une vignette de
    /// 80 points de large serait du gaspillage ; on n'en garde qu'un sur `n`.
    func trackPreview(maximumPoints: Int = 120) -> [GeographicCoordinate] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let samples = try? decoder.decode([LocationSample].self, from: trackData),
              !samples.isEmpty else {
            return []
        }
        guard samples.count > maximumPoints else { return samples.map(\.coordinate) }

        // Division arrondie **au supérieur**. Avec une division entière simple,
        // le pas est trop petit et l'échantillonnage dépasse la borne demandée —
        // de peu, mais assez pour rendre la garantie fausse.
        let step = (samples.count + maximumPoints - 1) / maximumPoints
        var result = stride(from: 0, to: samples.count, by: max(step, 1))
            .map { samples[$0].coordinate }
        // Le dernier point est toujours conservé : c'est l'arrivée, et la
        // vignette serait tronquée sans lui. D'où au plus `maximumPoints + 1`.
        if let last = samples.last?.coordinate, result.last != last {
            result.append(last)
        }
        return result
    }
}
