import XCTest

final class AccessHubCasinoUITests: XCTestCase {
    private var launched = false
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if launched { let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    }
    func testSupportWebsiteLoadsAndOpensSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--support-website-smoke"]
        app.launch(); launched = true
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout:15))
        XCTAssertTrue(app.webViews.staticTexts["Support, simplified."].waitForExistence(timeout:30))
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout:10)); signIn.tap()
        XCTAssertTrue(app.webViews.staticTexts["Welcome back"].waitForExistence(timeout:5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Support, simplified."].waitForExistence(timeout:30))
    }
    func testWelcomeAndSignIn() throws {
        let app = launch()
        if app.buttons["enterGuest"].waitForExistence(timeout:10) {
            XCTAssertTrue(app.staticTexts["Support, simplified."].exists)
            let signIn = app.buttons["Sign in"]
            for _ in 0..<3 where !signIn.isHittable { app.swipeUp() }
            signIn.tap()
            XCTAssertTrue(app.textFields["username"].waitForExistence(timeout:5))
            XCTAssertTrue(app.secureTextFields["password"].exists)
            app.buttons["Close"].tap()
        } else { XCTAssertTrue(app.tabBars.buttons["Support"].waitForExistence(timeout:30)) }
    }
    func testSupportAddOnsAndSessionRestore() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["ACCESSHUB_RUN_ZERO_CREDIT_TESTS"] == "1", "Requires an isolated test backend and explicit guest-test opt-in.")
        let app = launch()
        let guest = app.buttons["enterGuest"]
        XCTAssertTrue(guest.waitForExistence(timeout:15), "Use a fresh simulator.")
        wait { guest.isEnabled }; guest.tap()
        XCTAssertTrue(app.tabBars.buttons["Support"].waitForExistence(timeout:40))
        XCTAssertEqual(app.tabBars.buttons.count,2)
        for removed in ["Home","Play","Rewards","Community","Profile"] { XCTAssertFalse(app.tabBars.buttons[removed].exists) }
        let start = app.buttons["Start a support ticket"]
        XCTAssertTrue(start.waitForExistence(timeout:30)); wait { start.isEnabled }
        screenshot(app,"Support")
        start.tap()
        XCTAssertTrue(app.textFields["Subject"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Send ticket"].isEnabled)
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Add-ons"].tap()
        XCTAssertTrue(app.staticTexts["Scannable app"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["2 dollars and 99 cents per month"].exists)
        XCTAssertFalse(app.buttons["Buy"].exists)
        screenshot(app,"Add-ons")
        app.buttons["Account"].firstMatch.tap()
        let identifier = app.staticTexts["profileAccountID"]
        XCTAssertTrue(identifier.waitForExistence(timeout:5)); let owner = identifier.label
        XCTAssertFalse(owner.isEmpty)
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Support"].waitForExistence(timeout:40))
        app.buttons["Account"].firstMatch.tap()
        XCTAssertTrue(identifier.waitForExistence(timeout:10)); XCTAssertEqual(identifier.label,owner)
        app.buttons["copyAccountID"].tap(); XCTAssertEqual(app.buttons["copyAccountID"].label,"Copied")
        screenshot(app,"Account after relaunch")
        // Only delete the new guest whose identity was captured above.
        guard identifier.label == owner else { XCTFail("Refusing to delete another account"); return }
        let delete = app.buttons["Delete account and data"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        wait { delete.isEnabled }; delete.tap()
        XCTAssertTrue(app.alerts.buttons["Delete permanently"].waitForExistence(timeout:5))
        app.alerts.buttons["Delete permanently"].tap()
        XCTAssertTrue(guest.waitForExistence(timeout:30))
    }
    private func launch() -> XCUIApplication { let app = XCUIApplication(); app.launch(); launched = true; return app }
    private func wait(_ predicate:@escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in predicate() },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:30),.completed)
    }
    private func screenshot(_ app:XCUIApplication,_ name:String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
