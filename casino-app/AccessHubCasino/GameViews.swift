import SwiftUI
import UIKit

struct GameScreen: View {
    let game: CasinoGame
    @EnvironmentObject var store: CasinoStore
    @State private var showRules = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { CreditBalance(units:store.balance); Spacer(); HStack(spacing:5) { Circle().fill(store.online ? AH.emerald : AH.gold).frame(width:5,height:5); Text(store.online ? "CONNECTED" : "RECONNECTING").font(.system(size:9,weight:.semibold)).tracking(1) }.foregroundStyle(AH.muted) }
                switch game {
                case .crash: CrashView()
                case .blackjack: BlackjackView()
                case .mines: MinesView()
                case .slots: SlotsView()
                }
                NavigationLink { RulesView(game:game) } label: { HStack { Image(systemName:"book.closed"); Text("Rules, payouts & return"); Spacer(); Image(systemName:"chevron.right").font(.caption) }.font(.subheadline).padding(18).background(AH.panel,in:RoundedRectangle(cornerRadius:16)) }
                Text("Access Hub Credits\nNon-transferable and never redeemable.").font(.caption2).foregroundStyle(AH.muted).multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(.top,4)
            }.padding(18)
        }.scrollDismissesKeyboard(.interactively).pageBackground().navigationTitle(game.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button { showRules = true } label: { Image(systemName:"info.circle") }.accessibilityLabel("Game rules") }
                ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) } }
            }
            .sheet(isPresented:$showRules) { NavigationStack { RulesView(game:game).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { showRules = false } } } } }
    }
}

struct StakeControl: View {
    @Binding var value: String
    var disabled = false
    @EnvironmentObject var store: CasinoStore
    private var valid: Bool { let amount = Double(value) ?? 0; return amount >= 1 && amount <= 10_000 && amount.rounded() == amount && amount * Credits.scale <= store.balance }
    private var boundedStake: Int { let amount = Double(value) ?? 100; return amount.isFinite ? Int(min(10_000,max(1,amount))) : 100 }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("STAKE").font(.system(size:10,weight:.bold)).tracking(1.5).foregroundStyle(AH.muted)
                Spacer(); Text("Access Hub Credits").font(.caption2).foregroundStyle(AH.muted)
            }
            HStack(spacing:10) {
                TextField("100",text:$value).keyboardType(.numberPad).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit().fieldStyle().accessibilityIdentifier("stakeInput")
                Button("½") { value = String(max(1,boundedStake/2)) }.frame(width:42,height:52).background(AH.raised,in:RoundedRectangle(cornerRadius:12))
                Button("2×") { value = String(min(10_000,boundedStake*2)) }.frame(width:42,height:52).background(AH.raised,in:RoundedRectangle(cornerRadius:12))
            }.disabled(disabled)
            HStack(spacing:8) {
                ForEach([25,100,500,1000],id:\.self) { stake in Button(String(stake)) { value = String(stake) }.font(.caption.weight(.semibold)).frame(maxWidth:.infinity).padding(.vertical,9).background(value == String(stake) ? AH.emerald.opacity(0.15) : AH.raised,in:Capsule()).foregroundStyle(value == String(stake) ? AH.emerald : AH.muted) }
            }.disabled(disabled)
            if !valid && !disabled { Text("Choose a whole-credit stake from 1 to 10,000 within your balance.").font(.caption2).foregroundStyle(AH.gold) }
        }
    }
}

func validStake(_ value: String, balance: Double) -> Bool {
    guard let credits = Double(value), credits.isFinite else { return false }
    return credits >= 1 && credits <= 10_000 && floor(credits) == credits && credits * Credits.scale <= balance
}

