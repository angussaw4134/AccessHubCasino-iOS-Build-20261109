import SwiftUI

struct SnakeLobbyView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    var inviteeID: String? = nil
    @State private var mode = "duel"
    @State private var privacy = "private"
    @State private var spectators = false
    @State private var stake = "0"
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var destination: String?
    @State private var rules = false
    @State private var spectate = false
    private var createKey: String { "accesshub.snake.create." + hub.ownerID }
    var body: some View {
        HubPage(title:"Find your rhythm.",subtitle:"Solo practice and live friend challenges share the same fair rules.",refreshKey:"matches") {
            HubFeatureArt(name:"SnakeArt").frame(height:185).clipShape(RoundedRectangle(cornerRadius:22))
            if let saved = UserDefaults.standard.dictionary(forKey:"accesshub.snake.last."+hub.ownerID), let room = saved["roomID"] as? String, !["finished","cancelled"].contains(saved["phase"] as? String ?? "") {
                NavigationLink { SnakeRoomView(roomID:room) } label: { Label("Return to your room",systemImage:"arrow.clockwise") }.buttonStyle(PrimaryButton(secondary:true))
            }
            Panel { VStack(alignment:.leading,spacing:16) {
                Text(inviteeID == nil ? "Create a room" : "Challenge your friend").font(.headline)
                Picker("Mode",selection:$mode) { Text("Solo practice").tag("solo"); Text("Live 1 vs 1").tag("duel") }.pickerStyle(.segmented).disabled(inviteeID != nil)
                if mode == "duel" {
                    Picker("Room privacy",selection:$privacy) { Text("Private code").tag("private"); Text("Friends").tag("friends"); Text("Public").tag("public") }
                    Toggle("Allow spectators",isOn:$spectators)
                    TextField("Optional Access Hub Credit stake",text:$stake).keyboardType(.numberPad).fieldStyle()
                    Text("Default: 0, a friendly match. Both players must accept the same stake. Stakes are reserved only after acceptance; the winner receives the pot, draws and cancellations return stakes.").font(.caption).foregroundStyle(AH.muted)
                }
                Button("Create \(mode == "solo" ? "solo session" : "room")") { Task { await create() } }.buttonStyle(PrimaryButton()).disabled(busy || !hub.isAvailable || !validStake || !hub.featureEnabled("snake")).accessibilityIdentifier("snakeCreate")
                if UserDefaults.standard.data(forKey:createKey) != nil { Button("Check saved room request") { Task { await create() } }.font(.caption).disabled(busy) }
            } }
            Panel { VStack(alignment:.leading,spacing:14) {
                Text("Have a room code?").font(.headline)
                TextField("12-character room code",text:$code).textInputAutocapitalization(.characters).autocorrectionDisabled().fieldStyle()
                Toggle("Join as a spectator",isOn:$spectate).font(.subheadline)
                Button("Join room") { Task { await join() } }.buttonStyle(PrimaryButton(secondary:true)).disabled(busy || code.trimmingCharacters(in:.whitespacesAndNewlines).count != 12)
            } }
            if busy { ProgressView("Checking with the server…").tint(AH.emerald) }
            if let error { Text(error).font(.caption).foregroundStyle(AH.danger) }
            Button("Read the complete match rules") { rules = true }.font(.subheadline.bold())
            SectionTitle(title:"Your recent matches")
            HubStatus(key:"matches")
            if !hub.items("matches").isEmpty { Panel { HStack { Metric(title:"Loaded matches",value:String(hub.items("matches").count)); Metric(title:"Best loaded score",value:String(hub.items("matches").flatMap { $0["scores"].array }.filter { $0.id == hub.ownerID }.map { $0["score"].int }.max() ?? 0)) } } }
            if hub.items("matches").isEmpty { EmptyState(title:"Your first move is ahead.",detail:"Completed real matches will appear here.") }
            ForEach(hub.items("matches")) { match in
                NavigationLink { SnakeRoomView(roomID:match["roomId"].string.isEmpty ? match.id : match["roomId"].string) } label: { Panel { HStack { VStack(alignment:.leading,spacing:6) { Text(match["mode"].string == "solo" ? "Solo practice" : "Live challenge").font(.headline); Text(readableDate(match["endedAt"])).font(.caption).foregroundStyle(AH.muted) }; Spacer(); Text(matchResult(match)).font(.caption).foregroundStyle(AH.emerald) } } }.buttonStyle(.plain)
            }
            HubLoadMore(key:"matches")
        }.task { await hub.collection("matches") }
        .navigationDestination(isPresented:Binding(get:{ destination != nil },set:{ if !$0 { destination = nil } })) { if let destination { SnakeRoomView(roomID:destination) } }
        .sheet(isPresented:$rules) { NavigationStack { SnakeRulesView() } }
    }
    private var validStake: Bool { mode == "solo" || (Int(stake) != nil && (0...10000).contains(Int(stake) ?? -1)) }
    private func matchResult(_ match: JSONValue) -> String { let outcome = match["outcome"].string; if ["a","b"].contains(outcome) { return match["playerIds"][outcome == "a" ? 0 : 1].string == hub.ownerID ? "Won" : "Lost" }; return outcome == "solo" ? "Completed" : outcome.capitalized }
    private func create() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            var body: [String:JSONValue]
            if let saved = UserDefaults.standard.data(forKey:createKey) { body = try JSONValue.parse(saved).object }
            else { body = ["id":.string(UUID().uuidString),"mode":.string(mode),"privacy":.string(privacy),"stakeCredits":.number(mode == "solo" ? 0 : Double(Int(stake) ?? 0)),"allowSpectators":.bool(spectators)]; if let inviteeID { body["inviteeId"] = .string(inviteeID) }; UserDefaults.standard.set(try JSONEncoder().encode(JSONValue.object(body)),forKey:createKey) }
            let response = try await store.hubRequest("/v2/snake/rooms",body:body)
            guard !response["roomId"].string.isEmpty else { throw CasinoError.invalidResponse }
            UserDefaults.standard.removeObject(forKey:createKey); destination = response["roomId"].string
        } catch let failure as CasinoStore.HTTPFailure { if (400..<500).contains(failure.status) && ![401,408,429].contains(failure.status) { UserDefaults.standard.removeObject(forKey:createKey) }; error = failure.message }
        catch { self.error = "Room request saved. Retry to find its actual result. " + error.localizedDescription }
    }
    private func join() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { let response = try await store.hubRequest("/v2/snake/join",body:["code":.string(code.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()),"spectate":.bool(spectate)]); guard !response["roomId"].string.isEmpty else { throw CasinoError.invalidResponse }; destination = response["roomId"].string }
        catch { self.error = error.localizedDescription }
    }
}

