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

        XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 5))
        captureScreen(named: "Home-iPhone")

        tapPrimaryTab(named: "精选", fallbackX: 0.32, in: app)
        XCTAssertTrue(app.navigationBars["精选"].waitForExistence(timeout: 5))
        captureScreen(named: "Explore-iPhone")

        tapPrimaryTab(named: "我的", fallbackX: 0.67, in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        captureScreen(named: "Library-iPhone")
    }

    @MainActor
    func testAuthenticatedFMAndLibraryAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-settings.autoCheckUpdates", "NO",
            "--ui-test-authenticated",
        ]
        app.launch()

        let dismissUpdate = app.buttons["稍后"]
        if dismissUpdate.waitForExistence(timeout: 3) {
            dismissUpdate.tap()
        }

        tapPrimaryTab(named: "漫游", fallbackX: 0.48, in: app)
        XCTAssertTrue(app.navigationBars["漫游"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["私人漫游"].waitForExistence(timeout: 5))
        captureScreen(named: "FM-Authenticated-iPhone")

        tapPrimaryTab(named: "我的", fallbackX: 0.67, in: app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["RANDOMFLOW"].waitForExistence(timeout: 5))
        captureScreen(named: "Library-Authenticated-iPhone")
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

    private func captureScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
