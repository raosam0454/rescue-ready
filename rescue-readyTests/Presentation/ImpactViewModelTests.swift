import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct ImpactViewModelTests {
    let store = InMemoryDataStore()
    let batches: InMemoryBatchRepository
    let pantry = DropPoint(id: Identifier(), name: "Redfern Community Kitchen",
                           address: "12 Regent St, Redfern NSW 2016", openingHours: 7...21)

    init() {
        store.dropPoints[pantry.id] = pantry
        batches = InMemoryBatchRepository(store: store)
    }

    private func makeViewModel() -> ImpactViewModel {
        ImpactViewModel(computeImpactStats: ComputeImpactStatsUseCase(
            batches: batches, dropPoints: InMemoryDropPointRepository(store: store)
        ))
    }

    private func addBatch(_ kilograms: Double, _ status: BatchStatus) throws {
        let batch = FoodBatch(
            id: Identifier(), pickupID: Identifier(), foodDescription: "Pasta bake",
            weight: try Weight(kilograms: kilograms), allergens: [.wheat], allergensDeclared: true,
            holdWindow: HoldWindow(startedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            status: status, dropPointID: status == .handedOver ? pantry.id : nil
        )
        store.batches[batch.id] = batch
    }

    @Test func startsInLoadingState() {
        #expect(makeViewModel().state == .loading)
    }

    @Test func loadShowsComputedStats() async throws {
        try addBatch(12, .handedOver)
        try addBatch(3, .discarded)
        let viewModel = makeViewModel()

        await viewModel.load()

        guard case .loaded(let stats) = viewModel.state else {
            Issue.record("Expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(stats.kilogramsSaved == 12)
        #expect(stats.estimatedMeals == 24)
        #expect(viewModel.rescueRateText != nil)
    }

    @Test func loadShowsFriendlyMessageWhenStorageFails() async {
        batches.shouldFail = true
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.state == .failed(DomainError.storageFailure.errorDescription ?? ""))
    }

    @Test func reloadPicksUpNewHandovers() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        #expect(viewModel.state == .loaded(.empty))

        try addBatch(5, .handedOver)
        await viewModel.load()

        guard case .loaded(let stats) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(stats.batchesHandedOver == 1)
    }
}