struct SnakeRoomView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var live = LiveSession()
    let roomID: String
    @State private var confirmLeave = false
    @State private var pad = true
    @State private var rules = false
    private var room: JSONValue { live.room }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(room["mode"].string == "solo" ? "Solo practice" : "Live Snake").font(.title2.bold()); Text(live.status).font(.caption).foregroundStyle(live.connected ? AH.emerald : AH.gold) }; Spacer(); Button { rules = true } label: { Image(systemName:"info.circle") }.accessibilityLabel("Snake rules") }
            if let error = live.error { Text(error).font(.caption).foregroundStyle(AH.danger) }
            if !live.connected { Button("Reconnect to room") { Task { await restore() } }.font(.caption.bold()) }
            if room["yourRole"].string == "spectator" { Label("Spectating · \(room["spectatorCount"].int) viewers",systemImage:"eye").font(.caption).foregroundStyle(AH.muted) }
            HStack(alignment:.top,spacing:12) { ForEach(room["players"].array) { player in VStack(alignment:.leading,spacing:5) { Text(player["username"].string).font(.caption.bold()).lineLimit(1); Text(player["ready"].bool ? "Ready" : "Not ready").font(.caption2).foregroundStyle(player["ready"].bool ? AH.emerald : AH.muted); if let snake = room["game"]["snakes"].array.first(where:{ $0.id == player.id }) { Text("\(snake["score"].int) food").font(.headline) }; if !player["connected"].bool { Text("Reconnecting").font(.caption2).foregroundStyle(AH.gold) } }.frame(maxWidth:.infinity,alignment:.leading) } }
            ZStack {
                SnakeArena(current:room["game"],previous:live.previous["room"]["game"],players:room["players"],owner:hub.ownerID,skin:hub.equipped("snakeSkin"),trail:hub.equipped("snakeTrail"),receivedAt:live.receivedAt,reducedMotion:store.reducedMotion).aspectRatio(1,contentMode:.fit)
                if room["phase"].string == "countdown" {
                    TimelineView(.periodic(from:.now,by:0.1)) { _ in Text("\(max(1,Int(ceil((room["startAt"].double-live.now)/1000))))").font(.system(size:74,weight:.bold,design:.rounded)).foregroundStyle(AH.text).shadow(color:AH.emerald.opacity(0.5),radius:20) }
                } else if !room["game"].exists { VStack(spacing:10) { Image(systemName:"gamecontroller").font(.largeTitle); Text(room["phase"].string == "reserving" ? "Reserving agreed stakes…" : "Waiting for ready players").font(.headline) }.foregroundStyle(AH.muted).padding(20) }
            }.gesture(DragGesture(minimumDistance:14).onEnded { value in let x = value.translation.width,y = value.translation.height; live.direction(abs(x)>abs(y) ? (x>0 ? "right" : "left") : (y>0 ? "down" : "up")) })
            if room["phase"].string == "lobby" {
                Panel { VStack(alignment:.leading,spacing:14) {
                    if !room["code"].string.isEmpty { HStack { Text(room["code"].string).font(.system(.title3,design:.monospaced)).textSelection(.enabled); Spacer(); ShareLink(item:"Join my AccessHub Snake room: \(room["code"].string)") { Image(systemName:"square.and.arrow.up") } }; Text("Share this private code with the person you want to join.").font(.caption).foregroundStyle(AH.muted) }
                    Text(room["stakeUnits"].double == 0 ? "Friendly match · no stake" : "Each player commits \(Credits.format(room["stakeUnits"].double)) Access Hub Credits").font(.headline)
                    Text("24 × 24 · 10 moves/second · 2-minute limit. Both players see and accept these exact terms.").font(.caption).foregroundStyle(AH.muted)
                    if room["yourRole"].string == "player" { Button("Accept terms & ready") { live.send("ready",fields:["termsHash":room["termsHash"],"acceptedStakeUnits":room["stakeUnits"],"ready":.bool(true)]) }.buttonStyle(PrimaryButton()).disabled(!live.connected || !live.pending.isEmpty || room["players"].array.first(where:{ $0.id == hub.ownerID })?["ready"].bool == true) }
                } }
            }
            if room["phase"].string == "running",room["yourRole"].string == "player" {
                Toggle("Directional pad",isOn:$pad).font(.caption)
                if pad { directionPad }
                Text("Swipe the arena or use the pad. Inputs are accepted by the server; reconnecting restores its actual state.").font(.caption2).foregroundStyle(AH.muted)
            }
            if ["finished","cancelled"].contains(room["phase"].string) {
                Panel { VStack(alignment:.leading,spacing:12) {
                    Text(resultTitle).font(.title2.bold()).foregroundStyle(AH.emerald).accessibilityIdentifier("snakeResult")
                    Text(room["result"]["reason"].string.replacingOccurrences(of:"_",with:" ").capitalized).font(.subheadline).foregroundStyle(AH.muted)
                    Text(room["settlementStatus"].string == "pending" ? "Credit settlement pending · the server is retrying" : room["stakeUnits"].double == 0 ? "Friendly session complete" : room["settlementStatus"].string == "not_required" || room["settlement"]["reason"].string == "no_reservation" ? "No credits were reserved" : "Credit settlement confirmed").font(.caption).foregroundStyle(room["settlementStatus"].string == "pending" ? AH.gold : AH.emerald)
                    if room["settlementStatus"].string == "settled",room["settlement"]["returnedAUnits"].exists,room["yourRole"].string == "player" {
                        let returned = room["settlement"][room["settlement"]["playerA"].string == hub.ownerID ? "returnedAUnits" : "returnedBUnits"].double
                        HStack { Metric(title:"Committed",value:Credits.format(room["stakeUnits"].double)); Metric(title:"Returned",value:Credits.format(returned)); Metric(title:"Net",value:Credits.format(returned-room["stakeUnits"].double)) }
                    }
                    NavigationLink { SnakeLobbyView() } label: { Text("Play again") }.buttonStyle(PrimaryButton())
                } }
            } else if room["yourRole"].string == "player" { Button(room["phase"].string == "running" ? "Leave & forfeit" : "Cancel my participation",role:.destructive) { confirmLeave = true }.font(.caption).disabled(!live.connected || !live.pending.isEmpty) }
        }.padding(20) }.pageBackground().navigationBarTitleDisplayMode(.inline)
        .task { await restore() }.onDisappear { live.disconnect() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await restore() } } else { live.disconnect() } }
        .onChange(of:store.sessionRevision) { _,_ in live.disconnect() }
        .onChange(of:room["settlementStatus"].string) { _,_ in Task { await store.refresh(); await hub.collection("matches") } }
        .confirmationDialog("Leave this match?",isPresented:$confirmLeave,titleVisibility:.visible) { Button(room["phase"].string == "running" ? "Forfeit match" : "Cancel participation",role:.destructive) { live.send("leave") }; Button("Keep playing",role:.cancel) {} } message: { Text("Leaving during play forfeits. Before play starts, the match is cancelled and held stakes return. Backgrounding instead allows a 10-second reconnection window while normal collisions continue.") }
        .sheet(isPresented:$rules) { NavigationStack { SnakeRulesView() } }
    }
    private var directionPad: some View {
        VStack(spacing:8) { directionButton("up"); HStack(spacing:34) { directionButton("left"); directionButton("down"); directionButton("right") } }.frame(maxWidth:.infinity)
    }
    private func directionButton(_ value: String) -> some View { Button { live.direction(value) } label: { Image(systemName:"arrow."+value).font(.title3.bold()).frame(width:58,height:46).background(AH.raised,in:RoundedRectangle(cornerRadius:14)) }.disabled(!live.connected).accessibilityLabel("Move " + value) }
    private var resultTitle: String {
        let outcome = room["result"]["outcome"].string
        if outcome == "cancelled" { return "Match cancelled" }
        if outcome == "draw" { return "A shared finish" }
        if outcome == "solo" { return "Practice complete" }
        let index = outcome == "a" ? 0 : 1
        let winner = room["players"][index]
        return winner.id == hub.ownerID ? "You won" : "\(winner["username"].string) won"
    }
    private func restore() async {
        do { let state = try await hub.fetch("/v2/snake/rooms/" + HubStore.escape(roomID)); live.connect(store:store,path:"/v2/snake/rooms/" + HubStore.escape(roomID)); live.seed(state) }
        catch is CancellationError {} catch { live.error = error.localizedDescription }
    }
}

