import SwiftUI
import UIKit

struct CreditsView: View {
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                SectionTitle(title:"Your Access Hub Credits",caption:"Credits are added by an administrator.")
                Panel {
                    VStack(alignment:.leading,spacing:22) {
                        CreditBalance(units:store.balance,large:true).accessibilityIdentifier("creditsBalance")
                        Text(store.balance == 0 ? "Your account starts at 0. Credits are added by an administrator." : "Your administrator's credit additions appear in your history.").font(.subheadline).foregroundStyle(AH.muted).accessibilityIdentifier("adminCreditsInformation")
                        Text("No purchase, payment or transfer. Credits cannot be redeemed for money or prizes.").font(.caption).foregroundStyle(AH.muted)
                    }
                }
                NavigationLink { RakebackView() } label: {
                    Panel { HStack { VStack(alignment:.leading,spacing:7) { Text("Your 1% return").font(.headline); Text("\(Credits.format(store.availableRewards,precision:6)) credits available").font(.subheadline).foregroundStyle(AH.emerald) }; Spacer(); Image(systemName:"arrow.up.right").foregroundStyle(AH.emerald) } }
                }.buttonStyle(.plain)
                SectionTitle(title:"Every credit, accounted for.",caption:"Administrator additions, stakes, results and claimed rakeback.")
                HistoryList(items:Array(store.state["ledger"].array.prefix(12)),kind:"ledger")
                NavigationLink("View complete credit history") { HistoryScreen(kind:"ledger",title:"Credit history") }.font(.subheadline)
            }.padding(20)
        }.pageBackground().navigationTitle("Credits").navigationBarTitleDisplayMode(.inline).refreshable { await store.refresh() }
    }
}

