import Foundation
import Testing
@testable import rescue_ready

struct ScheduleExpiryAlertUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()

    private func addBatch(status: BatchStatus = .cleared, collectedHoursAgo: Double = 1) throws -> FoodBatch {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Vegetable fried rice",
                              weight: try Weight(kilograms: 8), allergens: [.soy], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-collectedHoursAgo * hour)),
                              status: status)
        store.batches[batch.id] = batch
        return batch
    }

    private func makeUseCase(notifications: InMemoryNotificationScheduler,
                             batchesFail: Bool = false) -> ScheduleExpiryAlertUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        let fixedNow = now
        return ScheduleExpiryAlertUseCase(batches: batches, notifications: notifications, now: { fixedNow })
    }

    // MARK: - Success

    @Test func schedulesAlertFifteenMinutesBeforeHoldTimeEnds() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler()

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        let expected = batch.holdWindow.expiresAt.addingTimeInterval(-15 * 60)
        #expect(result == .scheduled(at: expected))
        #expect(notifications.scheduledAlerts[batch.id] == expected)
    }

    @Test(arguments: [BatchStatus.awaitingCheck, .cleared, .failedCheck])
    func schedulesAlertForAnyOpenBatch(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)
        let notifications = InMemoryNotificationScheduler()

        _ = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(notifications.scheduledAlerts[batch.id] != nil)
    }

    // MARK: - Permission

    @Test func asksForPermissionTheFirstTime() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler(permission: .notDetermined)

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(notifications.permissionRequestCount == 1)
        #expect(notifications.scheduledAlerts[batch.id] != nil)
        #expect(result != .notificationsDenied)
    }

    @Test func doesNotAskAgainOnceAllowed() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler(permission: .authorized)

        _ = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(notifications.permissionRequestCount == 0)
    }

    @Test func reportsDeniedWhenVolunteerSaysNo() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler(permission: .notDetermined,
                                                          grantsPermissionOnRequest: false)

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(result == .notificationsDenied)
        #expect(notifications.scheduledAlerts.isEmpty)
    }

    @Test func reportsDeniedWithoutAskingAgain() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler(permission: .denied)

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(result == .notificationsDenied)
        #expect(notifications.permissionRequestCount == 0)
        #expect(notifications.scheduledAlerts.isEmpty)
    }

    // MARK: - Rules

    @Test func skipsAlertWhenLessThanFifteenMinutesAreLeft() async throws {
        let batch = try addBatch(collectedHoursAgo: 3.9)
        let notifications = InMemoryNotificationScheduler()

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(result == .tooLateToAlert)
        #expect(notifications.scheduledAlerts.isEmpty)
    }

    @Test(arguments: [BatchStatus.handedOver, .discarded])
    func rejectsBatchThatIsAlreadyClosed(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)
        let notifications = InMemoryNotificationScheduler()

        await #expect(throws: DomainError.batchAlreadyClosed) {
            try await makeUseCase(notifications: notifications).execute(batchID: batch.id)
        }
        #expect(notifications.scheduledAlerts.isEmpty)
    }

    @Test func rejectsUnknownBatch() async {
        await #expect(throws: DomainError.batchNotFound) {
            try await makeUseCase(notifications: InMemoryNotificationScheduler()).execute(batchID: Identifier())
        }
    }

    // MARK: - Failures

    @Test func reportsFailureWhenSchedulingFails() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler()
        notifications.shouldFail = true

        let result = try await makeUseCase(notifications: notifications).execute(batchID: batch.id)

        #expect(result == .failed)
    }

    @Test func mapsRepositoryFailureToStorageFailure() async throws {
        let batch = try addBatch()

        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(notifications: InMemoryNotificationScheduler(), batchesFail: true)
                .execute(batchID: batch.id)
        }
    }
}