struct SnakeArena: View {
    let current: JSONValue
    let previous: JSONValue
    let players: JSONValue
    let owner: String
    let skin: JSONValue
    let trail: JSONValue
    let receivedAt: Date
    let reducedMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval:reducedMotion ? 0.1 : 1.0/60.0)) { timeline in
            Canvas { context,size in
                let width = max(1,current["width"].int == 0 ? 24 : current["width"].int)
                let height = max(1,current["height"].int == 0 ? 24 : current["height"].int)
                let cell = min(size.width/CGFloat(width),size.height/CGFloat(height))
                context.fill(Path(roundedRect:CGRect(origin:.zero,size:size),cornerRadius:18),with:.color(AH.panel))
                for x in 1..<width { var path=Path(); path.move(to:CGPoint(x:CGFloat(x)*cell,y:0)); path.addLine(to:CGPoint(x:CGFloat(x)*cell,y:size.height)); context.stroke(path,with:.color(AH.emerald.opacity(0.035)),lineWidth:0.5) }
                for y in 1..<height { var path=Path(); path.move(to:CGPoint(x:0,y:CGFloat(y)*cell)); path.addLine(to:CGPoint(x:size.width,y:CGFloat(y)*cell)); context.stroke(path,with:.color(AH.emerald.opacity(0.035)),lineWidth:0.5) }
                if current["food"].exists {
                    let food = current["food"],x = CGFloat(food["x"].int)*cell,y = CGFloat(food["y"].int)*cell
                    var diamond = Path(); diamond.move(to:CGPoint(x:x+cell/2,y:y+1)); diamond.addLine(to:CGPoint(x:x+cell-1,y:y+cell/2)); diamond.addLine(to:CGPoint(x:x+cell/2,y:y+cell-1)); diamond.addLine(to:CGPoint(x:x+1,y:y+cell/2)); diamond.closeSubpath(); context.fill(diamond,with:.linearGradient(Gradient(colors:[AH.gold,.white,AH.gold]),startPoint:CGPoint(x:x,y:y),endPoint:CGPoint(x:x+cell,y:y+cell)))
                }
                let fraction = reducedMotion || !previous.exists ? 1.0 : min(1,max(0,timeline.date.timeIntervalSince(receivedAt)/0.1))
                for (player,snake) in current["snakes"].array.enumerated() {
                    let old = previous["snakes"].array.first { $0.id == snake.id }
                    let cosmetics = players.array.first(where:{ $0.id == snake.id })?["cosmetics"] ?? .null
                    let selectedSkin = cosmetics["snakeSkin"].exists ? cosmetics["snakeSkin"] : snake.id == owner ? skin : .null
                    let selectedTrail = cosmetics["snakeTrail"].exists ? cosmetics["snakeTrail"] : snake.id == owner ? trail : .null
                    let segments = snake["body"].array
                    for index in segments.indices.reversed() {
                        let next = segments[index],prior = old?["body"][index] ?? next
                        let start = prior.exists ? prior : next
                        let x = CGFloat(start["x"].double+(next["x"].double-start["x"].double)*fraction)*cell
                        let y = CGFloat(start["y"].double+(next["y"].double-start["y"].double)*fraction)*cell
                        let box = CGRect(x:x+0.8,y:y+0.8,width:cell-1.6,height:cell-1.6)
                        let color = selectedSkin.exists ? Color.hubHex(selectedSkin["color"].string) : player == 0 ? AH.emerald : AH.gold
                        context.fill(Path(roundedRect:box,cornerRadius:cell*0.3),with:.color(color.opacity(index == 0 ? 1 : max(0.4,0.9-Double(index)*0.01))))
                        if selectedTrail.exists && !reducedMotion && index % 3 == 0 { context.fill(Path(ellipseIn:box.insetBy(dx:cell*0.33,dy:cell*0.33)),with:.color(Color.hubHex(selectedTrail["color"].string).opacity(0.65))) }
                        if index == 0 { context.fill(Path(ellipseIn:CGRect(x:x+cell*0.6,y:y+cell*0.25,width:cell*0.14,height:cell*0.14)),with:.color(AH.background)) }
                    }
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(AH.emerald.opacity(0.2))).accessibilityLabel("Snake arena, \(current["snakes"].array.map { String($0["score"].int) }.joined(separator:" to ")) food score")
    }
}

