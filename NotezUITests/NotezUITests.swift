import XCTest

/// Smoke tests through the real UI, like Playwright for the native app.
/// `-ui-testing` gives the app an in-memory store and fresh settings, so each
/// launch starts from the welcome page and never touches the dev app's data.
final class NotezUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.outlines.firstMatch.staticTexts["Welcome to Notez"].waitForExistence(timeout: 15), "app didn't start")
        return app
    }

    /// The blank-window bug shipped once. The window must show the sidebar and the editor's content.
    @MainActor
    func testLaunchShowsTheWelcomePage() {
        let app = launch()
        // Rendered by the editor web view from the seeded markdown.
        XCTAssertTrue(app.webViews.staticTexts["Shortcuts"].waitForExistence(timeout: 10), "editor didn't render the page")
    }

    @MainActor
    func testQuickOpenJumpsToAPage() {
        let app = launch()
        app.typeKey("k", modifierFlags: .command)
        let query = app.textFields["palette.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5), "⌘K didn't open quick open")
        query.typeText("Sub-pages\r")
        XCTAssertTrue(query.waitForNonExistence(timeout: 5), "quick open didn't close")
        let body = app.webViews.staticTexts["Any page can hold other pages. Drag pages in the sidebar to re-nest them."]
        XCTAssertTrue(body.waitForExistence(timeout: 10), "didn't open the page")
    }

    @MainActor
    func testCommandPaletteCreatesAProject() {
        let app = launch()
        app.typeKey("k", modifierFlags: [.command, .shift])
        let query = app.textFields["palette.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5), "⇧⌘K didn't open the command palette")
        query.typeText("new project\r")

        let name = app.sheets.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New Project prompt didn't appear")
        name.typeText("Groceries\r")
        XCTAssertTrue(app.outlines.firstMatch.staticTexts["Groceries"].waitForExistence(timeout: 5), "project missing from the sidebar")
    }

    @MainActor
    func testNewPageTakesItsTitleFromTheEditor() {
        let app = launch()
        app.typeKey("n", modifierFlags: .command)
        // New pages focus the title in the editor, and its saves reach the sidebar.
        app.typeText("Shopping list")
        XCTAssertTrue(app.outlines.firstMatch.staticTexts["Shopping list"].waitForExistence(timeout: 10), "title didn't reach the sidebar")
    }
}
