import CoreData
import Foundation

final class CoreDataBatchRepository: BatchRepository {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func batch(id: Identifier<FoodBatch>) async throws -> FoodBatch? {
        try await container.performBackground(failure: .fetchFailed) { context in
            try context.fetchOne(FoodBatchEntity.self, id: id.rawValue)?.toDomain()
        }
    }

    func openBatches() async throws -> [FoodBatch] {
        let openStatuses = BatchStatus.allCases.filter(\.isOpen).map(\.rawValue)
        return try await fetchBatches(matching: NSPredicate(format: "statusRaw IN %@", openStatuses))
    }

    func batches(withStatus status: BatchStatus) async throws -> [FoodBatch] {
        try await fetchBatches(matching: NSPredicate(format: "statusRaw == %@", status.rawValue))
    }

    func update(_ batch: FoodBatch) async throws {
        try await container.performBackground(failure: .saveFailed) { context in
            guard let entity = try context.fetchOne(FoodBatchEntity.self, id: batch.id.rawValue) else {
                throw RepositoryError.notFound
            }
            try Self.apply(batch, to: entity, in: context)
            try context.save()
        }
    }

    func record(_ check: SafetyCheck, updating batch: FoodBatch) async throws {
        try await container.performBackground(failure: .saveFailed) { context in
            guard let batchEntity = try context.fetchOne(FoodBatchEntity.self, id: batch.id.rawValue) else {
                throw RepositoryError.notFound
            }
            try Self.apply(batch, to: batchEntity, in: context)

            let checkEntity = SafetyCheckEntity(context: context)
            checkEntity.update(from: check)
            checkEntity.batch = batchEntity

            // One save, so the check and the batch's new status are stored together or not at all.
            try context.save()
        }
    }

    func checks(for batchID: Identifier<FoodBatch>) async throws -> [SafetyCheck] {
        try await container.performBackground(failure: .fetchFailed) { context in
            let request = NSFetchRequest<SafetyCheckEntity>(entityName: "SafetyCheckEntity")
            request.predicate = NSPredicate(format: "batch.id == %@", batchID.rawValue as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "checkedAt", ascending: true)]
            return try context.fetch(request).map { try $0.toDomain() }
        }
    }

    // MARK: - Helpers

    /// Batches matching `predicate`, soonest hold-window expiry first.
    ///
    /// Every hold window lasts the same length of time, so sorting by when it
    /// started gives the same order as sorting by when it expires, and can use
    /// the store's `holdStartedAt` index.
    private func fetchBatches(matching predicate: NSPredicate) async throws -> [FoodBatch] {
        try await container.performBackground(failure: .fetchFailed) { context in
            let request = NSFetchRequest<FoodBatchEntity>(entityName: "FoodBatchEntity")
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "holdStartedAt", ascending: true)]
            return try context.fetch(request).map { try $0.toDomain() }
        }
    }

    /// Copies a batch's attributes onto its entity and links its drop point.
    ///
    /// `update(from:)` only copies attributes, so the drop point relationship is set
    /// here. Without it a handover would be saved with no record of where the food went.
    private static func apply(_ batch: FoodBatch, to entity: FoodBatchEntity,
                              in context: NSManagedObjectContext) throws {
        entity.update(from: batch)

        if let dropPointID = batch.dropPointID {
            guard let dropPoint = try context.fetchOne(DropPointEntity.self, id: dropPointID.rawValue) else {
                throw RepositoryError.notFound
            }
            entity.dropPoint = dropPoint
        } else {
            entity.dropPoint = nil
        }
    }
}
