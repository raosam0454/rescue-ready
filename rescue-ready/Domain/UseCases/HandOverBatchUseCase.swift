import Foundation

/// Records that a batch was delivered to a drop point.
///
/// Rules:
/// - the batch must exist and must have passed its safety check (`cleared`)
/// - a batch that is already handed over or discarded cannot be handed over
/// - the batch's safe hold time must not have run out
/// - the drop point must exist and be open
/// - once handed over, the batch's expiry alert is cancelled
struct HandOverBatchUseCase {
    let batches: BatchRepository
    let dropPoints: DropPointRepository
    let notifications: NotificationScheduling
    /// Injected so tests control time. Never call `Date()` directly in a use case.
    let now: () -> Date

    func execute(batchID: Identifier<FoodBatch>, dropPointID: Identifier<DropPoint>) async throws -> FoodBatch {
        let batch: FoodBatch?
        do {
            batch = try await batches.batch(id: batchID)
        } catch {
            throw DomainError.storageFailure
        }
        guard var batch else { throw DomainError.batchNotFound }

        switch batch.status {
        case .cleared:
            break
        case .handedOver:
            throw DomainError.alreadyHandedOver
        case .discarded:
            throw DomainError.batchAlreadyClosed
        case .awaitingCheck, .failedCheck:
            throw DomainError.batchNotCleared
        }

        let timestamp = now()
        // A batch that passed its check earlier can still run out of time on the way.
        guard !batch.holdWindow.hasExpired(at: timestamp) else { throw DomainError.exceededSafeHoldTime }

        let dropPoint: DropPoint?
        do {
            dropPoint = try await dropPoints.dropPoint(id: dropPointID)
        } catch {
            throw DomainError.storageFailure
        }
        guard let dropPoint else { throw DomainError.dropPointNotFound }
        guard dropPoint.isOpen(at: timestamp) else { throw DomainError.dropPointClosed }

        batch.status = .handedOver
        batch.dropPointID = dropPoint.id

        do {
            try await batches.update(batch)
        } catch {
            throw DomainError.storageFailure
        }

        await notifications.cancelExpiryAlert(for: batch.id)
        return batch
    }
}
