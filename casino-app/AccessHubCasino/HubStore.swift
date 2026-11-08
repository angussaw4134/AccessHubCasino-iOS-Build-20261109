import Foundation
import SwiftUI

struct HubCommand: Codable, Equatable {
    let id: String
    let ownerID: String
    let type: String
    let payload: [String: JSONValue]
    var body: [String: JSONValue] { ["id":.string(id),"type":.string(type),"payload":.object(payload)] }
    func accepts(_ response: JSONValue) -> Bool {
        response["receipt"]["id"].string == id && response["receipt"]["type"].string == type && response["receipt"]["status"].string == "accepted"
    }
}

enum HubDestination: Hashable, Identifiable {
    case daily, giveaways, vouchers, inventory, marketplace, points, friends, support, notifications, preferences, progress
    case ticket(String), snake(String), voucher(String)
    var id: String { String(describing:self) }
    static func notification(_ value: JSONValue) -> HubDestination? {
        let type = value["screen"].string
        let resource = value["id"].string
        switch type {
        case "support", "ticket": return resource.isEmpty ? .support : .ticket(resource)
        case "snake", "room": return resource.isEmpty ? nil : .snake(resource)
        case "voucher", "vouchers": return resource.isEmpty ? .vouchers : .voucher(resource)
        case "friend", "friends": return .friends
        case "giveaway", "giveaways": return .giveaways
        case "marketplace", "sale": return .marketplace
        case "daily": return .daily
        case "notifications": return .notifications
        case "profile": return .progress
        default: return nil
        }
    }
}

@MainActor final class HubStore: ObservableObject {
    @Published var bootstrap: JSONValue = .null
    @Published var collections: [String: JSONValue] = [:]
    @Published var loading = Set<String>()
    @Published var errors: [String:String] = [:]
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var pending: HubCommand?
    @Published var destination: HubDestination?
    @Published var lastResult: JSONValue = .null
    @Published var learning: JSONValue = .null
    @Published var hubLevelUp: Int?
    @Published private(set) var ownerID = ""
    private weak var casino: CasinoStore?
    private var refreshTask: Task<Void,Never>?
    private var generation = 0
    private var bootstrapVersion = 0
    private var collectionQueries: [String:(String,String)] = [:]
    var points: Int { bootstrap["pointsBalance"].int }
    var profile: JSONValue { bootstrap["profile"] }
    func equipped(_ kind: String) -> JSONValue { bootstrap["equippedItems"][kind] }
    func featureEnabled(_ name: String) -> Bool { bootstrap["config"]["features"][name] != .bool(false) }
    var canAct: Bool { casino?.authenticated == true && casino?.needsSignIn == false && !busy && pending == nil && bootstrap.exists }
    var isAvailable: Bool { bootstrap["schemaVersion"].int == 2 }
    static func storageKey(owner: String) -> String { "accesshub.hub.pending.v2." + owner }