struct ResultSummary: View {
    let roundID: String
    let title: String
    let committed: Double
    let returned: Double
    @EnvironmentObject var store: CasinoStore
    @State private var glow = false
    @State private var particlesVisible = false
    @State private var particleTravel = false
    private var particles: Int { ResultPresentation.particleCount(committed:committed,returned:returned,reducedMotion:store.reducedMotion) }
    var body: some View {
        Panel {
            VStack(alignment:.leading,spacing:16) {
                HStack { Circle().fill(returned > committed ? AH.emerald : AH.muted).frame(width:7,height:7); Text(title).font(.headline).fixedSize(horizontal:false,vertical:true) }
                HStack(alignment:.top) {
                    Metric(title:"Committed",value:Credits.format(committed,precision:6))
                    Metric(title:"Returned",value:Credits.format(returned,precision:6))
                    Metric(title:"Net change",value:(returned > committed ? "+" : "") + Credits.format(returned-committed,precision:6),color:returned > committed ? AH.emerald : AH.text)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(AH.emerald.opacity(glow ? 0.45 : 0),lineWidth:1).shadow(color:AH.emerald.opacity(glow ? 0.16 : 0),radius:12))
        .overlay {
            if particlesVisible && !store.reducedMotion {
                GeometryReader { geometry in
                    ForEach(0..<particles,id:\.self) { index in
                        let spread = (Double(index)/Double(max(1,particles-1))-0.5)*0.75
                        let rise = 30.0 + Double((index*17)%37)
                        Circle().fill(index.isMultiple(of:3) ? AH.gold : AH.emerald)
                            .frame(width:index.isMultiple(of:2) ? 3 : 4,height:index.isMultiple(of:2) ? 3 : 4)
                            .position(x:geometry.size.width*(0.5+(particleTravel ? spread : 0)),y:geometry.size.height*0.45-(particleTravel ? rise : 0))
                            .opacity(particleTravel ? 0 : 0.9)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children:.combine)
        .task(id:roundID) {
            glow = false; particlesVisible = false; particleTravel = false
            // A Slots result can enter the view tree briefly while its reel
            // animation starts. Cancellation keeps its sound after reel stopping.
            do { try await Task.sleep(for:.milliseconds(80)) } catch { return }
            guard !Task.isCancelled, store.presentResult(roundID:roundID,committed:committed,returned:returned),returned > committed else { return }
            withAnimation(.easeOut(duration:0.2)) { glow = true }
            guard particles > 0 else { return }
            particlesVisible = true
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration:1.15)) { particleTravel = true }
            do { try await Task.sleep(for:.seconds(1.25)) } catch { return }
            withAnimation(.easeOut(duration:0.35)) { glow = false; particlesVisible = false }
        }
    }
}

struct CrashView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var stake = "100"
    @State private var auto = true
    @State private var threshold = "2.00"
    private var round: JSONValue { store.state["crash"] }
    private var position: JSONValue { round["position"].exists ? round["position"] : round["previousPosition"] }
    private var activeEntry: Bool { ["pending","running"].contains(position["status"].string) }
    private var canEnter: Bool { store.canAct && round["phase"].string == "waiting" && !round["position"].exists && validStake(stake,balance:store.balance) && (!auto || ((Double(threshold) ?? 0) >= 1.01 && (Double(threshold) ?? 0) <= 100)) }
    var body: some View {
        VStack(spacing:18) {
            TimelineView(.animation(minimumInterval:store.reducedMotion ? 0.5 : 1/60,paused:!store.online)) { timeline in
                let now = store.serverNow
                let elapsed = max(0,(now-round["startAt"].double)/1000)
                let phase = round["phase"].string
                let snapshotElapsed = max(0,(round["serverTime"].double-round["startAt"].double)/1000)
                let animatedElapsed = store.online ? min(elapsed,snapshotElapsed+1.5) : snapshotElapsed
                let multiplier = phase == "running" ? min(100,exp(0.11*animatedElapsed)) : (phase == "finished" ? round["crashPoint"].double : 1)
                ZStack(alignment:.topLeading) {
                    RoundedRectangle(cornerRadius:24).fill(LinearGradient(colors:[AH.panel,Color(red:0.02,green:0.12,blue:0.12)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    CrashGraph(multiplier:multiplier,finished:phase == "finished",reducedMotion:store.reducedMotion).padding(.top,85).padding(22)
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(phase == "waiting" ? "NEXT FLIGHT" : phase == "finished" ? "ROUND FINISHED" : "IN FLIGHT").font(.system(size:10,weight:.bold)).tracking(1.7); Spacer(); Text("\(round["onlinePlayers"].int) connected").font(.caption2) }.foregroundStyle(AH.muted)
                        Text(phase == "waiting" ? String(format:"%.1fs",max(0,(round["startAt"].double-now)/1000)) : String(format:"%.2f×",multiplier)).font(.system(size:52,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(phase == "finished" ? AH.danger : AH.text).contentTransition(.numericText())
                        if let amount = CrashPotentialReturn.units(round:round,displayMultiplier:multiplier,online:store.online) {
                            VStack(alignment:.leading,spacing:3) {
                                Text(store.online ? "LIVE RETURN" : "LAST CONFIRMED RETURN").font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(AH.muted)
                                Text(Credits.format(amount) + " credits").font(.system(size:22,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(AH.emerald).accessibilityIdentifier("crashPotentialReturn")
                                Text("Estimate; the server confirms collection.").font(.caption2).foregroundStyle(AH.muted)
                            }.padding(.top,4)
                        }
                        if phase == "waiting" { Text("Enter before the countdown ends.").font(.caption).foregroundStyle(AH.muted) }
                        if phase == "finished" { Text("The next shared round starts shortly.").font(.caption).foregroundStyle(AH.muted) }
                    }.padding(22)
                }.frame(height:290)
                .accessibilityElement(children:.combine)
            }
            ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:8) { ForEach(Array(round["history"].array.prefix(15).enumerated()),id:\.offset) { _, item in Text(String(format:"%.2f×",item["crashPoint"].double)).font(.caption.weight(.semibold)).monospacedDigit().padding(.horizontal,11).padding(.vertical,8).background(AH.panel,in:Capsule()).foregroundStyle(item["crashPoint"].double >= 2 ? AH.emerald : AH.muted) } } }.accessibilityLabel("Previous shared round results")
            if position.exists {
                Panel {
                    VStack(alignment:.leading,spacing:12) {
                        Text(position["status"].string == "pending" ? "Entry accepted · waiting for launch" : position["status"].string.capitalized).font(.headline).foregroundStyle(AH.emerald)
                        HStack { Metric(title:"Committed",value:Credits.format(position["stakeUnits"].double)); Metric(title:"Auto collect",value:position["autoCollect"].exists ? String(format:"%.2f×",position["autoCollect"].double) : "Off") }
                        if position["status"].string == "running" {
                            Button { Task { await store.action("crash.collect",["roundId":.string(round["id"].string)]) } } label: { Text(store.busy ? "Confirming collection…" : "Collect now") }.buttonStyle(PrimaryButton()).disabled(!store.canAct || round["phase"].string != "running").accessibilityIdentifier("crashCollect")
                            Text("Collection is confirmed by the server. A request received at or after the crash is rejected.").font(.caption2).foregroundStyle(AH.muted)
                        }
                    }
                }
                if ["collected","lost"].contains(position["status"].string) { ResultSummary(roundID:position["roundId"].string,title:position["result"].string.isEmpty ? position["status"].string.capitalized : position["result"].string,committed:position["stakeUnits"].double,returned:position["returnedUnits"].double).accessibilityIdentifier("crashResult:"+position["roundId"].string) }
            }
            Panel {
                VStack(spacing:18) {
                    StakeControl(value:$stake,disabled:activeEntry || !store.canAct)
                    Toggle("Automatic collection",isOn:$auto).font(.subheadline).disabled(activeEntry)
                    if auto { HStack { Text("Collect at").font(.caption).foregroundStyle(AH.muted); TextField("2.00",text:$threshold).keyboardType(.decimalPad).multilineTextAlignment(.trailing).fieldStyle().frame(width:110).accessibilityIdentifier("crashAutoThreshold"); Text("×") }.disabled(activeEntry) }
                    Button { Task { await store.action("crash.enter",["roundId":.string(round["id"].string),"stakeUnits":.number(Credits.units(stake)),"autoCollect":auto ? .number(Double(threshold) ?? 2) : .null]) } } label: { Text(activeEntry ? "Entry accepted" : round["phase"].string == "waiting" ? "Enter next flight" : "Waiting for next round") }.buttonStyle(PrimaryButton()).disabled(!canEnter).accessibilityIdentifier("crashEnter")
                }
            }
            NavigationLink("Your Crash history") { FilteredHistory(game:"crash") }.font(.caption)
        }
    }
}

struct CrashGraph: View {
    let multiplier: Double
    let finished: Bool
    let reducedMotion: Bool
    var body: some View {
        Canvas { context, size in
            for n in 0...4 {
                let y = size.height*CGFloat(n)/4
                var line = Path(); line.move(to:CGPoint(x:0,y:y)); line.addLine(to:CGPoint(x:size.width,y:y))
                context.stroke(line,with:.color(.white.opacity(0.05)),lineWidth:1)
            }
            let progress = min(1,max(0.02,log(max(1,multiplier))/log(100)))
            var curve = Path(); curve.move(to:CGPoint(x:0,y:size.height))
            for i in 1...80 {
                let t = Double(i)/80
                let x = size.width*CGFloat(t*min(0.92,0.12+progress))
                let y = size.height*(1-CGFloat(pow(t,1.8)*min(0.95,0.08+progress)))
                curve.addLine(to:CGPoint(x:x,y:y))
            }
            let color = finished ? AH.danger : AH.emerald
            context.stroke(curve,with:.color(color),style:StrokeStyle(lineWidth:3,lineCap:.round))
            if let end = curve.currentPoint { context.fill(Path(ellipseIn:CGRect(x:end.x-5,y:end.y-5,width:10,height:10)),with:.color(color)) }
        }.accessibilityHidden(true)
    }
}

struct BlackjackView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var stake = "100"
    private var round: JSONValue { store.state["games"]["blackjack"] }
    private var active: Bool { round["status"].string == "active" }
    private var back: String { store.state["settings"]["cardBack"].string }
    var body: some View {
        VStack(spacing:18) {
            VStack(spacing:22) {
                HStack { Text("ACCESSHUB PRIVATE TABLE").font(.system(size:9,weight:.semibold)).tracking(2); Spacer(); Text("3 : 2").font(.caption.weight(.semibold)) }.foregroundStyle(AH.gold.opacity(0.8))
                VStack(spacing:10) {
                    HStack { Text("DEALER").font(.system(size:10,weight:.bold)).tracking(1.5); if round.exists { Text("\(round["dealerTotal"].int)" + (round["dealerSoft"].bool ? " · soft" : "")).font(.caption).padding(.horizontal,9).padding(.vertical,4).background(.white.opacity(0.08),in:Capsule()) } }
                    if round.exists { CardHand(cards:round["dealer"].array,back:back,seed:round["id"].string) }
                    else { HStack(spacing:8) { PlayingCard(card:.null,back:back); PlayingCard(card:.null,back:back) }.frame(height:100) }
                    Text("Dealer stands on all 17s").font(.caption2).foregroundStyle(AH.muted)
                }
                Rectangle().fill(AH.gold.opacity(0.14)).frame(height:1)
                if round.exists {
                    ForEach(Array(round["hands"].array.enumerated()),id:\.offset) { index, hand in
                        VStack(spacing:10) {
                            HStack { Text(round["hands"].array.count > 1 ? "HAND \(index+1)" : "YOUR HAND").font(.system(size:10,weight:.bold)).tracking(1.5); Spacer(); Text("\(hand["total"].int)" + (hand["soft"].bool ? " · soft" : "")).font(.subheadline.weight(.semibold)); if active && index == round["activeHand"].int { Circle().fill(AH.emerald).frame(width:6,height:6) } }
                            CardHand(cards:hand["cards"].array,back:back,seed:round["id"].string+"\(index)")
                            HStack { Text("Stake " + Credits.format(hand["stakeUnits"].double)).font(.caption2).foregroundStyle(AH.muted); Spacer(); if hand["result"].exists { Text(hand["result"].string).font(.caption.weight(.semibold)).foregroundStyle(hand["returnedUnits"].double > 0 ? AH.emerald : AH.muted) } }
                        }.padding(13).background(active && index == round["activeHand"].int ? AH.emerald.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(active && index == round["activeHand"].int ? AH.emerald.opacity(0.5) : .clear))
                    }
                } else { VStack(spacing:9) { Text("Your seat is ready.").font(.system(size:23,weight:.medium,design:.serif)); Text("Choose your stake to deal.").font(.caption).foregroundStyle(AH.muted) }.padding(.vertical,20) }
            }.padding(20).background {
                ZStack {
                    RoundedRectangle(cornerRadius:26).fill(tableColor)
                    if UIImage(named:"TableTexture") != nil { Image("TableTexture").resizable(resizingMode:.tile).opacity(0.35).clipShape(RoundedRectangle(cornerRadius:26)) }
                }
            }.overlay(RoundedRectangle(cornerRadius:26).strokeBorder(AH.gold.opacity(0.17)))
            if active {
                let actions = round["actions"].array.map(\.string)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(["hit","stand","double","split"],id:\.self) { action in
                        Button(action.capitalized) { Task { await store.action("blackjack."+action,["roundId":.string(round["id"].string)]) } }.buttonStyle(PrimaryButton(secondary:action == "stand" || action == "split")).disabled(!store.canAct || !actions.contains(action) || (["double","split"].contains(action) && store.balance < round["hands"][round["activeHand"].int]["stakeUnits"].double)).accessibilityIdentifier("blackjack"+action.capitalized)
                    }
                }
                Text(store.busy ? "Confirming your move…" : "Highlighted hand is active. Double and split commit an additional stake.").font(.caption).foregroundStyle(AH.muted).frame(maxWidth:.infinity,alignment:.leading)
            } else {
                if round.exists { ResultSummary(roundID:round["id"].string,title:round["result"].string,committed:round["committedUnits"].double,returned:round["returnedUnits"].double).accessibilityIdentifier("blackjackResult:"+round["id"].string) }
                Panel { VStack(spacing:18) { StakeControl(value:$stake,disabled:!store.canAct); Button(store.busy ? "Dealing…" : "Deal cards") { Task { await store.action("blackjack.start",["stakeUnits":.number(Credits.units(stake))]) } }.buttonStyle(PrimaryButton()).disabled(!store.canAct || !validStake(stake,balance:store.balance)).accessibilityIdentifier("blackjackDeal") } }
            }
        }
    }
    private var tableColor: Color {
        switch store.state["settings"]["theme"].string { case "midnight": return Color(red:0.05,green:0.10,blue:0.22); case "aurora": return Color(red:0.14,green:0.08,blue:0.22); default:return Color(red:0.02,green:0.16,blue:0.13) }
    }
}

struct CardHand: View {
    let cards: [JSONValue]
    let back: String
    let seed: String
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        GeometryReader { g in
            let width = min(66,(g.size.width-CGFloat(max(0,cards.count-1))*5)/CGFloat(max(1,cards.count)))
            HStack(spacing:5) {
                ForEach(Array(cards.enumerated()),id:\.offset) { index, card in
                    DealtCard(card:card,back:back,delay:Double(index)*0.1).frame(width:width).id(seed+"\(index)")
                }
            }.frame(maxWidth:.infinity)
        }.frame(height:98).animation(store.reducedMotion ? nil : .spring(response:0.4,dampingFraction:0.85),value:cards)
    }
}

struct DealtCard: View {
    let card: JSONValue
    let back: String
    let delay: Double
    @EnvironmentObject var store: CasinoStore
    @State private var appeared = false
    @State private var flipped = false
    var body: some View {
        PlayingCard(card:flipped ? card : .null,back:back)
            .rotation3DEffect(.degrees(flipped ? 0 : 180),axis:(x:0,y:1,z:0))
            .offset(x:appeared ? 0 : 25,y:appeared ? 0 : -35).opacity(appeared ? 1 : 0)
            .task {
                if store.reducedMotion { appeared = true; flipped = true; return }
                try? await Task.sleep(for:.seconds(delay))
                withAnimation(.spring(response:0.4,dampingFraction:0.78)) { appeared = true }
                withAnimation(.easeOut(duration:0.3).delay(0.12)) { flipped = true }
            }
            .onChange(of:card.exists) { wasVisible,isVisible in
                guard !wasVisible && isVisible && !store.reducedMotion else { return }
                flipped = false
                withAnimation(.easeOut(duration:0.35)) { flipped = true }
            }
    }
}

struct MinesView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var stake = "100"
    @State private var mineCount = 3
    private var round: JSONValue { store.state["games"]["mines"] }
    private var active: Bool { round["status"].string == "active" }
    var body: some View {
        VStack(spacing:18) {
            Panel {
                VStack(spacing:18) {
                    HStack { Metric(title:"Multiplier",value:String(format:"%.2f×",round.exists ? round["multiplier"].double : 1),color:AH.emerald); Metric(title:"Collect amount",value:Credits.format(round["collectUnits"].double,precision:6)) }
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:5),spacing:8) {
                        ForEach(0..<25,id:\.self) { tile in
                            let revealed = round["revealed"].array.map(\.int).contains(tile)
                            let finished = round["status"].string == "finished"
                            let mine = round["mines"].array.map(\.int).contains(tile)
                            Button { Task { await store.action("mines.reveal",["roundId":.string(round["id"].string),"tile":.number(Double(tile))]) } } label: { MineTile(revealed:revealed || finished,mine:mine,selected:revealed,hit:round["hitTile"].exists && round["hitTile"].int == tile) }.buttonStyle(.plain).disabled(!active || revealed || !store.canAct).accessibilityLabel("Tile \(tile+1), " + (revealed || finished ? (mine ? "mine" : "gem") : "unrevealed")).accessibilityIdentifier("mineTile\(tile)")
                        }
                    }
                    if active {
                        HStack { Metric(title:"Next reveal risk",value:String(format:"%.2f%%",round["nextRisk"].double*100),color:AH.gold); Metric(title:"If next tile is safe",value:Credits.format(round["nextCollectUnits"].double,precision:6)) }
                        Text("\(round["mineCount"].int) mines remain among \(25-round["revealed"].array.count) unopened tiles. The board was fixed when this round began.").font(.caption2).foregroundStyle(AH.muted)
                        Button("Collect " + Credits.format(round["collectUnits"].double,precision:6)) { Task { await store.action("mines.collect",["roundId":.string(round["id"].string)]) } }.buttonStyle(PrimaryButton()).disabled(!store.canAct || round["revealed"].array.isEmpty).accessibilityIdentifier("minesCollect")
                    } else { Text("Reveal emeralds. Avoid the hidden mines.").font(.caption).foregroundStyle(AH.muted) }
                }
            }
            if !active {
                if round.exists { ResultSummary(roundID:round["id"].string,title:round["result"].string,committed:round["stakeUnits"].double,returned:round["returnedUnits"].double).accessibilityIdentifier("minesResult:"+round["id"].string) }
                Panel {
                    VStack(spacing:18) {
                        StakeControl(value:$stake,disabled:!store.canAct)
                        HStack { Text("Mines").font(.subheadline); Spacer(); Picker("Mine count",selection:$mineCount) { ForEach(1...24,id:\.self) { Text("\($0) of 25").tag($0) } }.pickerStyle(.menu).disabled(!store.canAct) }
                        Button(store.busy ? "Preparing board…" : "Start exploration") { Task { await store.action("mines.start",["stakeUnits":.number(Credits.units(stake)),"mineCount":.number(Double(mineCount))]) } }.buttonStyle(PrimaryButton()).disabled(!store.canAct || !validStake(stake,balance:store.balance)).accessibilityIdentifier("minesStart")
                    }
                }
            } else { Text("Stake and mine count are locked until this round finishes.").font(.caption).foregroundStyle(AH.muted) }
        }
    }
}

