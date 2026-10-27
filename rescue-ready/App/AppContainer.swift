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

    /// Prepares the store on launch.
    ///
    /// Every build creates the volunteer's own record. Debug builds also load sample events,
    /// drop points and batches for development and demos; release builds start empty, and
    /// volunteers create their own events.
    func prepare() async {
        guard persistence.isAvailable else { return }
        try? await CoreDataSeeder.ensureVolunteer(Volunteer(id: currentVolunteerID, name: "Volunteer"),
                                                  in: persistence.container)
        #if DEBUG
        _ = try? await CoreDataSeeder.seedIfEmpty(persistence.container, now: now())
        #endif
    }

    // MARK: - ViewModel factories

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

    func makeNewEventViewModel() -> NewEventViewModel {
        NewEventViewModel(createEvent: CreateEventUseCase(events: eventRepository, now: now), now: now)
    }

    func makeSafetyCheckViewModel(for batch: FoodBatch) -> SafetyCheckViewModel {
        let scheduleExpiryAlert = ScheduleExpiryAlertUseCase(batches: batchRepository,
                                                             notifications: notificationScheduler, now: now)
        return SafetyCheckViewModel(
            batch: batch,
            recordCheck: RecordSafetyCheckUseCase(batches: batchRepository,
                                                  scheduleExpiryAlert: scheduleExpiryAlert, now: now),
            now: now
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

    func makeImpactViewModel() -> ImpactViewModel {
        ImpactViewModel(
            computeImpactStats: ComputeImpactStatsUseCase(batches: batchRepository, dropPoints: dropPointRepository)
        )
    }

    // MARK: - Previews

    /// An in-memory container for SwiftUI previews.
    static func preview() -> AppContainer {
        AppContainer(persistence: PersistenceController(inMemory: true))
    }
}