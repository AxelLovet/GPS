import Foundation

/// Stockage des sorties terminées.
///
/// L'implémentation réelle de l'application iOS s'appuie sur SwiftData ; ce
/// protocole existe pour que l'historique, l'export et les statistiques soient
/// testables sans base de données.
public protocol RideStoring: Sendable {
    func save(_ ride: RecordedRide) async throws
    func loadAll() async throws -> [RecordedRide]
    func delete(id: UUID) async throws
    func rename(id: UUID, to name: String) async throws
}

/// Sauvegarde de la sortie **en cours**, pour survivre à une fermeture
/// involontaire de l'application.
///
/// Séparée de `RideStoring` parce que les contraintes sont différentes :
/// l'instantané est écrit très souvent, ne conserve qu'un seul élément, et doit
/// pouvoir être écrit depuis l'arrière-plan pendant que l'écran est verrouillé.
public protocol RideSnapshotStoring: Sendable {
    func write(_ session: RideSession) async throws
    func read() async throws -> RideSession?
    func clear() async throws
}

/// Instantané de sortie sur disque, au format JSON.
///
/// Le JSON est préféré à SwiftData pour cet usage précis : l'écriture est
/// atomique, sans schéma à migrer et sans contexte à sauvegarder, ce qui compte
/// quand l'application peut être tuée par le système à tout moment.
public struct FileRideSnapshotStore: RideSnapshotStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// Emplacement par défaut : dossier Application Support de l'application.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("VeloBoucle", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("session-en-cours.json")
    }

    public func write(_ session: RideSession) async throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw VeloError.persistenceFailure(reason: "écriture de l'instantané")
        }
    }

    public func read() async throws -> RideSession? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(RideSession.self, from: data)
        } catch {
            // Un instantané corrompu ne doit pas empêcher l'application de
            // démarrer : on le signale et on laisse l'appelant décider.
            throw VeloError.rideRecoveryFailed(reason: "instantané illisible")
        }
    }

    public func clear() async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw VeloError.persistenceFailure(reason: "suppression de l'instantané")
        }
    }
}

/// Décide quoi faire d'un instantané retrouvé au démarrage.
public enum RideRecovery {
    /// Durée au-delà de laquelle une sortie interrompue n'est plus proposée.
    ///
    /// Reprendre une sortie vieille de trois jours n'a pas de sens : les
    /// statistiques de temps écoulé seraient absurdes. Douze heures couvrent
    /// largement une sortie longue interrompue par un plantage ou une batterie
    /// vide, sans réveiller un souvenir périmé.
    public static let maximumAge: TimeInterval = 12 * 3600

    public enum Decision: Sendable, Equatable {
        /// Proposer la reprise à l'utilisateur.
        case offerResume(RideSession)
        /// Proposer d'enregistrer la sortie telle quelle, sans la reprendre.
        case offerSaveOnly(RideSession)
        /// Effacer l'instantané sans rien demander.
        case discard
    }

    /// Analyse un instantané.
    public static func decide(for session: RideSession?, now: Date) -> Decision {
        guard let session else { return .discard }
        guard session.isResumable else { return .discard }

        let age = now.timeIntervalSince(session.lastUpdatedAt)
        if age > maximumAge {
            // Trop ancienne pour être reprise, mais les kilomètres parcourus
            // sont réels : on ne les jette pas en silence.
            return session.statistics.distance > 500 ? .offerSaveOnly(session) : .discard
        }
        return .offerResume(session)
    }

    /// Prépare la reprise d'une session.
    ///
    /// Le temps passé hors de l'application n'est **pas** ajouté au temps
    /// écoulé : le cycliste ne roulait pas pendant que l'application était
    /// fermée. La session repart en pause, à charge pour l'utilisateur de la
    /// relancer explicitement.
    public static func prepareResume(_ session: RideSession, now: Date) -> RideSession {
        var resumed = session
        resumed.state = .paused
        resumed.lastUpdatedAt = now
        return resumed
    }
}
