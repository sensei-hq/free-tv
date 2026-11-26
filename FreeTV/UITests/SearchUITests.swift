import XCTest

/// Drives the real app on an Apple TV simulator with the virtual Siri
/// Remote: shelves load, cards open, and search types and filters.
final class SearchUITests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }

    private func launchLoadedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
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
        let app = launchLoadedApp()
        press(.right)
        press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15),
                      "no search field on Search tab")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15),
                      "keyboard never appeared (autofocus broken)")
        field.typeText("sky")
        XCTAssertTrue(
            app.staticTexts["Sky News"].waitForExistence(timeout: 15),
            "search did not filter to Sky News")
    }
}
