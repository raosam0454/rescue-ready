import Foundation

/// Details of an event entered by the volunteer, before it is validated.
struct NewEvent: Equatable {
    var name: String
    var venue: String
    var startsAt: Date
    var endsAt: Date
}

/// Creates the event a volunteer is collecting surplus food from.
///
/// Rules:
/// - name and venue are required; whitespace alone does not count
/// - the event must end after it starts, and last no more than 24 hours
/// - an event that stopped accepting pickups (3 hours after it ended) cannot be created
struct CreateEventUseCase {
    static let maximumDuration: TimeInterval = 24 * 60 * 60

    let events: EventRepository
    /// Injected so tests control time. Never call `Date()` directly in a use case.
    let now: () -> Date

    func execute(_ draft: NewEvent) async throws -> Event {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let venue = draft.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.missingEventName }
        guard !venue.isEmpty else { throw DomainError.missingVenue }

        let duration = draft.endsAt.timeIntervalSince(draft.startsAt)
        guard duration > 0, duration <= Self.maximumDuration else { throw DomainError.invalidEventTimes }

        let event = Event(id: Identifier(), name: name, venue: venue,
                          startsAt: draft.startsAt, endsAt: draft.endsAt)
        // Same window as Event.acceptsPickups(at:): an event is useful until 3 hours after it ends.
        guard event.endsAt.addingTimeInterval(Event.pickupGracePeriod) >= now() else {
            throw DomainError.eventAlreadyFinished
        }

        do {
            try await events.save(event)
        } catch {
            throw DomainError.storageFailure
        }
        return event
    }
}
