import Foundation

/// Records that a batch was thrown away, and why.
///
/// Rules:
/// - a reason is required; whitespace alone does not count
/// - the batch must exist and still be open (awaiting a check, cleared, or failed)
/// - once discarded, the batch's expiry alert is cancelled
struct DiscardBatchUseCase {
    let batches: BatchRepository
    let notifications: NotificationScheduling

    func execute(batchID: Identifier<FoodBatch>, reason: String) async throws -> FoodBatch {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw DomainError.reasonRequired }

        let batch: FoodBatch?
        do {
            batch = try await batches.batch(id: batchID)
        } catch {
            throw DomainError.storageFailure
        }
        guard var batch else { throw DomainError.batchNotFound }
        guard batch.status.isOpen else { throw DomainError.batchAlreadyClosed }

        batch.status = .discarded
        batch.discardReason = trimmedReason

        do {
            try await batches.update(batch)
        } catch {
            throw DomainError.storageFailure
        }

        await notifications.cancelExpiryAlert(for: batch.id)
        return batch
    }
}