struct RakebackView: View {
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                SectionTitle(title:"A little back. Every round.",caption:"A fixed 1% of eligible completed stakes, whether you win or lose.")
                Panel {
                    VStack(alignment:.leading,spacing:22) {
                        Text("AVAILABLE TO CLAIM").font(.system(size:10,weight:.bold)).tracking(1.8).foregroundStyle(AH.muted)
                        Text(Credits.format(store.availableRewards,precision:6)).font(.system(size:38,weight:.semibold,design:.rounded)).monospacedDigit().contentTransition(.numericText()).accessibilityIdentifier("rakebackAvailable")
                        Text("Access Hub Credits").font(.caption).foregroundStyle(AH.muted)
                        HStack { Metric(title:"Current return rate",value:"1%",color:AH.emerald); Metric(title:"Total claimed",value:Credits.format(store.state["totalClaimedUnits"].double,precision:6)) }
                        Button(store.busy ? "Confirming claim…" : "Claim All") { Task { await store.action("rewards.claim") } }.buttonStyle(PrimaryButton()).disabled(!store.canAct || store.availableRewards <= 0).accessibilityIdentifier("claimRakeback")
                    }
                }
                Panel { VStack(alignment:.leading,spacing:12) {
                    Text("Simple by design.").font(.headline)
                    Text("A completed 100-credit stake generates 1 Access Hub Credit. Split and double stakes in Blackjack count after the entire round settles. Cancelled or refunded stakes do not count.").font(.subheadline).foregroundStyle(AH.muted)
                    Text("Fractions are retained to one millionth of a credit. No expiry, streak, level multiplier or additional play requirement. The 1% rate stays the same at every level.").font(.subheadline).foregroundStyle(AH.muted)
                    LearnButton(milestone:"rakeback.rules",title:"I understand rakeback")
                } }
                SectionTitle(title:"Where your return came from")
                HistoryList(items:Array(store.state["rewards"].array.prefix(12)),kind:"rewards")
                NavigationLink("View complete rakeback history") { HistoryScreen(kind:"rewards",title:"Rakeback history") }.font(.subheadline)
            }.padding(20)
        }.pageBackground().navigationTitle("Rakeback").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProgressScreen: View {
    @EnvironmentObject var store: CasinoStore
    private var progress: JSONValue { store.state["progress"] }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                SectionTitle(title:"Make it your own.",caption:"Learn, explore and unlock a different look.")
                Panel {
                    VStack(alignment:.leading,spacing:18) {
                        HStack { VStack(alignment:.leading,spacing:5) { Text("LEVEL \(progress["level"].int)").font(.system(size:11,weight:.bold)).tracking(2).foregroundStyle(AH.emerald); Text(levelTitle).font(.system(size:30,weight:.medium,design:.serif)) }; Spacer(); AvatarView(name:store.state["settings"]["avatar"].string).frame(width:62,height:62) }
                        ProgressView(value:progress["levelXP"].double,total:max(1,progress["nextLevelXP"].double)).tint(AH.emerald).scaleEffect(x:1,y:1.6,anchor:.center).animation(store.reducedMotion ? nil : .easeOut(duration:0.6),value:progress["levelXP"].double)
                        HStack { Text("\(progress["levelXP"].int) / \(progress["nextLevelXP"].int) XP"); Spacer(); Text("\(progress["xp"].int) total XP") }.font(.caption).foregroundStyle(AH.muted)
                        Text("Levels unlock cosmetics. Probabilities, base payouts and 1% rakeback never change.").font(.caption).foregroundStyle(AH.muted)
                    }
                }
                NavigationLink { RakebackView() } label: { Panel { HStack { VStack(alignment:.leading,spacing:6) { Text("Rakeback").font(.title3.weight(.semibold)); Text("\(Credits.format(store.availableRewards,precision:6)) available · 1% return").font(.caption).foregroundStyle(AH.emerald) }; Spacer(); Image(systemName:"arrow.up.right") } } }.buttonStyle(.plain).accessibilityIdentifier("rakebackShortcut")
                SectionTitle(title:"Learn your way around")
                Panel { VStack(alignment:.leading,spacing:15) {
                    Text("Welcome to AccessHub").font(.headline)
                    Text("Pick a game and read its rules. Your account starts at 0 Access Hub Credits; credits are added by an administrator. Stakes can be lost. Credits cannot be purchased, transferred or redeemed.").font(.subheadline).foregroundStyle(AH.muted)
                    LearnButton(milestone:"welcome",title:"Complete the introduction")
                    Divider()
                    ForEach(CasinoGame.allCases) { game in
                        NavigationLink { RulesView(game:game) } label: { HStack { Text(game.title + " fundamentals").font(.subheadline); Spacer(); if progress["milestones"].array.map(\.string).contains(game.rawValue+".rules") { Image(systemName:"checkmark.circle.fill").foregroundStyle(AH.emerald) } else { Text("100 XP").font(.caption).foregroundStyle(AH.muted); Image(systemName:"chevron.right").font(.caption) } }.padding(.vertical,6) }.buttonStyle(.plain)
                    }
                } }
                SectionTitle(title:"Your badges")
                if progress["badges"].array.isEmpty { Panel { EmptyState(title:"The first step counts.",detail:"Read a game's rules or complete a first practice round to earn a badge.") } }
                else { LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) { ForEach(progress["badges"].array.map(\.string),id:\.self) { badge in VStack(alignment:.leading,spacing:12) { Image(systemName:badge.contains("rules") ? "book.closed" : "seal").font(.title3).foregroundStyle(AH.gold); Text(badge.replacingOccurrences(of:".",with:" · ").capitalized).font(.caption.weight(.semibold)) }.padding(18).frame(maxWidth:.infinity,minHeight:96,alignment:.leading).background(AH.panel,in:RoundedRectangle(cornerRadius:18)) } } }
                SectionTitle(title:"Your collection",caption:"\(progress["unlocks"].array.count) cosmetics unlocked")
                Panel { VStack(alignment:.leading,spacing:14) { Text("Avatars, profile decorations, card backs and table styles live in Profile.").font(.subheadline).foregroundStyle(AH.muted); Button("Customize your look") { store.selectedTab = 4 }.buttonStyle(PrimaryButton(secondary:true)) } }
            }.padding(20)
        }.pageBackground().navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
    }
    private var levelTitle: String { switch progress["level"].int { case 0...1:return "New perspective"; case 2:return "Finding your rhythm"; case 3:return "At home at the table"; default:return "The connoisseur" } }
}

