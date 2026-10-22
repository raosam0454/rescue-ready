import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct HandoverViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemoryDataStore()
    let batches: InMemoryBatchRepository
    let pantry: DropPoint
    let closedPantry: DropPoint

    init() {
        batches = InMemoryBatchRepository(store: store)

        let currentHour = Calendar.current.component(.hour, from: now)
        let closedHours = currentHour == 23 ? 0...22 : (currentHour + 1)...23
        pantry = DropPoint(id: Identifier(), name: "Redfern Community Kitchen",
                           address: "12 Regent St, Redfern NSW 2016", openingHours: 0...23)
        closedPantry = DropPoint(id: Identifier(), name: "Parramatta Neighbourhood Pantry",
                                 address: "48 Church St, Parramatta NSW 2150", openingHours: closedHours)
        store.dropPoints[pantry.id] = pantry
        store.dropPoints[closedPantry.id] = closedPantry
    }

    private func makeViewModel(status: BatchStatus) throws -> HandoverViewModel {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: "Vegetable fried rice",
                              weight: try Weight(kilograms: 8), allergens: [.soy], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-3600)), status: status)
        store.batches[batch.id] = batch

        let dropPoints = InMemoryDropPointRepository(store: store)
        let notifications = InMemoryNotificationScheduler()
        let fixedNow = now
        let clock = { fixedNow }
        return HandoverViewModel(
            batch: batch,
            handOver: HandOverBatchUseCase(batches: batches, dropPoints: dropPoints,
                                           notifications: notifications, now: clock),
            discard: DiscardBatchUseCase(batches: batches, notifications: notifications),
            fetchDropPoints: FetchDropPointsUseCase(dropPoints: dropPoints, now: clock),
            now: clock
        )
    }

    @Test func loadSelectsFirstOpenDropPoint() async throws {
        let viewModel = try makeViewModel(status: .cleared)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.selectedDropPointID == pantry.id)
        #expect(viewModel.canHandOver)
    }

    @Test func cannotHandOverToClosedDropPoint() async throws {
        let viewModel = try makeViewModel(status: .cleared)
        await viewModel.load()

        viewModel.selectedDropPointID = closedPantry.id

        #expect(!viewModel.canHandOver)
    }

    @Test(arguments: [BatchStatus.awaitingCheck, .failedCheck])
    func explainsWhyUnclearedBatchCannotBeHandedOver(status: BatchStatus) async throws {
        let viewModel = try makeViewModel(status: status)
        await viewModel.load()

        #expect(viewModel.handoverBlockedReason != nil)
        #expect(!viewModel.canHandOver)
    }

    @Test func successfulHandoverFinishesWithUpdatedBatch() async throws {
        let viewModel = try makeViewModel(status: .cleared)
        await viewModel.load()

        await viewModel.handOverBatch()

        #expect(viewModel.actionState == .handedOver)
        #expect(viewModel.batch.status == .handedOver)
        #expect(viewModel.batch.dropPointID == pantry.id)
        #expect(!viewModel.canDiscard)
    }

    @Test func discardNeedsAReason() async throws {
        let viewModel = try makeViewModel(status: .failedCheck)
        await viewModel.load()

        #expect(!viewModel.canDiscard)
        viewModel.discardReason = "   "
        #expect(!viewModel.canDiscard)
        viewModel.discardReason = "Failed temperature check"
        #expect(viewModel.canDiscard)
    }

    @Test func successfulDiscardFinishesWithUpdatedBatch() async throws {
        let viewModel = try makeViewModel(status: .failedCheck)
        await viewModel.load()
        viewModel.discardReason = "Failed temperature check"

        await viewModel.discardBatch()

        #expect(viewModel.actionState == .discarded)
        #expect(viewModel.batch.status == .discarded)
        #expect(viewModel.batch.discardReason == "Failed temperature check")
    }

    @Test func failedHandoverShowsMessageAndCanBeRetried() async throws {
        let viewModel = try makeViewModel(status: .cleared)
        await viewModel.load()
        batches.shouldFail = true

        await viewModel.handOverBatch()

        #expect(viewModel.actionState == .failed(DomainError.storageFailure.errorDescription ?? ""))
        #expect(viewModel.batch.status == .cleared)

        viewModel.dismissError()
        #expect(viewModel.canHandOver)
    }
}
