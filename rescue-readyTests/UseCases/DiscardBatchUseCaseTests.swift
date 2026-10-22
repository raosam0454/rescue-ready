import Foundation
import Testing
@testable import rescue_ready

struct DiscardBatchUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemoryDataStore()
    let notifications = InMemoryNotificationScheduler()

    private func addBatch(status: BatchStatus) throws -> FoodBatch {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Garden salad",
                              weight: try Weight(kilograms: 3), allergens: [], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now), status: status)
        store.batches[batch.id] = batch
        return batch
    }

    private func makeUseCase(batchesFail: Bool = false) -> DiscardBatchUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        return DiscardBatchUseCase(batches: batches, notifications: notifications)
    }

    // MARK: - Success

    @Test(arguments: [BatchStatus.awaitingCheck, .cleared, .failedCheck])
    func discardsAnyOpenBatch(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)

        let result = try await makeUseCase().execute(batchID: batch.id, reason: "Failed temperature check")

        #expect(result.status == .discarded)
        #expect(store.batches[batch.id]?.status == .discarded)
    }

    @Test func storesTrimmedReason() async throws {
        let batch = try addBatch(status: .failedCheck)

        _ = try await makeUseCase().execute(batchID: batch.id, reason: "  Lid came off in transit \n")

        #expect(store.batches[batch.id]?.discardReason == "Lid came off in transit")
    }

    @Test func cancelsExpiryAlertAfterDiscard() async throws {
        let batch = try addBatch(status: .cleared)

        _ = try await makeUseCase().execute(batchID: batch.id, reason: "Dropped on the ground")

        #expect(notifications.cancelledBatchIDs == [batch.id])
    }

    // MARK: - Rules

    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsBlankReasonAndLeavesBatchUnchanged(reason: String) async throws {
        let batch = try addBatch(status: .cleared)

        await #expect(throws: DomainError.reasonRequired) {
            try await makeUseCase().execute(batchID: batch.id, reason: reason)
        }
        #expect(store.batches[batch.id] == batch)
        #expect(notifications.cancelledBatchIDs.isEmpty)
    }

    @Test(arguments: [BatchStatus.handedOver, .discarded])
    func rejectsBatchThatIsAlreadyClosed(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)

        await #expect(throws: DomainError.batchAlreadyClosed) {
            try await makeUseCase().execute(batchID: batch.id, reason: "Changed my mind")
        }
    }

    @Test func rejectsUnknownBatch() async {
        await #expect(throws: DomainError.batchNotFound) {
            try await makeUseCase().execute(batchID: Identifier(), reason: "Spoiled")
        }
    }

    @Test func mapsRepositoryFailureToStorageFailure() async throws {
        let batch = try addBatch(status: .cleared)

        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(batchesFail: true).execute(batchID: batch.id, reason: "Spoiled")
        }
    }
}
