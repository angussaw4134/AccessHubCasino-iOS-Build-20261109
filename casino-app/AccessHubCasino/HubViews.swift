import SwiftUI

struct HubHeader: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HStack(spacing:16) {
            Brand().accessibilityIdentifier("homeBrand")
            Spacer()
            Button { hub.destination = .support } label: { Image(systemName:"questionmark.bubble").font(.title3) }.accessibilityLabel("Help and support")
            Button { hub.destination = .notifications } label: {
                Image(systemName:"bell").font(.title3).overlay(alignment:.topTrailing) {
                    if hub.bootstrap["unreadNotifications"].int > 0 { Circle().fill(AH.emerald).frame(width:7,height:7).offset(x:3,y:-3) }
                }
            }.accessibilityLabel("Notifications, \(hub.bootstrap["unreadNotifications"].int) unread")
            Button { store.selectedTab = 4 } label: { HubAvatarView().frame(width:34,height:34) }.accessibilityLabel("Open profile")
        }.foregroundStyle(AH.text)
    }
}

struct HubStatus: View {
    @EnvironmentObject var hub: HubStore
    var key = "bootstrap"
    var body: some View {
        if hub.loading.contains(key) && (key == "bootstrap" ? !hub.bootstrap.exists : hub.items(key).isEmpty) {
            HStack(spacing:12) { ProgressView().tint(AH.emerald); Text("Loading your Hub…").font(.caption).foregroundStyle(AH.muted) }.padding(.vertical,8)
        }
        if let error = hub.errors[key] {
            Panel { VStack(alignment:.leading,spacing:12) {
                Label("Unable to load",systemImage:"wifi.exclamationmark").foregroundStyle(AH.gold)
                Text(error).font(.caption).foregroundStyle(AH.muted)
                Button("Try again") { Task { if key == "bootstrap" { await hub.refresh() } else if key == "daily" { await hub.daily() } else { await hub.collection(key) } } }.font(.caption.bold())
            } }
        }
    }
}

struct HubPage<Content: View>: View {
    @EnvironmentObject var hub: HubStore
    let title: String
    var subtitle: String? = nil
    var refreshKey: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            HubHeader()
            if hub.bootstrap["config"]["maintenance"].exists {
                Text(hub.bootstrap["config"]["maintenance"]["message"].string.isEmpty ? hub.bootstrap["config"]["maintenance"].string : hub.bootstrap["config"]["maintenance"]["message"].string).font(.caption).foregroundStyle(AH.gold).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(AH.gold.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
            }
            SectionTitle(title:title,caption:subtitle)
            if let notice = hub.notice { HStack(alignment:.top) { Label(notice,systemImage:"checkmark.circle").font(.caption).foregroundStyle(AH.emerald); Spacer(); Button { hub.notice = nil } label: { Image(systemName:"xmark").font(.caption) }.accessibilityLabel("Dismiss confirmation") }.padding(12).background(AH.emerald.opacity(0.06),in:RoundedRectangle(cornerRadius:12)) }
            content
        }.padding(20).frame(maxWidth:760) .frame(maxWidth:.infinity) }
        .pageBackground().navigationBarTitleDisplayMode(.inline)
        .refreshable { await hub.refresh(force:true); if let refreshKey { await hub.reload(refreshKey) } }
    }
}

struct HubFeatureArt: View {
    var name: String
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors:[AH.emerald.opacity(0.18),AH.raised,AH.background],startPoint:.topLeading,endPoint:.bottomTrailing)
                if UIImage(named:name) != nil {
                    Image(name).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped()
                } else {
                    Canvas { context,size in
                        for index in 0..<7 {
                            let inset = CGFloat(index)*18
                            let box = CGRect(x:size.width*0.5-105+inset/2,y:size.height*0.5-75+inset/2,width:210-inset,height:150-inset)
                            context.stroke(Path(roundedRect:box,cornerRadius:28),with:.color(AH.emerald.opacity(0.05+Double(index)*0.025)),lineWidth:1)
                        }
                    }
                    GemArt().frame(width:70,height:90).rotationEffect(.degrees(-12)).shadow(color:AH.emerald.opacity(0.3),radius:20)
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct HubLinkCard<Destination: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder var destination: Destination
    var body: some View {
        NavigationLink { destination } label: {
            Panel { HStack(spacing:14) {
                Image(systemName:symbol).font(.title3).foregroundStyle(AH.emerald).frame(width:32)
                VStack(alignment:.leading,spacing:5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(AH.muted).fixedSize(horizontal:false,vertical:true) }
                Spacer(minLength:4); Image(systemName:"chevron.right").font(.caption).foregroundStyle(AH.muted)
            } }
        }.buttonStyle(.plain)
    }
}

