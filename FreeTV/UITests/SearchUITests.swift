import XCTest

/// Drives the real app on an Apple TV simulator with the virtual Siri
/// Remote. Tests launch straight onto their tab (`-tab`) from a clean
/// slate (`-resetData`) so tab-bar focus races can't flake them.
final class SearchUITests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }

    private func launch(tab: String? = nil, reset: Bool = true)
        -> XCUIApplication {
        let app = XCUIApplication()
        if reset { app.launchArguments += ["-resetData"] }
        if let tab { app.launchArguments += ["-tab", tab] }
        app.launch()
        return app
    }

    private func launchLoadedApp() -> XCUIApplication {
        let app = launch()
        XCTAssertTrue(
            app.staticTexts["Sports"].waitForExistence(timeout: 60),
            "catalog shelves never loaded")
        return app
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0 ..< times {
            remote.press(button)
            sleep(1)
        }
    }

    /// Moves focus down until the button is focused (or gives up).
    private func focus(_ button: XCUIElement) {
        for _ in 0 ..< 6 {
            if button.exists && button.hasFocus { return }
            press(.down)
        }
    }

    func testShelvesLoad() {
        let app = launchLoadedApp()
        XCTAssertTrue(app.staticTexts["News"].exists)
    }

    func testOpenChannelDetail() {
        let app = launchLoadedApp()
        press(.down)
        press(.select)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 15),
                      "channel detail never opened")
    }

    func testSearchFindsChannel() {
        let app = launch(tab: "search")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15),
                      "no search field on Search tab")
        press(.select)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15),
                      "keyboard never appeared after Select")
        field.typeText("sky")
        XCTAssertTrue(
            app.staticTexts["Sky News"].waitForExistence(timeout: 15),
            "search did not filter to Sky News")
    }

    func testPlexLinkCodeAppears() {
        let app = launch(tab: "plex")
        let button = app.buttons["Sign in to Plex"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        focus(button)
        press(.select)
        XCTAssertTrue(app.staticTexts["Enter this code at plex.tv/link"]
            .waitForExistence(timeout: 20))
    }

    func testSettingsListsSources() {
        let app = launch(tab: "settings")
        XCTAssertTrue(app.buttons["Add source"].waitForExistence(
            timeout: 15))
        XCTAssertTrue(app.staticTexts["Free TV"].waitForExistence(
            timeout: 15),
            "default source missing from Settings")
        XCTAssertTrue(app.buttons["Sign in to Plex"].waitForExistence(
            timeout: 15))
    }
}
