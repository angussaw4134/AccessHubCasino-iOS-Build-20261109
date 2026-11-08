import Foundation
import SwiftUI

enum RealtimeWire {
    /// Cloudflare's room contract accepts JSON text frames, never binary data.
    static func message(_ body: [String:JSONValue]) throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return .string(String(decoding:try encoder.encode(JSONValue.object(body)),as:UTF8.self))
    }
}

@MainActor final class LiveSession: ObservableObject {
    @Published var snapshot: JSONValue = .null
    @Published var previous: JSONValue = .null
    @Published var messages: [JSONValue] = []
    @Published var connected = false
    @Published var status = "Connecting…"
    @Published var error: String?
    @Published var presence = 0
    @Published var unread = 0
    @Published var pending: [String:JSONValue] = [:]
    @Published var oldestCursor = 0
    var receivedAt = Date()
    var serverOffset: TimeInterval = 0
    private var socket: URLSessionWebSocketTask?
    private var loop: Task<Void,Never>?
    private var heartbeat: Task<Void,Never>?
    private weak var store: CasinoStore?
    private var path = ""
    private var owner = ""
    private var revision = 0
    private var active = false
    private var lastSequence = 0
    private var inputSequence = 0
    private var recoveryCursor = 0
    private var journalKey: String { "accesshub.live.pending.v2.\(owner).\(path)" }
    var room: JSONValue { snapshot["room"] }
    var now: Double { (Date().timeIntervalSince1970 + serverOffset)*1000 }
    func connect(store: CasinoStore,path: String) {
        disconnect()
        let newOwner = store.state["user"]["id"].string
        if newOwner != owner || self.path != path { snapshot = .null; previous = .null; messages = []; pending = [:]; lastSequence = 0; inputSequence = 0 }
        self.store = store; self.path = path; owner = newOwner; active = true
        if path.contains("/chat/") { messages = []; oldestCursor = 0; lastSequence = 0 }
        if let data = UserDefaults.standard.data(forKey:journalKey),let saved = try? JSONValue.parse(data) { pending = saved.object }
        let stamp = revision
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.active && stamp == self.revision {
                do {
                    guard store.state["user"]["id"].string == self.owner else { return }
                    if store.needsSignIn { self.status = "Sign in to reconnect"; self.disconnect(); return }
                    let request = try store.socketRequest(path + "/ws")
                    let socket = URLSession.shared.webSocketTask(with:request)
                    self.socket = socket; self.recoveryCursor = self.lastSequence; socket.resume()
                    self.heartbeat = Task { [weak self] in
                        while !Task.isCancelled { try? await Task.sleep(for:.seconds(10)); guard !Task.isCancelled else { return }; await self?.transmit(["type":.string("ping")]) }
                    }
                    while !Task.isCancelled && stamp == self.revision {
                        let message = try await socket.receive()
                        guard stamp == self.revision,store.state["user"]["id"].string == self.owner else { return }
                        let bytes: Data
                        switch message { case .data(let data): bytes = data; case .string(let string): bytes = Data(string.utf8); @unknown default: continue }
                        self.receive(try JSONValue.parse(bytes))
                    }
                } catch is CancellationError { return }
                catch {
                    guard stamp == self.revision && self.active else { return }
                    self.connected = false; self.status = "Reconnecting · state restored from server"; self.heartbeat?.cancel()
                    self.socket?.cancel(with:.goingAway,reason:nil)
                    try? await Task.sleep(for:.seconds(2))
                }
            }
        }
    }
    func disconnect() {
        active = false; revision += 1; loop?.cancel(); loop = nil; heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(with:.goingAway,reason:nil); socket = nil; connected = false
    }
    func seed(_ value: JSONValue) { receive(value); connected = false; status = "Connecting to room…" }
    func send(_ type: String,fields: [String:JSONValue] = [:],durable: Bool = true) {
        guard connected else { error = "Reconnect before sending this action."; return }
        var body = fields; body["type"] = .string(type)
        if durable { let id = UUID().uuidString; body["id"] = .string(id); pending[id] = .object(body); persist() }
        if ["send","reply","react","ready","leave"].contains(type) { store?.feedback("tap") }
        Task { await transmit(body) }
    }
    func direction(_ direction: String) {
        guard connected,room["phase"].string == "running",room["yourRole"].string == "player" else { return }
        inputSequence += 1
        store?.feedback("tap")
        send("direction",fields:["seq":.number(Double(inputSequence)),"direction":.string(direction)],durable:false)
    }
    private func transmit(_ body: [String:JSONValue]) async {
        guard let socket else { return }
        do { try await socket.send(RealtimeWire.message(body)) }
        catch { connected = false; status = "Reconnecting · saved actions will be checked" }
    }
    private func receive(_ value: JSONValue) {
        let type = value["type"].string
        if value["serverTime"].double > 0 { serverOffset = value["serverTime"].double/1000-Date().timeIntervalSince1970 }
        if type == "control_taken" { error = "Another device is controlling this player."; status = "Control moved to another device"; disconnect(); return }
        if type == "error" {
            error = value["error"]["message"].string
            let code = value["error"]["code"].string
            if !["service_unavailable","unauthorized","rate_limit"].contains(code) { pending.removeValue(forKey:value["id"].string); persist() }
            if code == "unauthorized" { store?.needsSignIn = true; status = "Sign in to reconnect"; disconnect() }
            else if ["moderated","account_restricted","forbidden"].contains(code) { status = "Access restricted"; disconnect() }
            return
        }
        if type == "ack" { pending.removeValue(forKey:value["id"].string); persist(); return }
        if type == "input_ack" { inputSequence = max(inputSequence,value["lastInputSeq"].int); return }
        if type == "state" {
            guard !snapshot.exists || value["seq"].int >= snapshot["seq"].int else { return }
            let justConnected = !connected
            connected = true; status = "Live"; previous = snapshot; snapshot = value; receivedAt = Date()
            if previous["room"]["phase"].string == "running" && ["finished","cancelled"].contains(room["phase"].string) { store?.feedback("finish") }
            if let mine = room["game"]["snakes"].array.first(where:{ $0.id == owner }),let before = previous["room"]["game"]["snakes"].array.first(where:{ $0.id == owner }),mine["score"].int > before["score"].int { store?.feedback("reveal") }
            if let snake = room["game"]["snakes"].array.first(where:{ $0.id == owner }) { inputSequence = max(inputSequence,snake["lastInputSeq"].int) }
            UserDefaults.standard.set(["roomID":room.id,"phase":room["phase"].string],forKey:"accesshub.snake.last.\(owner)")
            if justConnected { replay() }
            return
        }
        if type == "welcome" || type == "history" {
            let firstConnection = !connected
            connected = true; status = "Live"; unread = value["unread"].int
            for message in value["items"].array { merge(message) }
            for event in value["events"].array { apply(event) }
            if value["oldestCursor"].int > 0 { oldestCursor = oldestCursor == 0 ? value["oldestCursor"].int : min(oldestCursor,value["oldestCursor"].int) }
            lastSequence = max(lastSequence,value["nextCursor"].int)
            if type == "welcome" {
                if recoveryCursor > 0 { send("resume",fields:["after":.number(Double(recoveryCursor)),"limit":.number(100)],durable:false) }
                if firstConnection { replay() }
            } else if value["hasMore"].bool && !value["events"].array.isEmpty {
                send("resume",fields:["after":value["nextCursor"],"limit":.number(100)],durable:false)
            }
            return
        }
        if type == "presence" { presence = value["count"].int; return }
        apply(value)
    }
    private func apply(_ event: JSONValue) {
        let type = event["type"].string
        guard ["message","reaction","deleted","cursor"].contains(type) else { return }
        lastSequence = max(lastSequence,event["seq"].int)
        if type == "message" { merge(event["message"]) }
        else if let index = messages.firstIndex(where:{ $0.id == event["messageId"].string }) {
            var item = messages[index].object
            if type == "deleted" { item["body"] = .null; item["deletedAt"] = event["serverTime"] }
            else if type == "reaction" { item["reactions"] = event["reactions"] }
            messages[index] = .object(item)
        }
    }
    private func merge(_ message: JSONValue) {
        guard !message.id.isEmpty else { return }
        if let index = messages.firstIndex(where:{ $0.id == message.id }) { messages[index] = message }
        else { messages.append(message) }
        messages.sort { $0["seq"].int < $1["seq"].int }
    }
    private func replay() { for item in pending.values { Task { await transmit(item.object) } } }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(JSONValue.object(pending)),forKey:journalKey) }
    func readVisible() { if connected && lastSequence > 0 { send("read",fields:["seq":.number(Double(lastSequence))]); unread = 0 } }
}

