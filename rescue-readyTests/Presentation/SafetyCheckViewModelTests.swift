//
//  SafetyCheckViewModelTests.swift
//  rescue-ready
//
//  Created by Lam Nguyen on 21/10/2026.
//


import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct SafetyCheckViewModelTests {
    
    @Test
    func loadBatchResetsAllergenConfirmation() async throws {
        
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        
        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Vegetable fried rice",
            weight: try Weight(kilograms: 8),
            allergens: [.soy],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: now),
            status: .awaitingCheck,
            dropPointID: nil,
            discardReason: nil
        )
        
        let store = InMemoryDataStore()
        store.batches[batch.id] = batch
        
        let repository = InMemoryBatchRepository(store: store)
        
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )
        
        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )
        
        // Simulate an earlier user confirmation.
        viewModel.allergensConfirmed = true
        
        await viewModel.load()
        
        // Verify the correct batch was loaded.
        #expect(viewModel.batch == batch)
        
        // Verify loading completed successfully.
        #expect(viewModel.loadState == .loaded)
        
        // A new check requires fresh confirmation.
        #expect(viewModel.allergensConfirmed == false)
        
        // Submission must remain disabled for now.
        #expect(viewModel.canSubmit == false)
    }
    
    @Test
    func loadNonexistentBatchShowsError() async {

        // Arrange
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let repository = InMemoryBatchRepository()

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )

        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: Identifier<FoodBatch>()
        )

        // Act
        await viewModel.load()

        // Assert: No batch should be loaded.
        #expect(viewModel.batch == nil)

        // ViewModel should display the correct error.
        #expect(
            viewModel.loadState == .failed(
                DomainError.batchNotFound.errorDescription ?? ""
            )
        )

        // Safety check must remain unavailable.
        #expect(viewModel.canSubmit == false)
    }

    @Test
    func repositoryFailureShowsStorageError() async {
        
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        
        // Simulate a repository failure.
        let repository = InMemoryBatchRepository()
        repository.shouldFail = true
        
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { now }
        )
        
        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: Identifier<FoodBatch>()
        )
        
        await viewModel.load()
        
        // No batch should be available.
        #expect(viewModel.batch == nil)
        
        // The storage error should reach the UI state.
        #expect(
            viewModel.loadState == .failed(
                DomainError.storageFailure.errorDescription ?? ""
            )
        )
        
        // Submission must remain disabled.
        #expect(viewModel.canSubmit == false)
    }
    
    @Test
    @MainActor
    func submitWithoutLoadedBatchFails() async {
        
        // Arrange: Create a ViewModel without loading a batch.
        let repository = InMemoryBatchRepository(
            store: InMemoryDataStore()
        )
        
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { Date() }
        )
        
        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: Identifier<FoodBatch>()
        )
        
        // Act: Submit before calling load().
        await viewModel.submit()
        
        // Assert: Submission must fail safely.
        #expect(
            viewModel.saveState == .failed(
                "Food batch has not been loaded."
            )
        )
        
        // No batch should have been loaded or modified.
        #expect(viewModel.batch == nil)
    }
    
    @Test
    @MainActor
    func submitRecordsPassedResult() async throws {
        
        // MARK: - 1. Mock Safety Assessor
        
        struct PassedAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .passed
            }
        }
        
        // MARK: - 2. Create Test Batch
        
        let testNow = Date(timeIntervalSince1970: 1_800_000_000)
        
        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Prepared meals",
            weight: try Weight(kilograms: 2.0),
            allergens: [.milk],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: testNow),
            status: .awaitingCheck
        )
        
        // MARK: - 3. Set Up Repository
        
        let store = InMemoryDataStore()
        store.batches[batch.id] = batch
        
        let repository = InMemoryBatchRepository(
            store: store
        )
        
        // MARK: - 4. Set Up Use Case
        
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { testNow },
            assessor: PassedAssessor()
        )
        
        // MARK: - 5. Create ViewModel
        
        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )
        
        // MARK: - 6. Load Batch
        
        await viewModel.load()
        
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batch?.id == batch.id)
        #expect(viewModel.batch?.status == .awaitingCheck)
        
        // MARK: - 7. Enter Safety Information
        
        viewModel.temperatureInput = "20"
        viewModel.allergensConfirmed = true
        
        // MARK: - 8. Submit Safety Check
        
        await viewModel.submit()
        
        // MARK: - 9. Verify ViewModel State
        
        #expect(viewModel.saveState == .saved)
        #expect(viewModel.batch?.status == .cleared)
        
        // MARK: - 10. Verify Repository
        
        let updatedBatch = try await repository.batch(
            id: batch.id
        )
        
        #expect(updatedBatch?.status == .cleared)
        
        let checks = try await repository.checks(
            for: batch.id
        )
        
        #expect(checks.count == 1)
        #expect(checks.first?.outcome == .passed)
        #expect(checks.first?.batchID == batch.id)
        #expect(checks.first?.temperature.celsius == 20)
    }
    
    @Test
    @MainActor
    func submitRecordsFailedResult() async throws {

        // MARK: - 1. Mock Safety Assessor

        struct FailedAssessor: SafetyCheckAssessing {
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

        // MARK: - 2. Create Test Batch

        let testNow = Date(
            timeIntervalSince1970: 1_800_000_000
        )

        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Prepared meals",
            weight: try Weight(kilograms: 2.0),
            allergens: [.milk],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: testNow),
            status: .awaitingCheck
        )

        // MARK: - 3. Set Up Repository

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(
            store: store
        )

        // MARK: - 4. Set Up Use Case

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { testNow },
            assessor: FailedAssessor()
        )

        // MARK: - 5. Create ViewModel

        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )

        // MARK: - 6. Load Batch

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batch?.id == batch.id)
        #expect(viewModel.batch?.status == .awaitingCheck)

        // MARK: - 7. Enter Safety Information

        viewModel.temperatureInput = "20"
        viewModel.allergensConfirmed = true

        // MARK: - 8. Submit Safety Check

        await viewModel.submit()

        // MARK: - 9. Verify ViewModel State

        // Recording succeeded, even though the check failed.
        #expect(viewModel.saveState == .saved)

        // A failed batch must not become cleared.
        #expect(viewModel.batch?.status == .failedCheck)
        #expect(viewModel.batch?.status != .cleared)

        // MARK: - 10. Verify Repository

        let updatedBatch = try await repository.batch(
            id: batch.id
        )

        #expect(updatedBatch?.status == .failedCheck)

        let checks = try await repository.checks(
            for: batch.id
        )

        #expect(checks.count == 1)

        #expect(
            checks.first?.outcome == .failed(
                reason: "Rejected by mock assessor"
            )
        )

        #expect(checks.first?.batchID == batch.id)
        #expect(checks.first?.temperature.celsius == 20)
    }
    
    @Test
    @MainActor
    func submitRequiresReviewWithoutAssessor() async throws {

        // MARK: - 1. Create Test Batch

        let testNow = Date(
            timeIntervalSince1970: 1_800_000_000
        )

        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Prepared meals",
            weight: try Weight(kilograms: 2.0),
            allergens: [.milk],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: testNow),
            status: .awaitingCheck
        )

        // MARK: - 2. Set Up Repository

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(
            store: store
        )

        // MARK: - 3. Set Up Use Case

        // No Safety Assessor is configured.
        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { testNow }
        )

        // MARK: - 4. Create ViewModel

        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )

        // MARK: - 5. Load Batch

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batch?.status == .awaitingCheck)

        // MARK: - 6. Enter Safety Information

        viewModel.temperatureInput = "20"
        viewModel.allergensConfirmed = true

        // MARK: - 7. Submit

        await viewModel.submit()

        // MARK: - 8. Verify Review State

        #expect(
            viewModel.saveState == .requiresReview(
                "Safety assessment rules have not been configured."
            )
        )

        // Batch must not be cleared.
        #expect(viewModel.batch?.status == .awaitingCheck)

        // MARK: - 9. Verify Repository

        let storedBatch = try await repository.batch(
            id: batch.id
        )

        #expect(storedBatch?.status == .awaitingCheck)

        let checks = try await repository.checks(
            for: batch.id
        )

        #expect(checks.isEmpty)
    }

    @Test
    @MainActor
    func canSubmitRequiresValidInputsAndAssessor() async throws {

        // MARK: - 1. Mock Assessor

        struct ReviewAssessor: SafetyCheckAssessing {
            func assess(
                batch: FoodBatch,
                temperature: Temperature,
                input: SafetyCheckInput,
                at checkedAt: Date
            ) -> SafetyAssessment {
                return .requiresReview(
                    reason: "Handling history requires review."
                )
            }
        }

        // MARK: - 2. Create Test Batch

        let testNow = Date(
            timeIntervalSince1970: 1_800_000_000
        )

        let batch = FoodBatch(
            id: Identifier(),
            pickupID: Identifier(),
            foodDescription: "Prepared meals",
            weight: try Weight(kilograms: 2.0),
            allergens: [.milk],
            allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: testNow),
            status: .awaitingCheck
        )

        let store = InMemoryDataStore()
        store.batches[batch.id] = batch

        let repository = InMemoryBatchRepository(
            store: store
        )

        // MARK: - 3. Without Assessor

        let useCaseWithoutAssessor = RecordSafetyCheckUseCase(
            batches: repository,
            now: { testNow }
        )

        let disabledViewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCaseWithoutAssessor,
            batchID: batch.id
        )

        await disabledViewModel.load()

        disabledViewModel.temperatureInput = "20"
        disabledViewModel.allergensConfirmed = true

        // Even valid inputs cannot bypass missing safety rules.
        #expect(disabledViewModel.canSubmit == false)

        // MARK: - 4. With Mock Assessor

        let useCase = RecordSafetyCheckUseCase(
            batches: repository,
            now: { testNow },
            assessor: ReviewAssessor()
        )

        let viewModel = SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )

        // Cannot submit before loading.
        #expect(viewModel.canSubmit == false)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)

        // Cannot submit without temperature or confirmation.
        #expect(viewModel.canSubmit == false)

        // Invalid temperature format.
        viewModel.temperatureInput = "abc"
        viewModel.allergensConfirmed = true

        #expect(viewModel.canSubmit == false)

        // Implausible temperature.
        viewModel.temperatureInput = "200"

        #expect(viewModel.canSubmit == false)

        // Missing allergen confirmation.
        viewModel.temperatureInput = "20"
        viewModel.allergensConfirmed = false

        #expect(viewModel.canSubmit == false)


        // MARK: - 5. Valid Inputs

        viewModel.allergensConfirmed = true

        // Provide complete handling information.
        viewModel.dangerZoneMinutesInput = "30"
        viewModel.handlingHistoryConfirmed = true

        // All submission requirements are now satisfied.
        #expect(viewModel.canSubmit == true)

        // MARK: - 6. Remove Temperature

        viewModel.temperatureInput = ""

        #expect(viewModel.canSubmit == false)
    }
}
