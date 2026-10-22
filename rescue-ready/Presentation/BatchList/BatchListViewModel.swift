import Foundation
import Observation

/// State for the Batches screen: open batches, soonest deadline first.
@MainActor
@Observable
final class BatchListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var batches: [ExpiringBatch] = []
    private(set) var loadState: LoadState = .loading
    /// True when the volunteer has turned notifications off, so the screen can explain
    /// that expiry alerts won't arrive.
    private(set) var notificationsDenied = false

    private let fetchExpiringBatches: FetchExpiringBatchesUseCase
    private let notifications: NotificationScheduling

    init(fetchExpiringBatches: FetchExpiringBatchesUseCase, notifications: NotificationScheduling) {
        self.fetchExpiringBatches = fetchExpiringBatches
        self.notifications = notifications
    }

    func load() async {
        if batches.isEmpty { loadState = .loading }
        do {
            batches = try await fetchExpiringBatches.execute()
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
        notificationsDenied = await notifications.permission() == .denied
    }

    private static func message(for error: Error) -> String {
        let domainError = (error as? DomainError) ?? .storageFailure
        return domainError.errorDescription ?? ""
    }
}
