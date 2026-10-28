import Foundation

/// Realistic demo data for previews, screenshots and running the app without Core Data.
enum SampleData {
    /// The volunteer the sample data is recorded against.
    /// Uses a fixed ID so the seeded volunteer still matches after the app relaunches.
    static let volunteer = Volunteer(
        id: Identifier(UUID(uuidString: "6F2C8A4E-3B1D-4C7A-9E55-2D8F1A0B7C31") ?? UUID()),
        name: "Priya Sharma"
    )

    /// Example drop points, loaded in every build so a batch can always be handed over.
    /// Fixed IDs so they match across launches and across seeding steps.
    static let dropPoints: [DropPoint] = [
        DropPoint(id: Identifier(UUID(uuidString: "2B7E4C1A-8D3F-4A6B-9C21-5E0F7A3D9B14") ?? UUID()),
                  name: "Redfern Community Kitchen",
                  address: "12 Regent St, Redfern NSW 2016", openingHours: 7...21),
        DropPoint(id: Identifier(UUID(uuidString: "9A1D6F3E-4C2B-4E8A-B7D5-0F3C8E2A6D47") ?? UUID()),
                  name: "Parramatta Neighbourhood Pantry",
                  address: "48 Church St, Parramatta NSW 2150", openingHours: 9...17),
    ]

    /// A store filled with sample events, drop points, a pickup and batches.
    /// Times are relative to `now` so batches always show realistic time left.
    static func makeStore(now: Date = Date()) -> InMemoryDataStore {
        let store = InMemoryDataStore()
        do {
            try populate(store, now: now)
        } catch {
            // Sample values are fixed and valid; an empty store is a safe fallback.
        }
        return store
    }

    private static func populate(_ store: InMemoryDataStore, now: Date) throws {
        let hour: TimeInterval = 60 * 60

        store.volunteers[volunteer.id] = volunteer

        let match = Event(id: Identifier(), name: "Rugby League Semi-final",
                          venue: "Sydney Olympic Park",
                          startsAt: now.addingTimeInterval(-4 * hour),
                          endsAt: now.addingTimeInterval(-1 * hour))
        let summit = Event(id: Identifier(), name: "Harbour Tech Summit",
                           venue: "Darling Harbour Convention Centre",
                           startsAt: now.addingTimeInterval(-2 * hour),
                           endsAt: now.addingTimeInterval(3 * hour))
        for event in [match, summit] { store.events[event.id] = event }

        let redfern = dropPoints[0]
        let parramatta = dropPoints[1]
        for dropPoint in dropPoints { store.dropPoints[dropPoint.id] = dropPoint }

        let pickup = Pickup(id: Identifier(), eventID: match.id, volunteerID: volunteer.id,
                            collectedAt: now.addingTimeInterval(-1.5 * hour))
        store.pickups[pickup.id] = pickup

        let collected = HoldWindow(startedAt: pickup.collectedAt)
        let batches = [
            FoodBatch(id: Identifier(), pickupID: pickup.id, foodDescription: "Vegetable fried rice",
                      weight: try Weight(kilograms: 8), allergens: [.soy, .egg], allergensDeclared: true,
                      holdWindow: collected, status: .cleared),
            FoodBatch(id: Identifier(), pickupID: pickup.id, foodDescription: "Chicken skewers",
                      weight: try Weight(kilograms: 5.5), allergens: [], allergensDeclared: false,
                      holdWindow: collected, status: .awaitingCheck),
            FoodBatch(id: Identifier(), pickupID: pickup.id, foodDescription: "Garden salad",
                      weight: try Weight(kilograms: 3), allergens: [], allergensDeclared: true,
                      holdWindow: collected, status: .failedCheck),
            FoodBatch(id: Identifier(), pickupID: pickup.id, foodDescription: "Pasta bake",
                      weight: try Weight(kilograms: 12), allergens: [.wheat, .milk], allergensDeclared: true,
                      holdWindow: collected, status: .handedOver, dropPointID: redfern.id)
        ]
        for batch in batches { store.batches[batch.id] = batch }

        try populateHistory(store, now: now, dropPoints: [redfern, parramatta])
    }

    /// Earlier rescues, so the Impact dashboard shows a realistic track record.
    private static func populateHistory(_ store: InMemoryDataStore, now: Date, dropPoints: [DropPoint]) throws {
        let day: TimeInterval = 24 * 60 * 60
        guard dropPoints.count == 2 else { return }
        let redfern = dropPoints[0]
        let parramatta = dropPoints[1]

        let gala = Event(id: Identifier(), name: "Charity Gala Dinner", venue: "Hilton Sydney",
                         startsAt: now.addingTimeInterval(-3 * day), endsAt: now.addingTimeInterval(-3 * day + 4 * 3600))
        let concert = Event(id: Identifier(), name: "Summer Concert Series", venue: "The Domain, Sydney",
                            startsAt: now.addingTimeInterval(-6 * day), endsAt: now.addingTimeInterval(-6 * day + 5 * 3600))
        for event in [gala, concert] { store.events[event.id] = event }

        let galaPickup = Pickup(id: Identifier(), eventID: gala.id, volunteerID: volunteer.id,
                                collectedAt: gala.endsAt.addingTimeInterval(1800))
        let concertPickup = Pickup(id: Identifier(), eventID: concert.id, volunteerID: volunteer.id,
                                   collectedAt: concert.endsAt.addingTimeInterval(1800))
        for pickup in [galaPickup, concertPickup] { store.pickups[pickup.id] = pickup }

        let galaWindow = HoldWindow(startedAt: galaPickup.collectedAt)
        let concertWindow = HoldWindow(startedAt: concertPickup.collectedAt)
        let history = [
            FoodBatch(id: Identifier(), pickupID: galaPickup.id, foodDescription: "Roast vegetable lasagne",
                      weight: try Weight(kilograms: 14), allergens: [.wheat, .milk, .egg], allergensDeclared: true,
                      holdWindow: galaWindow, status: .handedOver, dropPointID: redfern.id),
            FoodBatch(id: Identifier(), pickupID: galaPickup.id, foodDescription: "Bread rolls",
                      weight: try Weight(kilograms: 4.5), allergens: [.wheat, .gluten], allergensDeclared: true,
                      holdWindow: galaWindow, status: .handedOver, dropPointID: parramatta.id),
            FoodBatch(id: Identifier(), pickupID: galaPickup.id, foodDescription: "Prawn cocktail cups",
                      weight: try Weight(kilograms: 2), allergens: [.crustacean, .egg], allergensDeclared: true,
                      holdWindow: galaWindow, status: .discarded, discardReason: "Held above 5°C for too long"),
            FoodBatch(id: Identifier(), pickupID: concertPickup.id, foodDescription: "Beef and black bean stir-fry",
                      weight: try Weight(kilograms: 10), allergens: [.soy, .wheat], allergensDeclared: true,
                      holdWindow: concertWindow, status: .handedOver, dropPointID: parramatta.id),
            FoodBatch(id: Identifier(), pickupID: concertPickup.id, foodDescription: "Fruit platters",
                      weight: try Weight(kilograms: 6), allergens: [], allergensDeclared: true,
                      holdWindow: concertWindow, status: .handedOver, dropPointID: redfern.id)
        ]
        for batch in history { store.batches[batch.id] = batch }
    }
}
