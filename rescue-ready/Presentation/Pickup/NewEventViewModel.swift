import Foundation
import Observation

/// State and actions for creating a new event.
@MainActor
@Observable
final class NewEventViewModel {
    enum State: Equatable {
        case editing
        case saving
        case failed(String)
    }

    var name = ""
    var venue = ""
    var startsAt: Date
    var endsAt: Date
    private(set) var state: State = .editing

    private let createEvent: CreateEventUseCase

    init(createEvent: CreateEventUseCase, now: () -> Date) {
        self.createEvent = createEvent
        // Defaults to an event happening now, the most common case at a venue.
        let start = now()
        startsAt = start
        endsAt = start.addingTimeInterval(3 * 60 * 60)
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .saving
    }

    /// Saves the event. Returns it on success so the caller can select it.
    func save() async -> Event? {
        guard canSave else { return nil }
        state = .saving
        do {
            let event = try await createEvent.execute(
                NewEvent(name: name, venue: venue, startsAt: startsAt, endsAt: endsAt)
            )
            state = .editing
            return event
        } catch {
            let domainError = (error as? DomainError) ?? .storageFailure
            state = .failed(domainError.errorDescription ?? "")
            return nil
        }
    }

    func dismissError() {
        if case .failed = state { state = .editing }
    }
}
