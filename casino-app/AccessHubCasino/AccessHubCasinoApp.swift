import SwiftUI

@main @MainActor struct AccessHubCasinoApp: App {
    @UIApplicationDelegateAdaptor(AccessHubAppDelegate.self) private var appDelegate
    @StateObject private var store = CasinoStore()
    @StateObject private var hub = HubStore()
    @StateObject private var push = PushCoordinator.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(hub).environmentObject(push).preferredColorScheme(.dark)
                .tint(AH.emerald)
                .onChange(of: phase) { _, phase in
                    if phase == .active { store.resume(); Task { await hub.resume() } } else { store.suspend(); hub.suspend() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    @EnvironmentObject var push: PushCoordinator
    @State private var launching = true
    var body: some View {
        ZStack {
            AH.background.ignoresSafeArea()
            if store.authenticated { MainTabs() }
            else { WelcomeView() }
            if launching {
                ZStack { AH.background.ignoresSafeArea(); VStack(spacing:24) { Brand(); Rectangle().fill(AH.emerald).frame(width:32,height:2); Text("SUPPORT & ADD-ONS").font(.caption2).tracking(3).foregroundStyle(AH.muted) } }
                    .transition(.opacity).zIndex(10)
            }
        }
        .task {
            async let launch: Void = store.launch()
            try? await Task.sleep(for:.milliseconds(800))
            withAnimation(store.reducedMotion ? nil : .easeOut(duration:0.45)) { launching = false }
            await launch
        }
        .task(id:store.state["user"]["id"].string + ":" + String(store.sessionRevision)) {
            await hub.attach(store)
            await push.attach(hub:hub,casino:store)
            if let id = push.pendingNotificationID { await push.open(id:id,hub:hub) }
        }
        .onChange(of:push.pendingNotificationID) { _,id in if let id { Task { await push.open(id:id,hub:hub) } } }
        .alert("AccessHub", isPresented: Binding(get:{ store.error != nil },set:{ if !$0 { store.error = nil } })) {
            Button("OK",role:.cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var signingIn = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Brand().padding(.top,24)
                    Image(systemName:"bubble.left.and.bubble.right.fill").font(.system(size:64)).foregroundStyle(AH.emerald).frame(maxWidth:.infinity).frame(height:max(150,min(geometry.size.height*0.26,220))).background(AH.panel,in:RoundedRectangle(cornerRadius:26))
                    VStack(alignment:.leading,spacing:10) {
                        Text("WELCOME TO ACCESSHUB").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(AH.emerald)
                        Text("Support, simplified.").font(.system(size:34,weight:.medium,design:.serif))
                        Text("Your conversations and add-ons, together in one place.").font(.subheadline).foregroundStyle(AH.muted)
                    }
                    VStack(spacing:12) {
                        Button {
                            if store.needsSignIn && !store.canRestoreGuest { signingIn = true }
                            else { Task { await store.guest() } }
                        } label: {
                            HStack {
                                if store.busy || store.connecting { ProgressView().tint(AH.background) }
                                Text(store.connecting ? "Restoring your session…" : store.busy ? "Opening your account…" : store.needsSignIn ? (store.canRestoreGuest ? "Restore guest access" : "Sign in to your account") : "Enter as guest")
                                Spacer(); Image(systemName:"arrow.right")
                            }
                        }.buttonStyle(PrimaryButton()).disabled(store.busy || store.connecting).accessibilityIdentifier("enterGuest")
                        Button("Sign in") { signingIn = true }.font(.subheadline.weight(.medium)).padding(8)
                    }
                    Text("Use your existing AccessHub account to keep your conversations together.").font(.caption).foregroundStyle(AH.muted).fixedSize(horizontal:false,vertical:true)
                }.padding(24).frame(minHeight:geometry.size.height,alignment:.top)
            }
        }.sheet(isPresented:$signingIn) { AccountView(register:false) }.pageBackground()
    }
}

struct MainTabs: View {
    @EnvironmentObject var store: CasinoStore
    @EnvironmentObject var hub: HubStore
    @State private var signIn = false
    var body: some View {
        TabView(selection:$store.selectedTab) {
            NavigationStack { HubSupportView().toolbar(.hidden,for:.navigationBar) }.tabItem { Label("Support",systemImage:"bubble.left.and.bubble.right") }.tag(0)
            NavigationStack { AddOnsView() }.tabItem { Label("Add-ons",systemImage:"square.stack.3d.up") }.tag(1)
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
            .sheet(item:$hub.destination) { destination in HubDestinationSheet(destination:destination) }
            .alert("AccessHub",isPresented:Binding(get:{ hub.error != nil },set:{ if !$0 { hub.error = nil } })) { Button("OK",role:.cancel) { hub.error = nil } } message: { Text(hub.error ?? "") }
            .safeAreaInset(edge:.bottom,spacing:0) {
                if hub.pending != nil { HStack { Text("Confirming your saved Hub request").font(.caption); Spacer(); Button("Retry") { Task { await hub.retry() } }.font(.caption.bold()).disabled(hub.busy) }.padding(12).background(AH.raised).foregroundStyle(AH.gold) }
            }
    }
}

struct HubDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: HubDestination
    var body: some View {
        NavigationStack { content.toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } } }
    }
    @ViewBuilder private var content: some View {
        switch destination {
        case .profile: SupportAccountView()
        case .ticket(let id): SupportTicketView(ticketID:id)
        default: HubSupportView()
        }
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
                    SectionTitle(title:register ? "Keep your place." : "Welcome back.",caption:register ? "Save this guest account and its conversations for your other devices." : "Sign in to access your existing conversations.")
                    if success {
                        Panel { VStack(alignment:.leading,spacing:14) { Label("Account saved",systemImage:"checkmark.circle.fill").foregroundStyle(AH.emerald); Text(store.notice ?? "Your account is ready."); Button("Continue") { dismiss() }.buttonStyle(PrimaryButton()) } }
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
            }.pageBackground().navigationTitle(register ? "Save account" : "Sign in").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } }
                .onChange(of:store.state["user"]["username"].string) { _,name in
                    if register && !name.isEmpty && name.lowercased() == username.lowercased() { success = true }
                }
        }
    }
}


