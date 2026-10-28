import Foundation
import Testing
@testable import rescue_ready

struct ComputeImpactStatsUseCaseTests {
    let store = InMemoryDataStore()
    let pickupID = Identifier<Pickup>()
    let pantry = DropPoint(id: Identifier(), name: "Redfern Community Kitchen",
                           address: "12 Regent St, Redfern NSW 2016", openingHours: 7...21)
    let kitchen = DropPoint(id: Identifier(), name: "Parramatta Neighbourhood Pantry",
                            address: "48 Church St, Parramatta NSW 2150", openingHours: 9...17)

    init() {
        store.dropPoints[pantry.id] = pantry
        store.dropPoints[kitchen.id] = kitchen
    }

    private func addBatch(_ kilograms: Double, _ status: BatchStatus, to dropPoint: DropPoint? = nil) throws {
        let batch = FoodBatch(
            id: Identifier(), pickupID: pickupID, foodDescription: "Vegetable fried rice",
            weight: try Weight(kilograms: kilograms), allergens: [], allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            status: status, dropPointID: dropPoint?.id
        )
        store.batches[batch.id] = batch
    }

    private func makeUseCase(batchesFail: Bool = false, dropPointsFail: Bool = false) -> ComputeImpactStatsUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        let dropPoints = InMemoryDropPointRepository(store: store)
        dropPoints.shouldFail = dropPointsFail
        return ComputeImpactStatsUseCase(batches: batches, dropPoints: dropPoints)
    }

    @Test func countsOnlyHandedOverBatchesTowardsKilogramsSaved() async throws {
        try addBatch(8, .handedOver, to: pantry)
        try addBatch(4.5, .handedOver, to: kitchen)
        try addBatch(10, .awaitingCheck)
        try addBatch(6, .cleared)
        try addBatch(2, .failedCheck)

        let stats = try await makeUseCase().execute()

        #expect(stats.kilogramsSaved == 12.5)
        #expect(stats.batchesHandedOver == 2)
    }

    @Test func excludesDiscardedFoodFromTotalsButReportsItSeparately() async throws {
        try addBatch(8, .handedOver, to: pantry)
        try addBatch(3, .discarded)
        try addBatch(1.5, .discarded)

        let stats = try await makeUseCase().execute()

        #expect(stats.kilogramsSaved == 8)
        #expect(stats.estimatedMeals == 16)
        #expect(stats.batchesDiscarded == 2)
        #expect(stats.kilogramsDiscarded == 4.5)
    }

    @Test func estimatesMealsAtTwoPerKilogramRoundedDown() async throws {
        try addBatch(5.3, .handedOver, to: pantry)

        let stats = try await makeUseCase().execute()

        // 5.3 kg x 2 = 10.6 meals, reported as 10 so impact is never overstated.
        #expect(stats.estimatedMeals == 10)
    }

    @Test func returnsEmptyStatsWhenNothingHasBeenHandedOverOrDiscarded() async throws {
        try addBatch(7, .awaitingCheck)

        let stats = try await makeUseCase().execute()

        #expect(stats == .empty)
        #expect(stats.isEmpty)
        #expect(stats.rescueRate == nil)
    }

    @Test func calculatesRescueRateFromClosedBatches() async throws {
        try addBatch(8, .handedOver, to: pantry)
        try addBatch(4, .handedOver, to: pantry)
        try addBatch(2, .handedOver, to: kitchen)
        try addBatch(1, .discarded)

        let stats = try await makeUseCase().execute()

        #expect(stats.rescueRate == 0.75)
    }

    @Test func groupsDeliveriesByDropPointWithMostKilogramsFirst() async throws {
        try addBatch(3, .handedOver, to: pantry)
        try addBatch(8, .handedOver, to: kitchen)
        try addBatch(2, .handedOver, to: pantry)

        let stats = try await makeUseCase().execute()

        #expect(stats.dropPoints.map(\.name) == ["Parramatta Neighbourhood Pantry", "Redfern Community Kitchen"])
        #expect(stats.dropPoints.map(\.kilograms) == [8, 5])
        #expect(stats.dropPoints.map(\.batches) == [1, 2])
    }

    @Test func labelsDeliveriesToADropPointThatNoLongerExists() async throws {
        let removed = DropPoint(id: Identifier(), name: "Old Hall", address: "1 Main St", openingHours: 9...17)
        try addBatch(4, .handedOver, to: removed)

        let stats = try await makeUseCase().execute()

        #expect(stats.kilogramsSaved == 4)
        #expect(stats.dropPoints.first?.name == "Removed drop point")
    }

    @Test func mapsBatchRepositoryFailureToStorageFailure() async {
        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(batchesFail: true).execute()
        }
    }

    @Test func mapsDropPointRepositoryFailureToStorageFailure() async {
        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(dropPointsFail: true).execute()
        }
    }
}
