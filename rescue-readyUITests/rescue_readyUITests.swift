import XCTest

/// Smoke tests for the main navigation. Runs against a debug build, which loads sample data.
final class RescueReadyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testAllThreeTabsAreReachable() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))

        for (tab, title) in [("Log Pickup", "Log Pickup"), ("Impact", "Impact"), ("Batches", "Batches")] {
            tabs.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) screen did not appear")
        }
    }

    @MainActor
    func testNewEventSheetOpensFromLogPickup() throws {
        app.tabBars.buttons["Log Pickup"].tap()
        app.buttons["New Event"].tap()

        XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Log Pickup"].waitForExistence(timeout: 5))
    }
}
