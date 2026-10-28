import CoreData
import Foundation
import Testing
@testable import rescue_ready

struct CoreDataSeederTests {
    let controller = PersistenceController(inMemory: true)
    let now = Date()

    private func count<T: NSManagedObject>(_ type: T.Type) async throws -> Int {
        try await controller.container.performBackground(failure: .fetchFailed) { context in
            try context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))
        }
    }

    @Test func dropPointsAreAddedOnlyWhenNoneExist() async throws {
        let first = try await CoreDataSeeder.ensureDropPoints(SampleData.dropPoints, in: controller.container)
        let second = try await CoreDataSeeder.ensureDropPoints(SampleData.dropPoints, in: controller.container)

        #expect(first)
        #expect(!second)
        #expect(try await count(DropPointEntity.self) == SampleData.dropPoints.count)
    }

    @Test func dropPointsAreAvailableForHandoverWithoutSampleData() async throws {
        try await CoreDataSeeder.ensureDropPoints(SampleData.dropPoints, in: controller.container)

        let dropPoints = try await CoreDataDropPointRepository(container: controller.container).all()

        #expect(Set(dropPoints.map(\.id)) == Set(SampleData.dropPoints.map(\.id)))
    }

    /// Regression test: the launch steps and the sample seed both write the volunteer and
    /// drop points. They must not create duplicates or leave records unlinked.
    @Test func sampleSeedReusesTheVolunteerAndDropPointsCreatedAtLaunch() async throws {
        try await CoreDataSeeder.ensureVolunteer(SampleData.volunteer, in: controller.container)
        try await CoreDataSeeder.ensureDropPoints(SampleData.dropPoints, in: controller.container)
        try await CoreDataSeeder.seedIfEmpty(controller.container, now: now)

        #expect(try await count(VolunteerEntity.self) == 1)
        #expect(try await count(DropPointEntity.self) == SampleData.dropPoints.count)

        let links = try await controller.container.performBackground(failure: .fetchFailed) { context in
            let pickups = try context.fetch(NSFetchRequest<PickupEntity>(entityName: "PickupEntity"))
            let handedOver = NSFetchRequest<FoodBatchEntity>(entityName: "FoodBatchEntity")
            handedOver.predicate = NSPredicate(format: "statusRaw == %@", BatchStatus.handedOver.rawValue)
            let batches = try context.fetch(handedOver)
            return (pickups.allSatisfy { $0.volunteer != nil }, batches.allSatisfy { $0.dropPoint != nil }, pickups.count)
        }
        #expect(links.2 > 0)
        #expect(links.0, "Every sample pickup should keep its volunteer")
        #expect(links.1, "Every handed-over sample batch should keep its drop point")
    }
}
