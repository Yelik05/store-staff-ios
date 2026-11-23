import SwiftUI
import Combine
import UIKit

// MARK: - 启动状态

@MainActor
final class AppModel: ObservableObject {
    @Published var checking = true
    @Published var loggedIn = false
    @Published var name = ""
    @Published var role = ""

    private var didBootstrap = false

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if !SessionStore.shared.hasToken {
            checking = false
            loggedIn = false
            return
        }

        do {
            try await AuthRepository.session()
            enter()
        } catch is SessionExpiredError {
            SessionStore.shared.clear()
            checking = false
            loggedIn = false
        } catch let error as APIError where error.code == "NETWORK_ERROR" {
            // 断网时允许用本地缓存进入，首页会提示网络错误。
            enter()
        } catch {
            enter()
        }
    }

    func onLoginSuccess() {
        enter()
    }

    func logout() async {
        await PushRegistry.unregister()
        await AuthRepository.logout()
        checking = false
        loggedIn = false
        name = ""
        role = ""
    }

    func forceLogout() {
        SessionStore.shared.clear()
        checking = false
        loggedIn = false
        name = ""
        role = ""
    }

    private func enter() {
        let storedName = SessionStore.shared.staffName
        name = storedName.isEmpty ? SessionStore.shared.accountName : storedName
        role = SessionStore.shared.role
        checking = false
        loggedIn = true
    }
}

// MARK: - 根视图

struct AppRootView: View {
    @StateObject private var app = AppModel()

    var body: some View {
        Group {
            if app.checking {
                LaunchView()
            } else if !app.loggedIn {
                LoginView(onLoggedIn: { app.onLoginSuccess() })
            } else {
                MainTabView(
                    userName: app.name,
                    role: app.role,
                    onLogout: { Task { await app.logout() } }
                )
            }
        }
        .screenBackground()
        .task { await app.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            app.forceLogout()
        }
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColor.primary)
                .frame(width: 64, height: 64)
                .overlay(
                    Text("塔")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                )
            ProgressView()
                .scaleEffect(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
    }
}

// MARK: - 主框架（底栏四格 + 消息 / 我的覆盖层）

struct MainTabView: View {
    let userName: String
    let role: String
    let onLogout: () -> Void

    @StateObject private var homeModel = HomeViewModel()
    @StateObject private var tasksModel = TasksViewModel()
    @StateObject private var messagesModel = MessagesViewModel()
    @StateObject private var scheduleModel = ScheduleViewModel()
    @StateObject private var expiryModel = ExpiryViewModel()
    @StateObject private var attendanceModel = AttendanceViewModel()
    @StateObject private var salaryModel = SalaryViewModel()
    @StateObject private var scoreModel = ScoreViewModel()
    @StateObject private var reimburseModel = ReimburseViewModel()
    @StateObject private var contactsModel = ContactsViewModel()
    @StateObject private var agendaModel = AgendaViewModel()

    @State private var tab = 0
    @State private var overlay: String?
    @State private var expiryAutoScan = false
    @State private var didHandleInitialRoute = false

