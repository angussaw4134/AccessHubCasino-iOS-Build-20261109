import XCTest
import Security
@testable import AccessHubCasino

final class ClientContractTests: XCTestCase {
    func testHubCommandsRetainOwnerAndExactPayloadForRetry() throws {
        let command = HubCommand(id:"stable-market-request",ownerID:"original-casino-account",type:"market.buy",payload:["listingId":.string("listing-123"),"expectedPrice":.number(20)])
        let restored = try JSONDecoder().decode(HubCommand.self,from:JSONEncoder().encode(command))
        XCTAssertEqual(restored,command)
        XCTAssertEqual(restored.body["payload"]?["expectedPrice"].int,20)
        let accepted = try JSONValue.parse(Data(#"{"receipt":{"id":"stable-market-request","type":"market.buy","status":"accepted"},"result":{}}"#.utf8))
        XCTAssertTrue(restored.accepts(accepted))
        XCTAssertFalse(HubCommand(id:"different",ownerID:command.ownerID,type:command.type,payload:command.payload).accepts(accepted))
        XCTAssertFalse(HubCommand(id:command.id,ownerID:command.ownerID,type:"market.cancel",payload:command.payload).accepts(accepted))
        XCTAssertFalse(restored.accepts(.object(["receipt":.object(["id":.string(command.id),"type":.string(command.type),"status":.string("queued")])])))
    }
    func testHubNotificationRoutesRemainInsideAuthorizedScreens() {
        XCTAssertEqual(HubDestination.notification(.object(["screen":.string("support"),"id":.string("private-ticket")])),.ticket("private-ticket"))
        XCTAssertEqual(HubDestination.notification(.object(["screen":.string("vouchers"),"id":.string("voucher-1")])),.voucher("voucher-1"))
        XCTAssertEqual(HubDestination.notification(.object(["screen":.string("snake"),"id":.string("room-1")])),.snake("room-1"))
        XCTAssertNil(HubDestination.notification(.object(["screen":.string("snake")])))
        XCTAssertNil(HubDestination.notification(.object(["screen":.string("https://untrusted.example"),"id":.string("anything")])))
    }
    func testCrashPotentialReturnUsesOnlyCurrentRunningServerPosition() throws {
        var round: JSONValue = .object(["id":.string("current"),"phase":.string("running"),"multiplier":.number(1.5),"position":.object(["roundId":.string("current"),"status":.string("running"),"stakeUnits":.number(3)])])
        XCTAssertEqual(CrashPotentialReturn.units(round:round,displayMultiplier:1.5,online:true),4,"Fractional microcredits must be floored, not rounded.")
        XCTAssertEqual(CrashPotentialReturn.units(round:round,displayMultiplier:1.9,online:true),5,"Online return follows the scene's bounded interpolation.")
        XCTAssertEqual(CrashPotentialReturn.units(round:round,displayMultiplier:1.9,online:false),4,"Offline freezes at the server snapshot.")
        var fields = round.object
        fields["multiplier"] = .number(2)
        round = .object(fields)
        XCTAssertEqual(CrashPotentialReturn.units(round:round,displayMultiplier:2,online:true),6)
        fields["phase"] = .string("finished")
        XCTAssertNil(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:2,online:true))
        fields["phase"] = .string("running")
        fields["position"] = .object(["roundId":.string("previous"),"status":.string("running"),"stakeUnits":.number(100)])
        XCTAssertNil(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:2,online:true),"Never show a previous round as collectable.")
        fields["position"] = .object(["roundId":.string("current"),"status":.string("collected"),"stakeUnits":.number(100)])
        XCTAssertNil(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:2,online:true))
        fields["position"] = .object(["roundId":.string("current"),"status":.string("running"),"stakeUnits":.number(100)])
        fields["multiplier"] = .number(.infinity)
        XCTAssertNil(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:2,online:false))
        XCTAssertNil(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:.infinity,online:true))
        fields["multiplier"] = .number(2.5)
        fields["position"] = .object(["roundId":.string("current"),"status":.string("running"),"stakeUnits":.number(100),"autoCollect":.number(2)])
        XCTAssertEqual(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:2.8,online:true),200,"Never display beyond the configured auto-collection return.")
        XCTAssertEqual(CrashPotentialReturn.units(round:.object(fields),displayMultiplier:3,online:false),200)
    }
    func testSecureSessionCanBeCreatedReadAndUpdated() throws {
        let account = "test-session-" + UUID().uuidString
        defer {
            SecItemDelete([kSecClass as String:kSecClassGenericPassword,
                           kSecAttrService as String:"app.accesshub.casino.session",
                           kSecAttrAccount as String:account] as CFDictionary)
        }
        try SessionVault.write("initial-session",account:account)
        XCTAssertEqual(SessionVault.read(account),"initial-session")
        try SessionVault.write("renewed-session",account:account)
        XCTAssertEqual(SessionVault.read(account),"renewed-session")
    }
    func testCreditPrecisionAndMaximumAccountingValue() throws {
        let fixture = Data(#"{"balanceUnits":1000000000000000,"availableRakebackUnits":10001,"games":{"blackjack":{"dealer":[{"rank":"A","suit":"spades"},null]}}}"#.utf8)
        let decoded = try JSONValue.parse(fixture)
        XCTAssertEqual(decoded["balanceUnits"].double, 1_000_000_000_000_000)
        XCTAssertEqual(decoded["availableRakebackUnits"].double / Credits.scale, 0.010001)
        XCTAssertFalse(decoded["games"]["blackjack"]["dealer"][1].exists)
        XCTAssertEqual(decoded["games"]["blackjack"]["dealer"][0]["rank"].string,"A")
        XCTAssertEqual(Credits.format(9_007_199_254_740_991,precision:6),"9,007,199,254.740991")
        XCTAssertEqual(Credits.format(10_001,precision:6),"0.010001")
        XCTAssertEqual(Credits.format(-1,precision:6),"-0.000001")
        XCTAssertEqual(Credits.format(999_999),"1")
    }
    func testSavedRequestRoundTripsWithoutChangingIdOrUnits() throws {
        let operation = PendingAction(id:"stable-action",body:["id":.string("stable-action"),"type":.string("mines.reveal"),"roundId":.string("round-123"),"tile":.number(24),"stakeUnits":.number(125_000_000)])
        let data = try JSONEncoder().encode(operation)
        XCTAssertEqual(try JSONDecoder().decode(PendingAction.self,from:data),operation)
    }
    func testStakeBoundariesAndInsufficientBalance() {
        XCTAssertTrue(validStake("1",balance:1_000_000))
        XCTAssertTrue(validStake("10000",balance:10_000_000_000))
        for invalid in ["0","-1","1.5","10001","NaN","inf",""] { XCTAssertFalse(validStake(invalid,balance:10_000_000_000),invalid) }
        XCTAssertFalse(validStake("101",balance:100_000_000))
    }
    func testPublicSnapshotKeepsHiddenValuesAndZeroesDistinct() throws {
        let snapshot = try JSONValue.parse(Data(#"{"games":{"mines":{"mines":null,"revealed":[],"hitTile":0},"slots":{"grid":[["gem","bell","cherry"]]}},"crash":{"endAt":null,"multiplier":1}}"#.utf8))
        XCTAssertFalse(snapshot["games"]["mines"]["mines"].exists)
        XCTAssertTrue(snapshot["games"]["mines"]["hitTile"].exists)
        XCTAssertEqual(snapshot["games"]["mines"]["hitTile"].int,0)
        XCTAssertFalse(snapshot["crash"]["endAt"].exists)
        XCTAssertEqual(snapshot["games"]["slots"]["grid"][0].array.map(\.string),["gem","bell","cherry"])
    }
    func testMemoizedRefillCooldownDoesNotBlockPendingQueueForever() {
        XCTAssertTrue(ActionReceipt.isDefinitiveRejection(status:429,code:"refill_wait"))
        XCTAssertFalse(ActionReceipt.isDefinitiveRejection(status:429,code:"rate_limit"))
        XCTAssertFalse(ActionReceipt.isDefinitiveRejection(status:401,code:"unauthorized"))
        XCTAssertFalse(ActionReceipt.isDefinitiveRejection(status:408,code:"timeout"))
        XCTAssertFalse(ActionReceipt.isDefinitiveRejection(status:503,code:"unavailable"))
        XCTAssertTrue(ActionReceipt.isDefinitiveRejection(status:409,code:"round_finished"))
    }
    func testOnlyMatchingAcceptedActionReceiptClearsPendingRequest() throws {
        let operation = PendingAction(id:"request-123",body:["id":.string("request-123"),"type":.string("rewards.claim")],ownerID:"owner-123")
        let valid = try JSONValue.parse(Data(#"{"action":{"id":"request-123","type":"rewards.claim","status":"accepted"},"state":{"user":{"id":"owner-123"},"balanceUnits":100,"serverTime":123}}"#.utf8))
        XCTAssertTrue(ActionReceipt.confirms(valid,operation:operation))
        XCTAssertFalse(ActionReceipt.confirms(.null,operation:operation))
        XCTAssertFalse(ActionReceipt.confirms(valid["state"],operation:operation))
        let wrongID = PendingAction(id:"different-request",body:operation.body,ownerID:operation.ownerID)
        XCTAssertFalse(ActionReceipt.confirms(valid,operation:wrongID))
        let wrongOwner = PendingAction(id:operation.id,body:operation.body,ownerID:"other-owner")
        XCTAssertFalse(ActionReceipt.confirms(valid,operation:wrongOwner))
        let rejected = try JSONValue.parse(Data(#"{"action":{"id":"request-123","type":"rewards.claim","status":"rejected"},"state":{"user":{"id":"owner-123"},"balanceUnits":100,"serverTime":123}}"#.utf8))
        XCTAssertFalse(ActionReceipt.confirms(rejected,operation:operation))
    }
    func testCelebrationUsesPositiveNetAndRespectsReducedMotion() {
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:99,reducedMotion:false),0)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:100,reducedMotion:false),0)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:101,reducedMotion:false),0)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:150,reducedMotion:false),6)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:200,reducedMotion:false),12)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:500,reducedMotion:false),18)
        XCTAssertEqual(ResultPresentation.particleCount(committed:100,returned:500,reducedMotion:true),0)
    }
}
