import SwiftUI
import Combine

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
        HubPage(title:"Find your rhythm.",subtitle:"Glide, grow and boost. Practise against bots or challenge a friend live.",refreshKey:"matches") {
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
            else { body = ["rulesVersion":.number(2),"id":.string(UUID().uuidString),"mode":.string(mode),"privacy":.string(privacy),"stakeCredits":.number(mode == "solo" ? 0 : Double(Int(stake) ?? 0)),"allowSpectators":.bool(spectators)]; if let inviteeID { body["inviteeId"] = .string(inviteeID) }; UserDefaults.standard.set(try JSONEncoder().encode(JSONValue.object(body)),forKey:createKey) }
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
    @State private var steering = 0.0
    @State private var boosting = false
    private let controlTick = Timer.publish(every:0.1,on:.main,in:.common).autoconnect()
    private var arenaStyle: Bool { room["rules"]["version"].int == 2 }
    private var room: JSONValue { live.room }
    var body: some View {
        GeometryReader { viewport in
        ScrollView { VStack(alignment:.leading,spacing:12) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(room["mode"].string == "solo" ? "Solo practice" : "Live Snake").font(.title2.bold()); Text(live.status).font(.caption).foregroundStyle(live.connected ? AH.emerald : AH.gold) }; Spacer(); Button { rules = true } label: { Image(systemName:"info.circle") }.accessibilityLabel("Snake rules") }
            if let error = live.error { Text(error).font(.caption).foregroundStyle(AH.danger) }
            if !live.connected { Button("Reconnect to room") { Task { await restore() } }.font(.caption.bold()) }
            if room["yourRole"].string == "spectator" { Label("Spectating · \(room["spectatorCount"].int) viewers",systemImage:"eye").font(.caption).foregroundStyle(AH.muted) }
            if !arenaStyle || room["phase"].string == "lobby" {
            HStack(alignment:.top,spacing:12) { ForEach(room["players"].array) { player in VStack(alignment:.leading,spacing:5) { Text(player["username"].string).font(.caption.bold()).lineLimit(1); Text(player["ready"].bool ? "Ready" : "Not ready").font(.caption2).foregroundStyle(player["ready"].bool ? AH.emerald : AH.muted); if let snake = room["game"]["snakes"].array.first(where:{ $0.id == player.id }) { Text("\(snake["score"].int) food").font(.headline) }; if !player["connected"].bool { Text("Reconnecting").font(.caption2).foregroundStyle(AH.gold) } }.frame(maxWidth:.infinity,alignment:.leading) } }
            }
            ZStack {
                if arenaStyle {
                    SnakeFlowArena(current:room["game"],previous:live.previous["room"]["game"],players:room["players"],owner:hub.ownerID,skin:hub.equipped("snakeSkin"),trail:hub.equipped("snakeTrail"),receivedAt:live.receivedAt,reducedMotion:store.reducedMotion,steering:$steering).frame(height:min(460,max(220,viewport.size.height-320)))
                } else {
                SnakeArena(current:room["game"],previous:live.previous["room"]["game"],players:room["players"],owner:hub.ownerID,skin:hub.equipped("snakeSkin"),trail:hub.equipped("snakeTrail"),receivedAt:live.receivedAt,reducedMotion:store.reducedMotion).aspectRatio(1,contentMode:.fit)
                }
                if room["phase"].string == "countdown" {
                    TimelineView(.periodic(from:.now,by:0.1)) { _ in Text("\(max(1,Int(ceil((room["startAt"].double-live.now)/1000))))").font(.system(size:74,weight:.bold,design:.rounded)).foregroundStyle(AH.text).shadow(color:AH.emerald.opacity(0.5),radius:20) }
                } else if !room["game"].exists { VStack(spacing:10) { Image(systemName:"gamecontroller").font(.largeTitle); Text(room["phase"].string == "reserving" ? "Reserving agreed stakes…" : "Waiting for ready players").font(.headline) }.foregroundStyle(AH.muted).padding(20) }
            }.gesture(DragGesture(minimumDistance:14).onEnded { value in let x = value.translation.width,y = value.translation.height; if !arenaStyle { live.direction(abs(x)>abs(y) ? (x>0 ? "right" : "left") : (y>0 ? "down" : "up")) } })
            if room["phase"].string == "lobby" {
                Panel { VStack(alignment:.leading,spacing:14) {
                    if !room["code"].string.isEmpty { HStack { Text(room["code"].string).font(.system(.title3,design:.monospaced)).textSelection(.enabled); Spacer(); ShareLink(item:"Join my AccessHub Snake room: \(room["code"].string)") { Image(systemName:"square.and.arrow.up") } }; Text("Share this private code with the person you want to join.").font(.caption).foregroundStyle(AH.muted) }
                    Text(room["stakeUnits"].double == 0 ? "Friendly match · no stake" : "Each player commits \(Credits.format(room["stakeUnits"].double)) Access Hub Credits").font(.headline)
                    Text(arenaStyle ? "Free steering · hold to boost · 2-minute round. Solo has 5 computer opponents. Live challenges have 2 human players." : "24 × 24 · 10 moves/second · 2-minute limit. Both players see and accept these exact terms.").font(.caption).foregroundStyle(AH.muted)
                    if room["yourRole"].string == "player" { Button("Accept terms & ready") { live.send("ready",fields:["rulesVersion":room["rules"]["version"],"termsHash":room["termsHash"],"acceptedStakeUnits":room["stakeUnits"],"ready":.bool(true)]) }.buttonStyle(PrimaryButton()).disabled(!live.connected || !live.pending.isEmpty || room["players"].array.first(where:{ $0.id == hub.ownerID })?["ready"].bool == true) }
                } }
            }
            if room["phase"].string == "running",room["yourRole"].string == "player" {
                if arenaStyle {
                    SnakeFlowControls(angle:$steering,boosting:$boosting,canBoost:(room["game"]["snakes"].array.first(where:{ $0.id == hub.ownerID })?["mass"].double ?? 0) >= 25,connected:live.connected)
                    Text("Drag to steer · hold boost to trade length for speed. Avoid walls and other snakes. You can cross your own tail.").font(.caption2).foregroundStyle(AH.muted)
                } else {
                    Toggle("Directional pad",isOn:$pad).font(.caption)
                    if pad { directionPad }
                    Text("Swipe the arena or use the pad.").font(.caption2).foregroundStyle(AH.muted)
                }
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
        .onReceive(controlTick) { _ in if arenaStyle { live.steer(angle:steering,boost:boosting) } }
        .onChange(of:steering) { _,value in live.steer(angle:value,boost:boosting) }
        .onChange(of:boosting) { _,value in live.steer(angle:steering,boost:value) }
        .onChange(of:room["phase"].string) { _,phase in
            if phase == "running",let mine = room["game"]["snakes"].array.first(where:{ $0.id == hub.ownerID }) { steering = mine["angle"].double }
            if phase != "running" { boosting = false }
        }
        .task { await restore() }.onDisappear { boosting = false; live.steer(angle:steering,boost:false); live.disconnect() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await restore() } } else { boosting = false; live.steer(angle:steering,boost:false); live.disconnect() } }
        .onChange(of:store.sessionRevision) { _,_ in live.disconnect() }
        .onChange(of:room["settlementStatus"].string) { _,_ in Task { await store.refresh(); await hub.collection("matches") } }
        .confirmationDialog("Leave this match?",isPresented:$confirmLeave,titleVisibility:.visible) { Button(room["phase"].string == "running" ? "Forfeit match" : "Cancel participation",role:.destructive) { live.send("leave") }; Button("Keep playing",role:.cancel) {} } message: { Text("Leaving during play forfeits. Before play starts, the match is cancelled and held stakes return. Backgrounding instead allows a 10-second reconnection window while normal collisions continue.") }
        .sheet(isPresented:$rules) { NavigationStack { SnakeRulesView(version:arenaStyle ? 2 : 1) } }
        }
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