struct LearnButton: View {
    @EnvironmentObject var store: CasinoStore
    let milestone: String
    let title: String
    private var completed: Bool { store.state["progress"]["milestones"].array.map(\.string).contains(milestone) }
    var body: some View {
        Button { Task { await store.action("progress.learn",["milestone":.string(milestone)]) } } label: { HStack { Image(systemName:completed ? "checkmark.circle.fill" : "checkmark.circle"); Text(completed ? "Completed · 100 XP earned" : title); Spacer(); if !completed { Text("+100 XP").font(.caption) } } }.font(.caption.weight(.semibold)).foregroundStyle(AH.emerald).disabled(completed || !store.canAct).padding(.vertical,6)
    }
}

struct AvatarView: View {
    let name: String
    var decoration: String? = nil
    @EnvironmentObject var store: CasinoStore
    private var selectedDecoration: String { decoration ?? (store.state["settings"]["decoration"].string.isEmpty ? "plain" : store.state["settings"]["decoration"].string) }
    var body: some View {
        ZStack {
            ZStack {
                Circle().fill(AH.emerald.opacity(0.08)).overlay(Circle().strokeBorder(AH.emerald.opacity(0.25)))
                if name == "gem" { GemArt().padding(12) }
                else if name == "crown" { SlotSymbol(symbol:"crown").padding(8) }
                else if name == "orbit" { ZStack { Ellipse().stroke(AH.emerald,lineWidth:1.3).rotationEffect(.degrees(-35)); Ellipse().stroke(AH.gold.opacity(0.6),lineWidth:1.3).rotationEffect(.degrees(35)); Circle().fill(AH.emerald).frame(width:6,height:6) }.padding(10) }
                else { Brand(compact:true).padding(6) }
            }.scaleEffect(selectedDecoration == "plain" ? 1 : 0.8)
            ProfileDecoration(name:selectedDecoration).allowsHitTesting(false)
        }.accessibilityLabel(name.capitalized + " avatar" + (selectedDecoration == "plain" ? "" : ", \(selectedDecoration) decoration"))
    }
}

