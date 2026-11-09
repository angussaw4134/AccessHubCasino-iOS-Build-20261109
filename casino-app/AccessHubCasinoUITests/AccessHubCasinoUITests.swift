import XCTest

final class AccessHubCasinoUITests: XCTestCase {
    private var launchedApplication = false
    override func setUpWithError() throws {
        continueAfterFailure = false
        launchedApplication = false
    }
    override func tearDownWithError() throws {
        // An offline XCTSkip never launches an app. Avoid asking the automation
        // service for a SpringBoard screenshot during skipped-test teardown.
        guard launchedApplication else { return }
        // Retain the final screen for every launched test, including failures.
        let shot = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        shot.name = "Final screen - " + name; shot.lifetime = .keepAlways; add(shot)
    }

    func testWelcomeIsReadableAndAccountFormOpens() throws {
        let app = launchApplication()
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
        let app = launchApplication(); connect(app)
        let brand = app.descendants(matching:.any).matching(identifier:"homeBrand").firstMatch
        XCTAssertTrue(app.frame.contains(brand.frame),"Home branding must fit within the small iPhone viewport.")
        XCTAssertTrue(app.frame.contains(app.buttons["Open profile"].frame),"Profile shortcut must not be clipped.")
        attach(app,"Home funded account")
        for tab in ["Play","Rewards","Community","Profile","Home"] { app.tabBars.buttons[tab].tap(); XCTAssertTrue(app.tabBars.buttons[tab].isSelected) }

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
        for _ in 0..<5 where !app.staticTexts["EMERALD VAULT"].isHittable { app.swipeDown() }
        attach(app,"Slots actual outcome")

        openCredits(app)
        XCTAssertFalse(app.buttons["freeRefill"].exists)
        openPlayRoot(app)
        scrollTo("openCasinoProgress",app:app).tap()
        app.buttons["rakebackShortcut"].tap()
        let claim = app.buttons["claimRakeback"]
        XCTAssertTrue(claim.waitForExistence(timeout:10)); waitEnabled(claim,timeout:20); claim.tap()
        let available = app.staticTexts["rakebackAvailable"]
        waitUntil(timeout:20) { available.exists && available.label == "0" }
        attach(app,"Rakeback claim")
    }