struct ChatRoomView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var live = LiveSession()
    let channel: String
    @State private var draft = ""
    @State private var reply: JSONValue?
    @State private var report: JSONValue?
    @State private var profile: JSONValue?
    var body: some View {
        VStack(spacing:0) {
            HStack { Circle().fill(live.connected ? AH.emerald : AH.gold).frame(width:6,height:6); Text(live.status); Spacer(); if live.connected { Text("\(live.presence) visible online") } }.font(.caption2).foregroundStyle(AH.muted).padding(14)
            if let error = live.error { HStack { Text(error).font(.caption).foregroundStyle(AH.gold); Spacer(); Button("Dismiss") { live.error = nil }.font(.caption) }.padding(.horizontal,16) }
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(alignment:.leading,spacing:12) {
                    if live.oldestCursor > 0 { Button("Load earlier messages") { live.send("history",fields:["before":.number(Double(live.oldestCursor)),"limit":.number(50)],durable:false) }.font(.caption).frame(maxWidth:.infinity).disabled(!live.connected) }
                    if live.messages.isEmpty { EmptyState(title:"Start a conversation.",detail:channel == "announcements" ? "Official announcements will appear here." : "Keep it friendly. Only real messages appear here.") }
                    ForEach(live.messages) { message in messageView(message).id(message.id) }
                    Color.clear.frame(height:1).id("latest")
                }.padding(16) }
                .onChange(of:live.messages.last?.id) { _,_ in if store.reducedMotion { proxy.scrollTo("latest",anchor:.bottom) } else { withAnimation(.easeOut(duration:0.2)) { proxy.scrollTo("latest",anchor:.bottom) } }; live.readVisible() }
            }
            if !live.pending.isEmpty { Text("\(live.pending.count) action(s) awaiting server confirmation").font(.caption2).foregroundStyle(AH.gold).padding(6) }
            if channel != "announcements" {
                if let reply { HStack { Text("Replying to \(reply["user"]["username"].string)").font(.caption); Spacer(); Button("Cancel") { self.reply = nil }.font(.caption) }.padding(.horizontal,16) }
                HStack(alignment:.bottom,spacing:10) {
                    TextField("Message the room",text:$draft,axis:.vertical).lineLimit(1...4).fieldStyle()
                    Button { let body = draft.trimmingCharacters(in:.whitespacesAndNewlines); guard !body.isEmpty else { return }; var fields: [String:JSONValue] = ["body":.string(body)]; if let reply { fields["parentId"] = .string(reply.id) }; live.send(reply == nil ? "send" : "reply",fields:fields); draft = ""; reply = nil } label: { Image(systemName:"arrow.up.circle.fill").font(.system(size:34)) }.disabled(!live.connected || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.count > 1000).accessibilityLabel("Send message")
                }.padding(14).background(AH.panel)
            }
        }.pageBackground().navigationTitle(channel == "global" ? "Global lounge" : channel.capitalized).navigationBarTitleDisplayMode(.inline)
        .onAppear { connect() }.onDisappear { live.disconnect() }
        .onChange(of:scenePhase) { _,value in if value == .active { connect() } else { live.disconnect() } }
        .onChange(of:store.sessionRevision) { _,_ in live.disconnect(); draft = ""; reply = nil; connect() }
        .sheet(item:$report) { message in ReportUserView(userID:message["user"].id,name:message["user"]["username"].string,messageID:message.id,channel:channel) }
        .sheet(item:$profile) { person in CommunityProfilePreview(person:person) }
    }
    private func connect() { live.connect(store:store,path:"/v2/chat/" + channel) }
    private func messageView(_ message: JSONValue) -> some View {
        Panel(padding:14) { VStack(alignment:.leading,spacing:8) {
            HStack { Text(message["user"]["username"].string).font(.caption.bold()).foregroundStyle(AH.emerald); Spacer(); Text(readableDate(message["createdAt"])).font(.system(size:9)).foregroundStyle(AH.muted) }
            if message["parentId"].exists { Text(live.messages.first(where:{ $0.id == message["parentId"].string })?["body"].string ?? "Reply to an earlier message").font(.caption2).foregroundStyle(AH.muted).lineLimit(2).padding(.leading,8).overlay(alignment:.leading) { Rectangle().fill(AH.emerald.opacity(0.4)).frame(width:2) } }
            if message["replyUnavailable"].bool { Text("Reply unavailable").font(.caption2).foregroundStyle(AH.muted) }
            Text(message["deletedAt"].exists ? "Message removed" : message["body"].string).font(.subheadline).foregroundStyle(message["deletedAt"].exists ? AH.muted : AH.text).textSelection(.enabled)
            if !message["reactions"].array.isEmpty { HStack { ForEach(Array(message["reactions"].array.enumerated()),id:\.offset) { _,reaction in Text("\(reaction["emoji"].string) \(reaction["count"].int)").font(.caption) } } }
        } }.contextMenu {
            Button("View profile") { profile = message["user"] }
            if !message["deletedAt"].exists {
                Button("Reply") { reply = message }
                ForEach(["👍","❤️","🎉","😂","🐍","💎"],id:\.self) { emoji in Menu("React \(emoji)") { Button("Add \(emoji)") { live.send("react",fields:["messageId":.string(message.id),"emoji":.string(emoji),"active":.bool(true)]) }; Button("Remove my \(emoji)") { live.send("react",fields:["messageId":.string(message.id),"emoji":.string(emoji),"active":.bool(false)]) } } }
            }
            if message["user"].id == hub.ownerID { Button("Delete message",role:.destructive) { live.send("delete",fields:["messageId":.string(message.id)]) } }
            else { Button("Report") { report = message }; Button("Block member",role:.destructive) { Task { if await hub.action("user.block",["userId":.string(message["user"].id)]) { live.disconnect(); live.messages = []; connect() } } } }
        }
    }
}

struct CommunityProfilePreview: View {
    @EnvironmentObject var hub: HubStore
    @Environment(\.dismiss) private var dismiss
    let person: JSONValue
    var body: some View {
        NavigationStack { VStack(alignment:.leading,spacing:24) {
            CosmeticMotif(kind:"avatarFrame",art:person["avatar"].string).frame(height:130)
            SectionTitle(title:person["username"].string,caption:"AccessHub community member")
            if person.id != hub.ownerID {
                Button("Send friend request") { Task { if await hub.action("friend.request",["userId":.string(person.id)]) { dismiss() } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct)
                NavigationLink { SnakeLobbyView(inviteeID:person.id) } label: { Label("Invite to Snake",systemImage:"gamecontroller") }
                NavigationLink { ReportUserView(userID:person.id,name:person["username"].string) } label: { Text("Report member") }
            }
            Spacer()
        }.padding(24).pageBackground().navigationTitle("Profile").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } } }
    }
}