    func attach(_ store: CasinoStore) async {
        refreshTask?.cancel(); refreshTask = nil
        generation += 1
        loading = []; busy = false
        let nextOwner = store.state["user"]["id"].string
        casino = store
        if nextOwner != ownerID {
            ownerID = nextOwner; bootstrap = .null; collections = [:]; loading = []; errors = [:]
            error = nil; notice = nil; destination = nil; lastResult = .null; pending = nil; learning = .null; hubLevelUp = nil
        }
        guard !ownerID.isEmpty else { store.hubHasPending = false; return }
        if let data = UserDefaults.standard.data(forKey:Self.storageKey(owner:ownerID)) {
            pending = try? JSONDecoder().decode(HubCommand.self,from:data)
        }
        store.hubHasPending = pending != nil
        await refresh()
        await loadLearning()
        if pending != nil { await retry() }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(20))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }
    func suspend() { refreshTask?.cancel(); refreshTask = nil }
    func resume() async { if let casino { await attach(casino) } }
    func fetch(_ path: String) async throws -> JSONValue {
        guard let casino, casino.state["user"]["id"].string == ownerID else { throw CancellationError() }
        let stamp = generation
        let result = try await casino.hubRequest(path)
        guard stamp == generation else { throw CancellationError() }
        return result
    }
    func refresh(force: Bool = false) async {
        guard !ownerID.isEmpty, force || !loading.contains("bootstrap") else { return }
        let stamp = generation
        bootstrapVersion += 1
        let version = bootstrapVersion
        loading.insert("bootstrap")
        defer { if stamp == generation && version == bootstrapVersion { loading.remove("bootstrap") } }
        do {
            let result = try await fetch("/v2/bootstrap")
            guard version == bootstrapVersion else { return }
            guard result["schemaVersion"].int == 2, result["profile"]["id"].string == ownerID else { throw CasinoError.invalidResponse }
            let priorLevel = profile["level"].int
            bootstrap = result; errors.removeValue(forKey:"bootstrap")
            if priorLevel > 0 && result["profile"]["level"].int > priorLevel { hubLevelUp = result["profile"]["level"].int }
        } catch is CancellationError {} catch { if stamp == generation && version == bootstrapVersion { errors["bootstrap"] = error.localizedDescription } }
    }
    func items(_ key: String) -> [JSONValue] { (collections[key] ?? .null)["items"].array }
    func collection(_ key: String, query: String = "", filter: String = "", more: Bool = false) async {
        guard !loading.contains(key), !ownerID.isEmpty else { return }
        let stamp = generation
        if !more { collectionQueries[key] = (query,filter) }
        loading.insert(key); defer { if stamp == generation { loading.remove(key) } }
        do {
            var path = "/v2/" + key + "?limit=40"
            if !query.isEmpty { path += "&q=" + Self.escape(query) }
            if !filter.isEmpty { path += "&filter=" + Self.escape(filter) }
            if more, let old = collections[key], !old["nextCursor"].string.isEmpty { path += "&cursor=" + Self.escape(old["nextCursor"].string) }
            let response = try await fetch(path)
            if more {
                let old = items(key)
                var seen = Set(old.map { $0["id"].string })
                let additional = response["items"].array.filter { seen.insert($0["id"].string).inserted }
                var body = response.object; body["items"] = .array(old + additional)
                collections[key] = .object(body)
            } else { collections[key] = response }
            errors.removeValue(forKey:key)
        } catch is CancellationError {} catch { if stamp == generation { errors[key] = error.localizedDescription } }
    }
    func loadMore(_ key: String) async { let criteria = collectionQueries[key] ?? ("",""); await collection(key,query:criteria.0,filter:criteria.1,more:true) }
    func daily() async {
        do { collections["daily"] = try await fetch("/v2/daily"); errors.removeValue(forKey:"daily") }
        catch is CancellationError {} catch { errors["daily"] = error.localizedDescription }
    }
    func loadLearning() async {
        do { learning = try await fetch("/v2/learning") } catch is CancellationError {} catch { errors["learning"] = error.localizedDescription }
    }
    @discardableResult func action(_ type: String, _ payload: [String:JSONValue] = [:]) async -> Bool {
        guard canAct else { return false }
        let family = type.split(separator:".").first.map(String.init) ?? ""
        let feature = ["daily":"daily","giveaway":"giveaways","voucher":"vouchers","market":"marketplace","friend":"community","user":"community"][family]
        if let feature,!featureEnabled(feature) { error = "This feature is temporarily unavailable. Please try again later."; return false }
        let command = HubCommand(id:UUID().uuidString,ownerID:ownerID,type:type,payload:payload)
        pending = command; casino?.hubHasPending = true
        UserDefaults.standard.set(try? JSONEncoder().encode(command),forKey:Self.storageKey(owner:ownerID))
        return await retry()
    }
    @discardableResult func retry() async -> Bool {
        guard let pending, let casino, !busy, pending.ownerID == ownerID else { return false }
        let stamp = generation
        busy = true; error = nil
        defer { if stamp == generation { busy = false } }
        do {
            let response = try await casino.hubRequest("/v2/action",body:pending.body)
            guard stamp == generation, pending.accepts(response) else { throw CasinoError.invalidResponse }
            lastResult = response["result"]
            clearPending()
            notice = response["receipt"]["message"].string.isEmpty ? "Saved" : response["receipt"]["message"].string
            casino.feedback(pending.type)
            await refresh(force:true)
            if pending.type == "learning.complete" { await loadLearning() }
            return true
        } catch is CancellationError { return false }
        catch let failure as CasinoStore.HTTPFailure {
            if stamp != generation { return false }
            if (400..<500).contains(failure.status) && ![401,408,429].contains(failure.status) { clearPending() }
            error = failure.message
        } catch {
            if stamp == generation { self.error = "Your request is saved. Reconnect and retry to confirm its actual result." }
        }
        return false
    }
    private func clearPending() {
        UserDefaults.standard.removeObject(forKey:Self.storageKey(owner:ownerID)); pending = nil; casino?.hubHasPending = false
    }
    func openNotification(_ notification: JSONValue) async {
        let id = notification["id"].string
        guard !id.isEmpty else { return }
        // Marking read itself authorizes the inbox record; destination fetches
        // independently authorize its resource after navigation.
        if await action("notification.read",["notificationId":.string(id)]) {
            destination = HubDestination.notification(notification["route"])
            await collection("notifications")
        }
    }
    static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? "" }
}

extension JSONValue: Identifiable { var id: String { self["id"].string.isEmpty ? self["period"].string : self["id"].string } }