    func testConnectedSharedCrashEntryAndSettlement() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ACCESSHUB_RUN_ONLINE_TESTS"] == "1","Requires a live backend and genuine shared round timing.")
        let app = launchApplication(); connect(app)
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
    /// Independent live inspection: creates only a new zero-credit guest.
    /// No fixture login, credit grant or wager is performed.
    func testZeroCreditGuestNavigation() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["ACCESSHUB_RUN_ZERO_CREDIT_TESTS"] == "1" && environment["ACCESSHUB_RUN_ONLINE_TESTS"] != "1","Requires the separate zero-credit opt-in with funded tests disabled.")
        let app = launchApplication()
        let guest = app.buttons["enterGuest"]
        XCTAssertTrue(guest.waitForExistence(timeout:15),"Use a fresh simulator; an existing account must not be changed by this test.")
        waitEnabled(guest,timeout:20); guest.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:30))
        openCredits(app)
        let balance = app.descendants(matching:.any).matching(identifier:"creditsBalance").firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout:10))
        XCTAssertEqual(balance.value as? String,"0")
        XCTAssertFalse(app.buttons["freeRefill"].exists)
        XCTAssertTrue(app.staticTexts["adminCreditsInformation"].exists)
        attach(app,"Zero-state credit policy")

        app.tabBars.buttons["Profile"].tap()
        let accountID = app.staticTexts["profileAccountID"]
        for _ in 0..<5 where !accountID.isHittable { app.swipeUp() }
        XCTAssertTrue(accountID.waitForExistence(timeout:10))
        let generatedID = accountID.label
        XCTAssertFalse(generatedID.isEmpty)
        addTeardownBlock { [self] in
            // Capture the state first so a later cleanup cannot hide a failure.
            attach(app,"Zero-state before guest cleanup")
            app.tabBars.buttons["Profile"].tap()
            guard app.staticTexts["profileAccountID"].label == generatedID else {
                XCTFail("Cleanup refused: this is not the guest created by the zero-credit test.")
                return
            }
            scrollTo("Delete account and data",app:app).tap()
            XCTAssertTrue(app.alerts.buttons["Delete permanently"].waitForExistence(timeout:5))
            app.alerts.buttons["Delete permanently"].tap()
            XCTAssertTrue(guest.waitForExistence(timeout:30),"The generated zero-credit guest must be removed after inspection.")
        }
        scrollTo("copyAccountID",app:app).tap()
        XCTAssertEqual(app.buttons["copyAccountID"].label,"Copied")
        attach(app,"Zero-state profile account ID")
        for tab in ["Play","Rewards","Community","Profile","Home"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
        }
        let brand = app.descendants(matching:.any).matching(identifier:"homeBrand").firstMatch
        XCTAssertTrue(app.frame.contains(brand.frame))
        XCTAssertTrue(app.frame.contains(app.buttons["Open profile"].frame))
        XCTAssertFalse(app.buttons["Free credits"].exists)
        attach(app,"Zero-state Home layout")
        if environment["ACCESSHUB_RUN_HUB_TESTS"] == "1" {
            app.tabBars.buttons["Rewards"].tap()
            scrollTo("dailyRewardShortcut",app:app).tap()
            let claim = scrollTo("claimDaily",app:app)
            waitEnabled(claim,timeout:20); claim.tap()
            waitUntil(timeout:20) { !claim.isEnabled && claim.label.contains("Claimed") }
            attach(app,"Hub daily reward claimed once")
            app.tabBars.buttons["Community"].tap()
            scrollTo("globalChatShortcut",app:app).tap()
            XCTAssertTrue(app.textFields["Message the room"].waitForExistence(timeout:20))
            waitUntil(timeout:20) { app.staticTexts["chatConnection"].label == "Live" }
            attach(app,"Hub real community chat")
            openPlayRoot(app)
            for _ in 0..<5 { app.swipeDown() }
            scrollTo("snakeLobbyShortcut",app:app).tap()
            app.segmentedControls.buttons["Solo practice"].tap()
            scrollTo("snakeCreate",app:app).tap()
            let ready = scrollTo("Accept terms & ready",app:app)
            waitEnabled(ready,timeout:20); ready.tap()
            XCTAssertTrue(app.staticTexts["snakeResult"].waitForExistence(timeout:30))
            attach(app,"Hub authoritative solo Snake completed")
        }
        for (name,control) in [("Blackjack","blackjackDeal"),("Mines","minesStart"),("Slots","slotsSpin"),("Crash","crashEnter")] {
            openGame(name,app:app)
            let action = scrollTo(control,app:app)
            XCTAssertFalse(action.isEnabled,"A zero-credit account cannot stake in \(name).")
            for _ in 0..<4 { app.swipeDown() }
            attach(app,"Zero-state " + name)
        }
    }
    private func launchApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        launchedApplication = true
        return app
    }
    private func openPlayRoot(_ app:XCUIApplication) {
        app.tabBars.buttons["Play"].tap()
        for _ in 0..<5 {
            let back = app.navigationBars.buttons.element(boundBy:0)
            if back.exists && back.isHittable { back.tap() } else { break }
        }
    }
    private func openCredits(_ app:XCUIApplication) {
        openPlayRoot(app)
        scrollTo("openCasinoCredits",app:app).tap()
    }
    private func openGame(_ name:String,app:XCUIApplication) {
        waitUntil(timeout:8) { app.tabBars.buttons["Play"].isHittable }
        openPlayRoot(app)
        let button = app.buttons["Play " + name]
        for _ in 0..<5 { app.swipeDown() }
        for _ in 0..<9 where !button.isHittable { app.swipeUp() }
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
        let createdGuest = !home.exists
        if createdGuest { guest.tap() }
        waitUntil(timeout:30) { home.exists || app.alerts.firstMatch.exists }
        if app.alerts.firstMatch.exists {
            XCTFail("Guest access failed: " + app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" · "))
        }
        XCTAssertTrue(home.waitForExistence(timeout:30))
        if createdGuest {
            openCredits(app)
            let balance = app.descendants(matching:.any).matching(identifier:"creditsBalance").firstMatch
            XCTAssertTrue(balance.waitForExistence(timeout:10))
            XCTAssertEqual(balance.value as? String,"0","A new account starts with zero credits.")
            XCTAssertFalse(app.buttons["freeRefill"].exists)
            XCTAssertTrue(app.staticTexts["adminCreditsInformation"].exists)
            attach(app,"New guest starts at zero")
            app.tabBars.buttons["Profile"].tap()
            let username = ProcessInfo.processInfo.environment["ACCESSHUB_TEST_USERNAME"] ?? ""
            let password = ProcessInfo.processInfo.environment["ACCESSHUB_TEST_PASSWORD"] ?? ""
            XCTAssertFalse(username.isEmpty,"An administrator-funded test account must be configured.")
            XCTAssertFalse(password.isEmpty,"The test account password must be supplied to the runner.")
            scrollTo("Sign in to an existing account",app:app).tap()
            let usernameField = app.textFields["username"]
            XCTAssertTrue(usernameField.waitForExistence(timeout:10))
            usernameField.tap(); usernameField.typeText(username)
            let passwordField = app.secureTextFields["password"]
            passwordField.tap(); passwordField.typeText(password)
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout:30))
            app.buttons["Continue"].tap()
            app.tabBars.buttons["Home"].tap()
        }
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
