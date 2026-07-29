import Foundation

/// Structures de décodage de la réponse GeoJSON d'OpenRouteService.
///
/// Volontairement internes : elles ne doivent jamais fuir hors du module de
/// routage. `OpenRouteServiceClient` les convertit immédiatement en
/// `CyclingRoute`, qui est le seul type connu du reste de l'application.
enum ORS {
    struct DirectionsResponse: Decodable {
        let features: [Feature]
    }

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable {
        /// `[[longitude, latitude, altitude?], …]` — l'ordre longitude/latitude
        /// est celui de GeoJSON, inverse de la convention CoreLocation.
        let coordinates: [[Double]]
    }

    struct Properties: Decodable {
        let segments: [Segment]?
        let summary: Summary?
        let ascent: Double?
        let descent: Double?
        let extras: Extras?
    }

    struct Summary: Decodable {
        let distance: Double?
        let duration: Double?
    }

    struct Segment: Decodable {
        let distance: Double?
        let duration: Double?
        let steps: [Step]?
    }

    struct Step: Decodable {
        let distance: Double
        let duration: Double
        let type: Int
        let instruction: String?
        let name: String?
        /// `[indexDébut, indexFin]` dans la polyligne complète.
        let wayPoints: [Int]
        let exitNumber: Int?

        enum CodingKeys: String, CodingKey {
            case distance, duration, type, instruction, name
            case wayPoints = "way_points"
            case exitNumber = "exit_number"
        }
    }

    struct Extras: Decodable {
        let surface: ExtraBlock?
        let waytype: ExtraBlock?
        let steepness: ExtraBlock?
    }

    struct ExtraBlock: Decodable {
        /// Chaque entrée vaut `[indexDébut, indexFin, valeur]`.
        let values: [[Int]]
    }

    /// Corps d'erreur renvoyé par ORS lorsque la requête échoue.
    struct ErrorResponse: Decodable {
        struct Payload: Decodable {
            let code: Int?
            let message: String?
        }
        let error: PayloadOrMessage

        /// ORS renvoie parfois `"error": {"code":…, "message":…}` et parfois
        /// `"error": "texte"`. Les deux formes sont acceptées.
        enum PayloadOrMessage: Decodable {
            case structured(Payload)
            case text(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let payload = try? container.decode(Payload.self) {
                    self = .structured(payload)
                } else {
                    self = .text(try container.decode(String.self))
                }
            }

            var message: String {
                switch self {
                case .structured(let payload): return payload.message ?? "erreur inconnue"
                case .text(let text): return text
                }
            }

            var code: Int? {
                switch self {
                case .structured(let payload): return payload.code
                case .text: return nil
                }
            }
        }
    }
}
