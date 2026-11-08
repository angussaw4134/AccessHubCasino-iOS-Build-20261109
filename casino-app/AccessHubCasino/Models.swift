import Foundation

/// The wire format uses integer millionths of one Access Hub Credit.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    subscript(_ index: Int) -> JSONValue { let v = array; return v.indices.contains(index) ? v[index] : .null }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var string: String {
        switch self { case .string(let v): return v; case .number(let v): return v == floor(v) ? String(format: "%.0f", v) : String(v); default: return "" }
    }
    var double: Double { if case .number(let v) = self { return v }; return Double(string) ?? 0 }
    var int: Int { Int(double) }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var exists: Bool { self != .null }
    static func parse(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
}

enum Credits {
    static let scale: Double = 1_000_000
    static func format(_ units: Double, precision: Int = 2) -> String {
        guard units.isFinite, abs(units) <= 9_007_199_254_740_991 else { return "—" }
        let places = min(6,max(0,precision))
        let divisor = Int64(pow(10,Double(6-places)))
        let fractionalBase = Int64(pow(10,Double(places)))
        let raw = Int64(units.rounded())
        let rounded = (abs(raw) + divisor/2) / divisor
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier:"en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let whole = formatter.string(from:NSNumber(value:rounded/fractionalBase)) ?? "0"
        let digits = String(rounded % fractionalBase)
        var fraction = places > 0 ? String(repeating:"0",count:max(0,places-digits.count)) + digits : ""
        while fraction.last == "0" { fraction.removeLast() }
        return (raw < 0 && rounded != 0 ? "-" : "") + whole + (fraction.isEmpty ? "" : "."+fraction)
    }
    static func units(_ credits: String) -> Double { (Double(credits) ?? 0) * scale }
}

enum CasinoGame: String, CaseIterable, Identifiable {
    case crash, blackjack, mines, slots
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var art: String { title + "Art" }
    var subtitle: String {
        switch self {
        case .crash: return "Find your moment. Collect before the climb ends."
        case .blackjack: return "A classic table. A considered next move."
        case .mines: return "Uncover emeralds. Choose when to collect."
        case .slots: return "Five reels. One luminous collection."
        }
    }
    var eyebrow: String {
        switch self { case .crash: return "LIVE SHARED ROUNDS"; case .blackjack: return "THE CLASSIC TABLE"; case .mines: return "EVERY REVEAL, YOUR CHOICE"; case .slots: return "EMERALD VAULT" }
    }
}

struct PendingAction: Codable, Equatable {
    let id: String
    let body: [String: JSONValue]
    var ownerID: String? = nil
    var ownerUsername: String? = nil
}

enum ActionReceipt {
    /// A cooldown rejection is recorded against this exact ID by the server;
    /// retrying it can never turn it into an accepted refill. Transport throttles
    /// and unavailable authentication remain retryable with the original ID.
    static func isDefinitiveRejection(status: Int, code: String) -> Bool {
        if status == 429 { return code == "refill_wait" }
        return (400..<500).contains(status) && ![401,408].contains(status)
    }
    static func confirms(_ response: JSONValue, operation: PendingAction) -> Bool {
        guard let expectedType = operation.body["type"]?.string, !expectedType.isEmpty else { return false }
        guard response["action"]["id"].string == operation.id,
              response["action"]["status"].string == "accepted",
              response["action"]["type"].string == expectedType,
              !response["state"]["user"]["id"].string.isEmpty,
              response["state"]["balanceUnits"].exists,
              response["state"]["serverTime"].exists else { return false }
        if let owner = operation.ownerID { return response["state"]["user"]["id"].string == owner }
        return true
    }
}

enum ResultPresentation {
    static func particleCount(committed: Double, returned: Double, reducedMotion: Bool) -> Int {
        guard !reducedMotion, committed > 0, returned > committed else { return 0 }
        let ratio = returned / committed
        if ratio < 1.25 { return 0 }
        if ratio < 2 { return 6 }
        if ratio < 5 { return 12 }
        return 18
    }
}

enum CasinoError: LocalizedError {
    case message(String), invalidEndpoint, invalidResponse
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .invalidEndpoint: return "The service address is not valid."
        case .invalidResponse: return "The service returned an unreadable response. Please reconnect."
        }
    }
}

func readableDate(_ value: JSONValue) -> String {
    let milliseconds = value.double
    guard milliseconds > 0 else { return "" }
    return Date(timeIntervalSince1970: milliseconds / 1000).formatted(date: .abbreviated, time: .shortened)
}