struct MineTile: View {
    let revealed: Bool
    let mine: Bool
    let selected: Bool
    let hit: Bool
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:12).fill(revealed ? (mine ? AH.danger.opacity(hit ? 0.22 : 0.07) : AH.emerald.opacity(selected ? 0.13 : 0.035)) : AH.raised)
            if revealed {
                Group {
                    if UIImage(named:mine ? "Mine" : "Gem") != nil { Image(mine ? "Mine" : "Gem").resizable().scaledToFit() }
                    else if mine { MineArt() } else { GemArt().padding(4) }
                }.padding(9).opacity(selected || hit ? 1 : 0.45).transition(store.reducedMotion ? .opacity : .scale.combined(with:.opacity))
            } else { RoundedRectangle(cornerRadius:4).strokeBorder(AH.muted.opacity(0.15),lineWidth:1).frame(width:15,height:15).rotationEffect(.degrees(45)) }
        }.aspectRatio(1,contentMode:.fit).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(hit ? AH.danger : .white.opacity(0.04))).animation(store.reducedMotion ? nil : .spring(response:0.32,dampingFraction:0.6),value:revealed)
    }
}

struct SlotsView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var stake = "100"
    @State private var animating = false
    @State private var spinStarted = Date()
    @State private var displayedRound = ""
    private var round: JSONValue { store.state["games"]["slots"] }
    private var quick: Bool { store.state["settings"]["quickSlots"].bool || store.reducedMotion }
    var body: some View {
        VStack(spacing:18) {
            VStack(spacing:18) {
                VStack(spacing:5) { Text("EMERALD VAULT").font(.system(size:19,weight:.medium,design:.serif)).tracking(3).foregroundStyle(AH.gold); Text("FIVE REELS · FIVE PAYLINES").font(.system(size:8,weight:.semibold)).tracking(1.7).foregroundStyle(AH.muted) }
                GeometryReader { geometry in
                    let reelWidth = (geometry.size.width-24)/5
                    HStack(spacing:6) {
                        ForEach(0..<5,id:\.self) { reel in
                            SlotReel(symbols:column(reel),index:reel,width:reelWidth,animating:animating,started:spinStarted,quick:quick,winningRows:animating ? [] : winningRows(reel))
                        }
                    }
                }.frame(height:210)
                HStack { Text(animating ? "REELS IN MOTION" : round.exists ? round["result"].string.uppercased() : "READY WHEN YOU ARE").font(.system(size:10,weight:.bold)).tracking(1.2).foregroundStyle(AH.emerald).lineLimit(2); Spacer(); if !animating && round["returnedUnits"].double > 0 { Text("+"+Credits.format(round["returnedUnits"].double,precision:6)).font(.subheadline.weight(.semibold)).foregroundStyle(AH.gold) } }
            }.padding(18).background(LinearGradient(colors:[AH.panel,Color(red:0.04,green:0.12,blue:0.11)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).strokeBorder(AH.gold.opacity(0.22)))
            if round.exists && !animating {
                ResultSummary(roundID:round["id"].string,title:round["result"].string,committed:round["stakeUnits"].double,returned:round["returnedUnits"].double).accessibilityIdentifier("slotsResult:"+round["id"].string)
                if !round["wins"].array.isEmpty {
                    Panel {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Winning combinations").font(.headline)
                            ForEach(Array(round["wins"].array.enumerated()),id:\.offset) { _,win in
                                HStack {
                                    Text("Line \(win["line"].int+1) · \(win["count"].int) \(win["symbol"].string)").font(.caption)
                                    Spacer()
                                    Text("+" + Credits.format(win["amountUnits"].double,precision:6)).font(.caption.weight(.semibold)).foregroundStyle(AH.emerald)
                                }
                            }
                        }
                    }
                }
            }
            Panel {
                VStack(spacing:18) {
                    StakeControl(value:$stake,disabled:animating || !store.canAct)
                    Toggle("Quick animations",isOn:Binding(get:{ store.state["settings"]["quickSlots"].bool },set:{ v in Task { await store.setting("quickSlots",value:.bool(v)) } })).font(.subheadline).disabled(!store.canAct || animating)
                    Button(store.busy ? "Confirming spin…" : animating ? "Reels settling…" : "Spin · " + stake) { Task { await store.action("slots.spin",["stakeUnits":.number(Credits.units(stake))]) } }.buttonStyle(PrimaryButton()).disabled(!store.canAct || animating || !validStake(stake,balance:store.balance)).accessibilityIdentifier("slotsSpin")
                    Text("Stake is divided equally across 5 lines. No wilds, scatters or bonus rounds.").font(.caption2).foregroundStyle(AH.muted)
                }
            }
        }.onAppear { displayedRound = round["id"].string }
            .onChange(of:round["id"].string) { old,new in
                guard !new.isEmpty,new != displayedRound else { return }
                displayedRound = new
                guard !store.reducedMotion else { animating = false; return }
                spinStarted = Date(); animating = true
                Task { try? await Task.sleep(for:.seconds(quick ? 0.35 : 2.6)); animating = false }
            }
    }
    private func column(_ index: Int) -> [String] { let col = round["grid"][index].array.map(\.string); return col.count == 3 ? col : ["crown","gem","bell"] }
    private func winningRows(_ reel: Int) -> [Int] { round["wins"].array.flatMap { $0["positions"].array.filter { $0[0].int == reel }.map { $0[1].int } } }
}