struct ProfileDecoration: View {
    let name: String
    var body: some View {
        Group {
            if name == "halo" {
                Circle().strokeBorder(AngularGradient(colors:[AH.emerald.opacity(0.2),AH.emerald,AH.gold,AH.emerald.opacity(0.2)],center:.center),lineWidth:1.5).padding(1).shadow(color:AH.emerald.opacity(0.3),radius:3)
            } else if name == "laurel" {
                Canvas { context,size in
                    let w=size.width,h=size.height,cx=w/2,cy=h/2
                    for side in [-1.0,1.0] {
                        var branch=Path()
                        branch.move(to:CGPoint(x:cx,y:h*0.96))
                        for index in 0..<7 {
                            let angle=Double(index)/6 * Double.pi*0.74 + Double.pi*0.08
                            let x=cx+CGFloat(side*sin(angle))*w*0.43
                            let y=cy+CGFloat(cos(angle))*h*0.43
                            branch.addLine(to:CGPoint(x:x,y:y))
                            let tip=CGPoint(x:x+CGFloat(side)*w*0.085,y:y-h*0.10)
                            var leaf=Path();leaf.move(to:CGPoint(x:x,y:y))
                            leaf.addQuadCurve(to:tip,control:CGPoint(x:x-CGFloat(side)*w*0.035,y:y-h*0.09))
                            leaf.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x:x+CGFloat(side)*w*0.12,y:y-h*0.025))
                            context.fill(leaf,with:.color(AH.gold.opacity(0.9)))
                        }
                        context.stroke(branch,with:.color(AH.gold.opacity(0.65)),lineWidth:0.8)
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

struct ProfileView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    @State private var register = false
    @State private var login = false
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var support = false
    @State private var copiedAccountID = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HubHeader()
                HStack(spacing:16) { HubAvatarView().frame(width:70,height:70); VStack(alignment:.leading,spacing:7) { Text(hub.profile["displayName"].string.isEmpty ? (store.state["user"]["isGuest"].bool ? "Your guest profile" : store.state["user"]["username"].string) : hub.profile["displayName"].string).font(.title2.weight(.semibold)); Text("Hub level \(max(1,hub.profile["level"].int)) · Casino level \(store.state["progress"]["level"].int)").font(.caption).foregroundStyle(AH.muted) } }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(LinearGradient(colors:[hub.equipped("profileTheme").exists ? Color.hubHex(hub.equipped("profileTheme")["color"].string).opacity(0.20) : AH.panel,AH.panel],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:22))
                HubLinkCard(title:"Community profile & privacy",detail:hub.profile["displayName"].string,symbol:"person.crop.circle") { HubProfileSettingsView() }
                HubLinkCard(title:"Hub level & collection",detail:"\(hub.points) Hub Points · cosmetic progression",symbol:"sparkles") { HubProgressView() }
                HubLinkCard(title:"Access Hub Credits",detail:"\(Credits.format(store.balance)) · administrator funded",symbol:"circle.hexagongrid") { CreditsView() }.accessibilityIdentifier("profileCredits")
                HubLinkCard(title:"Notifications",detail:"Inbox, categories and quiet hours",symbol:"bell") { NotificationsView() }
                Panel { VStack(alignment:.leading,spacing:12) {
                    Text("Your account ID").font(.headline)
                    Text(store.state["user"]["id"].string).font(.system(.caption,design:.monospaced)).textSelection(.enabled).accessibilityIdentifier("profileAccountID")
                    Text("Share this ID with your administrator when credits need to be added.").font(.caption).foregroundStyle(AH.muted)
                    Button(copiedAccountID ? "Copied" : "Copy account ID") {
                        UIPasteboard.general.string = store.state["user"]["id"].string
                        copiedAccountID = true
                    }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("copyAccountID")
                } }
                if store.state["user"]["isGuest"].bool {
                    Panel { VStack(alignment:.leading,spacing:14) { Text("Keep your progress with you.").font(.headline); Text("Save this guest account with a username and password for access on another iPhone.").font(.subheadline).foregroundStyle(AH.muted); Button("Save my progress") { register = true }.buttonStyle(PrimaryButton()).disabled(!store.canAct); Button("Sign in to an existing account") { login = true }.font(.caption).disabled(store.busy || store.pending != nil) } }
                }
                Panel { VStack(alignment:.leading,spacing:18) { Text("Your practice, in numbers").font(.headline); HStack { Metric(title:"Rounds",value:String(store.state["stats"]["rounds"].int)); Metric(title:"Credits staked",value:Credits.format(store.state["stats"]["stakedUnits"].double)) }; HStack { Metric(title:"Credits returned",value:Credits.format(store.state["stats"]["returnedUnits"].double)); Metric(title:"Game net",value:Credits.format(store.state["stats"]["netUnits"].double)) } } }
                SectionTitle(title:"Make yourself at home")
                Panel { VStack(alignment:.leading,spacing:20) {
                    Text("Casino progress avatar").font(.headline)
                    HStack(spacing:14) { ForEach(["monogram","gem","orbit","crown"],id:\.self) { avatar in
                        let unlocked = store.state["progress"]["unlocks"].array.map(\.string).contains(avatar)
                        Button { Task { await store.setting("avatar",value:.string(avatar)) } } label: { VStack(spacing:7) { AvatarView(name:avatar).frame(maxWidth:58).overlay(alignment:.bottomTrailing) { if !unlocked { Image(systemName:"lock.fill").font(.caption2).foregroundStyle(AH.muted) } }; Circle().fill(store.state["settings"]["avatar"].string == avatar ? AH.emerald : .clear).frame(width:4,height:4) } }.disabled(!unlocked || !store.canAct).opacity(unlocked ? 1 : 0.35).accessibilityLabel(avatar.capitalized + (unlocked ? " avatar" : " avatar, locked"))
                    } }
                    CosmeticPicker(title:"Table style",key:"theme",options:["emerald","midnight","aurora"])
                    CosmeticPicker(title:"Card back",key:"cardBack",options:["classic","circuit","royal"])
                    CosmeticPicker(title:"Profile decoration",key:"decoration",options:["plain","halo","laurel"])
                    if hub.equipped("cardBack").exists || hub.equipped("tableTheme").exists { Text("An equipped Hub card back or table theme takes priority at your Blackjack table. Unequip it in Inventory to use these Casino unlocks.").font(.caption2).foregroundStyle(AH.emerald) }
                    Text("Cosmetics unlock through learning at levels 2, 3 and 4. Table styles and card backs appear at the Blackjack table. Profile decorations surround your selected avatar across Home, Progress and Profile; Halo unlocks at level 2 and Laurel at level 4.").font(.caption2).foregroundStyle(AH.muted)
                } }
                Panel { VStack(spacing:18) { settingToggle("Sound effects",key:"sound"); settingToggle("Haptic feedback",key:"haptics"); settingToggle("Reduce motion",key:"reducedMotion"); Text("The iPhone's Reduce Motion setting is always respected. Sound and haptics are independent.").font(.caption2).foregroundStyle(AH.muted).frame(maxWidth:.infinity,alignment:.leading) } }
                Panel { VStack(alignment:.leading,spacing:18) { Button { support = true } label: { Label("Help & support",systemImage:"questionmark.circle") }; NavigationLink { HistoryScreen(kind:"history",title:"Game history") } label: { Label("Game history",systemImage:"clock") }; Button { confirmLogout = true } label: { Label("Sign out",systemImage:"rectangle.portrait.and.arrow.right") }.disabled(!store.canAct || store.hasUnresolvedGames); Button(role:.destructive) { confirmDelete = true } label: { Label("Delete account and data",systemImage:"trash") }.disabled(!store.canAct || store.hasUnresolvedGames); if store.hasUnresolvedGames { Text("Finish your active rounds before signing out or deleting this account.").font(.caption2).foregroundStyle(AH.muted) } }.font(.subheadline) }
                Text("AccessHub · v1.1 · Build 3\nAccess Hub Credits & Hub Points").font(.caption2).foregroundStyle(AH.muted).multilineTextAlignment(.center).frame(maxWidth:.infinity)
            }.padding(20)
        }.pageBackground().navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .onChange(of:store.state["user"]["id"].string) { _,_ in copiedAccountID = false }
            .sheet(isPresented:$register) { AccountView(register:true) }
            .sheet(isPresented:$login) { AccountView(register:false) }
            .sheet(isPresented:$support) { HubDestinationSheet(destination:.support) }
            .alert("Sign out?",isPresented:$confirmLogout) { Button("Cancel",role:.cancel) {}; Button("Sign out",role:.destructive) { Task { await store.endSession() } } } message: { Text(store.state["user"]["isGuest"].bool ? "This is a guest account. Save your progress with a username and password first if you want to return to it." : "Your progress will be available when you sign in again.") }
            .alert("Delete your account?",isPresented:$confirmDelete) { Button("Cancel",role:.cancel) {}; Button("Delete permanently",role:.destructive) { Task { await store.endSession(delete:true) } } } message: { Text("This permanently removes your account, saved progress, credits and history. This cannot be undone.") }
    }
    private func settingToggle(_ title: String,key: String) -> some View {
        Toggle(title,isOn:Binding(get:{ store.state["settings"][key].bool },set:{ value in Task { await store.setting(key,value:.bool(value)) } })).font(.subheadline).disabled(!store.canAct)
    }
}