// A camera-following arena, rendered between authoritative server snapshots.
struct SnakeFlowArena: View {
    let current: JSONValue
    let previous: JSONValue
    let players: JSONValue
    let owner: String
    let skin: JSONValue
    let trail: JSONValue
    let receivedAt: Date
    let reducedMotion: Bool
    @Binding var steering: Double
    private let palette: [Color] = [AH.emerald,AH.gold,Color.cyan,Color.pink,Color.purple,Color.orange]
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval:reducedMotion ? 0.1 : 1.0/60.0)) { timeline in
                Canvas { context,size in render(context:&context,size:size,date:timeline.date) }
            }
            .overlay(alignment:.topLeading) {
                VStack(alignment:.leading,spacing:4) {
                    Text(current["snakes"].array.contains(where:{ $0["bot"].bool }) ? "PRACTICE · COMPUTER OPPONENTS" : "LIVE ARENA").font(.system(size:9,weight:.heavy,design:.rounded)).tracking(1)
                    if let mine = current["snakes"].array.first(where:{ $0.id == owner }) {
                        Text("\(mine["score"].int)  •  FOOD").font(.system(.title3,design:.rounded).bold()).monospacedDigit()
                    }
                }.foregroundStyle(.white).padding(12).allowsHitTesting(false)
            }
            .overlay(alignment:.topTrailing) {
                VStack(alignment:.trailing,spacing:3) {
                    ForEach(Array(current["snakes"].array.filter { $0["alive"].bool }.sorted { $0["score"].int > $1["score"].int }.prefix(3))) { snake in
                        let name = snake["bot"].bool ? snake["name"].string+" CPU" : snake.id == owner ? "YOU" : players.array.first(where:{ $0.id == snake.id })?["username"].string ?? "Player"
                        Text("\(name)  \(snake["score"].int)").font(.system(size:9,weight:.bold,design:.rounded)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }.frame(maxWidth:100,alignment:.trailing).padding(.top,50).padding(.trailing,12).allowsHitTesting(false)
            }
            .overlay(alignment:.bottomTrailing) { minimap.padding(12).allowsHitTesting(false) }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance:0).onChanged { value in
                let x = value.location.x-geometry.size.width/2,y = value.location.y-geometry.size.height/2
                if hypot(x,y)>12 { steering = atan2(Double(y),Double(x)) }
            })
        }
        .clipShape(RoundedRectangle(cornerRadius:24))
        .overlay(RoundedRectangle(cornerRadius:24).strokeBorder(AH.emerald.opacity(0.25)))
        .accessibilityLabel("Open Snake arena. Use the steering pad below to turn.")
    }
    private var minimap: some View {
        Canvas { context,size in
            for snake in current["snakes"].array where snake["alive"].bool {
                let head = snake["body"][0]
                let point = CGPoint(x:head["x"].double/1800*size.width,y:head["y"].double/1800*size.height)
                let r: CGFloat = snake.id == owner ? 3 : 2
                context.fill(Path(ellipseIn:CGRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2)),with:.color(snake.id == owner ? .white : AH.emerald))
            }
        }.frame(width:66,height:66).padding(5).background(.black.opacity(0.5),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.18)))
    }
    private func render(context: inout GraphicsContext,size: CGSize,date: Date) {
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(red:0.025,green:0.055,blue:0.09)))
        let snakes = current["snakes"].array
        let fraction = reducedMotion || !previous.exists ? 1.0 : min(1,max(0,date.timeIntervalSince(receivedAt)/0.1))
        let focus = snakes.first(where:{ $0.id == owner }) ?? snakes.first ?? .null
        let oldFocus = previous["snakes"].array.first(where:{ $0.id == focus.id }) ?? focus
        func blend(_ a: JSONValue,_ b: JSONValue) -> CGPoint {
            let start = a.exists ? a : b
            // Respawning bots jump directly, without a trail across the map.
            let f = hypot(start["x"].double-b["x"].double,start["y"].double-b["y"].double)>80 ? 1 : fraction
            return CGPoint(x:start["x"].double+(b["x"].double-start["x"].double)*f,y:start["y"].double+(b["y"].double-start["y"].double)*f)
        }
        let center = focus.exists ? blend(oldFocus["body"][0],focus["body"][0]) : CGPoint(x:900,y:900)
        let zoom = size.width/CGFloat(560+min(180,max(0,focus["mass"].double-24)*1.1))
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x:(p.x-center.x)*zoom+size.width/2,y:(p.y-center.y)*zoom+size.height/2) }
        // Subtle world grid gives movement a sense of scale without square cells.
        for i in 0...36 {
            let offset = CGFloat(i)*50
            var line = Path();line.move(to:screen(CGPoint(x:offset,y:0)));line.addLine(to:screen(CGPoint(x:offset,y:1800)))
            line.move(to:screen(CGPoint(x:0,y:offset)));line.addLine(to:screen(CGPoint(x:1800,y:offset)))
            context.stroke(line,with:.color(.white.opacity(0.045)),lineWidth:0.7)
        }
        let corner = screen(.zero),edge = CGRect(x:corner.x,y:corner.y,width:1800*zoom,height:1800*zoom)
        context.stroke(Path(edge),with:.color(Color.pink.opacity(0.8)),lineWidth:4)
        for pellet in current["food"].array {
            let point = screen(CGPoint(x:pellet["x"].double,y:pellet["y"].double))
            guard point.x > -12,point.y > -12,point.x < size.width+12,point.y < size.height+12 else { continue }
            let color = palette[abs(pellet["color"].int)%palette.count],r = CGFloat(pellet["value"].int > 1 ? 5.0 : 3.5)*zoom
            context.fill(Path(ellipseIn:CGRect(x:point.x-r*2,y:point.y-r*2,width:r*4,height:r*4)),with:.color(color.opacity(0.14)))
            context.fill(Path(ellipseIn:CGRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2)),with:.color(color))
            context.fill(Path(ellipseIn:CGRect(x:point.x-r*0.3,y:point.y-r*0.6,width:r*0.6,height:r*0.6)),with:.color(.white.opacity(0.8)))
        }
        for (index,snake) in snakes.enumerated() where snake["alive"].bool {
            let old = previous["snakes"].array.first(where:{ $0.id == snake.id }) ?? snake
            let cosmetics = players.array.first(where:{ $0.id == snake.id })?["cosmetics"] ?? .null
            let selectedSkin = cosmetics["snakeSkin"].exists ? cosmetics["snakeSkin"] : snake.id == owner ? skin : .null
            let selectedTrail = cosmetics["snakeTrail"].exists ? cosmetics["snakeTrail"] : snake.id == owner ? trail : .null
            let color = selectedSkin.exists ? Color.hubHex(selectedSkin["color"].string) : palette[index%palette.count]
            let points = snake["body"].array.enumerated().map { i,p in screen(blend(old["body"][i],p)) }
            guard let head = points.first else { continue }
            let radius = 9*zoom
            var path = Path();path.move(to:head);for p in points.dropFirst() { path.addLine(to:p) }
            if snake["boosting"].bool && !reducedMotion { context.stroke(path,with:.color(color.opacity(0.18)),style:StrokeStyle(lineWidth:radius*3.5,lineCap:.round,lineJoin:.round)) }
            context.stroke(path,with:.color(.black.opacity(0.45)),style:StrokeStyle(lineWidth:radius*2+3,lineCap:.round,lineJoin:.round))
            context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:radius*2,lineCap:.round,lineJoin:.round))
            context.stroke(path,with:.color(.white.opacity(0.13)),style:StrokeStyle(lineWidth:radius*0.6,lineCap:.round,lineJoin:.round))
            for i in stride(from:4,to:points.count,by:5) {
                let p = points[i],dotColor = selectedTrail.exists ? Color.hubHex(selectedTrail["color"].string) : .white
                context.fill(Path(ellipseIn:CGRect(x:p.x-radius*0.3,y:p.y-radius*0.3,width:radius*0.6,height:radius*0.6)),with:.color(dotColor.opacity(0.3)))
            }
            context.fill(Path(ellipseIn:CGRect(x:head.x-radius,y:head.y-radius,width:radius*2,height:radius*2)),with:.color(color))
            let angle = snake["angle"].double
            for side in [-1.0,1.0] {
                let eye = CGPoint(x:head.x+CGFloat(cos(angle)*3-sin(angle)*side*4)*zoom,y:head.y+CGFloat(sin(angle)*3+cos(angle)*side*4)*zoom)
                let r = radius*0.38
                context.fill(Path(ellipseIn:CGRect(x:eye.x-r,y:eye.y-r,width:r*2,height:r*2)),with:.color(.white))
                context.fill(Path(ellipseIn:CGRect(x:eye.x+CGFloat(cos(angle))*r*0.4-r*0.5,y:eye.y+CGFloat(sin(angle))*r*0.4-r*0.5,width:r,height:r)),with:.color(.black))
            }
            let name = snake["bot"].bool ? snake["name"].string+" · CPU" : snake.id == owner ? "YOU" : players.array.first(where:{ $0.id == snake.id })?["username"].string ?? "Player"
            context.draw(Text(name).font(.system(size:9,weight:.bold,design:.rounded)).foregroundColor(.white.opacity(0.85)),at:CGPoint(x:head.x,y:head.y-radius-13))
        }
    }
}

