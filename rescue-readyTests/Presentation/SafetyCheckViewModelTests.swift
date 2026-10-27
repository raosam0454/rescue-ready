import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct SafetyCheckViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemoryDataStore()
    let batches: InMemoryBatchRepository
    let batch: FoodBatch

    init() throws {
        batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Lamb curry",
                          weight: try Weight(kilograms: 6), allergens: [.milk], allergensDeclared: false,
                          holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-3600)),
                          status: .awaitingCheck)
        store.batches[batch.id] = batch
        batches = InMemoryBatchRepository(store: store)
    }

    private func makeViewModel() -> SafetyCheckViewModel {
        let fixedNow = now
        let alerts = ScheduleExpiryAlertUseCase(batches: batches, notifications: InMemoryNotificationScheduler(),
                                                now: { fixedNow })
        return SafetyCheckViewModel(
            batch: batch,
            recordCheck: RecordSafetyCheckUseCase(batches: batches, scheduleExpiryAlert: alerts, now: { fixedNow }),
            now: { fixedNow }
        )
    }

    @Test func cannotSubmitUntilTemperatureAndAllergensAreEntered() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.temperatureText = "72"
        #expect(!viewModel.canSubmit)

        viewModel.allergensConfirmed = true
        #expect(viewModel.canSubmit)
    }

    @Test func warnsWhileTypingADangerZoneTemperature() {
        let viewModel = makeViewModel()

        viewModel.temperatureText = "25"
        #expect(viewModel.temperatureWarning == DomainError.temperatureOutOfRange.errorDescription)

        viewModel.temperatureText = "72"
        #expect(viewModel.temperatureWarning == nil)
    }

    @Test func passingCheckClearsTheBatch() async {
        let viewModel = makeViewModel()
        viewModel.temperatureText = "72"
        viewModel.allergensConfirmed = true

        await viewModel.submit()

        guard case .passed = viewModel.state else {
            Issue.record("Expected a passed state, got \(viewModel.state)")
            return
        }
        #expect(viewModel.batch.status == .cleared)
        #expect(viewModel.isFinished)
    }

    @Test func dangerZoneTemperatureBlocksTheBatch() async {
        let viewModel = makeViewModel()
        viewModel.temperatureText = "25"
        viewModel.allergensConfirmed = true

        await viewModel.submit()

        #expect(viewModel.state == .blocked(DomainError.temperatureOutOfRange.errorDescription ?? ""))
        #expect(viewModel.batch.status == .failedCheck)
    }

    @Test func storageFailureLetsTheVolunteerTryAgain() async {
        let viewModel = makeViewModel()
        viewModel.temperatureText = "72"
        viewModel.allergensConfirmed = true
        batches.shouldFail = true

        await viewModel.submit()
        #expect(viewModel.state == .failed(DomainError.storageFailure.errorDescription ?? ""))

        viewModel.dismissError()
        #expect(viewModel.state == .editing)
        #expect(viewModel.canSubmit)
    }
}
