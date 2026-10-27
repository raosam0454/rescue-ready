import Foundation
import Testing
@testable import rescue_ready

@MainActor
struct NewEventViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = InMemoryDataStore()
    let events: InMemoryEventRepository

    init() {
        events = InMemoryEventRepository(store: store)
    }

    private func makeViewModel() -> NewEventViewModel {
        let fixedNow = now
        return NewEventViewModel(createEvent: CreateEventUseCase(events: events, now: { fixedNow }),
                                 now: { fixedNow })
    }

    @Test func defaultsToAThreeHourEventStartingNow() {
        let viewModel = makeViewModel()

        #expect(viewModel.startsAt == now)
        #expect(viewModel.endsAt == now.addingTimeInterval(3 * 60 * 60))
    }

    @Test func cannotSaveWithoutNameAndVenue() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSave)

        viewModel.name = "Harbour Food Festival"
        #expect(!viewModel.canSave)

        viewModel.venue = "Barangaroo Reserve"
        #expect(viewModel.canSave)
    }

    @Test func savingReturnsTheNewEvent() async {
        let viewModel = makeViewModel()
        viewModel.name = "Harbour Food Festival"
        viewModel.venue = "Barangaroo Reserve"

        let event = await viewModel.save()

        #expect(event?.name == "Harbour Food Festival")
        #expect(store.events.count == 1)
        #expect(viewModel.state == .editing)
    }

    @Test func storageFailureShowsMessageAndAllowsRetry() async {
        let viewModel = makeViewModel()
        viewModel.name = "Harbour Food Festival"
        viewModel.venue = "Barangaroo Reserve"
        events.shouldFail = true

        let event = await viewModel.save()

        #expect(event == nil)
        #expect(viewModel.state == .failed(DomainError.storageFailure.errorDescription ?? ""))
        viewModel.dismissError()
        #expect(viewModel.canSave)
    }
}
