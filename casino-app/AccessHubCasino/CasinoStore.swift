import Foundation
import SwiftUI
import AVFoundation
import UIKit

@MainActor final class CasinoStore: ObservableObject {
    @Published var state: JSONValue = .null
    @Published var busy = false
    @Published var connecting = false
    @Published var online = false
    @Published var error: String?
    @Published var notice: String?
    @Published var pending: PendingAction?
    @Published var levelUp: Int?
    @Published var selectedTab = 0
    @Published var rules: JSONValue = .null
    @Published var needsSignIn = false
    @Published private(set) var sessionRevision = 0
    var hubHasPending = false
    var beforeSessionEnd: (() async throws -> Void)?
    private var token = SessionVault.read()
    private var lastKnownUsername = SessionVault.read("username") ?? ""
    private var polling: Task<Void, Never>?
    private var audio: AVAudioPlayer?
    private var offset: TimeInterval = 0
    private var lastResponseAt = Date.distantPast
    private var mutationGeneration = 0
    private var presentedResults = Set(UserDefaults.standard.stringArray(forKey:"accesshub.presented-results.v1") ?? [])
    static let pendingKey = "accesshub.pending.v1"
    let baseURL: URL

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AccessHubAPIBaseURL") as? String ?? ""
        if let endpoint = URL(string:configured), endpoint.scheme == "https", endpoint.host != nil {
            baseURL = endpoint
        } else {
            baseURL = URL(string:"https://accesshub-casino-native.fejiofasj.workers.dev")!
        }
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey) { pending = try? JSONDecoder().decode(PendingAction.self, from: data) }
    }
    var balance: Double { state["balanceUnits"].double }
    var availableRewards: Double { state["availableRakebackUnits"].double }
    var authenticated: Bool { state["user"]["id"].exists }
    var reducedMotion: Bool { state["settings"]["reducedMotion"].bool || UIAccessibility.isReduceMotionEnabled }
    var canAct: Bool { authenticated && online && !needsSignIn && !busy && pending == nil }
    var serverNow: Double { (Date().timeIntervalSince1970 + offset) * 1000 }
    var canRestoreGuest: Bool {
        let username = state["user"]["username"].string.isEmpty ? (pending?.ownerUsername ?? lastKnownUsername) : state["user"]["username"].string
        return username.isEmpty && SessionVault.read("guest-id") != nil
    }
    var hasUnresolvedGames: Bool {
        state["games"]["mines"]["status"].string == "active" || state["games"]["blackjack"]["status"].string == "active" || ["pending", "running"].contains(state["crash"]["position"]["status"].string)
    }

    func launch() async {
        guard !connecting else { return }
        if token != nil { await refresh(); startPolling() }
    }
    func guest() async {
        guard !busy, !connecting else { return }
        busy = true; error = nil
        mutationGeneration += 1
        defer { busy = false }
        do {
            var guestID = SessionVault.read("guest-id")
            if guestID == nil { guestID = UUID().uuidString; try SessionVault.write(guestID!, account: "guest-id") }
            let response = try await request("/v1/guest", body: ["id": .string(guestID!)], authenticated: false)
            try acceptSession(response)
            notice = pending == nil ? "Your account is ready. Credits are added by an administrator." : "Guest session restored. Checking your saved request."
            startPolling()
        } catch { self.error = error.localizedDescription }
    }
    func account(username: String, password: String, register: Bool) async -> Bool {
        guard !busy else { return false }
        if hubHasPending && !register { error = "Resolve your saved Hub request before changing accounts."; return false }
        let expectedUsername = pending?.ownerUsername ?? state["user"]["username"].string
        if pending != nil && (register || username.lowercased() != expectedUsername.lowercased()) {
            error = "Sign back in to the same account to resolve your saved request before changing accounts."
            return false
        }
        guard username.range(of: "^[A-Za-z0-9_]{3,24}$", options: .regularExpression) != nil else { error = "Use 3–24 letters, numbers or underscores for your username."; return false }
        guard (10...128).contains(password.count) else { error = "Use a password between 10 and 128 characters."; return false }
        busy = true; error = nil
        mutationGeneration += 1
        defer { busy = false }
        do {
            let response = try await request("/v1/account/" + (register ? "register" : "login"), body: ["username": .string(username), "password": .string(password)], authenticated: register)
            try acceptSession(response)
            needsSignIn = false
            notice = register ? "Your progress is now saved to your account." : "Welcome back. Your progress is restored."
            startPolling()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func endSession(delete: Bool = false) async {
        guard canAct else { return }
        guard !hubHasPending else { error = "Resolve your saved Hub request before signing out."; return }
        busy = true; defer { busy = false }
        mutationGeneration += 1
        do {
            try await beforeSessionEnd?()
            _ = try await request(delete ? "/v1/account/delete" : "/v1/account/logout", body: [:])
            if delete {
                let ownerPrefix = state["user"]["id"].string + ":"
                presentedResults = Set(presentedResults.filter { !$0.hasPrefix(ownerPrefix) })
                UserDefaults.standard.set(Array(presentedResults),forKey:"accesshub.presented-results.v1")
            }
            polling?.cancel(); polling = nil; SessionVault.delete(); token = nil; state = .null
            try SessionVault.write(UUID().uuidString, account: "guest-id")
            try SessionVault.write("",account:"username"); lastKnownUsername = ""
            online = false; error = nil; notice = nil; selectedTab = 0
            sessionRevision += 1
        } catch { self.error = error.localizedDescription }
    }
    func action(_ type: String, _ fields: [String: JSONValue] = [:]) async {
        guard canAct else { return }
        var body = fields
        let id = UUID().uuidString
        body["id"] = .string(id); body["type"] = .string(type)
        let operation = PendingAction(id:id,body:body,ownerID:state["user"]["id"].string,ownerUsername:state["user"]["username"].string)
        pending = operation
        UserDefaults.standard.set(try? JSONEncoder().encode(operation), forKey: Self.pendingKey)
        await retryPending()
    }
    func retryPending() async {
        guard let operation = pending, !busy, !needsSignIn else { return }
        if let ownerID = operation.ownerID, state["user"]["id"].exists, ownerID != state["user"]["id"].string {
            error = "This request belongs to a different account. Sign in to its original account to resolve it."
            return
        }
        busy = true; error = nil; defer { busy = false }
        mutationGeneration += 1
        do {
            let response = try await request("/v1/action", body: operation.body)
            guard ActionReceipt.confirms(response,operation:operation) else { throw CasinoError.invalidResponse }
            clearPending(); update(response["state"])
            let message = response["action"]["message"].string
            if !message.isEmpty { notice = message }
            feedback(operation.body["type"]?.string ?? "tap")
        } catch is CancellationError {
            return
        } catch let issue as HTTPFailure {
            if ActionReceipt.isDefinitiveRejection(status:issue.status,code:issue.code) { clearPending() }
            if issue.status == 401 { needsSignIn = true }
            error = issue.message
            if issue.state.exists { update(issue.state) }
        } catch {
            online = false
            self.error = "Connection interrupted. Your request is saved. Reconnect to check its actual result."
        }
    }
    func refresh() async {
        guard token != nil, !connecting, !busy, !needsSignIn else { return }
        let generation = mutationGeneration
        connecting = true; defer { connecting = false }
        do {
            let response = try await request("/v1/state")
            guard generation == mutationGeneration else { return }
            update(response["state"])
            if pending != nil && !busy { await retryPending() }
        } catch is CancellationError {
            return
        } catch let issue as HTTPFailure {
            online = false
            if issue.status == 401 { needsSignIn = true; if !authenticated { error = canRestoreGuest ? "Your guest session expired. Restore guest access using this device's saved key." : "This session has expired. Sign in again to restore your account." } }
            else if !authenticated { error = issue.message }
        } catch { online = false; if !authenticated { self.error = "Unable to connect. Check your connection and try again." } }
    }
    func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func suspend() { polling?.cancel(); polling = nil; online = false }
    func resume() { if token != nil { startPolling() } }
    func loadRules() async {
        do { rules = try await request("/v1/rules", authenticated: false) } catch { self.error = error.localizedDescription }
    }
    func history(_ kind: String, before: String? = nil) async throws -> JSONValue {
        var path = "/v1/history?kind=\(kind)&limit=50"
        if let before { path += "&before=" + (before.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? before) }
        return try await request(path)
    }
    func setting(_ name: String, value: JSONValue) async { await action("settings.update", ["settings": .object([name: value])]) }
    func feedback(_ kind: String) {
        if state["settings"]["haptics"].bool { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        let file = kind.contains("collect") || kind.contains("claim") ? "collect" : kind.contains("reveal") ? "reveal" : kind.contains("spin") ? "reel" : "tap"
        playSound(file)
    }
    /// Returns true only for the first visible presentation of this account's
    /// settled round. Navigation and reconnection cannot replay the celebration.
    func presentResult(roundID: String, committed: Double, returned: Double) -> Bool {
        guard !roundID.isEmpty, authenticated else { return false }
        let key = state["user"]["id"].string + ":" + roundID
        guard !presentedResults.contains(key) else { return false }
        presentedResults.insert(key)
        UserDefaults.standard.set(Array(presentedResults),forKey:"accesshub.presented-results.v1")
        if state["settings"]["haptics"].bool && returned > committed {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        playSound(returned > committed ? "win" : returned == committed ? "tap" : "finish")
        return true
    }
    private func playSound(_ file: String) {
        guard state["settings"]["sound"].bool else { return }
        guard let url = Bundle.main.url(forResource: file, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        audio = try? AVAudioPlayer(contentsOf: url); audio?.volume = 0.3; audio?.play()
    }
    private func acceptSession(_ response: JSONValue) throws {
        let nextToken = response["token"].string
        guard !nextToken.isEmpty, response["state"]["user"]["id"].exists else { throw CasinoError.invalidResponse }
        if let owner = pending?.ownerID, owner != response["state"]["user"]["id"].string {
            throw CasinoError.message("This is a different account from your saved request. Restore the original account to confirm its result.")
        }
        try SessionVault.write(nextToken); token = nextToken
        sessionRevision += 1
        lastKnownUsername = response["state"]["user"]["username"].string
        try? SessionVault.write(lastKnownUsername,account:"username")
        needsSignIn = false
        update(response["state"])
    }
    private func clearPending() { pending = nil; UserDefaults.standard.removeObject(forKey: Self.pendingKey) }
    private func update(_ next: JSONValue) {
        guard next["user"]["id"].exists else { return }
        if next["user"]["id"].string == state["user"]["id"].string {
            if next["revision"].exists && state["revision"].exists {
                if next["revision"].double < state["revision"].double { return }
            } else if next["serverTime"].double < state["serverTime"].double { return }
        }
        let oldLevel = state["progress"]["level"].int
        let newLevel = next["progress"]["level"].int
        offset = next["serverTime"].double / 1000 - Date().timeIntervalSince1970
        lastResponseAt = Date()
        withAnimation(reducedMotion ? nil : .easeOut(duration: 0.3)) { state = next; online = true }
        if oldLevel > 0 && newLevel > oldLevel { levelUp = newLevel }
    }
    struct HTTPFailure: LocalizedError { let status: Int; let code: String; let message: String; let state: JSONValue; var errorDescription: String? { message } }

    /// All Hub features use the existing session. A late response from a previous
    /// account is rejected before private data can reach a view or cache.
    func hubRequest(_ path: String, body: [String: JSONValue]? = nil) async throws -> JSONValue {
        guard authenticated, !needsSignIn else { throw CasinoError.message("Sign in to continue.") }
        return try await request(path, body:body)
    }
    func socketRequest(_ path: String) throws -> URLRequest {
        guard authenticated, !needsSignIn, let token,
              let endpoint = URL(string:path, relativeTo:baseURL)?.absoluteURL,
              var parts = URLComponents(url:endpoint,resolvingAgainstBaseURL:true) else { throw CasinoError.invalidEndpoint }
        parts.scheme = "wss"
        guard let url = parts.url else { throw CasinoError.invalidEndpoint }
        var request = URLRequest(url:url)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        return request
    }
    func privateData(_ path: String, upload: Data? = nil, contentType: String = "application/octet-stream", filename: String = "Screenshot") async throws -> (Data, HTTPURLResponse) {
        guard authenticated, !needsSignIn, let token,
              let endpoint = URL(string:path,relativeTo:baseURL)?.absoluteURL else { throw CasinoError.invalidEndpoint }
        let originalToken = token
        var request = URLRequest(url:endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        if let upload { request.httpMethod = "PUT"; request.httpBody = upload; request.setValue(contentType,forHTTPHeaderField:"Content-Type"); request.setValue(filename,forHTTPHeaderField:"X-Filename") }
        let (data,response) = try await URLSession.shared.data(for:request)
        try Task.checkCancellation()
        guard originalToken == self.token else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw CasinoError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONValue.parse(data)) ?? .null
            throw HTTPFailure(status:http.statusCode,code:json["error"]["code"].string,message:json["error"]["message"].string.isEmpty ? "Attachment request failed (\(http.statusCode))." : json["error"]["message"].string,state:.null)
        }
        return (data,http)
    }
    private func request(_ path: String, body: [String: JSONValue]? = nil, authenticated: Bool = true) async throws -> JSONValue {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw CasinoError.invalidEndpoint }
        let requestToken = token
        var request = URLRequest(url: url)
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(JSONValue.object(body))
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        if authenticated && requestToken != token { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw CasinoError.invalidResponse }
        let json = (try? JSONValue.parse(data)) ?? .null
        guard (200..<300).contains(http.statusCode) else {
            let message = json["error"]["message"].string
            throw HTTPFailure(status:http.statusCode,code:json["error"]["code"].string,message:message.isEmpty ? "The service could not complete this request (\(http.statusCode))." : message,state:json["state"])
        }
        return json
    }
}
