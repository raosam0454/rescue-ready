import Foundation

/// Storage for events. Implementations throw `RepositoryError` on storage failures.
protocol EventRepository {
    func event(id: Identifier<Event>) async throws -> Event?

    /// Events that accept pickups at `date`, earliest start first.
    func events(acceptingPickupsAt date: Date) async throws -> [Event]

    /// Inserts the event, or replaces it if an event with the same ID exists.
    func save(_ event: Event) async throws
}
