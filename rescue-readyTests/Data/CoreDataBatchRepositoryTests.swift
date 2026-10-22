import CoreData
import Foundation
import Testing
@testable import rescue_ready

struct CoreDataBatchRepositoryTests {
    let controller = PersistenceController(inMemory: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60

    var repository: CoreDataBatchRepository {
        CoreDataBatchRepository(container: controller.container)
    }

    /// Stores an event, volunteer and drop point, then a pickup with four batches whose
    /// hold windows start at different times. Builds its own data rather than using the
    /// sample data, so changes to the sample data can't break these tests.
    private func makeFixture() async throws -> (early: FoodBatch, late: FoodBatch, failed: FoodBatch,
                                                discarded: FoodBatch, dropPoint: DropPoint) {
        let event = Event(id: Identifier(), name: "Test Match", venue: "Test Stadium",
                          startsAt: now.addingTimeInterval(-4 * hour), endsAt: now.addingTimeInterval(-1 * hour))
        let volunteer = Volunteer(id: Identifier(), name: "Test Volunteer")
        let dropPoint = DropPoint(id: Identifier(), name: "Redfern Community Kitchen",
                                  address: "12 Regent St, Redfern NSW 2016", openingHours: 0...23)

        try await controller.container.performBackground(failure: .saveFailed) { context in
            EventEntity(context: context).update(from: event)
            VolunteerEntity(context: context).update(from: volunteer)
            DropPointEntity(context: context).update(from: dropPoint)
            try context.save()
        }

        let pickup = Pickup(id: Identifier(), eventID: event.id, volunteerID: volunteer.id, collectedAt: now)
        let early = try makeBatch("Beef lasagne", pickupID: pickup.id,
                                  startedAt: now.addingTimeInterval(-3 * hour), status: .awaitingCheck)
        let late = try makeBatch("Fruit platter", pickupID: pickup.id,
                                 startedAt: now.addingTimeInterval(-0.25 * hour), status: .cleared)
        let failed = try makeBatch("Garden salad", pickupID: pickup.id,
                                   startedAt: now.addingTimeInterval(-1 * hour), status: .failedCheck)
        let discarded = try makeBatch("Prawn rolls", pickupID: pickup.id,
                                      startedAt: now.addingTimeInterval(-2 * hour), status: .discarded)

        try await CoreDataPickupRepository(container: controller.container)
            .save(pickup, batches: [early, late, failed, discarded])

        return (early, late, failed, discarded, dropPoint)
    }

    private func makeBatch(_ description: String, pickupID: Identifier<Pickup>,
                           startedAt: Date, status: BatchStatus) throws -> FoodBatch {
        FoodBatch(id: Identifier(), pickupID: pickupID, foodDescription: description,
                  weight: try Weight(kilograms: 4), allergens: [], allergensDeclared: true,
                  holdWindow: HoldWindow(startedAt: startedAt), status: status)
    }

    private func storedBatch(_ id: Identifier<FoodBatch>) async throws -> FoodBatch {
        let batch = try await repository.batch(id: id)
        return try #require(batch)
    }

    // MARK: - Fetching

    @Test func openBatchesExcludeClosedBatchesAndSortBySoonestExpiry() async throws {
        let fixture = try await makeFixture()

        let open = try await repository.openBatches()

        #expect(open.map(\.id) == [fixture.early.id, fixture.failed.id, fixture.late.id])
    }

    @Test func batchesWithStatusReturnOnlyThatStatus() async throws {
        let fixture = try await makeFixture()

        let failed = try await repository.batches(withStatus: .failedCheck)

        #expect(failed.map(\.id) == [fixture.failed.id])
    }

    @Test func unknownBatchIDReturnsNil() async throws {
        _ = try await makeFixture()

        let missing = try await repository.batch(id: Identifier())

        #expect(missing == nil)
    }

    // MARK: - Updating

    @Test func handoverIsSavedWithItsDropPoint() async throws {
        let fixture = try await makeFixture()
        let dropPoint = fixture.dropPoint

        var handedOver = fixture.late
        handedOver.status = .handedOver
        handedOver.dropPointID = dropPoint.id
        try await repository.update(handedOver)

        let stored = try await storedBatch(handedOver.id)
        #expect(stored.status == .handedOver)
        #expect(stored.dropPointID == dropPoint.id)
    }

    @Test func discardIsSavedWithItsReason() async throws {
        let fixture = try await makeFixture()

        var discarded = fixture.early
        discarded.status = .discarded
        discarded.discardReason = "Lid missing during transport"
        try await repository.update(discarded)

        let stored = try await storedBatch(discarded.id)
        #expect(stored.status == .discarded)
        #expect(stored.discardReason == "Lid missing during transport")
    }

    @Test func updatingUnknownBatchThrowsNotFound() async throws {
        let fixture = try await makeFixture()
        let stranger = try makeBatch("Not in the store", pickupID: fixture.late.pickupID,
                                     startedAt: now, status: .cleared)

        await #expect(throws: RepositoryError.notFound) {
            try await repository.update(stranger)
        }
    }

    @Test func unknownDropPointThrowsNotFoundAndLeavesBatchUnchanged() async throws {
        let fixture = try await makeFixture()

        var handedOver = fixture.late
        handedOver.status = .handedOver
        handedOver.dropPointID = Identifier()

        await #expect(throws: RepositoryError.notFound) {
            try await repository.update(handedOver)
        }
        let stored = try await storedBatch(fixture.late.id)
        #expect(stored.status == .cleared)
        #expect(stored.dropPointID == nil)
    }

    // MARK: - Safety checks

    @Test func recordStoresCheckAndNewBatchStatusTogether() async throws {
        let fixture = try await makeFixture()

        let check = SafetyCheck(id: Identifier(), batchID: fixture.early.id,
                                temperature: try Temperature(celsius: 3.5),
                                checkedAt: now, outcome: .passed)
        var cleared = fixture.early
        cleared.status = .cleared
        try await repository.record(check, updating: cleared)

        let stored = try await storedBatch(fixture.early.id)
        let checks = try await repository.checks(for: fixture.early.id)
        #expect(stored.status == .cleared)
        #expect(checks == [check])
    }

    @Test func checksAreReturnedOldestFirst() async throws {
        let fixture = try await makeFixture()
        let batchID = fixture.early.id

        let failed = SafetyCheck(id: Identifier(), batchID: batchID,
                                 temperature: try Temperature(celsius: 22),
                                 checkedAt: now.addingTimeInterval(-600),
                                 outcome: .failed(reason: "Temperature in danger zone"))
        let passed = SafetyCheck(id: Identifier(), batchID: batchID,
                                 temperature: try Temperature(celsius: 4),
                                 checkedAt: now, outcome: .passed)

        // Recorded newest first to show the repository, not insertion order, sets the order.
        try await repository.record(passed, updating: fixture.early)
        try await repository.record(failed, updating: fixture.early)

        let checks = try await repository.checks(for: batchID)
        #expect(checks.map(\.id) == [failed.id, passed.id])
        #expect(checks.first?.outcome == .failed(reason: "Temperature in danger zone"))
    }
}
