import Foundation

final class InMemoryEventRepository: EventRepository {
    private let store: InMemoryDataStore
    /// Set to true to make every call throw, for testing error handling.
    var shouldFail = false

    init(store: InMemoryDataStore = InMemoryDataStore()) {
        self.store = store
    }

    func event(id: Identifier<Event>) async throws -> Event? {
        if shouldFail { throw RepositoryError.fetchFailed }
        return store.events[id]
    }

    func events(acceptingPickupsAt date: Date) async throws -> [Event] {
        if shouldFail { throw RepositoryError.fetchFailed }
        return store.events.values
            .filter { $0.acceptsPickups(at: date) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func save(_ event: Event) async throws {
        if shouldFail { throw RepositoryError.saveFailed }
        store.events[event.id] = event
    }
}
