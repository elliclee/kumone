import XCTest

final class KumoneIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryTabsOpenTheirRootScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-settings.autoCheckUpdates", "NO"]
        app.launch()

        let dismissUpdate = app.buttons["稍后"]
        if dismissUpdate.waitForExistence(timeout: 3) {
            dismissUpdate.tap()
        }

        tapPrimaryTab(named: "精选", fallbackX: 0.32, in: app)
        XCTAssertTrue(app.navigationBars["精选"].waitForExistence(timeout: 5))

        let exploreScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        exploreScreenshot.name = "Explore-iPhone"
        exploreScreenshot.lifetime = .keepAlways
        add(exploreScreenshot)

        tapPrimaryTab(named: "我的", fallbackX: 0.67, in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    /// iOS 26's floating TabView can expose a tab button before XCTest has a
    /// valid hit point for it. Keep the accessibility lookup as the primary
    /// path, then fall back to the stable iPhone tab position used by this test.
    @MainActor
    private func tapPrimaryTab(named name: String, fallbackX: CGFloat, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))

        if tab.isHittable {
            tab.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: fallbackX, dy: 0.94)).tap()
        }
    }
}