struct HubHomeView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    private var daily: JSONValue { hub.bootstrap["daily"] }
    var body: some View {
        HubPage(title:"Your place to play.",subtitle:"Games, people and a collection that's yours.") {
            HubStatus()
            ForEach(Array(hub.bootstrap["config"]["banners"].array.enumerated()),id:\.offset) { _,banner in
                Panel { VStack(alignment:.leading,spacing:8) { Text(banner["title"].string).font(.headline); Text(banner["body"].string).font(.subheadline).foregroundStyle(AH.muted) } }
            }
            HStack(alignment:.top,spacing:12) {
                Panel { VStack(alignment:.leading,spacing:8) { Text("HUB POINTS").font(.system(size:10,weight:.bold)).tracking(1.4).foregroundStyle(AH.muted); Text(hub.isAvailable ? "\(hub.points)" : "—").font(.system(size:30,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText()); Text("Community rewards").font(.caption2).foregroundStyle(AH.muted) } }
                Panel { CreditBalance(units:store.balance).padding(.vertical,6) }
            }
            if daily.exists {
                NavigationLink { DailyRewardView() } label: {
                    ZStack(alignment:.bottomLeading) {
                        HubFeatureArt(name:"RewardsArt").frame(height:215)
                        LinearGradient(colors:[.clear,AH.background.opacity(0.95)],startPoint:.top,endPoint:.bottom)
                        VStack(alignment:.leading,spacing:8) {
                            Text(daily["available"].bool ? "READY WHEN YOU ARE" : "YOUR DAILY REWARD").font(.system(size:10,weight:.bold)).tracking(1.7).foregroundStyle(AH.emerald)
                            Text(daily["reward"]["name"].string.isEmpty ? "Your daily moment" : daily["reward"]["name"].string).font(.title2.bold())
                            Text(daily["claimed"].bool ? "Claimed · see what's next" : "Open today's reward").font(.subheadline)
                        }.padding(22)
                    }.clipShape(RoundedRectangle(cornerRadius:24))
                }.buttonStyle(.plain)
            }
            ForEach(hub.bootstrap["invitations"].array) { invitation in
                if !invitation["roomId"].string.isEmpty {
                    HubLinkCard(title:"A friend wants to play",detail:invitation["message"].string.isEmpty ? "Open your Snake invitation" : invitation["message"].string,symbol:"gamecontroller") { SnakeRoomView(roomID:invitation["roomId"].string) }
                } else if invitation["direction"].string == "incoming" {
                    HubLinkCard(title:"\(invitation["displayName"].string) sent a friend request",detail:"Review your invitations",symbol:"person.badge.plus") { FriendsView(initialFilter:"requests") }
                }
            }
            ForEach(hub.bootstrap["recentNotifications"].array.prefix(3)) { notification in
                Button { Task { await hub.openNotification(notification) } } label: { Panel { HStack { VStack(alignment:.leading,spacing:6) { Text(notification["title"].string).font(.headline); Text(notification["body"].string).font(.caption).foregroundStyle(AH.muted) }; Spacer(); Image(systemName:"arrow.up.right").foregroundStyle(AH.emerald) } } }.buttonStyle(.plain).disabled(!hub.canAct)
            }
            SectionTitle(title:"Make your next move")
            NavigationLink { SnakeLobbyView() } label: {
                ZStack(alignment:.bottomLeading) { HubFeatureArt(name:"SnakeArt").frame(height:180); LinearGradient(colors:[.clear,AH.background.opacity(0.9)],startPoint:.top,endPoint:.bottom); VStack(alignment:.leading,spacing:6) { Text("SNAKE").font(.title2.bold()); Text("Solo rhythm. Live rivalries.").font(.subheadline).foregroundStyle(AH.muted) }.padding(20) }.clipShape(RoundedRectangle(cornerRadius:22))
            }.buttonStyle(.plain).accessibilityIdentifier("homeSnakeShortcut")
            NavigationLink { CasinoCollectionView() } label: { FeaturedGame(game:.blackjack) }.buttonStyle(.plain)
            if let giveaway = hub.bootstrap["giveaways"].array.first {
                HubLinkCard(title:giveaway["title"].string,detail:"Free entry · closes \(readableDate(giveaway["closesAt"]))",symbol:"gift") { GiveawaysView() }
            }
            if hub.bootstrap["unreadNotifications"].int > 0 {
                HubLinkCard(title:"You're up to date in one tap",detail:"\(hub.bootstrap["unreadNotifications"].int) unread updates",symbol:"bell.badge") { NotificationsView() }
            }
            SectionTitle(title:"Your recent casino rounds")
            HistoryList(items:Array(store.state["history"].array.prefix(3)))
        }.toolbar(.hidden,for:.navigationBar)
    }
}

