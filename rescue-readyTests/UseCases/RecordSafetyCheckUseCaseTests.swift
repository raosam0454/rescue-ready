//
//  Untitled.swift
//  rescue-ready
//
//  Created by Lam Nguyen on 21/10/2026.
//

import Foundation
import Testing
@testable import rescue_ready

struct RecordSafetyCheckUseCaseTests {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBatch(
        allergensDeclared: Bool = true,
        elapsedSeconds: TimeInterval = 0
    ) throws -> FoodBatch {
        FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Vegetable fried rice",
            weight: try Weight(kilograms: 8),
            allergens: [.soy],
            allergensDeclared: allergensDeclared,
            holdWindow: HoldWindow(
                startedAt: now.addingTimeInterval(-elapsedSeconds)
            ),
            status: .awaitingCheck,
            dropPointID: nil,
            discardReason: nil
        )
    }

    @Test
    func fixtureCreatesBatchAwaitingCheck() throws {
        let batch = try makeBatch()

        #expect(batch.status == .awaitingCheck)
        #expect(batch.allergensDeclared)
        #expect(batch.holdWindow.startedAt == now)
    }

    @Test
    func fixtureSupportsMissingAllergenDeclaration() throws {
        let batch = try makeBatch(allergensDeclared: false)

        #expect(batch.allergensDeclared == false)
    }

    @Test
    func fixtureSupportsHoldTimeScenarios() throws {
        let batch = try makeBatch(elapsedSeconds: 3600)

        #expect(
            batch.holdWindow.startedAt ==
            now.addingTimeInterval(-3600)
        )
    }
    
    // MARK: - Repository Tests

    @Test
    func loadsExistingBatchSuccessfully() async throws {
        let batch = try makeBatch()

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let result = try await useCase.loadBatch(id: batch.id)

        #expect(result == batch)
    }

    @Test
    func rejectsUnknownBatch() async {
        let repository = InMemoryBatchRepository()

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        await #expect(throws: DomainError.batchNotFound) {
            try await useCase.loadBatch(id: Identifier<FoodBatch>())
        }
    }

    @Test
    func mapsRepositoryFailureToDomainError() async {
        let repository = InMemoryBatchRepository()
        repository.shouldFail = true

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        await #expect(throws: DomainError.storageFailure) {
            try await useCase.loadBatch(id: Identifier<FoodBatch>())
        }
    }
    
    @Test
    func rejectsClosedBatches() async throws {

        for status in [BatchStatus.handedOver, .discarded] {

            var batch = try makeBatch()
            batch.status = status

            let store = InMemoryDataStore()
            store.batches[batch.id] = batch

            let repository = InMemoryBatchRepository(store: store)

            let useCase = RecordSafetyCheckUseCase(
                batches: repository,
                now: { now }
            )

            await #expect(throws: DomainError.batchAlreadyClosed) {
                try await useCase.loadOpenBatch(id: batch.id)
            }
        }
    }
    
    @Test
    func acceptsPlausibleTemperatureReading() throws {
        let repository = InMemoryBatchRepository()

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let input = SafetyCheckInput(
            batchID: Identifier<FoodBatch>(),
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        let temperature = try useCase.validateTemperature(from: input)

        #expect(temperature.celsius == 20)
    }

    @Test
    func rejectsImplausibleTemperatureReading() {
        let repository = InMemoryBatchRepository()

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let input = SafetyCheckInput(
            batchID: Identifier<FoodBatch>(),
            temperatureCelsius: 200,
            allergensConfirmed: true
        )

        #expect(throws: DomainError.invalidTemperatureReading) {
            try useCase.validateTemperature(from: input)
        }
    }
    
    @Test
    func allowsBatchAwaitingFirstCheck() async throws {

        let batch = try makeBatch()

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let result = try await useCase.loadCheckableBatch(
            id: batch.id
        )

        #expect(result.id == batch.id)
        #expect(result.status == .awaitingCheck)
    }

    @Test
    func rejectsPreviouslyCheckedBatches() async throws {

        for status in [BatchStatus.cleared, .failedCheck] {

            var batch = try makeBatch()
            batch.status = status

            let store = InMemoryDataStore()
            store.batches[batch.id] = batch

            let repository = InMemoryBatchRepository(store: store)

            let useCase = RecordSafetyCheckUseCase(
                batches: repository,
                now: { now }
            )

            await #expect(
                throws: SafetyCheckEligibilityError.alreadyChecked
            ) {
                try await useCase.loadCheckableBatch(id: batch.id)
            }
        }
    }
    
    @Test
    func acceptsConfirmedAllergens() throws {
        let batch = try makeBatch(allergensDeclared: true)

        let useCase = RecordSafetyCheckUseCase(
            batches: InMemoryBatchRepository(),
            now: { now }
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        try useCase.validateAllergens(
            for: batch,
            input: input
        )
    }

    @Test
    func rejectsMissingAllergenConfirmation() throws {
        let useCase = RecordSafetyCheckUseCase(
            batches: InMemoryBatchRepository(),
            now: { now }
        )

        // Test all combinations that lack required confirmation.
        for (declared, confirmed) in [
            (true, false),
            (false, true),
            (false, false)
        ] {
            let batch = try makeBatch(
                allergensDeclared: declared
            )

            let input = SafetyCheckInput(
                batchID: batch.id,
                temperatureCelsius: 20,
                allergensConfirmed: confirmed
            )

            #expect(throws: DomainError.allergensUndeclared) {
                try useCase.validateAllergens(
                    for: batch,
                    input: input
                )
            }
        }
    }
    
    @Test
    func prepareCheckValidatesInputsWithoutSaving() async throws {

        // Arrange: Create an eligible batch.
        let batch = try makeBatch(allergensDeclared: true)

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act: Prepare the safety check.
        let result = try await useCase.prepareCheck(input)

        // Assert: Correct batch and temperature returned.
        #expect(result.batch.id == batch.id)
        #expect(result.temperature.celsius == 20)

        // Assert: Batch status remains unchanged.
        let storedBatch = try await repository.batch(id: batch.id)
        #expect(storedBatch?.status == .awaitingCheck)

        // Assert: No safety check has been recorded yet.
        let recordedChecks = try await repository.checks(for: batch.id)
        #expect(recordedChecks.isEmpty)
    }
    
    @Test
    func executeRequiresReviewWithoutAssessor() async throws {

        // Arrange: Create an eligible batch.
        let batch = try makeBatch(allergensDeclared: true)

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        // No assessor is configured.
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act
        let result = try await useCase.execute(input)

        // Assert: The batch requires review.
        #expect(
            result == .requiresReview(
                reason: "Safety assessment rules have not been configured."
            )
        )

        // The batch must remain awaiting check.
        let storedBatch = try await repository.batch(id: batch.id)
        #expect(storedBatch?.status == .awaitingCheck)

        // No safety check should be recorded.
        let checks = try await repository.checks(for: batch.id)
        #expect(checks.isEmpty)
    }
    
    @Test
    func executeRecordsPassedSafetyCheck() async throws {

        // Arrange: Mock assessor returns Passed.
        struct MockAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .passed
            }
        }

        let batch = try makeBatch(allergensDeclared: true)

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now },
            assessor: MockAssessor()
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act
        let result = try await useCase.execute(input)

        // Assert: A SafetyCheck was recorded.
        guard case .recorded(let recordedCheck) = result else {
            Issue.record("Expected a recorded safety check.")
            return
        }

        #expect(recordedCheck.batchID == batch.id)
        #expect(recordedCheck.temperature.celsius == 20)
        #expect(recordedCheck.outcome == .passed)

        // Batch status must change to Cleared.
        let updatedBatch = try await repository.batch(id: batch.id)
        #expect(updatedBatch?.status == .cleared)

        // Repository must contain exactly one SafetyCheck.
        let checks = try await repository.checks(for: batch.id)

        #expect(checks.count == 1)
        #expect(checks.first == recordedCheck)
    }
    
    @Test
    func executeRecordsFailedSafetyCheck() async throws {

        // Arrange: Mock assessor rejects the batch.
        struct MockAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .failed(
                    reason: "Rejected by mock assessor"
                )
            }
        }

        let batch = try makeBatch(allergensDeclared: true)

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now },
            assessor: MockAssessor()
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act
        let result = try await useCase.execute(input)

        // Assert: A failed SafetyCheck was recorded.
        guard case .recorded(let recordedCheck) = result else {
            Issue.record("Expected a recorded safety check.")
            return
        }

        #expect(recordedCheck.batchID == batch.id)
        #expect(
            recordedCheck.outcome == .failed(
                reason: "Rejected by mock assessor"
            )
        )

        // Batch must transition to failedCheck.
        let updatedBatch = try await repository.batch(
            id: batch.id
        )

        #expect(updatedBatch?.status == .failedCheck)
        #expect(updatedBatch?.status != .cleared)

        // Repository must contain exactly one check.
        let checks = try await repository.checks(
            for: batch.id
        )

        #expect(checks.count == 1)
        #expect(checks.first == recordedCheck)
    }
    
    @Test
    func executeRequiresReviewWithoutRecording() async throws {

        // Arrange: Mock assessor requires manual review.
        struct MockAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .requiresReview(
                    reason: "Handling history is incomplete."
                )
            }
        }

        let batch = try makeBatch(allergensDeclared: true)

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(store: store)

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now },
            assessor: MockAssessor()
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act
        let result = try await useCase.execute(input)

        // Assert: Review is required.
        #expect(
            result == .requiresReview(
                reason: "Handling history is incomplete."
            )
        )

        // Batch status must remain unchanged.
        let updatedBatch = try await repository.batch(
            id: batch.id
        )

        #expect(updatedBatch?.status == .awaitingCheck)

        // No SafetyCheck should be recorded.
        let checks = try await repository.checks(
            for: batch.id
        )

        #expect(checks.isEmpty)
    }
    
    @Test
    func executeHandlesStorageFailure() async throws {

        // Mock assessor approves the batch.
        struct MockAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .passed
            }
        }

        // Simulates an unexpected database write error.
        struct SimulatedWriteError: Error {}

        struct FailingRecordRepository: BatchRepository {
            let existingBatch: FoodBatch

            func batch(
                id: Identifier<FoodBatch>
            ) async throws -> FoodBatch? {
                id == existingBatch.id ? existingBatch : nil
            }

            func openBatches() async throws -> [FoodBatch] {
                [existingBatch]
            }

            func batches(
                withStatus status: BatchStatus
            ) async throws -> [FoodBatch] {
                existingBatch.status == status ? [existingBatch] : []
            }

            func update(_ batch: FoodBatch) async throws {
                throw SimulatedWriteError()
            }

            func record(
                _ check: SafetyCheck,
                updating batch: FoodBatch
            ) async throws {
                throw SimulatedWriteError()
            }

            func checks(
                for batchID: Identifier<FoodBatch>
            ) async throws -> [SafetyCheck] {
                []
            }
        }

        // Arrange
        let batch = try makeBatch(allergensDeclared: true)

        let repository = FailingRecordRepository(
            existingBatch: batch
        )

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now },
            assessor: MockAssessor()
        )

        let input = SafetyCheckInput(
            batchID: batch.id,
            temperatureCelsius: 20,
            allergensConfirmed: true
        )

        // Act & Assert
        do {
            _ = try await useCase.execute(input)

            Issue.record(
                "Expected storageFailure, but execute succeeded."
            )
        } catch {
            #expect(
                error as? DomainError == .storageFailure
            )
        }
    }

    @Test
    func foodSafetyAssessorEvaluatesHandlingHistory() throws {

        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Prepared meals",
            weight: try Weight(kilograms: 2),
            allergens: [.milk],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: now),
            status: .awaitingCheck
        )

        let assessor = FoodSafetyAssessor()

        func evaluate(
            temperature: Double,
            seconds: TimeInterval?,
            confirmed: Bool = true
        ) throws -> SafetyAssessment {

            let input = SafetyCheckInput(
                batchID: batch.id,
                temperatureCelsius: temperature,
                allergensConfirmed: true,
                cumulativeDangerZoneSeconds: seconds,
                handlingHistoryConfirmed: confirmed
            )

            return assessor.assess(
                batch: batch,
                temperature: try Temperature(celsius: temperature),
                input: input,
                at: now
            )
        }

        // Missing handling history.
        #expect(
            try evaluate(temperature: 3, seconds: nil)
                == .requiresReview(
                    reason: "Complete handling history must be verified."
                )
        )

        // History has not been verified.
        #expect(
            try evaluate(
                temperature: 3,
                seconds: 1800,
                confirmed: false
            ) == .requiresReview(
                reason: "Complete handling history must be verified."
            )
        )

        // Less than two hours, controlled current temperature.
        #expect(
            try evaluate(temperature: 3, seconds: 3600)
                == .passed
        )

        // Exactly two hours: additional review required.
        #expect(
            try evaluate(temperature: 3, seconds: 7200)
                == .requiresReview(
                    reason: "Immediate-use conditions require verification."
                )
        )

        // Four hours or more: failed.
        #expect(
            try evaluate(temperature: 3, seconds: 14400)
                == .failed(
                    reason: "Cumulative danger-zone time is four hours or more."
                )
        )

        // Current reading in danger zone.
        #expect(
            try evaluate(temperature: 20, seconds: 1800)
                == .requiresReview(
                    reason: "Current temperature requires handling review."
                )
        )

        // Invalid handling duration.
        #expect(
            try evaluate(temperature: 3, seconds: -60)
                == .requiresReview(
                    reason: "Enter a valid cumulative handling duration."
                )
        )
    }

}

