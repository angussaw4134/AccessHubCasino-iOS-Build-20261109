import SwiftUI

@main @MainActor struct AccessHubCasinoApp: App {
    @StateObject private var store = CasinoStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
                .tint(AH.emerald)
                .onChange(of: phase) { _, phase in
                    if phase == .active { store.resume() } else { store.suspend() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var launching = true
    var body: some View {
        ZStack {
            AH.background.ignoresSafeArea()
            if store.authenticated { MainTabs() }
            else { WelcomeView() }
            if launching {
                ZStack { AH.background.ignoresSafeArea(); VStack(spacing:24) { Brand(); Rectangle().fill(AH.emerald).frame(width:32,height:2); Text("YOUR NEXT MOVE").font(.caption2).tracking(3).foregroundStyle(AH.muted) } }
                    .transition(.opacity).zIndex(10)
            }
        }
        .task {
            async let launch: Void = store.launch()
            try? await Task.sleep(for:.milliseconds(800))
            withAnimation(store.reducedMotion ? nil : .easeOut(duration:0.45)) { launching = false }
            await launch
        }
        .alert("AccessHub", isPresented: Binding(get:{ store.error != nil },set:{ if !$0 { store.error = nil } })) {
            Button("OK",role:.cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(item: Binding(get:{ store.levelUp.map(LevelNotice.init) },set:{ if $0 == nil { store.levelUp = nil } })) { level in
            VStack(spacing:24) {
                GemArt().frame(width:76,height:88).shadow(color:AH.emerald.opacity(0.3),radius:22)
                Text("Level \(level.id)").font(.system(size:38,weight:.bold,design:.rounded))
                Text("More to make your own.").font(.title3)
                Text("Explore your new cosmetics in Profile. Game probabilities, payouts and 1% rakeback stay the same.").font(.subheadline).foregroundStyle(AH.muted).multilineTextAlignment(.center)
                Button("Keep exploring") { store.levelUp = nil }.buttonStyle(PrimaryButton())
            }.padding(30).presentationDetents([.medium]).presentationDragIndicator(.visible).presentationBackground(AH.panel)
        }
    }
    struct LevelNotice: Identifiable { let id: Int }
}

struct WelcomeView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var signingIn = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Brand().padding(.top,24)
                    GameArtwork(game:.blackjack).frame(height:max(160,min(geometry.size.height*0.32,280))).clipShape(RoundedRectangle(cornerRadius:26))
                    VStack(alignment:.leading,spacing:10) {
                        Text("THE ART OF THE NEXT MOVE").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(AH.emerald)
                        Text("A little strategy.\nA little possibility.").font(.system(size:34,weight:.medium,design:.serif))
                        Text("Four original games. 10,000 free Access Hub Credits to explore them.").font(.subheadline).foregroundStyle(AH.muted)
                    }
                    VStack(spacing:12) {
                        Button {
                            if store.needsSignIn && !store.canRestoreGuest { signingIn = true }
                            else { Task { await store.guest() } }
                        } label: {
                            HStack {
                                if store.busy || store.connecting { ProgressView().tint(AH.background) }
                                Text(store.connecting ? "Restoring your session…" : store.busy ? "Opening your account…" : store.needsSignIn ? (store.canRestoreGuest ? "Restore guest access" : "Sign in to restore progress") : "Enter as guest")
                                Spacer(); Image(systemName:"arrow.right")
                            }
                        }.buttonStyle(PrimaryButton()).disabled(store.busy || store.connecting).accessibilityIdentifier("enterGuest")
                        Button("Sign in to saved progress") { signingIn = true }.font(.subheadline.weight(.medium)).padding(8)
                    }
                    Text("Access Hub Credits have no cash value. They are free, cannot be purchased or transferred, and cannot be redeemed for money or prizes.").font(.caption).foregroundStyle(AH.muted).fixedSize(horizontal:false,vertical:true)
                }.padding(24).frame(minHeight:geometry.size.height,alignment:.top)
            }
        }.sheet(isPresented:$signingIn) { AccountView(register:false) }.pageBackground()
    }
}