struct HubPlayView: View {
    var body: some View {
        HubPage(title:"Choose your next move.",subtitle:"A quiet practice session or a live challenge with a friend.") {
            NavigationLink { SnakeLobbyView() } label: {
                VStack(alignment:.leading,spacing:0) { HubFeatureArt(name:"SnakeArt").frame(height:210); VStack(alignment:.leading,spacing:8) { Text("Snake").font(.title2.bold()); Text("Smooth movement. Shared countdowns. Solo and live one-versus-one rooms.").font(.subheadline).foregroundStyle(AH.muted) }.padding(20) }.background(AH.panel,in:RoundedRectangle(cornerRadius:24)).clipShape(RoundedRectangle(cornerRadius:24))
            }.buttonStyle(.plain).accessibilityIdentifier("snakeLobbyShortcut")
            HubLinkCard(title:"Private rooms & match history",detail:"Join a friend's room or revisit a finished match.",symbol:"person.2") { SnakeLobbyView() }
            SectionTitle(title:"AccessHub Casino",caption:"Four original games · Access Hub Credits")
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(CasinoGame.allCases) { game in NavigationLink { GameScreen(game:game) } label: { CompactGame(game:game) }.buttonStyle(.plain).accessibilityLabel("Play " + game.title) }
            }
            HubLinkCard(title:"Casino credits & history",detail:"Every stake, return and administrator addition.",symbol:"circle.hexagongrid") { CreditsView() }.accessibilityIdentifier("openCasinoCredits")
            HubLinkCard(title:"Casino learning & rakeback",detail:"Your existing progress and 1% eligible stake returns.",symbol:"chart.bar.xaxis") { ProgressScreen() }.accessibilityIdentifier("openCasinoProgress")
        }.toolbar(.hidden,for:.navigationBar)
    }
}

struct CasinoCollectionView: View {
    var body: some View { GamesView().navigationTitle("AccessHub Casino") }
}

struct RewardsView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HubPage(title:"Good things, collected.",subtitle:"Free community rewards, separate from casino credits and game results.") {
            HubStatus()
            Panel { HStack { VStack(alignment:.leading,spacing:8) { Text("HUB POINTS").font(.caption.bold()).tracking(1.5).foregroundStyle(AH.muted); Text(hub.isAvailable ? "\(hub.points)" : "—").font(.system(size:40,weight:.semibold,design:.rounded)); Text("Earned from free community rewards.").font(.caption).foregroundStyle(AH.muted) }; Spacer(); GemArt().frame(width:48,height:60) } }
            HubLinkCard(title:"Daily reward",detail:hub.bootstrap["daily"]["claimed"].bool ? "Claimed today · preview the schedule" : "See today's available reward",symbol:"sun.max") { DailyRewardView() }.accessibilityIdentifier("dailyRewardShortcut")
            HubLinkCard(title:"Weekly giveaways",detail:"Free entries and actual configured prizes",symbol:"gift") { GiveawaysView() }
            HubLinkCard(title:"Voucher wallet",detail:"Free drops and your available benefits",symbol:"ticket") { VoucherWalletView() }
            HubLinkCard(title:"Your inventory",detail:"Collect, equip and trade eligible cosmetics",symbol:"square.stack.3d.up") { InventoryView() }
            HubLinkCard(title:"Marketplace",detail:"Member listings, priced in Hub Points",symbol:"bag") { MarketplaceView() }
            HubLinkCard(title:"Hub Point history",detail:"A separate record of your points",symbol:"clock") { PointsHistoryView() }
            Text("Hub Points cannot be purchased, withdrawn or exchanged for Access Hub Credits. Casino activity never awards Hub Points or promotion eligibility.").font(.caption).foregroundStyle(AH.muted)
        }.toolbar(.hidden,for:.navigationBar)
    }
}

