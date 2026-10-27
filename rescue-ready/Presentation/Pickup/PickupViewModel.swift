import Foundation
import Observation

/// State and actions for the Log Pickup screen.
@MainActor
@Observable
final class PickupViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private(set) var events: [Event] = []
    var selectedEventID: Identifier<Event>?
    private(set) var batches: [NewBatch] = []
    private(set) var loadState: LoadState = .loading
    private(set) var saveState: SaveState = .idle

    private let logPickup: LogPickupUseCase
    private let fetchActiveEvents: FetchActiveEventsUseCase
    private let volunteerID: Identifier<Volunteer>

    init(logPickup: LogPickupUseCase, fetchActiveEvents: FetchActiveEventsUseCase, volunteerID: Identifier<Volunteer>) {
        self.logPickup = logPickup
        self.fetchActiveEvents = fetchActiveEvents
        self.volunteerID = volunteerID
    }

    var canSave: Bool {
        selectedEventID != nil && !batches.isEmpty && saveState != .saving
    }

    var totalWeightKg: Double {
        batches.reduce(0) { $0 + $1.weightKg }
    }

    func load() async {
        loadState = .loading
        do {
            events = try await fetchActiveEvents.execute()
            if !events.contains(where: { $0.id == selectedEventID }) {
                selectedEventID = events.first?.id
            }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    /// Reloads events after one is created, and selects it.
    func eventCreated(_ event: Event) async {
        selectedEventID = event.id
        await load()
    }

    func addBatch(_ batch: NewBatch) {
        batches.append(batch)
    }

    func removeBatches(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            batches.remove(at: index)
        }
    }

    func save() async {
        guard let selectedEventID, canSave else { return }
        saveState = .saving
        do {
            _ = try await logPickup.execute(eventID: selectedEventID, volunteerID: volunteerID, batches: batches)
            batches = []
            saveState = .saved
        } catch {
            saveState = .failed(Self.message(for: error))
        }
    }

    func dismissSaveResult() {
        saveState = .idle
    }

    private static func message(for error: Error) -> String {
        let domainError = (error as? DomainError) ?? .storageFailure
        return domainError.errorDescription ?? ""
    }
}
