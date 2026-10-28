import Testing
@testable import rescue_ready

struct CheckAlertPermissionUseCaseTests {
    @Test(arguments: [
        (NotificationPermission.denied, true),
        (NotificationPermission.authorized, false),
        (NotificationPermission.notDetermined, false),
    ])
    func reportsAlertsOffOnlyWhenDenied(permission: NotificationPermission, expected: Bool) async {
        let useCase = CheckAlertPermissionUseCase(notifications: InMemoryNotificationScheduler(permission: permission))

        #expect(await useCase.alertsAreOff() == expected)
    }

    @Test func doesNotPromptForPermission() async {
        let notifications = InMemoryNotificationScheduler(permission: .notDetermined)

        _ = await CheckAlertPermissionUseCase(notifications: notifications).alertsAreOff()

        #expect(notifications.permissionRequestCount == 0)
    }
}