struct DailyRewardView: View {
    @EnvironmentObject var hub: HubStore
    @EnvironmentObject var store: CasinoStore
    @State private var revealed = false
    private var daily: JSONValue { hub.collections["daily"] ?? hub.bootstrap["daily"] }
    var body: some View {
        HubPage(title:"A little something, daily.",subtitle:"No streak to protect. Come back whenever it suits you.",refreshKey:"daily") {
            HubStatus(key:"daily")
            Panel { VStack(alignment:.leading,spacing:18) {
                HubFeatureArt(name:"RewardsArt").frame(height:190).clipShape(RoundedRectangle(cornerRadius:16)).scaleEffect(revealed && !store.reducedMotion ? 1.02 : 1)
                Text(daily["reward"]["name"].string.isEmpty ? "No reward is scheduled" : daily["reward"]["name"].string).font(.title2.bold())
                if daily["claimed"].bool || revealed { Label("Today's reward is yours",systemImage:"checkmark.seal.fill").foregroundStyle(AH.emerald) }
                Button { Task { if await hub.action("daily.claim") { withAnimation(store.reducedMotion ? nil : .spring(duration:0.5)) { revealed = true }; await hub.daily() } } } label: { HStack { if hub.busy { ProgressView() }; Text(daily["claimed"].bool ? "Claimed" : "Claim today's reward"); Spacer(); Image(systemName:"arrow.up.right") } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || !daily["available"].bool || daily["claimed"].bool).accessibilityIdentifier("claimDaily")
                if daily["nextResetAt"].double > 0 { Text("Next reset: \(readableDate(daily["nextResetAt"]))").font(.caption).foregroundStyle(AH.muted) }
                Text("Campaign calendar: Australia/Sydney. Times above use your iPhone's local timezone.").font(.caption2).foregroundStyle(AH.muted)
            } }
            SectionTitle(title:"The reward schedule")
            ForEach(Array(daily["schedule"].array.enumerated()),id:\.offset) { index,offer in
                Panel { HStack { Text(offer["name"].string.isEmpty ? offer["reward"]["name"].string : offer["name"].string).font(.subheadline); Spacer(); Text(offer["period"].string.isEmpty ? "Day \(index+1)" : offer["period"].string).font(.caption).foregroundStyle(AH.muted) } }
            }
            if daily["schedule"].array.isEmpty { EmptyState(title:"The next schedule is on its way.",detail:"Only configured rewards appear here.") }
            SectionTitle(title:"Claimed rewards")
            ForEach(daily["history"].array) { claim in Panel { VStack(alignment:.leading,spacing:6) { Text(claim["reward"]["name"].string).font(.headline); Text(readableDate(claim["claimedAt"])).font(.caption).foregroundStyle(AH.muted) } } }
        }.task { await hub.daily() }
    }
}

struct GiveawaysView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HubPage(title:"Something worth sharing.",subtitle:"Entry is free. Casino play, stakes and balances never affect eligibility.",refreshKey:"giveaways") {
            HubStatus(key:"giveaways")
            if hub.items("giveaways").isEmpty && !hub.loading.contains("giveaways") { EmptyState(title:"No giveaway is open.",detail:"Configured promotions and previous results will appear here.") }
            ForEach(hub.items("giveaways")) { item in
                Panel { VStack(alignment:.leading,spacing:14) {
                    CosmeticPreview(item:item["prize"]).frame(height:140)
                    Text(item["title"].string).font(.title3.bold())
                    Text(item["description"].string).font(.subheadline).foregroundStyle(AH.muted)
                    Text(item["prize"]["name"].string).font(.headline).foregroundStyle(AH.emerald)
                    HStack { Text("\(item["entryCount"].int) entries"); Spacer(); Text(item["status"].string.capitalized) }.font(.caption).foregroundStyle(AH.muted)
                    Text("Opens \(readableDate(item["opensAt"]))\nCloses \(readableDate(item["closesAt"]))").font(.caption).foregroundStyle(AH.muted)
                    if item["status"].string == "open" {
                        Button(item["entered"].bool ? "You're entered" : "Enter free") { Task { if await hub.action("giveaway.enter",["giveawayId":.string(item.id)]) { await hub.collection("giveaways") } } }.buttonStyle(PrimaryButton()).disabled(item["entered"].bool || !hub.canAct)
                    }
                    ForEach(Array(item["winners"].array.enumerated()),id:\.offset) { _,winner in Text(winner["displayName"].string.isEmpty ? "A winner was notified privately" : "Winner: \(winner["displayName"].string)").font(.caption).foregroundStyle(AH.emerald) }
                } }
            }
            HubLoadMore(key:"giveaways")
        }.task { await hub.collection("giveaways") }
    }
}

