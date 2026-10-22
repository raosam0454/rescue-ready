import Foundation

/// The outcome of asking for a batch's expiry alert.
enum ExpiryAlertResult: Equatable {
    case scheduled(at: Date)
    case notificationsDenied
    case tooLateToAlert
    case failed
}

/// Alerts the volunteer 15 minutes before a batch's safe hold time runs out.
///
/// Rules:
/// - the batch must exist and still be open
/// - no alert once that 15 minute mark has passed
/// - permission is asked the first time an alert is needed
/// - denied or failed notifications never block the volunteer
struct ScheduleExpiryAlertUseCase {
    static let leadTime: TimeInterval = 15 * 60

    let batches: BatchRepository
    let notifications: NotificationScheduling
    /// Injected so tests control time. Never call `Date()` directly in a use case.
    let now: () -> Date

    func execute(batchID: Identifier<FoodBatch>) async throws -> ExpiryAlertResult {
        let batch: FoodBatch?
        do {
            batch = try await batches.batch(id: batchID)
        } catch {
            throw DomainError.storageFailure
        }
        guard let batch else { throw DomainError.batchNotFound }
        guard batch.status.isOpen else { throw DomainError.batchAlreadyClosed }

        let alertDate = batch.holdWindow.expiresAt.addingTimeInterval(-Self.leadTime)
        guard alertDate > now() else { return .tooLateToAlert }

        switch await notifications.permission() {
        case .authorized:
            break
        case .denied:
            return .notificationsDenied
        case .notDetermined:
            guard await notifications.requestPermission() else { return .notificationsDenied }
        }

        do {
            try await notifications.scheduleExpiryAlert(for: batch, at: alertDate)
        } catch {
            return .failed
        }
        return .scheduled(at: alertDate)
    }
}