struct SnakeFlowControls: View {
    @Binding var angle: Double
    @Binding var boosting: Bool
    let canBoost: Bool
    let connected: Bool
    @State private var offset = CGSize.zero
    var body: some View {
        HStack(spacing:20) {
            ZStack {
                Circle().fill(AH.raised).overlay(Circle().strokeBorder(AH.emerald.opacity(0.25),lineWidth:1))
                Image(systemName:"plus").font(.system(size:40,weight:.ultraLight)).foregroundStyle(.white.opacity(0.12))
                Circle().fill(AH.emerald.gradient).frame(width:44,height:44).shadow(color:AH.emerald.opacity(0.3),radius:10).offset(offset)
            }.frame(width:112,height:112).contentShape(Circle())
            .highPriorityGesture(DragGesture(minimumDistance:0).onChanged { value in
                guard connected else { return }
                let x = value.location.x-56,y = value.location.y-56,length = hypot(x,y)
                guard length>4 else { return }
                angle = atan2(Double(y),Double(x));let scale = min(34,length)/length;offset = CGSize(width:x*scale,height:y*scale)
            }.onEnded { _ in offset = .zero })
            .accessibilityElement().accessibilityLabel("Steering").accessibilityValue("Turn direction")
            .accessibilityAdjustableAction { direction in angle += direction == .increment ? 0.25 : -0.25 }
            Spacer(minLength:0)
            VStack(spacing:8) {
                ZStack {
                    Circle().fill((boosting && canBoost ? AH.gold : AH.raised).gradient)
                    Circle().strokeBorder(canBoost ? AH.gold.opacity(0.65) : .white.opacity(0.12),lineWidth:2)
                    VStack(spacing:4) { Image(systemName:"bolt.fill").font(.title2);Text("BOOST").font(.system(size:10,weight:.heavy,design:.rounded)).tracking(1) }.foregroundStyle(boosting && canBoost ? Color.black : AH.gold)
                }.frame(width:90,height:90).contentShape(Circle())
                .highPriorityGesture(DragGesture(minimumDistance:0).onChanged { _ in boosting = connected && canBoost }.onEnded { _ in boosting = false })
                .accessibilityElement().accessibilityLabel("Boost").accessibilityHint("Consumes length. Hold to move faster.")
                .accessibilityAction { boosting.toggle() }
                Text(canBoost ? "HOLD TO SPEED UP" : "EAT TO UNLOCK").font(.system(size:8,weight:.bold)).foregroundStyle(AH.muted)
            }
        }.padding(.horizontal,20).opacity(connected ? 1 : 0.45)
        .onChange(of:canBoost) { _,value in if !value { boosting = false } }
        .onChange(of:connected) { _,value in if !value { boosting = false } }
    }
}