struct HubLoadMore: View {
    @EnvironmentObject var hub: HubStore
    let key: String
    var body: some View {
        if !(hub.collections[key]?["nextCursor"].string ?? "").isEmpty {
            Button("Load more") { Task { await hub.loadMore(key) } }.buttonStyle(PrimaryButton(secondary:true)).disabled(hub.loading.contains(key))
        }
    }
}

struct CosmeticPreview: View {
    let item: JSONValue
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[AH.emerald.opacity(0.12),AH.raised],startPoint:.topLeading,endPoint:.bottomTrailing))
            if let url = URL(string:item["art"].string), url.scheme == "https" {
                AsyncImage(url:url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.padding(14)
            } else if UIImage(named:item["art"].string) != nil { Image(item["art"].string).resizable().scaledToFit().padding(14) }
            else { CosmeticMotif(kind:item["kind"].string,art:item["art"].string,color:item["color"].string).padding(20) }
        }.accessibilityLabel(item["name"].string + " preview")
    }
}

struct CosmeticMotif: View {
    var kind: String
    var art: String
    var color = "#00D5A0"
    var body: some View {
        GeometryReader { geo in
            ZStack {
                let side = min(geo.size.width,geo.size.height)
                if kind == "cardBack" {
                    PlayingCard(card:.null,back:"hub|"+color+"|"+art).frame(width:side*0.65,height:side)
                } else if kind == "tableTheme" {
                    RoundedRectangle(cornerRadius:22).fill(Color.hubHex(color).opacity(0.7)).overlay(RoundedRectangle(cornerRadius:22).strokeBorder(AH.gold.opacity(0.4)))
                    if UIImage(named:"TableTexture") != nil { Image("TableTexture").resizable(resizingMode:.tile).opacity(0.2).clipShape(RoundedRectangle(cornerRadius:22)) }
                    HStack(spacing:-12) { PlayingCard(card:.object(["rank":.string("A"),"suit":.string("spades")])); PlayingCard(card:.null,back:"circuit") }.frame(width:side*0.8,height:side*0.75).rotationEffect(.degrees(-8))
                } else if kind == "snakeSkin" || kind == "snakeTrail" {
                    Canvas { context,size in
                        for index in 0..<9 {
                            let x = size.width*0.15+CGFloat(index)*size.width*0.08
                            let y = size.height*0.5+sin(Double(index)*0.8)*size.height*0.2
                            context.fill(Path(roundedRect:CGRect(x:x,y:y,width:18,height:18),cornerRadius:7),with:.color(Color.hubHex(color).opacity(0.5+Double(index)*0.055)))
                        }
                    }
                } else if kind == "avatarFrame" || kind == "profileTheme" {
                    Circle().stroke(AngularGradient(colors:[Color.hubHex(color),AH.gold,Color.hubHex(color)],center:.center),lineWidth:4).frame(width:side*0.8,height:side*0.8)
                    Brand(compact:true).scaleEffect(1.3)
                } else { GemArt().frame(width:side*0.55,height:side*0.75).shadow(color:AH.emerald.opacity(0.2),radius:14) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}

struct HubAvatarView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View { PublicHubAvatar(name:hub.profile["avatar"].string,frameColor:hub.equipped("avatarFrame")["color"].string).accessibilityLabel(hub.profile["displayName"].string + " profile") }
}

struct PublicHubAvatar: View {
    let name: String
    var frameColor = ""
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle().fill(AH.emerald.opacity(0.10))
                if name == "serpent" { CosmeticMotif(kind:"snakeSkin",art:"jade-snake").padding(geometry.size.width*0.12) }
                else if ["emerald","jade","diamond","gem"].contains(name) { GemArt().colorMultiply(name == "diamond" ? Color(red:0.7,green:0.85,blue:1) : name == "jade" ? Color(red:0.8,green:1,blue:0.8) : .white).padding(geometry.size.width*0.25) }
                else if name == "orbit" { Circle().stroke(AH.emerald,lineWidth:1).padding(geometry.size.width*0.2); Ellipse().stroke(AH.gold,lineWidth:1).rotationEffect(.degrees(-35)).padding(geometry.size.width*0.13) }
                else if name == "comet" { Capsule().fill(LinearGradient(colors:[.clear,AH.gold],startPoint:.leading,endPoint:.trailing)).frame(width:geometry.size.width*0.6,height:geometry.size.width*0.14).rotationEffect(.degrees(-35)); Circle().fill(AH.gold).frame(width:geometry.size.width*0.23,height:geometry.size.width*0.23).offset(x:geometry.size.width*0.16,y:-geometry.size.width*0.1) }
                else { Brand(compact:true).scaleEffect(geometry.size.width/48) }
                if !frameColor.isEmpty { Circle().stroke(AngularGradient(colors:[Color.hubHex(frameColor),AH.gold,AH.emerald],center:.center),lineWidth:2.5).padding(1) }
            }
        }.clipShape(Circle()).accessibilityHidden(true)
    }
}

