import CoreData
import Foundation
import Testing
@testable import rescue_ready

struct CoreDataDropPointRepositoryTests {
    let controller = PersistenceController(inMemory: true)

    var repository: CoreDataDropPointRepository {
        CoreDataDropPointRepository(container: controller.container)
    }

    /// Stores drop points directly, so the tests don't depend on the sample data.
    private func insert(_ dropPoints: [DropPoint]) async throws {
        try await controller.container.performBackground(failure: .saveFailed) { context in
            for dropPoint in dropPoints {
                DropPointEntity(context: context).update(from: dropPoint)
            }
            try context.save()
        }
    }

    private func makeDropPoint(_ name: String, hours: ClosedRange<Int> = 8...20) -> DropPoint {
        DropPoint(id: Identifier(), name: name, address: "1 Test St, Sydney NSW 2000", openingHours: hours)
    }

    @Test func allReturnsEveryDropPointSortedByName() async throws {
        let zeta = makeDropPoint("Zeta Kitchen")
        let alpha = makeDropPoint("Alpha Pantry")
        let beta = makeDropPoint("Beta Meals")
        try await insert([zeta, alpha, beta])

        let dropPoints = try await repository.all()

        #expect(dropPoints.map(\.id) == [alpha.id, beta.id, zeta.id])
    }

    @Test func dropPointKeepsItsOpeningHours() async throws {
        let pantry = makeDropPoint("Redfern Community Kitchen", hours: 7...21)
        try await insert([pantry])

        let fetched = try await repository.dropPoint(id: pantry.id)
        let stored = try #require(fetched)

        #expect(stored == pantry)
        #expect(stored.openingHours == 7...21)
    }

    @Test func unknownDropPointReturnsNil() async throws {
        try await insert([makeDropPoint("Redfern Community Kitchen")])

        let missing = try await repository.dropPoint(id: Identifier())

        #expect(missing == nil)
    }
}
