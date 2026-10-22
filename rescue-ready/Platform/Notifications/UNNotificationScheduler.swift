import Foundation
import UserNotifications

/// Schedules expiry alerts as local notifications on the device.
final class UNNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        // Lets alerts show as a banner even while the app is open.
        center.delegate = self
    }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleExpiryAlert(for batch: FoodBatch, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Batch expiring soon"
        content.body = "\(batch.foodDescription) has 15 minutes of safe hold time left. Hand it over or discard it."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // The same identifier replaces any alert already pending for this batch.
        let request = UNNotificationRequest(identifier: Self.identifier(for: batch.id), content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancelExpiryAlert(for batchID: Identifier<FoodBatch>) async {
        let identifier = Self.identifier(for: batchID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    private static func identifier(for batchID: Identifier<FoodBatch>) -> String {
        "expiry-\(batchID.rawValue.uuidString)"
    }
}