    private let tabs: [(String, String, String)] = [
        ("首页", "house", "house.fill"),
        ("任务", "list.bullet.rectangle", "list.bullet.rectangle.fill"),
        ("排班", "calendar", "calendar"),
        ("效期", "shippingbox", "shippingbox.fill")
    ]

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if overlay == nil {
                    bottomBar
                }
            }
            .task {
                await messagesModel.refreshUnread()
                NotifyPoller.shared.start()
                await loopPolling()
            }
            .onAppear(perform: handleInitialRoute)
            .onReceive(NotificationCenter.default.publisher(for: .appOpenRoute)) { note in
                if let route = note.userInfo?["route"] as? String {
                    handleRoute(route)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let overlay = overlay {
            if overlay == "messages" {
                MessagesView(
                    model: messagesModel,
                    onOpenLink: { link, refId, hint in
                        self.overlay = nil
                        openLink(link: link, refId: refId, hint: hint)
                    },
                    onBack: { self.overlay = nil }
                )
            } else if overlay == "attendance" {
                AttendanceView(model: attendanceModel, onBack: { self.overlay = nil })
            } else if overlay == "salary" {
                SalaryView(model: salaryModel, onBack: { self.overlay = nil })
            } else if overlay == "score" {
                ScoreView(model: scoreModel, onBack: { self.overlay = nil })
            } else if overlay == "reimburse" {
                ReimburseView(model: reimburseModel, onBack: { self.overlay = nil })
            } else if overlay == "contacts" {
                ContactsView(model: contactsModel, onBack: { self.overlay = nil })
            } else if overlay == "agenda" {
                AgendaView(model: agendaModel, onBack: { self.overlay = nil })
            } else {
                ProfileView(
                    userName: userName,
                    role: role,
                    onBack: { self.overlay = nil },
                    onLogout: onLogout,
                    onAvatarChanged: {
                        Task { await homeModel.load(refresh: true) }
                    }
                )
            }
        } else {
            switch tab {
            case 1:
                TasksView(model: tasksModel)
            case 2:
                ScheduleView(model: scheduleModel)
            case 3:
                ExpiryView(model: expiryModel, autoOpenScanner: expiryAutoScan, onAutoOpenConsumed: { expiryAutoScan = false })
            default:
                HomeView(
                    model: homeModel,
                    unreadCount: messagesModel.unreadBadge,
                    onOpenSchedule: { tab = 2 },
                    onOpenProfile: { overlay = "profile" },
                    onOpenMessages: { overlay = "messages" },
                    onOpenFeature: { overlay = $0 }
                )
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                let item = tabs[index]
                Button {
                    tab = index
                    overlay = nil
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab == index ? item.2 : item.1)
                                .font(.system(size: 20, weight: .regular))
                            if index == 1 && taskBadge {
                                Circle()
                                    .fill(Sem.bad)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 5, y: -3)
                            }
                        }
                        Text(item.0)
                            .font(.ssCaption)
                            .lineLimit(1)
                    }
                    .foregroundColor(tab == index ? AppColor.primary : AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(AppColor.surface.ignoresSafeArea(edges: .bottom))
        .overlay(
            Rectangle()
                .fill(AppColor.outline)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private var taskBadge: Bool {
        guard let overview = tasksModel.overview else { return false }
        return overview.todayPending > 0 || overview.overdueCount > 0
    }

    // MARK: 路由

    private func handleInitialRoute() {
        guard !didHandleInitialRoute else { return }
        didHandleInitialRoute = true
        if let route = AppDelegate.pendingRoute {
            AppDelegate.pendingRoute = nil
            handleRoute(route)
        }
    }

    private func handleRoute(_ route: String) {
        overlay = nil
        switch route {
        case "tasks":
            tab = 1
        case "schedule", "leave":
            tab = 2
        case "expiry":
            tab = 3
        case "expiryScan":
            tab = 3
            expiryAutoScan = true
        case "messages":
            overlay = "messages"
        case "profile":
            overlay = "profile"
        case "attendance", "salary", "score", "reimburse", "contacts", "agenda":
            overlay = route
        default:
            tab = 0
        }
    }

    private func openLink(link: String, refId: String, hint: String) {
        if link.contains("schedule") || link.contains("leave") {
            tab = 2
        } else if link.contains("expiry") {
            tab = 3
        } else if link.contains("profile") {
            overlay = "profile"
        } else if link.contains("attendance") {
            overlay = "attendance"
        } else if link.contains("salary") {
            overlay = "salary"
        } else if link.contains("score") {
            overlay = "score"
        } else if link.contains("reimburse") {
            overlay = "reimburse"
        } else if link.contains("contacts") {
            overlay = "contacts"
        } else if link.contains("agenda") {
            overlay = "agenda"
        } else if link.contains("tasks") {
            tab = 1
            let ref = parseTaskRef(link: link, refId: refId)
            if !ref.isEmpty || !hint.isEmpty {
                tasksModel.focusTask(ref: ref, titleHint: hint)
            }
        }
    }

    private func parseTaskRef(link: String, refId: String) -> String {
        if let groups = Fmt.regexGroups("[?&]task=(\\d+)", link), groups.count > 1 {
            return groups[1]
        }
        return refId
    }

    /// 前台短轮询 5 分钟；后台由 BGTask 兜底（30 分钟）。
    private func loopPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            if Task.isCancelled { break }
            _ = await NotifyRepository.poll()
            await messagesModel.refreshUnread()
            await homeModel.silentRefresh()
            await tasksModel.silentRefresh()
        }
    }
}