struct SlotReel: View {
    let symbols: [String]
    let index: Int
    let width: CGFloat
    let animating: Bool
    let started: Date
    let quick: Bool
    let winningRows: [Int]
    var body: some View {
        TimelineView(.animation(minimumInterval:1/60,paused:!animating)) { timeline in
            let duration = quick ? 0.3 : 1.55+Double(index)*0.22
            let t = min(1,max(0,timeline.date.timeIntervalSince(started)/duration))
            let eased = t*t*(3-2*t)
            let rowHeight: CGFloat = 70
            let distance = CGFloat(12+index*3)*rowHeight
            let offset = animating ? -(1-eased)*distance : 0
            AH.background
              .overlay(alignment:.top) {
                VStack(spacing:0) {
                    // The final three cells are the authoritative grid. Intermediate strip repeats
                    // those symbols; it never substitutes a different settled outcome.
                    ForEach(-24..<3,id:\.self) { row in
                        let normalized = ((row%3)+3)%3
                        SlotSymbol(symbol:symbols[normalized]).padding(7).frame(width:width,height:rowHeight)
                            .background(row >= 0 && !animating && winningRows.contains(row) ? AH.emerald.opacity(0.15) : .clear)
                            .overlay(Rectangle().strokeBorder(row >= 0 && !animating && winningRows.contains(row) ? AH.emerald.opacity(0.7) : .clear,lineWidth:1))
                    }
                }.fixedSize(horizontal:false,vertical:true).offset(y:-24*rowHeight-offset)
              }
              .overlay {
                LinearGradient(colors:[.black.opacity(0.35),.clear,.clear,.black.opacity(0.35)],startPoint:.top,endPoint:.bottom).allowsHitTesting(false)
              }.frame(width:width,height:210).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.08)))
        }.accessibilityElement(children:.ignore).accessibilityLabel("Reel \(index+1): " + symbols.joined(separator:", "))
    }
}

struct FilteredHistory: View {
    @EnvironmentObject var store: CasinoStore
    let game: String
    var body: some View {
        ScrollView { VStack(spacing:18) { HistoryList(items:store.state["history"].array.filter { $0["game"].string == game }); NavigationLink("Browse full account history") { HistoryScreen(kind:"history",title:"Game history") } }.padding(20) }.pageBackground().navigationTitle(game.capitalized + " history")
    }
}
