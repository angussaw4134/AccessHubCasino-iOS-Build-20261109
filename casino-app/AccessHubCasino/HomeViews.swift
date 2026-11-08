import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:26) {
                HStack { Brand(); Spacer(); Button { store.selectedTab = 4 } label: { AvatarView(name:store.state["settings"]["avatar"].string).frame(width:42,height:42) }.accessibilityLabel("Open profile") }
                Panel {
                    HStack(alignment:.center) {
                        CreditBalance(units:store.balance,large:true)
                        Spacer()
                        Button { store.selectedTab = 2 } label: { Image(systemName:"plus").font(.title3.weight(.semibold)).frame(width:44,height:44).background(AH.emerald.opacity(0.1),in:Circle()) }.accessibilityLabel("Free credits")
                    }
                }
                VStack(alignment:.leading,spacing:14) {
                    HStack { SectionTitle(title:"Make your next move."); Spacer() }
                    NavigationLink { GameScreen(game:.crash) } label: { FeaturedGame(game:.crash) }.buttonStyle(.plain)
                }
                HStack { Text("THE COLLECTION").font(.system(size:11,weight:.bold)).tracking(1.8).foregroundStyle(AH.muted); Spacer(); Button("View all") { store.selectedTab = 1 }.font(.caption.weight(.semibold)) }
                LazyVGrid(columns:[GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)],spacing:12) {
                    ForEach([CasinoGame.blackjack,.mines,.slots]) { game in
                        NavigationLink { GameScreen(game:game) } label: { CompactGame(game:game) }.buttonStyle(.plain)
                    }
                    Button { store.selectedTab = 3 } label: {
                        VStack(alignment:.leading,spacing:13) {
                            Text("01%").font(.system(size:35,weight:.light,design:.rounded)).foregroundStyle(AH.emerald)
                            Text("A little back.").font(.headline)
                            Text("Claim your credit rakeback.").font(.caption).foregroundStyle(AH.muted)
                            Image(systemName:"arrow.up.right").foregroundStyle(AH.emerald)
                        }.padding(18).frame(maxWidth:.infinity,minHeight:190,alignment:.leading).background(AH.panel,in:RoundedRectangle(cornerRadius:20))
                    }.buttonStyle(.plain)
                }
                SectionTitle(title:"Your recent rounds")
                HistoryList(items:Array(store.state["history"].array.prefix(5)))
                NavigationLink("View complete history") { HistoryScreen(kind:"history",title:"Game history") }.font(.subheadline)
                Text("Free credits. Real choices. No cash value.").font(.caption).foregroundStyle(AH.muted).frame(maxWidth:.infinity).padding(.vertical,8)
            }.padding(20)
        }.pageBackground().toolbar(.hidden,for:.navigationBar).refreshable { await store.refresh() }
    }
}

struct FeaturedGame: View {
    let game: CasinoGame
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        ZStack(alignment:.bottomLeading) {
            GameArtwork(game:game).frame(height:260)
                .phaseAnimator(store.reducedMotion ? [false] : [false,true]) { content,phase in
                    content.scaleEffect(phase ? 1.035 : 1)
                } animation: { _ in .easeInOut(duration:5) }
            LinearGradient(colors:[.clear,AH.background.opacity(0.95)],startPoint:.center,endPoint:.bottom)
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:6) { Circle().fill(AH.emerald).frame(width:5,height:5); Text(game.eyebrow).font(.system(size:9,weight:.bold)).tracking(1.7) }.foregroundStyle(AH.emerald)
                HStack(alignment:.bottom) {
                    VStack(alignment:.leading,spacing:6) { Text(game.title).font(.system(size:34,weight:.medium,design:.serif)); Text("The climb is live. The moment is yours.").font(.caption).foregroundStyle(AH.muted) }
                    Spacer()
                    Image(systemName:"arrow.up.right").font(.title3).frame(width:44,height:44).background(AH.emerald,in:Circle()).foregroundStyle(AH.background)
                }
            }.padding(22)
        }.frame(height:260).clipShape(RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).strokeBorder(AH.emerald.opacity(0.12)))
    }
}

struct CompactGame: View {
    let game: CasinoGame
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            GameArtwork(game:game).frame(height:124)
                .phaseAnimator(store.reducedMotion ? [false] : [false,true]) { content,phase in
                    content.scaleEffect(phase ? 1.025 : 1)
                } animation: { _ in .easeInOut(duration:4) }
            HStack { Text(game.title).font(.headline); Spacer(); Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(AH.emerald) }.padding(16)
        }.background(AH.panel).clipShape(RoundedRectangle(cornerRadius:20))
    }
}