struct CosmeticPicker: View {
    @EnvironmentObject var store: CasinoStore
    let title: String
    let key: String
    let options: [String]
    var body: some View {
        VStack(alignment:.leading,spacing:11) {
            Text(title).font(.headline)
            HStack(spacing:8) {
                ForEach(options,id:\.self) { option in
                    let unlocked = store.state["progress"]["unlocks"].array.map(\.string).contains(option)
                    let selected = store.state["settings"][key].string == option
                    Button { Task { await store.setting(key,value:.string(option)) } } label: {
                        VStack(spacing:7) {
                            if key == "cardBack" { PlayingCard(card:.null,back:option).frame(height:65) }
                            else if key == "decoration" { AvatarView(name:store.state["settings"]["avatar"].string,decoration:option).frame(width:50,height:50) }
                            else { RoundedRectangle(cornerRadius:8).fill(option == "emerald" ? Color(red:0.02,green:0.20,blue:0.14) : option == "midnight" ? Color(red:0.06,green:0.12,blue:0.26) : Color(red:0.22,green:0.10,blue:0.3)).frame(height:30) }
                            Text(option.capitalized).font(.system(size:10,weight:.semibold))
                            Image(systemName:unlocked ? (selected ? "checkmark.circle.fill" : "circle") : "lock.fill").font(.caption2)
                        }.padding(9).frame(maxWidth:.infinity).background(selected ? AH.emerald.opacity(0.10) : AH.background,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(selected ? AH.emerald : AH.muted)
                    }.disabled(!unlocked || !store.canAct).opacity(unlocked ? 1 : 0.45).accessibilityIdentifier("cosmetic-\(key)-\(option)")
                }
            }
        }
    }
}

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment:.leading,spacing:22) {
                SectionTitle(title:"Here to help.")
                Panel { VStack(alignment:.leading,spacing:14) {
                    Text("A round was interrupted").font(.headline)
                    Text("Open the app again. The server restores your board, hands and accepted entries. Saved requests are retried with the same ID so a stake or claim is never applied twice. Automatic Crash collection runs even while you are disconnected.").font(.subheadline).foregroundStyle(AH.muted)
                    Text("Your balance looks different").font(.headline)
                    Text("Credits records every change, including administrator additions, stakes, returns and rakeback. Open the full credit history to inspect the originating round.").font(.subheadline).foregroundStyle(AH.muted)
                    NavigationLink("Open credit history") { HistoryScreen(kind:"ledger",title:"Credit history") }
                    Text("Saved accounts").font(.headline)
                    Text("Guest access is tied to this device. Create a username and password in Profile before changing devices. There is no email reset; keep your password in a secure password manager.").font(.subheadline).foregroundStyle(AH.muted)
                } }
                Panel { VStack(alignment:.leading,spacing:14) {
                    Text("Service information").font(.headline)
                    Text("Share this diagnostic summary with the person who provided your app build. It contains no password or session token.").font(.subheadline).foregroundStyle(AH.muted)
                    ShareLink(item:"AccessHub Casino v1.0\nService: \(store.baseURL.absoluteString)\nStatus: \(store.online ? "connected" : "offline")\nDate: \(Date().ISO8601Format())") { Label("Share diagnostics",systemImage:"square.and.arrow.up") }
                    Text("Credits are added by an administrator. There are no payments, withdrawals, prizes or transfers.").font(.caption).foregroundStyle(AH.muted)
                } }
            }.padding(20) }.pageBackground().navigationTitle("Help & support").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
