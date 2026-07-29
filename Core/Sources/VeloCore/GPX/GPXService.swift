import Foundation

#if canImport(FoundationXML)
// Sous Linux, XMLParser vit dans un module distinct.
import FoundationXML
#endif

/// Contenu utile d'un fichier GPX importé.
public struct GPXDocument: Sendable, Equatable {
    public var name: String?
    /// Points de trace (`<trkpt>`), avec horodatage lorsqu'il est présent.
    public var trackPoints: [LocationSample]
    /// Points d'itinéraire planifié (`<rtept>`), sans horodatage.
    public var routePoints: [GeographicCoordinate]

    public init(
        name: String? = nil,
        trackPoints: [LocationSample] = [],
        routePoints: [GeographicCoordinate] = []
    ) {
        self.name = name
        self.trackPoints = trackPoints
        self.routePoints = routePoints
    }

    public var isEmpty: Bool { trackPoints.isEmpty && routePoints.isEmpty }
}

/// Lecture et écriture de fichiers GPX 1.1.
public protocol GPXServicing: Sendable {
    func export(ride: RecordedRide) throws -> Data
    func export(route: CyclingRoute, name: String) throws -> Data
    func parse(data: Data) throws -> GPXDocument
}

/// Implémentation GPX 1.1.
///
/// Le format retenu est volontairement conservateur : `<trk>` pour la trace
/// réellement parcourue, `<rte>` pour le circuit planifié. C'est ce que
/// comprennent Garmin Connect, Strava, Komoot et les compteurs Garmin Edge,
/// ce qui est le but recherché — pouvoir transférer une sortie ailleurs.
public struct GPXService: GPXServicing {
    public static let namespace = "http://www.topografix.com/GPX/1/1"
    public static let creator = "VéloBoucle"

    public init() {}

    // MARK: - Écriture

    public func export(ride: RecordedRide) throws -> Data {
        var xml = header()

        xml += "  <metadata>\n"
        xml += "    <name>\(escape(ride.name))</name>\n"
        xml += "    <time>\(Self.timestampFormatter.string(from: ride.startedAt))</time>\n"
        xml += "    <desc>\(escape(summaryDescription(of: ride)))</desc>\n"
        xml += "  </metadata>\n"

        if let planned = ride.plannedRoute {
            xml += routeElement(coordinates: planned.coordinates, name: "Circuit prévu")
        }

        xml += "  <trk>\n"
        xml += "    <name>\(escape(ride.name))</name>\n"
        xml += "    <type>cycling</type>\n"
        xml += "    <trkseg>\n"
        for sample in ride.track {
            xml += trackPointElement(sample)
        }
        xml += "    </trkseg>\n"
        xml += "  </trk>\n"
        xml += "</gpx>\n"

        guard let data = xml.data(using: .utf8) else {
            throw VeloError.persistenceFailure(reason: "encodage UTF-8 impossible")
        }
        return data
    }

    public func export(route: CyclingRoute, name: String) throws -> Data {
        var xml = header()
        xml += "  <metadata>\n"
        xml += "    <name>\(escape(name))</name>\n"
        xml += "  </metadata>\n"
        xml += routeElement(coordinates: route.coordinates, name: name)
        xml += "</gpx>\n"

        guard let data = xml.data(using: .utf8) else {
            throw VeloError.persistenceFailure(reason: "encodage UTF-8 impossible")
        }
        return data
    }

    private func header() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(Self.creator)" xmlns="\(Self.namespace)">

