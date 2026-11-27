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

    /// Focuses the first content element from anywhere: climb to the
    /// pill bar, then step down once.
    private func focusFirstContent() {
        press(.up, times: 3)
        press(.down)
    }

    /// Focuses a button from anywhere, verifying via focus state.
    private func focusButton(_ button: XCUIElement) {
        press(.up, times: 3)
        for _ in 0 ..< 8 {
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
        focusFirstContent()
        press(.select)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 15),
                      "channel detail never opened")
    }

    func testPlaybackResumeAppears() {
        let app = launchLoadedApp()
        focusFirstContent()
        press(.select)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 15))
        focusButton(app.buttons["Play"])
        press(.select)
        sleep(10)
        press(.menu)
        press(.menu)
        XCTAssertTrue(app.staticTexts["Continue watching"].waitForExistence(
            timeout: 20),
            "continue shelf never appeared after playback")
    }

    func testSearchFindsChannel() {
        let app = launch(tab: "search")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15),
                      "no search field on Search tab")
        sleep(1)
        press(.select)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15),
                      "keyboard never appeared after Select")
        field.typeText("sky")
        XCTAssertTrue(
            app.staticTexts["Sky News"].waitForExistence(timeout: 15),
            "search did not filter to Sky News")
    }

    func testChannelsGridLoadsGuide() {
        let app = launch(tab: "channels")
        XCTAssertTrue(app.buttons["Sports"].waitForExistence(timeout: 60),
                      "channel shelves never loaded")
        let query = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'programmes'"))
        var loaded = false
        for _ in 0 ..< 36 {
            if query.allElementsBoundByIndex.contains(where: {
                !$0.label.hasPrefix("0 ")
            }) {
                loaded = true
                break
            }
            sleep(5)
        }
        XCTAssertTrue(loaded, "guide programmes never loaded")
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

    func testMoviesPromptWithoutKey() {
        let app = launch(tab: "movies")
        XCTAssertTrue(app.staticTexts["TMDB key needed"].waitForExistence(
            timeout: 15))
    }

    func testShowsTabExists() {
        let app = launch(tab: "shows")
        XCTAssertTrue(app.staticTexts["TMDB key needed"].waitForExistence(
            timeout: 15))
    }

    /// Full live TMDB flow. Runs only when /tmp/freetv-tmdb-test-key
    /// holds a key, so CI skips it and local runs prove live search.
    func testMoviesLiveSearch() throws {
        let keyFile = "/tmp/freetv-tmdb-test-key"
        guard let key = try? String(contentsOfFile: keyFile,
                                     encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw XCTSkip("TMDB test key file missing")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-resetData", "-tab", "movies",
                                "-tmdbKey", key]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending movies"].waitForExistence(
            timeout: 30))
        let field = app.textFields["TitleSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        sleep(1)
        press(.select)
        field.typeText("inception")
        XCTAssertTrue(app.staticTexts["Inception"].waitForExistence(
            timeout: 15),
            "search did not find Inception")
        press(.menu)
        press(.down)
        press(.select)
        XCTAssertTrue(
            app.staticTexts["Rent"].waitForExistence(timeout: 20),
            "provider sections never rendered on detail")
        XCTAssertTrue(app.staticTexts["RENT"].waitForExistence(timeout: 10),
                      "cost badges never rendered")
    }
}
