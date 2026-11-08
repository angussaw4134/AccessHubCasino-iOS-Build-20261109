import XCTest

final class AccessHubCasinoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        // Always retain the final screen, including assertion failures.
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        shot.name = "Final screen - " + name; shot.lifetime = .keepAlways; add(shot)
    }

    func testWelcomeIsReadableAndAccountFormOpens() throws {
        let app = XCUIApplication(); app.launch()
        if app.buttons["enterGuest"].waitForExistence(timeout:8) {
            XCTAssertTrue(app.staticTexts["A little strategy.\nA little possibility."].exists)
            app.buttons["Sign in to saved progress"].tap()
            XCTAssertTrue(app.textFields["username"].waitForExistence(timeout:3))
            XCTAssertTrue(app.secureTextFields["password"].exists)
            app.buttons["Close"].tap()
        } else { XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:30),"A prior saved session must restore or show its connection error.") }
        let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name = "Launch layout"; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// Explicit opt-in: creates a genuine free-credit guest on the configured backend.
    /// Set ACCESSHUB_RUN_ONLINE_TESTS=1 in this test's Xcode scheme environment.
    func testConnectedNavigationAndCompletedRounds() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ACCESSHUB_RUN_ONLINE_TESTS"] == "1","Requires explicit online test opt-in and a deployed backend.")
        let app = XCUIApplication(); app.launch(); connect(app)
        for tab in ["Games","Credits","Progress","Profile","Home"] { app.tabBars.buttons[tab].tap(); XCTAssertTrue(app.tabBars.buttons[tab].isSelected) }

        openGame("Blackjack",app:app)
        let oldBlackjack = resultID(app,"blackjack")
        scrollTo("blackjackDeal",app:app).tap()
        let blackjackResult = result(app,"blackjack",excluding:oldBlackjack)
        for _ in 0..<4 {
            let stand = app.buttons["blackjackStand"]
            waitUntil(timeout:20) { blackjackResult.exists || (stand.exists && stand.isEnabled) }
            if blackjackResult.exists { break }
            scrollTo("blackjackStand",app:app).tap()
        }
        waitUntil(timeout:20) { blackjackResult.exists }
        attach(app,"Blackjack settled")

        openGame("Mines",app:app)
        let oldMines = resultID(app,"mines")
        scrollTo("minesStart",app:app).tap()
        let tile = app.buttons["mineTile0"]; XCTAssertTrue(tile.waitForExistence(timeout:10)); waitEnabled(tile,timeout:20)
        for _ in 0..<6 where !tile.isHittable { app.swipeDown() }
        tile.tap()
        let minesResult = result(app,"mines",excluding:oldMines)
        let collect = app.buttons["minesCollect"]
        waitUntil(timeout:20) { minesResult.exists || (collect.exists && collect.isEnabled) }
        if !minesResult.exists { scrollTo("minesCollect",app:app).tap() }
        waitUntil(timeout:20) { minesResult.exists }
        attach(app,"Mines full board")

        openGame("Slots",app:app)
        let oldSlots = resultID(app,"slots")
        let spin = scrollTo("slotsSpin",app:app); spin.tap()
        waitUntil(timeout:25) { self.result(app,"slots",excluding:oldSlots).exists }
        attach(app,"Slots actual outcome")

        waitUntil(timeout:5) { app.tabBars.buttons["Credits"].isHittable }
        app.tabBars.buttons["Credits"].tap()
        let refill = app.buttons["freeRefill"]
        if refill.waitForExistence(timeout:5) && refill.isEnabled {
            let balance = app.descendants(matching:.any).matching(identifier:"creditsBalance").firstMatch
            let before = balance.label
            refill.tap()
            waitUntil(timeout:20) { balance.label != before }
        }
        app.tabBars.buttons["Progress"].tap()
        app.buttons["rakebackShortcut"].tap()
        let claim = app.buttons["claimRakeback"]
        XCTAssertTrue(claim.waitForExistence(timeout:10)); waitEnabled(claim,timeout:20); claim.tap()
        let available = app.staticTexts["rakebackAvailable"]
        waitUntil(timeout:20) { available.exists && available.label == "0" }
        attach(app,"Rakeback claim")
    }

    func testConnectedSharedCrashEntryAndSettlement() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ACCESSHUB_RUN_ONLINE_TESTS"] == "1","Requires a live backend and genuine shared round timing.")
        let app = XCUIApplication(); app.launch(); connect(app)
        openGame("Crash",app:app)
        let previousResult = resultID(app,"crash")
        let enter = scrollTo("crashEnter",app:app)
        waitEnabled(enter,timeout:65)
        enter.tap()
        // An entry can be rejected if network arrival crosses the shared cutoff.
        // Retry during the next open entry window using the UI's new request ID.
        if app.alerts.firstMatch.waitForExistence(timeout:2) {
            app.alerts.buttons["OK"].tap(); waitEnabled(enter,timeout:65); enter.tap()
        }
        waitUntil(timeout:65) { self.result(app,"crash",excluding:previousResult).exists }
        attach(app,"Crash resolved position")
    }
    private func openGame(_ name:String,app:XCUIApplication) {
        waitUntil(timeout:8) { app.tabBars.buttons["Games"].isHittable }
        app.tabBars.buttons["Games"].tap()
        // Return to the Games list if its navigation stack already contains a game.
        for _ in 0..<4 where !app.navigationBars["Games"].exists {
            let back = app.navigationBars.buttons.element(boundBy:0)
            if back.exists && back.isHittable { back.tap() }
        }
        let button = app.buttons["Play " + name]
        // Start at the top; otherwise a previously opened Slots card could leave
        // earlier games above the viewport on a small iPhone.
        for _ in 0..<4 where !app.staticTexts["The collection"].isHittable { app.swipeDown() }
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    @discardableResult private func scrollTo(_ identifier:String,app:XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<7 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout:10)); return button
    }
    private func attach(_ app:XCUIApplication,_ name:String) {
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func waitEnabled(_ element:XCUIElement,timeout:TimeInterval) {
        waitUntil(timeout:timeout) { element.exists && element.isEnabled }
    }
    private func result(_ app:XCUIApplication,_ game:String,excluding old:String = "") -> XCUIElement {
        app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@ AND identifier != %@",game+"Result:",old)).firstMatch
    }
    private func resultID(_ app:XCUIApplication,_ game:String) -> String {
        let element = result(app,game)
        return element.exists ? element.identifier : ""
    }
    private func connect(_ app:XCUIApplication) {
        let guest = app.buttons["enterGuest"]
        let home = app.tabBars.buttons["Home"]
        waitUntil(timeout:30) { home.exists || (guest.exists && guest.isEnabled && guest.isHittable) }
        if !home.exists { guest.tap() }
        waitUntil(timeout:30) { home.exists || app.alerts.firstMatch.exists }
        if app.alerts.firstMatch.exists {
            XCTFail("Guest access failed: " + app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" · "))
        }
        XCTAssertTrue(home.waitForExistence(timeout:30))
    }
    private func waitUntil(timeout:TimeInterval,_ condition:@escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            // The real third first-game milestone can level up during this flow.
            // Dismiss that legitimate celebration before inspecting the game result.
            let celebration = XCUIApplication().buttons["Keep exploring"]
            if celebration.exists && celebration.isHittable { celebration.tap() }
            return condition()
        },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:timeout),.completed)
    }
}
