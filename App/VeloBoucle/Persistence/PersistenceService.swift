import Foundation
import SwiftData
import VeloCore

/// Enregistrement et lecture de l'historique dans SwiftData.
///
/// Implémente `RideStoring`, défini dans `VeloCore`, ce qui permet aux tests du
/// cœur métier d'utiliser un magasin en mémoire.
@MainActor
final class PersistenceService: RideStoring {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save(_ ride: RecordedRide) async throws {
        do {
            // Une sortie reprise après interruption conserve son identifiant :
            // il faut remplacer l'enregistrement existant plutôt que d'en créer
            // un doublon.
            try deleteExisting(id: ride.id)
            context.insert(try StoredRide(ride: ride))
            try context.save()
            AppLog.persistence.info("Sortie enregistrée dans l'historique")
        } catch {
            throw VeloError.persistenceFailure(reason: "enregistrement de la sortie")
        }
    }

    func loadAll() async throws -> [RecordedRide] {
        do {
            let descriptor = FetchDescriptor<StoredRide>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map { $0.toRecordedRide() }
        } catch {
            throw VeloError.persistenceFailure(reason: "lecture de l'historique")
        }
    }

    func delete(id: UUID) async throws {
        do {
            try deleteExisting(id: id)
            try context.save()
        } catch {
            throw VeloError.persistenceFailure(reason: "suppression de la sortie")
        }
    }

    func rename(id: UUID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let descriptor = FetchDescriptor<StoredRide>(
                predicate: #Predicate { $0.id == id }
            )
            guard let stored = try context.fetch(descriptor).first else { return }
            stored.name = trimmed
            try context.save()
        } catch {
            throw VeloError.persistenceFailure(reason: "renommage de la sortie")
        }
    }

    private func deleteExisting(id: UUID) throws {
        let descriptor = FetchDescriptor<StoredRide>(predicate: #Predicate { $0.id == id })
        for stored in try context.fetch(descriptor) {
            context.delete(stored)
        }
    }
}