// MARK: - 我的（首页头像进入）

struct ProfileView: View {
    let userName: String
    let role: String
    let onBack: () -> Void
    let onLogout: () -> Void
    let onAvatarChanged: () -> Void

    @State private var notifyEnabled = NotifyPrefs.shared.enabled
    @State private var dndEnabled = NotifyPrefs.shared.dndEnabled
    @State private var showAccountInfo = false
    @State private var showPassword = false
    @State private var showLogoutConfirm = false
    @State private var avatarKey = SessionStore.shared.avatar
    @State private var showAvatarPicker = false
    @State private var avatarBusy = false
    @State private var avatarError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 4) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColor.text)
                            .frame(width: 40, height: 40)
                    }
                    Text("我的")
                        .font(.ssTitle3)
                        .foregroundColor(AppColor.text)
                    Spacer()
                }
                .padding(.top, 4)

                HStack(spacing: 12) {
                    Group {
                        if avatarKey.isEmpty {
                            Circle()
                                .fill(AppColor.primaryContainer)
                                .overlay(
                                    Text(String(userName.prefix(1)))
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(AppColor.primary)
                                )
                        } else {
                            RemoteImage(key: avatarKey, corner: 26, contentMode: .fill)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColor.outline.opacity(0.7), lineWidth: 0.6))
                    .onTapGesture { showAvatarPicker = true }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(userName.isEmpty ? "门店伙伴" : userName)
                            .font(.ssTitle3)
                            .foregroundColor(AppColor.text)
                        Text(roleLabel(role))
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    InfoRow(label: "工号", value: SessionStore.shared.displayEmpNo.isEmpty ? "—" : SessionStore.shared.displayEmpNo)
                    Divider().background(AppColor.outline)
                    InfoRow(label: "岗位", value: SessionStore.shared.position.isEmpty ? "—" : SessionStore.shared.position)
                    Divider().background(AppColor.outline)
                    InfoRow(label: "门店", value: SessionStore.shared.storeName.isEmpty ? "—" : SessionStore.shared.storeName)
                }
                .padding(.horizontal, 16)
                .cardSurface()

                VStack(spacing: 0) {
                    EntryRow(title: "更换头像", subtitle: avatarBusy ? "上传中…" : "从相册选择照片") { showAvatarPicker = true }
                    Divider().background(AppColor.outline).padding(.leading, 16)
                    EntryRow(title: "账号资料", subtitle: "手机号、工号与本次登录") { showAccountInfo = true }
                    Divider().background(AppColor.outline).padding(.leading, 16)
                    EntryRow(title: "修改密码", subtitle: "6—20 位，需包含字母和数字") { showPassword = true }
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: 10) {
                    Text("通知设置")
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                    SwitchRow(title: "接收通知", subtitle: "任务、私信、审批、排班与公告", isOn: $notifyEnabled) {
                        NotifyPrefs.shared.enabled = $0
                    }
                    SwitchRow(title: "免打扰 22:00–08:00", subtitle: "静默期内不弹出，解除后补发", isOn: $dndEnabled) {
                        NotifyPrefs.shared.dndEnabled = $0
                    }
                }
                .padding(16)
                .cardSurface()

                Button {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                        .font(.ssBody14)
                        .foregroundColor(Sem.bad)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                .stroke(Sem.bad.opacity(0.6), lineWidth: 1)
                        )
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .sheet(isPresented: $showAccountInfo) {
            AccountInfoSheet(userName: userName)
        }
        .sheet(isPresented: $showPassword) {
            PasswordSheet(onSuccess: { showPassword = false })
        }
        .sheet(isPresented: $showAvatarPicker) {
            PhotoPicker(limit: 1) { images in
                showAvatarPicker = false
                guard let image = images.first else { return }
                Task { await uploadAvatar(image) }
            }
        }
        .alert("退出登录", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { onLogout() }
        } message: {
            Text("退出后需要重新输入手机号和密码，确定退出吗？")
        }
        .alert("头像更新失败", isPresented: Binding(
            get: { avatarError != nil },
            set: { if !$0 { avatarError = nil } }
        )) {
            Button("好", role: .cancel) { avatarError = nil }
        } message: {
            Text(avatarError ?? "")
        }
    }

    private func uploadAvatar(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            avatarError = "图片处理失败，请换一张"
            return
        }
        avatarBusy = true
        defer { avatarBusy = false }
        do {
            let key = try await UploadRepository.uploadImage(
                data: data,
                filename: "avatar_\(Int(Date().timeIntervalSince1970)).jpg",
                type: "photo"
            )
            try await ProfileRepository.saveAvatar(key: key)
            SessionStore.shared.setAvatar(key)
            avatarKey = key
            onAvatarChanged()
        } catch {
            avatarError = ErrText.readable(error)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.ssBody14)
                .foregroundColor(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(.ssBody14)
                .foregroundColor(AppColor.text)
                .lineLimit(1)
        }
        .padding(.vertical, 9)
    }
}

