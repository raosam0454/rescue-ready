import Foundation
import Testing
@testable import rescue_ready

struct FetchExpiringBatchesUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()

    @discardableResult
    private func addBatch(_ description: String, status: BatchStatus = .cleared,
                          collectedHoursAgo: Double) throws -> FoodBatch {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: description,
                              weight: try Weight(kilograms: 5), allergens: [], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-collectedHoursAgo * hour)),
                              status: status)
        store.batches[batch.id] = batch
        return batch
    }

    private func makeUseCase(batchesFail: Bool = false) -> FetchExpiringBatchesUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        let fixedNow = now
        return FetchExpiringBatchesUseCase(batches: batches, now: { fixedNow })
    }

    // MARK: - Ordering

    @Test func listsSoonestDeadlineFirst() async throws {
        try addBatch("Fruit platter", collectedHoursAgo: 0.5)
        try addBatch("Beef lasagne", collectedHoursAgo: 3)
        try addBatch("Garden salad", collectedHoursAgo: 1.5)

        let result = try await makeUseCase().execute()

        #expect(result.map(\.batch.foodDescription) == ["Beef lasagne", "Garden salad", "Fruit platter"])
    }

    @Test func includesTimeRemaining() async throws {
        try addBatch("Beef lasagne", collectedHoursAgo: 3)

        let result = try await makeUseCase().execute()

        #expect(result.first?.timeRemaining == hour)
        #expect(result.first?.hasExpired == false)
    }

    @Test func marksBatchPastItsHoldTimeAsExpired() async throws {
        try addBatch("Prawn rolls", collectedHoursAgo: 5)

        let result = try await makeUseCase().execute()

        #expect(result.first?.timeRemaining == 0)
        #expect(result.first?.hasExpired == true)
    }

    // MARK: - Filtering

    @Test func onlyIncludesOpenBatches() async throws {
        try addBatch("Awaiting", status: .awaitingCheck, collectedHoursAgo: 1)
        try addBatch("Cleared", status: .cleared, collectedHoursAgo: 1)
        try addBatch("Failed", status: .failedCheck, collectedHoursAgo: 1)
        try addBatch("Handed over", status: .handedOver, collectedHoursAgo: 1)
        try addBatch("Discarded", status: .discarded, collectedHoursAgo: 1)

        let result = try await makeUseCase().execute()

        #expect(Set(result.map(\.batch.foodDescription)) == ["Awaiting", "Cleared", "Failed"])
    }

    @Test func returnsEmptyListWhenNothingIsOpen() async throws {
        try addBatch("Handed over", status: .handedOver, collectedHoursAgo: 1)

        let result = try await makeUseCase().execute()

        #expect(result.isEmpty)
    }

    // MARK: - Limit

    @Test func limitKeepsOnlyTheSoonestBatches() async throws {
        try addBatch("Fruit platter", collectedHoursAgo: 0.5)
        try addBatch("Beef lasagne", collectedHoursAgo: 3)
        try addBatch("Garden salad", collectedHoursAgo: 1.5)

        let result = try await makeUseCase().execute(limit: 2)

        #expect(result.map(\.batch.foodDescription) == ["Beef lasagne", "Garden salad"])
    }

    // MARK: - Failures

    @Test func mapsRepositoryFailureToStorageFailure() async {
        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(batchesFail: true).execute()
        }
    }
}