struct SnakeRulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            SectionTitle(title:"One arena. Equal rules.")
            rule("The match","24 × 24 cells. Ten server-controlled moves per second, four starting segments, a three-second countdown and a two-minute limit. Food is chosen uniformly from unoccupied cells; each food adds one point and one segment.")
            rule("Collisions","Walls, retained bodies and head-to-head collisions end a snake's run. Moving heads into the same cell or swapping head positions kills both. A tail vacates unless its snake eats that tick. Simultaneous deaths draw. At time limit, higher food score wins; equal scores draw.")
            rule("Your controls","Swipe or use the pad. Two turns can queue, one per tick. Reversing into your current direction is invalid. The server accepts direction requests and determines every position, collision and result.")
            rule("Reconnection","A disconnected snake continues its last direction for up to ten seconds. Collisions still count. Explicit leave during play forfeits; leaving before play cancels. A substantial server interruption cancels and refunds held stakes.")
            rule("Friendly by default","Solo and ordinary matches cost zero. Optional Access Hub Credit challenges require both players to accept the exact same amount. The winner receives both stakes; a draw or cancellation returns each stake. Settlement can remain pending while the server retries.")
            rule("Cosmetics stay cosmetic","Skins and trails never change movement or collisions. Snake grants no casino rakeback, Hub Points, voucher advantages or giveaway eligibility.")
            HubLearningButton(milestone:"snake-rules",title:"Complete Snake rules introduction")
        }.padding(22) }.pageBackground().navigationTitle("Snake rules").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
    }
    private func rule(_ title: String,_ body: String) -> some View { VStack(alignment:.leading,spacing:9) { Text(title).font(.headline); Text(body).font(.subheadline).foregroundStyle(AH.muted) } }
}
