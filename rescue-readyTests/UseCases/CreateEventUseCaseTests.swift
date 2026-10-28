import Foundation
import Testing
@testable import rescue_ready

struct CreateEventUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 60 * 60
    let store = InMemoryDataStore()

    private func makeUseCase(eventsFail: Bool = false) -> CreateEventUseCase {
        let events = InMemoryEventRepository(store: store)
        events.shouldFail = eventsFail
        let fixedNow = now
        return CreateEventUseCase(events: events, now: { fixedNow })
    }

    private func draft(name: String = "Harbour Food Festival", venue: String = "Barangaroo Reserve",
                       startsIn: Double = 0, lastsHours: Double = 3) -> NewEvent {
        let start = now.addingTimeInterval(startsIn * hour)
        return NewEvent(name: name, venue: venue, startsAt: start, endsAt: start.addingTimeInterval(lastsHours * hour))
    }

    @Test func savesEventWithTrimmedNameAndVenue() async throws {
        let event = try await makeUseCase().execute(draft(name: "  Harbour Food Festival ", venue: " Barangaroo \n"))

        #expect(event.name == "Harbour Food Festival")
        #expect(event.venue == "Barangaroo")
        #expect(store.events[event.id] == event)
    }

    @Test func createdEventIsImmediatelyAvailableForPickups() async throws {
        let event = try await makeUseCase().execute(draft())

        #expect(event.acceptsPickups(at: now))
    }

    @Test func allowsAnUpcomingEvent() async throws {
        let event = try await makeUseCase().execute(draft(startsIn: 48))

        #expect(store.events[event.id] != nil)
    }

    @Test func rejectsBlankName() async {
        await #expect(throws: DomainError.missingEventName) {
            try await makeUseCase().execute(draft(name: "   "))
        }
    }

    @Test func rejectsBlankVenue() async {
        await #expect(throws: DomainError.missingVenue) {
            try await makeUseCase().execute(draft(venue: ""))
        }
    }

    @Test(arguments: [0.0, -1.0, 25.0])
    func rejectsEndTimeNotAfterStartOrLongerThanADay(lastsHours: Double) async {
        await #expect(throws: DomainError.invalidEventTimes) {
            try await makeUseCase().execute(draft(lastsHours: lastsHours))
        }
        #expect(store.events.isEmpty)
    }

    @Test func rejectsEventThatStoppedAcceptingPickups() async {
        // Started 8 hours ago, ended 5 hours ago: past the 3 hour pickup window.
        await #expect(throws: DomainError.eventAlreadyFinished) {
            try await makeUseCase().execute(draft(startsIn: -8, lastsHours: 3))
        }
    }

    @Test func mapsRepositoryFailureToStorageFailure() async {
        await #expect(throws: DomainError.storageFailure) {
            try await makeUseCase(eventsFail: true).execute(draft())
        }
    }
}