struct GamesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                SectionTitle(title:"The collection",caption:"Four ways to play. Explore the rules, then find your rhythm.")
                ForEach(CasinoGame.allCases) { game in
                    VStack(alignment:.leading,spacing:16) {
                        NavigationLink { GameScreen(game:game) } label: { GameArtwork(game:game).frame(height:184).clipShape(RoundedRectangle(cornerRadius:18)) }.buttonStyle(.plain)
                        HStack { VStack(alignment:.leading,spacing:6) { Text(game.title).font(.title2.weight(.semibold)); Text(game.subtitle).font(.subheadline).foregroundStyle(AH.muted) }; Spacer() }
                        HStack(spacing:10) {
                            NavigationLink("Play \(game.title)") { GameScreen(game:game) }.buttonStyle(PrimaryButton())
                            NavigationLink { RulesView(game:game) } label: { Image(systemName:"info.circle").frame(width:48,height:48).background(AH.raised,in:RoundedRectangle(cornerRadius:14)) }.accessibilityLabel("\(game.title) rules and payouts")
                        }
                    }.padding(16).background(AH.panel,in:RoundedRectangle(cornerRadius:24))
                }
            }.padding(20)
        }.pageBackground().navigationTitle("Games").navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryList: View {
    let items: [JSONValue]
    var kind = "history"
    var body: some View {
        if items.isEmpty { Panel { EmptyState(title:"A clean slate",detail:kind == "rewards" ? "Complete a round to receive 1% of its eligible stake." : "Your completed activity will appear here.") } }
        else {
            VStack(spacing:0) {
                ForEach(Array(items.enumerated()),id:\.offset) { index, item in
                    HStack(alignment:.top,spacing:12) {
                        Circle().fill(AH.emerald.opacity(0.1)).frame(width:34,height:34).overlay(Text(String((item["game"].exists ? item["game"].string : "C").prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(AH.emerald))
                        VStack(alignment:.leading,spacing:5) {
                            Text(kind == "ledger" ? item["description"].string : item["game"].string.capitalized).font(.subheadline.weight(.medium))
                            if kind == "rewards" {
                                Text("\(Credits.format(item["eligibleStakeUnits"].double,precision:6)) staked × 1%").font(.caption).foregroundStyle(AH.muted)
                                Text("Claimed \(Credits.format(item["claimedUnits"].double,precision:6))").font(.caption2).foregroundStyle(AH.muted)
                            } else if kind == "history" { Text(item["result"].string).font(.caption).foregroundStyle(AH.muted) }
                            Text(readableDate(item["createdAt"])).font(.caption2).foregroundStyle(AH.muted)
                            if item["roundId"].exists { Text("Round · " + String(item["roundId"].string.prefix(8))).font(.system(size:10,design:.monospaced)).foregroundStyle(AH.muted) }
                        }
                        Spacer(minLength:4)
                        VStack(alignment:.trailing,spacing:5) {
                            let value = kind == "history" ? item["netUnits"].double : item["amountUnits"].double
                            Text((value > 0 ? "+" : "") + Credits.format(value,precision:6)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(value >= 0 ? AH.emerald : AH.text)
                            if kind == "ledger" { Text("Balance " + Credits.format(item["balanceUnits"].double,precision:6)).font(.caption2).foregroundStyle(AH.muted) }
                            if kind == "history" { Text("In " + Credits.format(item["stakeUnits"].double)).font(.caption2).foregroundStyle(AH.muted); Text("Back " + Credits.format(item["returnedUnits"].double,precision:6)).font(.caption2).foregroundStyle(AH.muted) }
                        }
                    }.padding(16)
                    if index < items.count-1 { Divider().overlay(.white.opacity(0.04)).padding(.leading,62) }
                }
            }.background(AH.panel,in:RoundedRectangle(cornerRadius:20))
        }
    }
}

struct HistoryScreen: View {
    @EnvironmentObject var store: CasinoStore
    let kind: String
    let title: String
    @State private var items: [JSONValue] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var failure: String?
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                HistoryList(items:items,kind:kind)
                if let failure { Text(failure).foregroundStyle(AH.danger); Button("Try again") { Task { await load() } }.buttonStyle(PrimaryButton(secondary:true)) }
                if loading { ProgressView().padding() }
                else if cursor != nil { Button("Load earlier activity") { Task { await load() } }.buttonStyle(PrimaryButton(secondary:true)) }
                Text("All amounts are Access Hub Credits · No cash value").font(.caption).foregroundStyle(AH.muted)
            }.padding(20)
        }.pageBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline).task { if !loaded { await load() } }
    }
    private func load() async {
        guard !loading else { return }; loading = true; failure = nil
        defer { loading = false }
        do {
            let page = try await store.history(kind,before:cursor)
            let existing = Set(items.map { $0["id"].string })
            items.append(contentsOf:page["items"].array.filter { !existing.contains($0["id"].string) })
            cursor = page["nextBefore"].exists && !page["nextBefore"].string.isEmpty ? page["nextBefore"].string : nil
            loaded = true
        } catch { failure = error.localizedDescription }
    }
}
