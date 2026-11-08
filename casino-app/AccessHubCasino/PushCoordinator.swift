import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Security

@MainActor final class PushCoordinator: ObservableObject {
    static let shared = PushCoordinator()
    @Published var status = "Checking notification settings…"
    @Published var pendingNotificationID: String?
    private var token: String?
    private var boundOwner = ""
    private weak var hub: HubStore?
    private let installationID: String
    let capable: Bool
    let environment: String
    init() {
        let key = "accesshub.push.installation.v1"
        if let saved = UserDefaults.standard.string(forKey:key) { installationID = saved }
        else { installationID = UUID().uuidString; UserDefaults.standard.set(installationID,forKey:key) }
        // The default loader build has no APNs entitlement. Owner-signed builds
        // explicitly opt in using Push.xcconfig and a matching provisioning profile.
        environment = Bundle.main.object(forInfoDictionaryKey:"AccessHubPushEnvironment") as? String ?? ""
        capable = (Bundle.main.object(forInfoDictionaryKey:"AccessHubPushEnabled") as? String == "YES") && ["development","production"].contains(environment)
    }
    func attach(hub: HubStore,casino: CasinoStore) async {
        self.hub = hub
        if boundOwner != hub.ownerID { boundOwner = "" }
        casino.beforeSessionEnd = { [weak self,weak hub] in
            guard let self,let hub,!self.boundOwner.isEmpty else { return }
            guard await hub.action("push.unregister",["installationId":.string(self.installationID)]) else { throw CasinoError.message("Reconnect to unlink push notifications before signing out.") }
            self.boundOwner = ""
        }
        await refreshStatus()
        if capable, hub.bootstrap["push"]["available"].bool {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus) { UIApplication.shared.registerForRemoteNotifications() }
        }
        if let token { await bind(token) }
    }
    func refreshStatus() async {
        guard capable else { status = "Device push is unavailable in this loader build."; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized,.provisional,.ephemeral: status = boundOwner.isEmpty ? "Permission granted. Waiting for secure device registration." : "This iPhone is registered for push updates."
        case .denied: status = "Notifications are disabled in iPhone Settings."
        case .notDetermined: status = "Choose whether AccessHub can send updates to this iPhone."
        @unknown default: status = "Notification permission is unavailable."
        }
    }
    func requestPermission(hub: HubStore) async {
        guard capable,hub.bootstrap["push"]["available"].bool else { status = "Push is not configured for this installation."; return }
        do {
            if try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound]) {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await refreshStatus()
        } catch { status = error.localizedDescription }
    }
    func registered(_ bytes: Data) async { token = bytes.map { String(format:"%02x",$0) }.joined(); if let token { await bind(token) } }
    private func bind(_ token: String) async {
        guard capable,let hub,hub.canAct,hub.bootstrap["push"]["available"].bool else { return }
        let owner = hub.ownerID
        let registered = await hub.action("push.register",["installationId":.string(installationID),"token":.string(token),"topic":.string(Bundle.main.bundleIdentifier ?? "app.accesshub.casino"),"environment":.string(environment)])
        if registered && owner == hub.ownerID { boundOwner = owner; status = "This iPhone is registered for push updates." }
    }
    func failed(_ message: String) { status = "Device registration failed: " + message }
    func open(id: String,hub: HubStore) async {
        guard !id.isEmpty, !hub.ownerID.isEmpty else { return }
        do {
            let notification = try await hub.fetch("/v2/notifications/" + HubStore.escape(id))
            await hub.openNotification(notification)
            pendingNotificationID = nil
        } catch is CancellationError {} catch { hub.error = "This notification is unavailable for the signed-in account."; pendingNotificationID = nil }
    }
}

final class AccessHubAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushCoordinator.shared.registered(deviceToken) }
    }
    func application(_ application: UIApplication,didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushCoordinator.shared.failed(error.localizedDescription) }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,didReceive response: UNNotificationResponse,withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["notificationId"] as? String ?? ""
        Task { @MainActor in PushCoordinator.shared.pendingNotificationID = id; completionHandler() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,willPresent notification: UNNotification,withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground updates are shown by the authorized in-app inbox, avoiding
        // a lock-screen-style preview leaking across an account switch.
        completionHandler([])
    }
}