struct AddOnsView: View {
    var body: some View {
        HubPage(title:"Add-ons") {
            Panel(padding:24) {
                VStack(alignment:.leading,spacing:24) {
                    Image(systemName:"square.stack.3d.up.fill")
                        .font(.system(size:30)).foregroundStyle(AH.emerald)
                        .frame(width:64,height:64).background(AH.emerald.opacity(0.10),in:RoundedRectangle(cornerRadius:18))
                    Text("Scannable app").font(.title2.weight(.semibold))
                    (Text("$2.99").font(.system(size:36,weight:.semibold,design:.rounded)) + Text(" / month").font(.subheadline))
                        .accessibilityLabel("2 dollars and 99 cents per month")
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.accessibilityIdentifier("scannableAddon")
        }.toolbar(.hidden,for:.navigationBar)
    }
}

struct SupportAccountView: View {
    @EnvironmentObject var store: CasinoStore
    @State private var register = false
    @State private var login = false
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                SectionTitle(title:store.state["user"]["isGuest"].bool ? "Your guest account" : store.state["user"]["username"].string)
                Panel { VStack(alignment:.leading,spacing:14) {
                    Text("Account ID").font(.headline)
                    Text(store.state["user"]["id"].string).font(.system(.caption,design:.monospaced)).textSelection(.enabled).accessibilityIdentifier("profileAccountID")
                    Button(copied ? "Copied" : "Copy account ID") { UIPasteboard.general.string = store.state["user"]["id"].string; copied = true }.accessibilityIdentifier("copyAccountID")
                } }
                if store.state["user"]["isGuest"].bool {
                    Panel { VStack(alignment:.leading,spacing:16) {
                        Text("Keep your conversations").font(.headline)
                        Text("Save your guest account to sign in on another device.").font(.subheadline).foregroundStyle(AH.muted)
                        Button("Save my account") { register = true }.buttonStyle(PrimaryButton()).disabled(!store.canAct)
                        Button("Sign in to an existing account") { login = true }.disabled(store.busy || store.pending != nil)
                    } }
                }
                Panel { VStack(alignment:.leading,spacing:22) {
                    Button("Sign out") { confirmLogout = true }.disabled(!store.canAct)
                    Button("Delete account and data",role:.destructive) { confirmDelete = true }.disabled(!store.canAct)
                } }
            }.padding(22)
        }.pageBackground().navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$register) { AccountView(register:true) }
        .sheet(isPresented:$login) { AccountView(register:false) }
        .alert("Sign out?",isPresented:$confirmLogout) {
            Button("Cancel",role:.cancel) {}
            Button("Sign out",role:.destructive) { Task { await store.endSession() } }
        } message: { Text(store.state["user"]["isGuest"].bool ? "Save this guest account first if you want to return to its conversations." : "Your conversations will be available when you sign in again.") }
        .alert("Delete your account?",isPresented:$confirmDelete) {
            Button("Cancel",role:.cancel) {}
            Button("Delete permanently",role:.destructive) { Task { await store.endSession(delete:true) } }
        } message: { Text("This permanently removes account access and saved data. Audit records are retained. This cannot be undone.") }
    }
}
