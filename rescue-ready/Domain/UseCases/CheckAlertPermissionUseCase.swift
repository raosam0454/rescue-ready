import Foundation

/// Reports whether expiry alerts can reach the volunteer, so screens can explain when they can't.
struct CheckAlertPermissionUseCase {
    let notifications: NotificationScheduling

    /// True when the volunteer has turned notifications off for the app.
    func alertsAreOff() async -> Bool {
        await notifications.permission() == .denied
    }
}