struct SnakeRulesView: View {
    var version = 2
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            SectionTitle(title:"One arena. Equal rules.")
            if version == 2 {
                rule("The arena","A large open arena with free-angle steering, a three-second countdown and a two-minute round. Collect colourful pellets to grow. Solo practice includes five clearly labelled computer opponents; live friend matches contain two human players and no bots.")
                rule("Glide and boost","Drag the arena or the circular steering pad. Hold BOOST for extra speed; it consumes four length units per second. Collect food first: boost stops at your starting length. Letting go returns to normal speed.")
                rule("Stay alive","Your head must avoid the boundary and other snakes’ bodies. You may cross your own body. Head-to-head contact eliminates both snakes. Eliminated practice bots drop food and respawn. In a live challenge the survivor wins; simultaneous deaths draw. At two minutes, the higher collected-food score wins, with equal scores drawing.")
                rule("Server checked","The server controls movement, food, boost cost and collisions. Steering never lets a client submit positions or scores. Cosmetic skins have no speed or size advantage.")
            } else {
            rule("The match","24 × 24 cells. Ten server-controlled moves per second, four starting segments, a three-second countdown and a two-minute limit. Food is chosen uniformly from unoccupied cells; each food adds one point and one segment.")
            rule("Collisions","Walls, retained bodies and head-to-head collisions end a snake's run. Moving heads into the same cell or swapping head positions kills both. A tail vacates unless its snake eats that tick. Simultaneous deaths draw. At time limit, higher food score wins; equal scores draw.")
            rule("Your controls","Swipe or use the pad. Two turns can queue, one per tick. Reversing into your current direction is invalid. The server accepts direction requests and determines every position, collision and result.")
            }
            rule("Reconnection","A disconnected snake continues its last direction for up to ten seconds. Collisions still count. Explicit leave during play forfeits; leaving before play cancels. A substantial server interruption cancels and refunds held stakes.")
            rule("Friendly by default","Solo and ordinary matches cost zero. Optional Access Hub Credit challenges require both players to accept the exact same amount. The winner receives both stakes; a draw or cancellation returns each stake. Settlement can remain pending while the server retries.")
            rule("Cosmetics stay cosmetic","Skins and trails never change movement or collisions. Snake grants no casino rakeback, Hub Points, voucher advantages or giveaway eligibility.")
            HubLearningButton(milestone:"snake-rules",title:"Complete Snake rules introduction")
        }.padding(22) }.pageBackground().navigationTitle("Snake rules").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
    }
    private func rule(_ title: String,_ body: String) -> some View { VStack(alignment:.leading,spacing:9) { Text(title).font(.headline); Text(body).font(.subheadline).foregroundStyle(AH.muted) } }
}
