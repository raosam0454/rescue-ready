import CoreData
import Foundation

/// Prepares the store on launch: the volunteer's own record, plus sample data in debug builds.
enum CoreDataSeeder {
    /// Makes sure the device's volunteer exists, so pickups can be saved against them.
    /// Does nothing if they already exist.
    static func ensureVolunteer(_ volunteer: Volunteer, in container: NSPersistentContainer) async throws {
        try await container.performBackground(failure: .saveFailed) { context in
            guard try context.fetchOne(VolunteerEntity.self, id: volunteer.id.rawValue) == nil else { return }
            VolunteerEntity(context: context).update(from: volunteer)
            try context.save()
        }
    }

    /// Inserts sample data only when the store has no events. Returns true if it seeded.
    @discardableResult
    static func seedIfEmpty(_ container: NSPersistentContainer, now: Date = Date()) async throws -> Bool {
        let sample = SampleData.makeStore(now: now)

        return try await container.performBackground(failure: .saveFailed) { context in
            let existing = NSFetchRequest<EventEntity>(entityName: "EventEntity")
            guard try context.count(for: existing) == 0 else { return false }

            var events: [UUID: EventEntity] = [:]
            for event in sample.events.values {
                let entity = EventEntity(context: context)
                entity.update(from: event)
                events[event.id.rawValue] = entity
            }

            var volunteers: [UUID: VolunteerEntity] = [:]
            for volunteer in sample.volunteers.values {
                let entity = VolunteerEntity(context: context)
                entity.update(from: volunteer)
                volunteers[volunteer.id.rawValue] = entity
            }

            var dropPoints: [UUID: DropPointEntity] = [:]
            for dropPoint in sample.dropPoints.values {
                let entity = DropPointEntity(context: context)
                entity.update(from: dropPoint)
                dropPoints[dropPoint.id.rawValue] = entity
            }

            var pickups: [UUID: PickupEntity] = [:]
            for pickup in sample.pickups.values {
                let entity = PickupEntity(context: context)
                entity.update(from: pickup)
                entity.event = events[pickup.eventID.rawValue]
                entity.volunteer = volunteers[pickup.volunteerID.rawValue]
                pickups[pickup.id.rawValue] = entity
            }

            var batches: [UUID: FoodBatchEntity] = [:]
            for batch in sample.batches.values {
                let entity = FoodBatchEntity(context: context)
                entity.update(from: batch)
                entity.pickup = pickups[batch.pickupID.rawValue]
                entity.dropPoint = batch.dropPointID.flatMap { dropPoints[$0.rawValue] }
                batches[batch.id.rawValue] = entity
            }

            for check in sample.checks {
                let entity = SafetyCheckEntity(context: context)
                entity.update(from: check)
                entity.batch = batches[check.batchID.rawValue]
            }

            try context.save()
            return true
        }
    }
}
