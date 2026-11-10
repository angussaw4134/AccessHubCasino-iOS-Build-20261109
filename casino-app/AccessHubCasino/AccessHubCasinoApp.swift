import SwiftUI
import WebKit

@main @MainActor struct AccessHubCasinoApp: App {
    @UIApplicationDelegateAdaptor(AccessHubAppDelegate.self) private var appDelegate
    @StateObject private var store = CasinoStore()
    @StateObject private var hub = HubStore()
    @StateObject private var push = PushCoordinator.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            AppEntryView().environmentObject(store).environmentObject(hub).environmentObject(push).preferredColorScheme(.dark)
                .tint(AH.emerald)
                .onChange(of: phase) { _, phase in
                    if phase == .active { store.resume(); Task { await hub.resume() } } else { store.suspend(); hub.suspend() }
                }
        }
    }
}

struct AppEntryView: View {
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--support-website-smoke") { SupportWebsiteSmokeView() } else { RootView() }
        #else
        RootView()
        #endif
    }
}
#if DEBUG
struct SupportWebsiteSmokeView: View {
    @StateObject private var web = SupportWebModel()
    var body: some View { SupportWebSurface(model:web).task { web.web.load(URLRequest(url:SupportWebModel.base,cachePolicy:.reloadIgnoringLocalCacheData)) } }
}
#endif

struct RootView: View {
    var body: some View { MainTabs() }
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
    @StateObject private var web = SupportWebModel()
    @State private var account = false
    var body: some View {
        ZStack {
            AH.background.ignoresSafeArea()
            SupportWebSurface(model:web).ignoresSafeArea(.container,edges:.bottom)
            if web.loading { ProgressView("Opening support…").padding(24).background(AH.panel,in:RoundedRectangle(cornerRadius:20)) }
            if let error = web.error {
                VStack(spacing:20) { Text("Let’s reconnect.").font(.title2); Text(error).font(.subheadline); Button("Try again") { Task { await web.prepare() } }.buttonStyle(PrimaryButton()); Button("Open sign-in") { web.web.load(URLRequest(url:SupportWebModel.base)) } }.padding(28).background(AH.panel,in:RoundedRectangle(cornerRadius:24)).padding(24)
            }
        }
        .task { web.openAccount = { web.web.load(URLRequest(url:SupportWebModel.base)) }; await web.prepare() }
        .sheet(isPresented:$account) { NavigationStack { SupportAccountView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { account = false } } } } }
    }
}

@MainActor final class SupportWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    static let base = URL(string:"https://accesshub-support-app.fejiofasj.workers.dev")!
    let web: WKWebView
    @Published var loading = true
    @Published var error: String?
    var openAccount: (() -> Void)?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame:.zero,configuration:configuration)
        super.init()
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = UIColor(red:16/255,green:27/255,blue:24/255,alpha:1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.accessibilityIdentifier = "supportWebsite"
    }
    func prepare() async {
        loading = true; error = nil
        // The hosted key login owns authentication. Keep its HttpOnly cookie on-device.
        // Import an older native session once so existing conversations can be linked.
        let cookies = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie],Never>) in
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning:$0) }
        }
        let existing = cookies.contains { $0.name == "__Host-ah-support" && $0.domain == Self.base.host && ($0.expiresDate ?? .distantFuture) > Date() }
        if !existing && !UserDefaults.standard.bool(forKey:"supportWebSessionImported") {
            if let token = SessionVault.read() {
                do {
                    var request = URLRequest(url:Self.base.appendingPathComponent("api/session/restore"))
                    request.httpMethod = "POST"; request.timeoutInterval = 15
                    request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpShouldSetCookies = false
                    let session = URLSession(configuration:configuration)
                    defer { session.finishTasksAndInvalidate() }
                    let (_,response) = try await session.data(for:request)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 200, let value = http.value(forHTTPHeaderField:"Set-Cookie"),
                           let cookie = HTTPCookie.cookies(withResponseHeaderFields:["Set-Cookie":value],for:Self.base).first(where:{$0.name == "__Host-ah-support"}) {
                            await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
                                web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
                            }
                            UserDefaults.standard.set(true,forKey:"supportWebSessionImported")
                        } else if http.statusCode == 401 { UserDefaults.standard.set(true,forKey:"supportWebSessionImported") }
                    }
                } catch { /* The normal website sign-in remains available. */ }
            } else { UserDefaults.standard.set(true,forKey:"supportWebSessionImported") }
        }
        web.load(URLRequest(url:Self.base,cachePolicy:.reloadRevalidatingCacheData))
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { loading = false; error = nil }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { failed(error) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { failed(error) }
    func failed(_ issue:Error) { if (issue as NSError).code != NSURLErrorCancelled { loading = false; error = "Support could not load. Your saved account is unchanged." } }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { Task { await prepare() } }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "https",url.host == Self.base.host,url.port == nil {
            if url.path == "/native/account" { decisionHandler(.cancel); openAccount?(); return }
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated && url.scheme == "https" { UIApplication.shared.open(url) }
    }
}
struct SupportWebSurface: UIViewRepresentable {
    @ObservedObject var model: SupportWebModel
    func makeUIView(context:Context) -> WKWebView { model.web }
    func updateUIView(_ uiView:WKWebView,context:Context) {}
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
