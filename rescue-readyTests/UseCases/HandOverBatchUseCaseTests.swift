import Foundation
import Testing
@testable import rescue_ready

struct HandOverBatchUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()
    let notifications = InMemoryNotificationScheduler()
    let pantry: DropPoint
    let closedPantry: DropPoint

    init() {
        pantry = DropPoint(id: Identifier(), name: "Redfern Community Kitchen",
                           address: "12 Regent St, Redfern NSW 2016", openingHours: 0...23)

        // Built from the test's own clock so it is closed whatever time zone the tests run in.
        let currentHour = Calendar.current.component(.hour, from: now)
        let closedHours = currentHour == 23 ? 0...22 : (currentHour + 1)...23
        closedPantry = DropPoint(id: Identifier(), name: "Parramatta Neighbourhood Pantry",
                                 address: "48 Church St, Parramatta NSW 2150", openingHours: closedHours)

        store.dropPoints[pantry.id] = pantry
        store.dropPoints[closedPantry.id] = closedPantry
    }

    private func addBatch(status: BatchStatus, collectedHoursAgo: Double = 1) throws -> FoodBatch {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Vegetable fried rice",
                              weight: try Weight(kilograms: 8), allergens: [.soy], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-collectedHoursAgo * hour)),
                              status: status)
        store.batches[batch.id] = batch
        return batch
    }

    private func makeUseCase(batchesFail: Bool = false) -> HandOverBatchUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        let fixedNow = now
        return HandOverBatchUseCase(batches: batches, dropPoints: InMemoryDropPointRepository(store: store),
                                    notifications: notifications, now: { fixedNow })
    }

    // MARK: - Success

    @Test func handsOverClearedBatchToOpenDropPoint() async throws {
        let batch = try addBatch(status: .cleared)

        let result = try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)

        #expect(result.status == .handedOver)
        #expect(result.dropPointID == pantry.id)
        #expect(store.batches[batch.id] == result)
    }

    @Test func cancelsExpiryAlertAfterHandover() async throws {
        let batch = try addBatch(status: .cleared)

        _ = try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)

        #expect(notifications.cancelledBatchIDs == [batch.id])
    }

    // MARK: - Batch rules

    @Test(arguments: [BatchStatus.awaitingCheck, .failedCheck])
    func rejectsBatchThatHasNotPassedItsCheck(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)

        await #expect(throws: DomainError.batchNotCleared) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)
        }
    }

    @Test func rejectsBatchAlreadyHandedOver() async throws {
        let batch = try addBatch(status: .handedOver)

        await #expect(throws: DomainError.alreadyHandedOver) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)
        }
    }

    @Test func rejectsDiscardedBatch() async throws {
        let batch = try addBatch(status: .discarded)

        await #expect(throws: DomainError.batchAlreadyClosed) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)
        }
    }

    @Test func rejectsClearedBatchWhoseHoldTimeHasRunOut() async throws {
        let batch = try addBatch(status: .cleared, collectedHoursAgo: 4.5)

        await #expect(throws: DomainError.exceededSafeHoldTime) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: pantry.id)
        }
    }

    @Test func rejectsUnknownBatch() async {
        await #expect(throws: DomainError.batchNotFound) {
            try await makeUseCase().execute(batchID: Identifier(), dropPointID: pantry.id)
        }
    }

    // MARK: - Drop point rules

    @Test func rejectsClosedDropPoint() async throws {
        let batch = try addBatch(status: .cleared)

        await #expect(throws: DomainError.dropPointClosed) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: closedPantry.id)
        }
    }

    @Test func rejectsUnknownDropPoint() async throws {
        let batch = try addBatch(status: .cleared)

        await #expect(throws: DomainError.dropPointNotFound) {
            try await makeUseCase().execute(batchID: batch.id, dropPointID: Identifier())
        }
    }

    // MARK: - Failures leave things unchanged

    @Test func rejectedHandoverLeavesBatchAndAlertUnchanged() async throws {
        let batch = try addBatch(status: .cleared)

        _ = try? await makeUseCase().execute(batchID: batch.id, dropPointID: closedPantry.id)

        #expect(store.batches[batch.id] == batch)
        #expect(notifications.cancelledBatchIDs.isEmpty)
    }

    @Test func mapsRepositoryFailureToStorageFailure() async throws {
        let batch = try addBatch(status: .cleared)

        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(batchesFail: true).execute(batchID: batch.id, dropPointID: pantry.id)
        }
    }
}
