import Foundation
import Testing
@testable import rescue_ready

struct RecordSafetyCheckUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()

    private func addBatch(status: BatchStatus = .awaitingCheck, collectedHoursAgo: Double = 1,
                          allergensDeclared: Bool = true) throws -> FoodBatch {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Lamb curry",
                              weight: try Weight(kilograms: 6), allergens: [.milk],
                              allergensDeclared: allergensDeclared,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-collectedHoursAgo * hour)),
                              status: status)
        store.batches[batch.id] = batch
        return batch
    }

    private func makeUseCase(notifications: InMemoryNotificationScheduler = InMemoryNotificationScheduler(),
                             batchesFail: Bool = false) -> RecordSafetyCheckUseCase {
        let batches = InMemoryBatchRepository(store: store)
        batches.shouldFail = batchesFail
        let fixedNow = now
        let alerts = ScheduleExpiryAlertUseCase(batches: batches, notifications: notifications, now: { fixedNow })
        return RecordSafetyCheckUseCase(batches: batches, scheduleExpiryAlert: alerts, now: { fixedNow })
    }

    // MARK: - Passing checks

    @Test(arguments: [72.0, 60.0, 5.0, 3.0, -18.0])
    func clearsBatchOutsideTheDangerZone(celsius: Double) async throws {
        let batch = try addBatch()

        let result = try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: celsius,
                                                     allergensConfirmed: false)

        #expect(result.passed)
        #expect(store.batches[batch.id]?.status == .cleared)
        #expect(store.checks.last?.outcome == .passed)
    }

    @Test func schedulesExpiryAlertWhenTheBatchPasses() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler()

        let result = try await makeUseCase(notifications: notifications)
            .execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)

        let expected = batch.holdWindow.expiresAt.addingTimeInterval(-15 * 60)
        #expect(result.alert == .scheduled(at: expected))
        #expect(notifications.scheduledAlerts[batch.id] == expected)
    }

    @Test func stillClearsTheBatchWhenNotificationsAreDenied() async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler(permission: .denied)

        let result = try await makeUseCase(notifications: notifications)
            .execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)

        #expect(result.passed)
        #expect(result.alert == .notificationsDenied)
        #expect(store.batches[batch.id]?.status == .cleared)
    }

    @Test func confirmingAllergensMarksThemDeclared() async throws {
        let batch = try addBatch(allergensDeclared: false)

        _ = try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: true)

        #expect(store.batches[batch.id]?.allergensDeclared == true)
    }

    // MARK: - Failing checks are recorded

    @Test(arguments: [25.0, 5.5, 59.9])
    func blocksFoodInTheDangerZone(celsius: Double) async throws {
        let batch = try addBatch()
        let notifications = InMemoryNotificationScheduler()

        let result = try await makeUseCase(notifications: notifications)
            .execute(batchID: batch.id, temperatureCelsius: celsius, allergensConfirmed: false)

        #expect(result.violation == .temperatureOutOfRange)
        #expect(store.batches[batch.id]?.status == .failedCheck)
        #expect(store.checks.count == 1)
        #expect(store.checks.last?.outcome.isPassed == false)
        #expect(notifications.scheduledAlerts.isEmpty)
    }

    @Test func blocksBatchOutForMoreThanFourHoursEvenAtASafeTemperature() async throws {
        let batch = try addBatch(collectedHoursAgo: 4.5)

        let result = try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 72,
                                                     allergensConfirmed: false)

        #expect(result.violation == .exceededSafeHoldTime)
        #expect(store.batches[batch.id]?.status == .failedCheck)
    }

    // MARK: - Rejected input

    @Test func requiresAllergenConfirmationAndRecordsNothing() async throws {
        let batch = try addBatch(allergensDeclared: false)

        await #expect(throws: DomainError.allergensUndeclared) {
            try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)
        }
        #expect(store.checks.isEmpty)
        #expect(store.batches[batch.id]?.status == .awaitingCheck)
    }

    @Test func rejectsImplausibleReading() async throws {
        let batch = try addBatch()

        await #expect(throws: DomainError.invalidTemperatureReading) {
            try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 650, allergensConfirmed: false)
        }
    }

    @Test(arguments: [BatchStatus.cleared, .failedCheck])
    func rejectsBatchThatWasAlreadyChecked(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)

        await #expect(throws: DomainError.alreadyChecked) {
            try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)
        }
    }

    @Test(arguments: [BatchStatus.handedOver, .discarded])
    func rejectsClosedBatch(status: BatchStatus) async throws {
        let batch = try addBatch(status: status)

        await #expect(throws: DomainError.batchAlreadyClosed) {
            try await makeUseCase().execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)
        }
    }

    @Test func rejectsUnknownBatch() async {
        await #expect(throws: DomainError.batchNotFound) {
            try await makeUseCase().execute(batchID: Identifier(), temperatureCelsius: 72, allergensConfirmed: false)
        }
    }

    @Test func mapsRepositoryFailureToStorageFailure() async throws {
        let batch = try addBatch()

        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(batchesFail: true)
                .execute(batchID: batch.id, temperatureCelsius: 72, allergensConfirmed: false)
        }
    }
}