extension Color {
    static func hubHex(_ value: String) -> Color {
        let clean = value.replacingOccurrences(of:"#",with:"")
        guard clean.count == 6,let rgb = UInt64(clean,radix:16) else { return AH.emerald }
        return Color(red:Double((rgb>>16)&255)/255,green:Double((rgb>>8)&255)/255,blue:Double(rgb&255)/255)
    }
}

struct HubCardBack: View {
    let specification: String
    var body: some View {
        let parts = specification.split(separator:"|").map(String.init)
        let color = Color.hubHex(parts.count > 1 ? parts[1] : "#007E62")
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius:7).fill(color.opacity(0.35))
                Canvas { context,size in
                    for index in -8...8 {
                        let shift = CGFloat(index)*size.width/7
                        var a=Path(); a.move(to:CGPoint(x:shift,y:0)); a.addLine(to:CGPoint(x:shift+size.height,y:size.height))
                        context.stroke(a,with:.color(color.opacity(0.65)),lineWidth:0.7)
                        var b=Path(); b.move(to:CGPoint(x:shift+size.height,y:0)); b.addLine(to:CGPoint(x:shift,y:size.height))
                        context.stroke(b,with:.color(AH.gold.opacity(0.25)),lineWidth:0.7)
                    }
                }.clipShape(RoundedRectangle(cornerRadius:7))
                RoundedRectangle(cornerRadius:5).strokeBorder(color,lineWidth:1).padding(5)
                Brand(compact:true).scaleEffect(geometry.size.width/70).padding(4).background(AH.panel,in:Circle())
            }
        }
    }
}