        """
    }

    private func routeElement(coordinates: [GeographicCoordinate], name: String) -> String {
        var xml = "  <rte>\n"
        xml += "    <name>\(escape(name))</name>\n"
        for coordinate in coordinates {
            xml += "    <rtept lat=\"\(format(coordinate.latitude))\""
            xml += " lon=\"\(format(coordinate.longitude))\">"
            if let altitude = coordinate.altitude {
                xml += "<ele>\(format(altitude, decimals: 1))</ele>"
            }
            xml += "</rtept>\n"
        }
        xml += "  </rte>\n"
        return xml
    }

    private func trackPointElement(_ sample: LocationSample) -> String {
        var xml = "      <trkpt lat=\"\(format(sample.coordinate.latitude))\""
        xml += " lon=\"\(format(sample.coordinate.longitude))\">\n"
        if let altitude = sample.coordinate.altitude {
            xml += "        <ele>\(format(altitude, decimals: 1))</ele>\n"
        }
        xml += "        <time>\(Self.timestampFormatter.string(from: sample.timestamp))</time>\n"
        xml += "      </trkpt>\n"
        return xml
    }

    private func summaryDescription(of ride: RecordedRide) -> String {
        let distance = InstructionPhrasing.displayDistance(ride.statistics.distance)
        let duration = InstructionPhrasing.displayDuration(ride.statistics.movingTime)
        let speed = InstructionPhrasing.displaySpeed(
            metersPerSecond: ride.statistics.averageMovingSpeed
        )
        return "\(distance) — \(duration) — moyenne \(speed) km/h"
    }

    /// Sept décimales ≈ 1 cm : au-delà, on n'écrit que du bruit.
    private func format(_ value: Double, decimals: Int = 7) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// ISO 8601 en UTC, seule forme acceptée sans ambiguïté par la spécification GPX.
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    // MARK: - Lecture

    public func parse(data: Data) throws -> GPXDocument {
        guard !data.isEmpty else {
            throw VeloError.gpxParsingFailed(reason: "fichier vide")
        }
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "XML mal formé"
            throw VeloError.gpxParsingFailed(reason: reason)
        }
        guard !delegate.document.isEmpty else {
            throw VeloError.gpxParsingFailed(reason: "aucun point trouvé")
        }
        return delegate.document
    }
}

/// Analyseur SAX du format GPX.
///
/// Un analyseur événementiel plutôt qu'un arbre en mémoire : une trace d'une
/// sortie de 100 km contient plusieurs milliers de points, et rien n'oblige à
/// tous les charger simultanément sous forme d'objets.
private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var document = GPXDocument()

    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentElevation: Double?
    private var currentTime: Date?
    private var currentText = ""
    private var isInsideTrackPoint = false
    private var isInsideRoutePoint = false
    private var isReadingName = false
    private var hasCapturedName = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentText = ""
        switch elementName {
        case "trkpt", "rtept", "wpt":
            isInsideTrackPoint = (elementName == "trkpt")
            isInsideRoutePoint = (elementName != "trkpt")
            currentLatitude = attributeDict["lat"].flatMap(Double.init)
            currentLongitude = attributeDict["lon"].flatMap(Double.init)
            currentElevation = nil
            currentTime = nil
        case "name":
            isReadingName = !hasCapturedName
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            currentElevation = Double(text)
        case "time":
            currentTime = GPXParserDelegate.parseTimestamp(text)
        case "name":
            if isReadingName, !text.isEmpty {
                document.name = text
                hasCapturedName = true
            }
            isReadingName = false
        case "trkpt", "rtept", "wpt":
            appendCurrentPoint()
            isInsideTrackPoint = false
            isInsideRoutePoint = false
        default:
            break
        }
        currentText = ""
    }

    private func appendCurrentPoint() {
        guard let latitude = currentLatitude, let longitude = currentLongitude else { return }
        let coordinate = GeographicCoordinate(
            latitude: latitude,
            longitude: longitude,
            altitude: currentElevation
        )
        guard coordinate.isValid else { return }

        if isInsideTrackPoint {
            document.trackPoints.append(
                LocationSample(
                    coordinate: coordinate,
                    timestamp: currentTime ?? Date(timeIntervalSince1970: 0),
                    // Un fichier GPX ne transporte pas l'incertitude de mesure.
                    // On déclare une valeur neutre plutôt que d'inventer une
                    // précision qui tromperait le filtre de trace.
                    horizontalAccuracy: 10,
                    verticalAccuracy: currentElevation != nil ? 10 : -1
                )
            )
        } else if isInsideRoutePoint {
            document.routePoints.append(coordinate)
        }
    }

    /// Accepte les deux variantes courantes : avec et sans fraction de seconde.
    static func parseTimestamp(_ text: String) -> Date? {
        for formatter in [plainFormatter, fractionalFormatter] {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let plainFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    private static let fractionalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
}
