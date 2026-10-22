import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct BatchListViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()
    let batches: InMemoryBatchRepository

    init() {
        batches = InMemoryBatchRepository(store: store)
    }

    private func addBatch(_ description: String, status: BatchStatus = .cleared,
                          collectedHoursAgo: Double) throws {
        let batch = FoodBatch(id: Identifier(), pickupID: Identifier(), foodDescription: description,
                              weight: try Weight(kilograms: 5), allergens: [], allergensDeclared: true,
                              holdWindow: HoldWindow(startedAt: now.addingTimeInterval(-collectedHoursAgo * hour)),
                              status: status)
        store.batches[batch.id] = batch
    }

    private func makeViewModel(permission: NotificationPermission = .authorized) -> BatchListViewModel {
        let fixedNow = now
        return BatchListViewModel(
            fetchExpiringBatches: FetchExpiringBatchesUseCase(batches: batches, now: { fixedNow }),
            notifications: InMemoryNotificationScheduler(permission: permission)
        )
    }

    // MARK: - Loading

    @Test func loadShowsOpenBatchesSoonestFirst() async throws {
        try addBatch("Fruit platter", collectedHoursAgo: 0.5)
        try addBatch("Beef lasagne", collectedHoursAgo: 3)
        try addBatch("Handed over", status: .handedOver, collectedHoursAgo: 2)
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batches.map(\.batch.foodDescription) == ["Beef lasagne", "Fruit platter"])
    }

    @Test func loadWithNoOpenBatchesShowsEmptyList() async {
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batches.isEmpty)
    }

    @Test func failedLoadShowsMessageAndCanBeRetried() async throws {
        try addBatch("Beef lasagne", collectedHoursAgo: 3)
        let viewModel = makeViewModel()
        batches.shouldFail = true

        await viewModel.load()
        #expect(viewModel.loadState == .failed(DomainError.storageFailure.errorDescription ?? ""))

        batches.shouldFail = false
        await viewModel.load()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.batches.count == 1)
    }

    // MARK: - Notifications banner

    @Test func showsBannerWhenNotificationsAreDenied() async {
        let viewModel = makeViewModel(permission: .denied)

        await viewModel.load()

        #expect(viewModel.notificationsDenied)
    }

    @Test(arguments: [NotificationPermission.authorized, .notDetermined])
    func hidesBannerUnlessNotificationsAreDenied(permission: NotificationPermission) async {
        let viewModel = makeViewModel(permission: permission)

        await viewModel.load()

        #expect(!viewModel.notificationsDenied)
    }
}
