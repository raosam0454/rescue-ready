import Foundation

/// Builds and wires every dependency in one place.
///
/// Each feature adds a `make<Feature>ViewModel()` factory here. Views never create
/// repositories or use cases themselves.
@MainActor
final class AppContainer {
    let persistence: PersistenceController
    let currentVolunteerID: Identifier<Volunteer>
    let now: () -> Date

    let eventRepository: EventRepository
    let pickupRepository: PickupRepository
    let batchRepository: BatchRepository
    let dropPointRepository: DropPointRepository
    let notificationScheduler: NotificationScheduling

    init(persistence: PersistenceController = PersistenceController(), now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        self.now = now
        currentVolunteerID = SampleData.volunteer.id

        // Used when the Core Data store fails to load, and for repositories
        // that do not have a Core Data implementation yet.
        let fallbackStore = SampleData.makeStore(now: now())

        if persistence.isAvailable {
            eventRepository = CoreDataEventRepository(container: persistence.container)
            pickupRepository = CoreDataPickupRepository(container: persistence.container)
            batchRepository = CoreDataBatchRepository(container: persistence.container)
            dropPointRepository = CoreDataDropPointRepository(container: persistence.container)
        } else {
            eventRepository = InMemoryEventRepository(store: fallbackStore)
            pickupRepository = InMemoryPickupRepository(store: fallbackStore)
            batchRepository = InMemoryBatchRepository(store: fallbackStore)
            dropPointRepository = InMemoryDropPointRepository(store: fallbackStore)
        }

        notificationScheduler = UNNotificationScheduler()
    }

    /// Seeds an empty store with sample data so the app has content on first launch.
    func prepare() async {
        guard persistence.isAvailable else { return }
        _ = try? await CoreDataSeeder.seedIfEmpty(persistence.container, now: now())
    }

    // MARK: - ViewModel factories

    func makeSafetyCheckViewModel(
        for batch: FoodBatch
    ) -> SafetyCheckViewModel {

        let useCase = RecordSafetyCheckUseCase(
            batches: batchRepository,
            now: now,
            assessor: FoodSafetyAssessor()
        )

        return SafetyCheckViewModel(
            recordSafetyCheck: useCase,
            batchID: batch.id
        )
    }
    
    func makeBatchListViewModel() -> BatchListViewModel {
        BatchListViewModel(
            fetchExpiringBatches: FetchExpiringBatchesUseCase(batches: batchRepository, now: now),
            notifications: notificationScheduler
        )
    }

    func makePickupViewModel() -> PickupViewModel {
        PickupViewModel(
            logPickup: LogPickupUseCase(events: eventRepository, pickups: pickupRepository, now: now),
            fetchActiveEvents: FetchActiveEventsUseCase(events: eventRepository, now: now),
            volunteerID: currentVolunteerID
        )
    }

    func makeHandoverViewModel(for batch: FoodBatch) -> HandoverViewModel {
        HandoverViewModel(
            batch: batch,
            handOver: HandOverBatchUseCase(batches: batchRepository, dropPoints: dropPointRepository,
                                           notifications: notificationScheduler, now: now),
            discard: DiscardBatchUseCase(batches: batchRepository, notifications: notificationScheduler),
            fetchDropPoints: FetchDropPointsUseCase(dropPoints: dropPointRepository, now: now),
            now: now
        )
    }

    // MARK: - Previews

    /// An in-memory container for SwiftUI previews.
    static func preview() -> AppContainer {
        AppContainer(persistence: PersistenceController(inMemory: true))
    }
}
