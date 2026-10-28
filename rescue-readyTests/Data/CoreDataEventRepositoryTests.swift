import CoreData
import Foundation
import Testing
@testable import rescue_ready

struct CoreDataEventRepositoryTests {
    let controller = PersistenceController(inMemory: true)
    let now = Date()

    private func makeEvent(name: String = "Harbour Food Festival") -> Event {
        Event(id: Identifier(), name: name, venue: "Barangaroo Reserve",
              startsAt: now.addingTimeInterval(-3600), endsAt: now.addingTimeInterval(3600))
    }

    @Test func savedEventCanBeReadBack() async throws {
        let repository = CoreDataEventRepository(container: controller.container)
        let event = makeEvent()

        try await repository.save(event)

        let fetched = try await repository.event(id: event.id)
        #expect(fetched?.name == event.name)
        let active = try await repository.events(acceptingPickupsAt: now)
        #expect(active.contains { $0.id == event.id })
    }

    @Test func savingTheSameEventAgainUpdatesIt() async throws {
        let repository = CoreDataEventRepository(container: controller.container)
        var event = makeEvent()
        try await repository.save(event)

        event.name = "Harbour Food Festival Day 2"
        try await repository.save(event)

        let active = try await repository.events(acceptingPickupsAt: now)
        #expect(active.filter { $0.id == event.id }.count == 1)
        #expect(active.first { $0.id == event.id }?.name == "Harbour Food Festival Day 2")
    }

    @Test func ensuringTheVolunteerTwiceKeepsOneRecord() async throws {
        let volunteer = Volunteer(id: Identifier(), name: "Volunteer")

        try await CoreDataSeeder.ensureVolunteer(volunteer, in: controller.container)
        try await CoreDataSeeder.ensureVolunteer(volunteer, in: controller.container)

        let count = try await controller.container.performBackground(failure: .fetchFailed) { context in
            try context.count(for: NSFetchRequest<VolunteerEntity>(entityName: "VolunteerEntity"))
        }
        #expect(count == 1)
    }
}