private struct EntryRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ssBody)
                        .foregroundColor(AppColor.text)
                    Text(subtitle)
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColor.textSecondary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SwitchRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ssBody14)
                    .foregroundColor(AppColor.text)
                Text(subtitle)
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColor.primary)
                .onChange(of: isOn) { value in onChange(value) }
        }
        .padding(.vertical, 8)
    }
}

private struct AccountInfoSheet: View {
    let userName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    let rows: [(String, String)] = [
                        ("姓名", userName),
                        ("手机号", SessionStore.shared.phone.isEmpty ? "—" : SessionStore.shared.phone),
                        ("飞书工号", SessionStore.shared.displayEmpNo.isEmpty ? "待审核" : SessionStore.shared.displayEmpNo),
                        ("岗位", SessionStore.shared.position.isEmpty ? "—" : SessionStore.shared.position),
                        ("门店", SessionStore.shared.storeName.isEmpty ? "—" : SessionStore.shared.storeName),
                        ("本次登录", SessionStore.shared.lastLoginAt.isEmpty ? "—" : Fmt.dateTime(SessionStore.shared.lastLoginAt))
                    ]
                    ForEach(rows.indices, id: \.self) { index in
                        InfoRow(label: rows[index].0, value: rows[index].1)
                        if index < rows.count - 1 {
                            Divider().background(AppColor.outline)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("账号资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct PasswordSheet: View {
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("原密码", text: $oldPassword)
                        .textContentType(.password)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    SecureField("新密码（6—20 位，包含字母和数字）", text: $newPassword)
                        .textContentType(.newPassword)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    SecureField("确认新密码", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    if let error = error {
                        Text(error)
                            .font(.ssCaption)
                            .foregroundColor(Sem.bad)
                    }
                    Button {
                        submit()
                    } label: {
                        Text(submitting ? "保存中…" : "保存")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(submitting)
                    Spacer()
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(submitting)
    }

    private func submit() {
        if oldPassword.isEmpty {
            error = "请输入原密码"
            return
        }
        let validLength = newPassword.count >= 6 && newPassword.count <= 20
        let hasLetter = newPassword.rangeOfCharacter(from: .letters) != nil
        let hasDigit = newPassword.rangeOfCharacter(from: .decimalDigits) != nil
        if !validLength || !hasLetter || !hasDigit {
            error = "新密码需 6—20 位，且包含字母和数字"
            return
        }
        if newPassword != confirmPassword {
            error = "两次输入的新密码不一致"
            return
        }
        if newPassword == oldPassword {
            error = "新密码不能与原密码相同"
            return
        }
        error = nil
        submitting = true
        Task {
            do {
                try await AccountRepository.changePassword(
                    oldPassword: oldPassword,
                    newPassword: newPassword,
                    confirmPassword: confirmPassword
                )
                submitting = false
                dismiss()
                onSuccess()
            } catch {
                submitting = false
                self.error = ErrText.readable(error)
            }
        }
    }
}

func roleLabel(_ role: String) -> String {
    switch role {
    case "super": return "超级管理员"
    case "admin": return "管理员"
    case "manager": return "店长"
    case "staff": return "员工"
    default: return role.isEmpty ? "员工" : role
    }
}