struct MainTabs: View {
    @EnvironmentObject var store: CasinoStore
    @State private var signIn = false
    var body: some View {
        TabView(selection:$store.selectedTab) {
            NavigationStack { HomeView() }.tabItem { Label("Home",systemImage:"square.grid.2x2") }.tag(0)
            NavigationStack { GamesView() }.tabItem { Label("Games",systemImage:"suit.spade") }.tag(1)
            NavigationStack { CreditsView() }.tabItem { Label("Credits",systemImage:"circle.hexagongrid") }.tag(2)
            NavigationStack { ProgressScreen() }.tabItem { Label("Progress",systemImage:"chart.bar.xaxis") }.tag(3)
            NavigationStack { ProfileView() }.tabItem { Label("Profile",systemImage:"person.crop.circle") }.tag(4)
        }.toolbarBackground(AH.background,for:.tabBar).toolbarBackground(.visible,for:.tabBar)
            .safeAreaInset(edge:.top,spacing:0) {
                if !store.online || store.pending != nil || store.needsSignIn {
                    HStack(spacing:10) {
                        Image(systemName:store.pending == nil ? "wifi.slash" : "arrow.triangle.2.circlepath")
                        Text(store.needsSignIn ? (store.canRestoreGuest ? "Restore your guest session" : "Sign in to restore this session") : store.pending == nil ? "Reconnecting · controls paused" : "Confirming your saved request").font(.caption)
                        Spacer()
                        if store.needsSignIn && store.canRestoreGuest { Button("Restore") { Task { await store.guest() } }.font(.caption.bold()).disabled(store.busy || store.connecting) }
                        else if store.needsSignIn { Button("Sign in") { signIn = true }.font(.caption.bold()) }
                        else { Button("Retry") { Task { if store.pending != nil { await store.retryPending() } else { await store.refresh() } } }.font(.caption.bold()).disabled(store.busy) }
                    }.padding(.horizontal,16).padding(.vertical,10).background(AH.raised).foregroundStyle(AH.gold)
                }
            }
            .sheet(isPresented:$signIn) { AccountView(register:false) }
    }
}

struct AccountView: View {
    @EnvironmentObject var store: CasinoStore
    @Environment(\.dismiss) private var dismiss
    let register: Bool
    @State private var username = ""
    @State private var password = ""
    @State private var success = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Brand()
                    SectionTitle(title:register ? "Keep your place." : "Welcome back.",caption:register ? "Save this guest account and restore it on your other devices." : "Sign in to restore your credits, history and progress.")
                    if success {
                        Panel { VStack(alignment:.leading,spacing:14) { Label("Progress saved",systemImage:"checkmark.circle.fill").foregroundStyle(AH.emerald); Text(store.notice ?? "Your account is ready."); Button("Continue") { dismiss() }.buttonStyle(PrimaryButton()) } }
                    } else {
                        VStack(alignment:.leading,spacing:16) {
                            if let error = store.error { Text(error).font(.subheadline).foregroundStyle(AH.danger).accessibilityIdentifier("accountError") }
                            TextField("Username",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().fieldStyle().accessibilityIdentifier("username")
                            SecureField("Password",text:$password).textContentType(register ? .newPassword : .password).fieldStyle().accessibilityIdentifier("password")
                            Text("Username: 3–24 letters, numbers or underscores. Password: 10–128 characters. Keep your password somewhere safe; there is no email recovery.").font(.caption).foregroundStyle(AH.muted)
                            Button { Task { success = await store.account(username:username,password:password,register:register) } } label: { HStack { if store.busy { ProgressView().tint(AH.background) }; Text(register ? "Save my account" : "Sign in") } }.buttonStyle(PrimaryButton()).disabled(store.busy || username.isEmpty || password.isEmpty)
                        }
                    }
                }.padding(24)
            }.pageBackground().navigationTitle(register ? "Save progress" : "Sign in").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } }
                .onChange(of:store.state["user"]["username"].string) { _,name in
                    if register && !name.isEmpty && name.lowercased() == username.lowercased() { success = true }
                }
        }
    }
}
