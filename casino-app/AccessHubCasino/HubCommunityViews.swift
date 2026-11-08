import SwiftUI
import PhotosUI
import UserNotifications

struct CommunityView: View {
    var body: some View {
        HubPage(title:"A good place to meet.",subtitle:"Real conversations. Shared games. A community you shape.") {
            HubLinkCard(title:"Global lounge",detail:"Join the conversation",symbol:"bubble.left.and.bubble.right") { ChatRoomView(channel:"global") }
            HubLinkCard(title:"Announcements",detail:"Updates from the AccessHub team",symbol:"megaphone") { ChatRoomView(channel:"announcements") }
            HubLinkCard(title:"Snake club",detail:"Find opponents and talk tactics",symbol:"gamecontroller") { ChatRoomView(channel:"snake") }
            HubLinkCard(title:"Friends & invitations",detail:"Your people, one tap away",symbol:"person.2") { FriendsView() }
            Panel { VStack(alignment:.leading,spacing:12) {
                Text("Make room for everyone.").font(.headline)
                Text("Keep conversations respectful. Never post passwords, private voucher codes or account details. Block unwanted contact and report messages for staff review.").font(.subheadline).foregroundStyle(AH.muted)
                HubLearningButton(milestone:"community-rules",title:"I've read the community rules")
            } }
        }.toolbar(.hidden,for:.navigationBar)
    }
}

struct HubLearningButton: View {
    @EnvironmentObject var hub: HubStore
    let milestone: String
    let title: String
    @State private var completed = false
    var body: some View {
        Button(completed ? "Learning saved" : title) { Task { completed = await hub.action("learning.complete",["milestone":.string(milestone)]) } }.font(.caption.bold()).foregroundStyle(AH.emerald).disabled(!hub.canAct || completed)
    }
}