struct VoucherWalletView: View {
    @EnvironmentObject var hub: HubStore
    @State private var filter = "available"
    @State private var reveal = false
    @State private var drop: JSONValue = .null
    @State private var selectedVoucher: JSONValue = .null
    var selectedID: String? = nil
    var body: some View {
        HubPage(title:"Your voucher wallet.",subtitle:"Real benefits, allocated once. Free drops never require credits or points.",refreshKey:"vouchers") {
            Panel { VStack(alignment:.leading,spacing:12) {
                Text("Discover a free drop").font(.headline)
                HubFeatureArt(name:"VoucherArt").frame(height:140).clipShape(RoundedRectangle(cornerRadius:14))
                Text(drop["description"].string).font(.caption).foregroundStyle(AH.muted)
                Text("The server selects from the currently stocked options below. Nothing is charged.").font(.caption).foregroundStyle(AH.muted)
                ForEach(Array(drop["options"].array.enumerated()),id:\.offset) { _,option in Text("\(option["name"].string) · \(String(format:"%.1f",option["probability"].double*100))%").font(.caption) }
                if !drop["available"].bool { Text(drop["unavailableReason"].string).font(.caption).foregroundStyle(AH.gold) }
                Button("Reveal available drop") { Task { if await hub.action("voucher.reveal") { reveal = true; await hub.collection("vouchers",filter:filter) }; await loadDrop() } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || !drop["available"].bool)
                if reveal { Label("Your allocated benefit is in this wallet",systemImage:"checkmark.seal").foregroundStyle(AH.emerald).font(.caption) }
            } }
            Picker("Wallet",selection:$filter) { Text("Available").tag("available"); Text("Redeemed").tag("redeemed"); Text("Expired").tag("expired") }.pickerStyle(.segmented)
            HubStatus(key:"vouchers")
            if hub.items("vouchers").isEmpty { EmptyState(title:"Nothing here yet.",detail:"Allocated vouchers will appear with their actual benefit and instructions.") }
            ForEach(walletItems) { item in
                Panel { VStack(alignment:.leading,spacing:14) {
                    CosmeticPreview(item:item).frame(height:130)
                    Text(item["title"].string).font(.title3.bold()); Text(item["benefit"].string).font(.subheadline)
                    Text(item["instructions"].string).font(.caption).foregroundStyle(AH.muted)
                    if item["expiresAt"].exists { Text("Expires \(readableDate(item["expiresAt"]))").font(.caption).foregroundStyle(AH.gold) } else { Text("No expiry").font(.caption).foregroundStyle(AH.muted) }
                    if !item["code"].string.isEmpty { Text(item["code"].string).font(.system(.headline,design:.monospaced)).textSelection(.enabled).privacySensitive() }
                    if item["status"].string == "available" { Button("Redeem benefit") { Task { if await hub.action("voucher.redeem",["voucherId":.string(item.id)]) { selectedVoucher = .null; filter = "redeemed"; await hub.collection("vouchers",filter:filter) } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct) }
                    else { Text(item["status"].string.capitalized).font(.caption).foregroundStyle(AH.muted) }
                } }
            }
            HubLoadMore(key:"vouchers")
        }.task(id:filter) { await hub.collection("vouchers",filter:filter); await loadDrop(); if let selectedID { do { selectedVoucher = try await hub.fetch("/v2/vouchers/" + HubStore.escape(selectedID)) } catch { hub.error = error.localizedDescription } } }
    }
    private var walletItems: [JSONValue] { selectedVoucher.exists ? [selectedVoucher] + hub.items("vouchers").filter { $0.id != selectedVoucher.id } : hub.items("vouchers") }
    private func loadDrop() async { do { drop = try await hub.fetch("/v2/vouchers/drop") } catch { hub.errors["vouchers"] = error.localizedDescription } }
}

struct InventoryView: View {
    @EnvironmentObject var hub: HubStore
    @State private var selected: JSONValue?
    @State private var price = ""
    var body: some View {
        HubPage(title:"Make it yours.",subtitle:"Cosmetics change your style. Game rules and probabilities stay the same.",refreshKey:"inventory") {
            HubFeatureArt(name:"CollectionArt").frame(height:170).clipShape(RoundedRectangle(cornerRadius:20))
            HubStatus(key:"inventory")
            if hub.items("inventory").isEmpty { EmptyState(title:"Your collection starts here.",detail:"Free rewards and eligible marketplace purchases appear here. Casino level unlocks remain in your casino profile.") }
            ForEach(hub.items("inventory")) { item in
                Panel { VStack(alignment:.leading,spacing:12) {
                    CosmeticPreview(item:item).frame(height:150)
                    Text(item["name"].string).font(.headline); Text(item["description"].string).font(.caption).foregroundStyle(AH.muted)
                    HStack { Text(item["state"].string.capitalized); Spacer(); Text(item["tradable"].bool ? "Tradable cosmetic" : "Account bound") }.font(.caption).foregroundStyle(AH.muted)
                    if item["activeUntil"].exists { Text("Active until \(readableDate(item["activeUntil"]))").font(.caption).foregroundStyle(AH.emerald) }
                    if item["state"].string == "owned" {
                        Button(item["consumable"].bool ? "Activate boost" : "Equip item") { Task { if await hub.action("inventory.activate",["inventoryId":.string(item.id)]) { await hub.collection("inventory") } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct)
                        if item["tradable"].bool { Button("List for Hub Points") { selected = item; price = "" }.font(.subheadline).disabled(!hub.canAct) }
                    } else if item["state"].string == "active" && !item["consumable"].bool {
                        Button("Unequip") { Task { if await hub.action("inventory.deactivate",["inventoryId":.string(item.id)]) { await hub.collection("inventory") } } }.buttonStyle(PrimaryButton(secondary:true)).disabled(!hub.canAct)
                    }
                } }
            }
            HubLoadMore(key:"inventory")
        }.task { await hub.collection("inventory") }
        .sheet(item:$selected) { item in
            NavigationStack { ScrollView { VStack(alignment:.leading,spacing:20) {
                CosmeticPreview(item:item).frame(height:160); SectionTitle(title:"List \(item["name"].string)",caption:"Your item is locked while listed. You can cancel before someone buys it.")
                TextField("Whole Hub Points",text:$price).keyboardType(.numberPad).fieldStyle()
                Button("Confirm listing · \(Int(price) ?? 0) points") { Task { if await hub.action("market.list",["inventoryId":.string(item.id),"price":.number(Double(Int(price) ?? 0))]) { selected = nil; await hub.collection("inventory") } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || (Int(price) ?? 0) <= 0)
            }.padding(22) }.pageBackground().navigationTitle("Create listing").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { selected = nil } } } }
        }
    }
}

struct MarketplaceView: View {
    @EnvironmentObject var hub: HubStore
    @State private var query = ""
    @State private var filter = "open"
    @State private var buying: JSONValue?
    init(initialFilter: String = "open") { _filter = State(initialValue:initialFilter) }
    var body: some View {
        HubPage(title:"The community collection.",subtitle:"\(hub.points) Hub Points available. Cosmetics only; no withdrawal or external resale.",refreshKey:"marketplace") {
            TextField("Search cosmetics",text:$query).fieldStyle().submitLabel(.search).onSubmit { Task { await hub.collection("marketplace",query:query,filter:filter) } }
            Picker("Listings",selection:$filter) { Text("Browse").tag("open"); Text("My listings").tag("mine"); Text("History").tag("history") }.pickerStyle(.segmented)
            HubStatus(key:"marketplace")
            if hub.items("marketplace").isEmpty { EmptyState(title:"No listings here.",detail:"Try another search or list an eligible item from your inventory.") }
            ForEach(hub.items("marketplace")) { listing in
                Panel { VStack(alignment:.leading,spacing:12) {
                    if listing["item"].exists { CosmeticPreview(item:listing["item"]).frame(height:145) }
                    Text(listing["item"]["name"].string.isEmpty ? listing["direction"].string.capitalized : listing["item"]["name"].string).font(.headline)
                    Text(listing["item"]["description"].string).font(.caption).foregroundStyle(AH.muted)
                    HStack { Text("\(listing["price"].int) Hub Points").font(.headline).foregroundStyle(AH.emerald); Spacer(); Text(listing["sellerName"].string).font(.caption).foregroundStyle(AH.muted) }
                    if listing["status"].string == "open" {
                        if listing["sellerId"].string == hub.ownerID { Button("Cancel listing") { Task { if await hub.action("market.cancel",["listingId":.string(listing.id)]) { await hub.collection("marketplace",query:query,filter:filter) } } }.buttonStyle(PrimaryButton(secondary:true)).disabled(!hub.canAct) }
                        else { Button("Review purchase") { buying = listing }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || hub.points < listing["price"].int) }
                    } else { Text(listing["status"].string.capitalized + " · " + readableDate(listing["createdAt"])).font(.caption).foregroundStyle(AH.muted); Text(listing["listingId"].string).font(.caption2).foregroundStyle(AH.muted).textSelection(.enabled) }
                } }
            }
            HubLoadMore(key:"marketplace")
        }.task(id:filter) { await hub.collection("marketplace",query:query,filter:filter) }
        .sheet(item:$buying) { listing in
            NavigationStack { VStack(alignment:.leading,spacing:22) {
                CosmeticPreview(item:listing["item"]).frame(height:190)
                SectionTitle(title:listing["item"]["name"].string,caption:"From \(listing["sellerName"].string)")
                Text("Price: \(listing["price"].int) Hub Points\nYour balance after purchase: \(hub.points-listing["price"].int)").font(.headline)
                Text("The server confirms current price and ownership together. If another member buys first, your points stay with you.").font(.caption).foregroundStyle(AH.muted)
                Button("Confirm purchase") { Task { if await hub.action("market.buy",["listingId":.string(listing.id),"expectedPrice":listing["price"]]) { buying = nil; await hub.collection("marketplace",query:query,filter:filter) } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct)
                Spacer()
            }.padding(22).pageBackground().navigationTitle("Review purchase").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { buying = nil } } } }
        }
    }
}

struct PointsHistoryView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HubPage(title:"Every point, accounted for.",subtitle:"Hub Points and Access Hub Credits have separate histories.",refreshKey:"points/history") {
            HubStatus(key:"points/history")
            if hub.items("points/history").isEmpty { EmptyState(title:"A clean slate.",detail:"Your daily rewards and marketplace transactions will appear here.") }
            ForEach(hub.items("points/history")) { item in Panel { HStack(alignment:.top) { VStack(alignment:.leading,spacing:6) { Text(item["reason"].string).font(.headline); Text(readableDate(item["createdAt"])).font(.caption).foregroundStyle(AH.muted); Text(item["sourceId"].string).font(.caption2).foregroundStyle(AH.muted).textSelection(.enabled); Text("Balance after: \(item["balanceAfter"].int)").font(.caption) }; Spacer(); Text((item["delta"].int > 0 ? "+" : "") + item["delta"].string).font(.headline).foregroundStyle(item["delta"].int >= 0 ? AH.emerald : AH.text) } } }
            HubLoadMore(key:"points/history")
        }.task { await hub.collection("points/history") }
    }
}
