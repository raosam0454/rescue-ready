import Foundation

/// An open batch and how much safe hold time it has left.
struct ExpiringBatch: Identifiable, Equatable {
    let batch: FoodBatch
    let timeRemaining: TimeInterval

    var id: Identifier<FoodBatch> { batch.id }
    var hasExpired: Bool { timeRemaining <= 0 }
}

/// Lists open batches for the batch list and the home screen widget.
///
/// Rules:
/// - only open batches (awaiting a check, cleared, or failed)
/// - soonest safe hold deadline first
/// - the widget can ask for just the first few
struct FetchExpiringBatchesUseCase {
    let batches: BatchRepository
    /// Injected so tests control time. Never call `Date()` directly in a use case.
    let now: () -> Date

    func execute(limit: Int? = nil) async throws -> [ExpiringBatch] {
        let open: [FoodBatch]
        do {
            open = try await batches.openBatches()
        } catch {
            throw DomainError.storageFailure
        }

        let timestamp = now()
        let sorted = open
            .filter { $0.status.isOpen }
            .sorted { $0.holdWindow.expiresAt < $1.holdWindow.expiresAt }
            .map { ExpiringBatch(batch: $0, timeRemaining: $0.holdWindow.remaining(at: timestamp)) }

        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }
}