struct FriendsView: View {
    @EnvironmentObject var hub: HubStore
    @State private var query = ""
    @State private var filter = "friends"
    @State private var reporting: JSONValue?
    var body: some View {
        HubPage(title:"Better with your people.",subtitle:"Find a member by username. Invitations follow their privacy settings.") {
            HStack { TextField("Search username",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled().fieldStyle(); Button("Search") { Task { await hub.collection("friends",query:query) } }.font(.caption.bold()) }
            Picker("People",selection:$filter) { Text("Friends").tag("friends"); Text("Requests").tag("requests"); Text("Blocked").tag("blocked") }.pickerStyle(.segmented)
            HubStatus(key:"friends")
            if hub.items("friends").isEmpty { EmptyState(title:"Your people will appear here.",detail:"Search for a username or share yours from Profile.") }
            ForEach(hub.items("friends")) { person in
                Panel { VStack(alignment:.leading,spacing:14) {
                    HStack { Circle().fill(AH.emerald.opacity(0.12)).frame(width:42,height:42).overlay(Text(String(person["displayName"].string.prefix(1))).font(.headline)); VStack(alignment:.leading,spacing:4) { Text(person["displayName"].string).font(.headline); Text("@" + person["username"].string).font(.caption).foregroundStyle(AH.muted) }; Spacer(); if person["online"].bool { Text("Online").font(.caption2).foregroundStyle(AH.emerald) } }
                    if person["relationship"].string == "friend" {
                        NavigationLink { SnakeLobbyView(inviteeID:person.id) } label: { Label("Invite to Snake",systemImage:"gamecontroller") }.font(.subheadline)
                        Button("Remove friend") { run("friend.remove",["userId":.string(person.id)]) }.font(.caption).foregroundStyle(AH.muted)
                    } else if person["direction"].string == "incoming" {
                        HStack { Button("Accept") { run("friend.accept",["requestId":person["requestId"]]) }.buttonStyle(PrimaryButton()); Button("Decline") { run("friend.reject",["requestId":person["requestId"]]) }.buttonStyle(PrimaryButton(secondary:true)) }
                    } else if person["relationship"].string == "blocked" {
                        Button("Unblock") { run("user.unblock",["userId":.string(person.id)]) }.font(.subheadline)
                    } else if person["direction"].string == "outgoing" { Text("Request sent").font(.caption).foregroundStyle(AH.muted) }
                    else if person.id != hub.ownerID { Button("Send friend request") { run("friend.request",["userId":.string(person.id)]) }.buttonStyle(PrimaryButton()) }
                    if person.id != hub.ownerID && person["relationship"].string != "blocked" {
                        HStack { Button("Block") { run("user.block",["userId":.string(person.id)]) }; Spacer(); Button("Report") { reporting = person } }.font(.caption).foregroundStyle(AH.muted)
                    }
                }.disabled(!hub.canAct) }
            }
            HubLoadMore(key:"friends")
        }.task(id:filter) { query = ""; await hub.collection("friends",filter:filter) }
        .sheet(item:$reporting) { person in ReportUserView(userID:person.id,name:person["displayName"].string) }
    }
    private func run(_ type: String,_ payload: [String:JSONValue]) {
        Task { if await hub.action(type,payload) { await hub.collection("friends",query:query,filter:filter) } }
    }
}

struct ReportUserView: View {
    @EnvironmentObject var hub: HubStore
    @Environment(\.dismiss) private var dismiss
    let userID: String
    let name: String
    var messageID = ""
    var channel = ""
    @State private var reason = ""
    var body: some View {
        NavigationStack { VStack(alignment:.leading,spacing:20) {
            SectionTitle(title:"Report \(name)",caption:"Your report is private and sent to authorized staff.")
            TextEditor(text:$reason).frame(minHeight:120,maxHeight:220).scrollContentBackground(.hidden).padding(12).background(AH.panel,in:RoundedRectangle(cornerRadius:16))
            Text("Describe what happened (10–1,000 characters).").font(.caption).foregroundStyle(AH.muted)
            Button("Send report") { Task { if await hub.action("user.report",["userId":.string(userID),"reason":.string(reason),"messageId":.string(messageID),"channel":.string(channel)]) { dismiss() } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || reason.count < 10 || reason.count > 1000)
            Spacer()
        }.padding(22).pageBackground().navigationTitle("Report").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}

struct HubSupportView: View {
    @EnvironmentObject var hub: HubStore
    @State private var search = ""
    @State private var creating = false
    var body: some View {
        HubPage(title:"We're here to help.",subtitle:"Your tickets and attachments are private to you and authorized support staff.") {
            Button { creating = true } label: { Label("Start a support ticket",systemImage:"plus.bubble") }.buttonStyle(PrimaryButton()).disabled(!hub.isAvailable)
            TextField("Search help articles",text:$search).fieldStyle().submitLabel(.search).onSubmit { Task { await hub.collection("support/articles",query:search) } }
            HubStatus(key:"support/articles")
            ForEach(hub.items("support/articles")) { article in Panel { DisclosureGroup(article["title"].string) { Text(article["body"].string).font(.subheadline).foregroundStyle(AH.muted).padding(.top,8).frame(maxWidth:.infinity,alignment:.leading) } } }
            SectionTitle(title:"Your conversations")
            HubStatus(key:"support/tickets")
            if hub.items("support/tickets").isEmpty { EmptyState(title:"No tickets yet.",detail:"Start a private conversation when you need a hand.") }
            ForEach(hub.items("support/tickets")) { ticket in
                HubLinkCard(title:ticket["subject"].string,detail:ticket["status"].string.replacingOccurrences(of:"_",with:" ").capitalized + " · " + readableDate(ticket["updatedAt"]),symbol:"bubble.left") { SupportTicketView(ticketID:ticket.id) }
            }
            HubLoadMore(key:"support/tickets")
        }.task { await hub.collection("support/articles"); await hub.collection("support/tickets") }
        .sheet(isPresented:$creating) { NewSupportTicketView() }
    }
}

struct NewSupportTicketView: View {
    @EnvironmentObject var hub: HubStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var category = "account"
    @State private var message = ""
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment:.leading,spacing:20) {
            SectionTitle(title:"Tell us what happened.",caption:"Do not include passwords. Add screenshots after opening your ticket.")
            TextField("Subject",text:$subject).fieldStyle()
            Picker("Category",selection:$category) { Text("Account").tag("account"); Text("Games").tag("game"); Text("Rewards").tag("rewards"); Text("Other").tag("other") }.pickerStyle(.menu)
            TextEditor(text:$message).frame(height:180).scrollContentBackground(.hidden).padding(12).background(AH.panel,in:RoundedRectangle(cornerRadius:16)).accessibilityLabel("Message")
            Button("Send ticket") { Task { if await hub.action("support.create",["subject":.string(subject),"category":.string(category),"body":.string(message)]) { await hub.collection("support/tickets"); dismiss() } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || subject.count < 3 || subject.count > 120 || message.count < 10 || message.count > 5000)
        }.padding(22) }.pageBackground().navigationTitle("New ticket").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}

struct SupportTicketView: View {
    @EnvironmentObject var hub: HubStore
    @EnvironmentObject var store: CasinoStore
    let ticketID: String
    @State private var ticket: JSONValue = .null
    @State private var message = ""
    @State private var error: String?
    @State private var loading = false
    @State private var photo: PhotosPickerItem?
    @State private var attachmentImage: UIImage?
    @State private var showingImage = false
    @State private var uploading = false
    @State private var uploadID = UUID().uuidString
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:18) {
            SectionTitle(title:ticket["subject"].string.isEmpty ? "Private conversation" : ticket["subject"].string,caption:ticket["status"].string.replacingOccurrences(of:"_",with:" ").capitalized)
            if loading { ProgressView() }
            if let error { Text(error).font(.caption).foregroundStyle(AH.danger); Button("Retry") { Task { await load() } } }
            ForEach(ticket["messages"].array) { message in
                Panel { VStack(alignment:.leading,spacing:8) { HStack { Text(message["name"].string).font(.caption.bold()).foregroundStyle(message["author"].string == "customer" ? AH.emerald : AH.gold); Spacer(); Text(readableDate(message["createdAt"])).font(.caption2).foregroundStyle(AH.muted) }; Text(message["body"].string).font(.subheadline).textSelection(.enabled) } }
            }
            ForEach(ticket["attachments"].array) { attachment in
                Button { Task { await open(attachment) } } label: { Label(attachment["name"].string,systemImage:"photo") }.font(.subheadline).disabled(uploading)
            }
            if ticket.exists && ticket["status"].string != "resolved" {
                TextEditor(text:$message).frame(height:110).scrollContentBackground(.hidden).padding(12).background(AH.panel,in:RoundedRectangle(cornerRadius:16)).accessibilityLabel("Reply")
                Button("Send reply") { Task { if await hub.action("support.reply",["ticketId":.string(ticketID),"body":.string(message)]) { message = ""; await load() } } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || message.count > 5000)
                PhotosPicker(selection:$photo,matching:.images) { Label(uploading ? "Uploading screenshot…" : "Attach screenshot",systemImage:"paperclip") }.font(.subheadline).disabled(uploading || !hub.canAct)
                Text("Images only, up to 5 MB. Attachments require account authorization to view.").font(.caption2).foregroundStyle(AH.muted)
                Button("Mark resolved") { Task { if await hub.action("support.resolve",["ticketId":.string(ticketID)]) { await load() } } }.font(.caption).disabled(!hub.canAct)
            }
        }.padding(20) }.pageBackground().navigationTitle("Support").navigationBarTitleDisplayMode(.inline).privacySensitive()
        .task { await load() }.refreshable { await load() }
        .onChange(of:photo) { _,newPhoto in guard let newPhoto else { return }; uploadID = UUID().uuidString; Task { await upload(newPhoto) } }
        .sheet(isPresented:$showingImage) { NavigationStack { Group { if let attachmentImage { Image(uiImage:attachmentImage).resizable().scaledToFit() } }.pageBackground().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { showingImage = false; attachmentImage = nil } } } }
        .onChange(of:hub.ownerID) { _,_ in ticket = .null; attachmentImage = nil; showingImage = false; message = "" }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { ticket = try await hub.fetch("/v2/support/tickets/" + HubStore.escape(ticketID)); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func upload(_ item: PhotosPickerItem) async {
        uploading = true; defer { uploading = false }
        do {
            guard let source = try await item.loadTransferable(type:Data.self), let image = UIImage(data:source), let bytes = image.jpegData(compressionQuality:0.85) else { throw CasinoError.message("This photo could not be opened.") }
            guard bytes.count <= 5*1024*1024 else { throw CasinoError.message("Choose a smaller screenshot, under 5 MB.") }
            _ = try await store.privateData("/v2/support/tickets/\(HubStore.escape(ticketID))/attachments/\(uploadID)",upload:bytes,contentType:"image/jpeg",filename:"Screenshot.jpg")
            photo = nil; await load()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func open(_ attachment: JSONValue) async {
        do { let (data,_) = try await store.privateData("/v2/support/tickets/\(HubStore.escape(ticketID))/attachments/\(HubStore.escape(attachment.id))"); guard let image = UIImage(data:data) else { throw CasinoError.invalidResponse }; attachmentImage = image; showingImage = true }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct NotificationsView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HubPage(title:"Your updates.",subtitle:"Private details stay inside AccessHub.") {
            HubLinkCard(title:"Notification settings",detail:"Categories, quiet hours and device push",symbol:"slider.horizontal.3") { NotificationPreferencesView() }
            if !hub.items("notifications").isEmpty { Button("Mark all read") { Task { if await hub.action("notification.readAll") { await hub.collection("notifications") } } }.font(.caption.bold()).disabled(!hub.canAct) }
            HubStatus(key:"notifications")
            if hub.items("notifications").isEmpty { EmptyState(title:"All quiet here.",detail:"Friend invitations, support replies and rewards appear here as they happen.") }
            ForEach(hub.items("notifications")) { notification in
                Button { Task { await hub.openNotification(notification) } } label: {
                    Panel { HStack(alignment:.top,spacing:12) { Circle().fill(notification["readAt"].exists ? AH.muted.opacity(0.2) : AH.emerald).frame(width:7,height:7).padding(.top,6); VStack(alignment:.leading,spacing:7) { Text(notification["title"].string).font(.headline); Text(notification["body"].string).font(.subheadline).foregroundStyle(AH.muted); Text(readableDate(notification["createdAt"])).font(.caption2).foregroundStyle(AH.muted) }; Spacer(minLength:0) } }
                }.buttonStyle(.plain).disabled(!hub.canAct)
            }
            HubLoadMore(key:"notifications")
        }.task { await hub.collection("notifications") }
    }
}

struct NotificationPreferencesView: View {
    @EnvironmentObject var hub: HubStore
    @EnvironmentObject var push: PushCoordinator
    @State private var prefs: JSONValue = .null
    @State private var categories: [String:Bool] = [:]
    @State private var enabled = false
    @State private var quietStart = "22:00"
    @State private var quietEnd = "08:00"
    @State private var limit = 10
    @State private var error: String?
    private let names = ["friend","snake","support","giveaway","voucher","marketplace","daily","service"]
    var body: some View {
        HubPage(title:"Updates on your terms.") {
            Panel { VStack(alignment:.leading,spacing:14) {
                Text("Device push").font(.headline)
                Text(push.status).font(.caption).foregroundStyle(AH.muted)
                if push.capable && hub.bootstrap["push"]["available"].bool {
                    Button("Enable on this iPhone") { Task { await push.requestPermission(hub:hub) } }.buttonStyle(PrimaryButton())
                    Toggle("Allow push notifications",isOn:$enabled)
                } else { Text("This installation does not have a configured push identity. Your in-app inbox remains available.").font(.caption).foregroundStyle(AH.gold) }
                Button("Open iPhone notification settings") { if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.caption)
            } }
            Panel { VStack(alignment:.leading,spacing:16) { Text("Categories").font(.headline); ForEach(names,id:\.self) { name in Toggle(name.capitalized,isOn:Binding(get:{ categories[name] ?? true },set:{ categories[name] = $0 })) } } }
            Panel { VStack(alignment:.leading,spacing:14) {
                Text("Quiet hours").font(.headline)
                HStack { TextField("22:00",text:$quietStart).fieldStyle(); Text("to"); TextField("08:00",text:$quietEnd).fieldStyle() }
                Text("24-hour times in \(TimeZone.current.identifier). Quiet hours apply to push, not your inbox.").font(.caption).foregroundStyle(AH.muted)
                Stepper("Up to \(limit) push updates per day",value:$limit,in:1...50).font(.subheadline)
            } }
            if let error { Text(error).font(.caption).foregroundStyle(AH.danger) }
            Button("Save notification settings") { Task {
                let fields: [String:JSONValue] = ["pushEnabled":.bool(enabled && push.capable),"categories":.object(categories.mapValues(JSONValue.bool)),"quietStart":.string(quietStart),"quietEnd":.string(quietEnd),"timezone":.string(TimeZone.current.identifier),"maxPerDay":.number(Double(limit))]
                if await hub.action("notification.preferences",fields) { error = nil }
            } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || !validTime(quietStart) || !validTime(quietEnd))
        }.task {
            do { prefs = try await hub.fetch("/v2/notifications/preferences"); enabled = prefs["pushEnabled"].bool; quietStart = prefs["quietStart"].string; quietEnd = prefs["quietEnd"].string; limit = max(1,prefs["maxPerDay"].int); categories = prefs["categories"].object.mapValues(\.bool) }
            catch { self.error = error.localizedDescription }
            await push.refreshStatus()
        }
    }
    private func validTime(_ value: String) -> Bool { value.range(of:"^([01][0-9]|2[0-3]):[0-5][0-9]$",options:.regularExpression) != nil }
}

struct HubProgressView: View {
    @EnvironmentObject var hub: HubStore
    var body: some View {
        HubPage(title:"More ways to make it yours.",subtitle:"Hub cosmetic progression is earned through community learning. Casino progress stays separate.") {
            Panel { VStack(alignment:.leading,spacing:16) {
                Text("HUB LEVEL \(max(1,hub.profile["level"].int))").font(.caption.bold()).tracking(1.5).foregroundStyle(AH.emerald)
                Text("\(hub.profile["hubXP"].int) cosmetic XP").font(.title2.bold())
                ProgressView(value:Double(hub.profile["hubXP"].int % 100),total:100).tint(AH.emerald)
                Text("Cosmetic boosts do not change game speed, collisions, payouts or reward eligibility.").font(.caption).foregroundStyle(AH.muted)
            } }
            Panel { VStack(alignment:.leading,spacing:16) {
                Text("Learn your way around").font(.headline)
                Text("Hub Points are separate from casino credits. Giveaways are free; marketplace purchases exchange points for cosmetic ownership.").font(.subheadline).foregroundStyle(AH.muted)
                HubLearningButton(milestone:"rewards-basics",title:"Complete rewards introduction")
                HubLearningButton(milestone:"marketplace-basics",title:"Complete marketplace introduction")
            } }
            HubLinkCard(title:"Your inventory",detail:"Equip your collection",symbol:"square.stack.3d.up") { InventoryView() }
            HubLinkCard(title:"Casino progress & rakeback",detail:"Your existing milestones and credit rewards",symbol:"chart.bar.xaxis") { ProgressScreen() }
        }
    }
}

struct HubProfileSettingsView: View {
    @EnvironmentObject var hub: HubStore
    @State private var displayName = ""
    @State private var online = true
    @State private var invites = "friends"
    @State private var publicWinners = false
    @State private var avatar = "emerald"
    var body: some View {
        HubPage(title:"Your community profile.") {
            TextField("Display name",text:$displayName).fieldStyle()
            Picker("Avatar",selection:$avatar) { ForEach(["emerald","jade","orbit","comet","diamond","serpent"],id:\.self) { Text($0.capitalized).tag($0) } }
            Toggle("Show my online status",isOn:$online)
            Picker("Who can invite me",selection:$invites) { Text("Friends").tag("friends"); Text("Everyone").tag("all"); Text("No one").tag("none") }
            Toggle("Show my name in public giveaway results",isOn:$publicWinners)
            Button("Save profile") { Task {
                guard await hub.action("profile.update",["displayName":.string(displayName),"avatar":.string(avatar)]) else { return }
                _ = await hub.action("privacy.update",["showOnline":.bool(online),"invites":.string(invites),"publicWinners":.bool(publicWinners)])
            } }.buttonStyle(PrimaryButton()).disabled(!hub.canAct || displayName.count < 2 || displayName.count > 32)
        }.onAppear { displayName = hub.profile["displayName"].string; online = hub.profile["privacy"]["showOnline"].bool; invites = hub.profile["privacy"]["invites"].string; publicWinners = hub.profile["privacy"]["publicWinners"].bool; if ["emerald","jade","orbit","comet","diamond","serpent"].contains(hub.profile["avatar"].string) { avatar = hub.profile["avatar"].string } }
    }
}
