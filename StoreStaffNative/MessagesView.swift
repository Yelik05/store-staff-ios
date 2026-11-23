import SwiftUI

// MARK: - ViewModel

@MainActor
final class MessagesViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case all, system, task, privateThreads

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "全部"
            case .system: return "系统"
            case .task: return "任务"
            case .privateThreads: return "私信"
            }
        }

        var apiScope: String {
            switch self {
            case .system: return "system"
            case .task: return "task"
            default: return "all"
            }
        }
    }

    @Published var scope: Scope = .all
    @Published var page = 1
    @Published var items: [MessageItem] = []
    @Published var total = 0
    @Published var totalPages = 1
    @Published var threads: [ThreadItem] = []
    @Published var unreadAll = 0
    @Published var unreadSystem = 0
    @Published var unreadTask = 0
    @Published var threadUnread = 0
    @Published var unreadBadge = 0
    @Published var loading = true
    @Published var loadingMore = false
    @Published var error: String?
    @Published var flash: Flash?
    @Published var conversation: MessageThread?
    @Published var conversationLoading = false
    @Published var sending = false

    private var listInFlight = false

    func load(reset: Bool = true) async {
        if listInFlight { return }
        listInFlight = true
        if reset {
            page = 1
            loading = true
            error = nil
        }
        do {
            if scope == .privateThreads {
                let (list, unread) = try await MessageRepository.threads()
                threads = list
                threadUnread = unread
                items = []
                total = list.count
                totalPages = 1
            } else {
                let data = try await MessageRepository.list(scope: scope.apiScope, page: page)
                if reset {
                    items = data.items
                } else {
                    let existing = Set(items.map { $0.id })
                    items.append(contentsOf: data.items.filter { !existing.contains($0.id) })
                }
                total = data.total
                totalPages = data.totalPages
                if data.unreadAll > 0 || data.unreadSystem > 0 || data.unreadTask > 0 {
                    unreadAll = data.unreadAll
                    unreadSystem = data.unreadSystem
                    unreadTask = data.unreadTask
                }
            }
            unreadBadge = unreadAll + threadUnread
            loading = false
            loadingMore = false
        } catch is SessionExpiredError {
            loading = false
            loadingMore = false
        } catch {
            loading = false
            loadingMore = false
            self.error = ErrText.readable(error)
        }
        listInFlight = false
    }

    func refreshUnread() async {
        if let count = try? await MessageRepository.unreadCount() {
            unreadBadge = count
        }
    }

    func setScope(_ value: Scope) async {
        scope = value
        await load(reset: true)
    }

    func nextPage() async {
        guard page < totalPages, !loadingMore else { return }
        page += 1
        loadingMore = true
        await load(reset: false)
    }

    func previousPage() async {
        guard page > 1, !loadingMore else { return }
        page -= 1
        loadingMore = true
        await load(reset: false)
    }

    func markAllRead() async {
        do {
            try await MessageRepository.markAllRead()
            unreadAll = 0
            unreadSystem = 0
            unreadTask = 0
            unreadBadge = threadUnread
            items = items.map { item in
                var copy = item
                copy.read = true
                return copy
            }
            await load(reset: true)
            flash = Flash(text: "已全部标记为已读")
        } catch {
            flash = Flash(text: ErrText.readable(error), error: true)
        }
    }

    func openMessage(_ item: MessageItem) async {
        if item.type == "private" {
            let peerId = item.threadId.isEmpty ? item.refId : item.threadId
            if !peerId.isEmpty {
                await openThread(peerId: peerId, fallbackName: item.title)
            }
            return
        }
        if item.read { return }
        do {
            try await MessageRepository.markRead(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].read = true
            }
            unreadAll = max(0, unreadAll - 1)
            if item.type == "system" { unreadSystem = max(0, unreadSystem - 1) }
            if item.type == "task" { unreadTask = max(0, unreadTask - 1) }
            unreadBadge = max(0, unreadBadge - 1)
        } catch {
            // 已读失败不阻断查看。
        }
    }

    func openThread(peerId: String, fallbackName: String = "") async {
        conversationLoading = true
        error = nil
        do {
            let thread = try await MessageRepository.thread(peerId: peerId)
            var loaded = thread
            if loaded.peerName.isEmpty { loaded.peerName = fallbackName }
            conversation = loaded
            conversationLoading = false
            if let index = threads.firstIndex(where: { $0.peerId == peerId }) {
                let unread = threads[index].unread
                threads[index].unread = 0
                threadUnread = max(0, threadUnread - unread)
                unreadBadge = max(0, unreadBadge - unread)
            }
            await refreshUnread()
        } catch is SessionExpiredError {
            conversationLoading = false
        } catch {
            conversationLoading = false
            flash = Flash(text: ErrText.readable(error), error: true)
        }
    }

    func closeConversation() async {
        conversation = nil
        await load(reset: true)
    }

    func send(_ body: String) async -> Bool {
        guard let thread = conversation else { return false }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return false }
        sending = true
        do {
            let sent = try await MessageRepository.send(toStaffId: thread.peerId, body: text)
            var messages = conversation?.messages ?? []
            if let sent = sent {
                if !messages.contains(where: { $0.id == sent.id && !sent.id.isEmpty }) {
                    messages.append(sent)
                }
            } else {
                messages.append(
                    MessageItem(
                        id: "local:\(UUID().uuidString)",
                        type: "private",
                        title: "",
                        body: text,
                        link: "",
                        refId: thread.peerId,
                        read: true,
                        createdAt: isoNow(),
                        threadId: thread.peerId,
                        isMine: true
                    )
                )
            }
            conversation?.messages = messages
            sending = false
            if let index = threads.firstIndex(where: { $0.peerId == thread.peerId }) {
                threads[index].lastText = text
                threads[index].lastAt = isoNow()
                threads[index].lastIsMine = true
            }
            return true
        } catch {
            sending = false
            flash = Flash(text: ErrText.readable(error), error: true)
            return false
        }
    }

    func clearFlash() { flash = nil }

    private func isoNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

// MARK: - 页面

struct MessagesView: View {
    @ObservedObject var model: MessagesViewModel
    let onOpenLink: (String, String, String) -> Void
    let onBack: () -> Void

    @State private var detail: MessageItem?
    @State private var showAnnouncements = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let conversation = model.conversation {
                ConversationView(
                    model: model,
                    thread: conversation,
                    onBack: {
                        Task { await model.closeConversation() }
                    }
                )
            } else {
                inbox
            }
            if let flash = model.flash {
                ToastBanner(flash: flash)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        model.clearFlash()
                    }
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .task {
            if model.items.isEmpty && model.threads.isEmpty {
                await model.load(reset: true)
            }
        }
        .sheet(item: $detail) { item in
            MessageDetailSheet(item: item) {
                if !item.link.isEmpty {
                    detail = nil
                    onOpenLink(item.link, item.refId, item.title)
                }
            }
        }
        .sheet(isPresented: $showAnnouncements) {
            AnnouncementsView()
        }
    }

    private var inbox: some View {
        VStack(spacing: 0) {
            header
            scopeTabs
            content
            pager
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.text)
                    .frame(width: 40, height: 40)
            }
            Text("消息通知")
                .font(.ssTitle3)
                .foregroundColor(AppColor.text)
            Spacer()
            Button {
                showAnnouncements = true
            } label: {
                Text("公告")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                            .stroke(AppColor.outline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            if model.scope != .privateThreads {
                Button {
                    Task { await model.markAllRead() }
                } label: {
                    Text("全部已读")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColor.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                                .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 4)
    }

    private var scopeTabs: some View {
        HStack(spacing: 4) {
            ForEach(MessagesViewModel.Scope.allCases) { scope in
                Button {
                    Task { await model.setScope(scope) }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Text(scope.label)
                                .font(.system(size: 13, weight: model.scope == scope ? .semibold : .regular))
                            let badge = badgeCount(scope)
                            if badge > 0 {
                                Text("\(badge)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Sem.bad)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(model.scope == scope ? AppColor.primary : AppColor.textSecondary)
                        Rectangle()
                            .fill(model.scope == scope ? AppColor.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func badgeCount(_ scope: MessagesViewModel.Scope) -> Int {
        switch scope {
        case .system: return model.unreadSystem
        case .task: return model.unreadTask
        case .privateThreads: return model.threadUnread
        case .all: return model.unreadAll
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error {
            ErrorStateView(message: error) {
                Task { await model.load(reset: true) }
            }
            Spacer()
        } else if model.scope == .privateThreads {
            threadList
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.items.isEmpty {
                    EmptyStateView(title: "暂无消息", hint: "新的系统通知和任务通知会出现在这里。")
                }
                ForEach(model.items) { item in
                    Button {
                        detail = item
                        Task { await model.openMessage(item) }
                    } label: {
                        MessageRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != model.items.last?.id {
                        Divider().background(AppColor.outlineVariant).padding(.leading, 16)
                    }
                }
                Spacer().frame(height: 12)
            }
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.threads.isEmpty {
                    EmptyStateView(title: "暂无私信", hint: "可从通讯录或员工主页发起会话。")
                }
                ForEach(model.threads) { thread in
                    Button {
                        Task { await model.openThread(peerId: thread.peerId, fallbackName: thread.peerName) }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(AppColor.primaryContainer)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(thread.peerName.prefix(1)))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppColor.primary)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(thread.peerName.isEmpty ? "同事" : thread.peerName)
                                        .font(.ssBody14)
                                        .foregroundColor(AppColor.text)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(Fmt.time(thread.lastAt))
                                        .font(.ssCaption)
                                        .foregroundColor(AppColor.textSecondary)
                                }
                                HStack(spacing: 6) {
                                    Text((thread.lastIsMine ? "我：" : "") + thread.lastText)
                                        .font(.ssSmall)
                                        .foregroundColor(AppColor.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if thread.unread > 0 {
                                        Text("\(thread.unread)")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Sem.bad)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if thread.id != model.threads.last?.id {
                        Divider().background(AppColor.outlineVariant).padding(.leading, 64)
                    }
                }
                Spacer().frame(height: 12)
            }
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var pager: some View {
        if model.scope != .privateThreads && model.totalPages > 1 {
            HStack(spacing: 12) {
                Button("上一页") {
                    Task { await model.previousPage() }
                }
                .font(.ssSmall)
                .foregroundColor(model.page > 1 ? AppColor.primary : AppColor.textSecondary.opacity(0.5))
                .disabled(model.page <= 1 || model.loadingMore)

                Text("第 \(model.page)/\(model.totalPages) 页 · 共 \(model.total) 条")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)

                Button("下一页") {
                    Task { await model.nextPage() }
                }
                .font(.ssSmall)
                .foregroundColor(model.page < model.totalPages ? AppColor.primary : AppColor.textSecondary.opacity(0.5))
                .disabled(model.page >= model.totalPages || model.loadingMore)
            }
            .padding(.vertical, 8)
        }
    }
}

struct MessageRow: View {
    let item: MessageItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.read ? Color.clear : Sem.bad)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "通知" : item.title)
                        .font(.system(size: 14, weight: item.read ? .regular : .semibold))
                        .foregroundColor(AppColor.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(Fmt.time(item.createdAt))
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                }
                Text(item.body)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - 详情

struct MessageDetailSheet: View {
    let item: MessageItem
    let onOpenLink: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title.isEmpty ? "通知" : item.title)
                        .font(.ssTitle3)
                        .foregroundColor(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Fmt.dateTime(item.createdAt))
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    Divider().background(AppColor.outline)
                    Text(item.body)
                        .font(.ssBody)
                        .foregroundColor(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.link.isEmpty {
                        Button(action: onOpenLink) {
                            Text("查看相关")
                                .font(.ssBody14)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AppColor.primary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("消息详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 私信会话

struct ConversationView: View {
    @ObservedObject var model: MessagesViewModel
    let thread: MessageThread
    let onBack: () -> Void

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(thread.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: thread.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .background(AppColor.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.text)
                    .frame(width: 40, height: 40)
            }
            Circle()
                .fill(AppColor.primaryContainer)
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(thread.peerName.prefix(1)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColor.primary)
                )
            Text(thread.peerName.isEmpty ? "同事" : thread.peerName)
                .font(.ssBody14)
                .foregroundColor(AppColor.text)
            Spacer()
            if model.conversationLoading {
                ProgressView().scaleEffect(0.7).padding(.trailing, 12)
            }
        }
        .padding(.vertical, 4)
        .background(AppColor.surface)
        .overlay(Rectangle().fill(AppColor.outline).frame(height: 0.5), alignment: .bottom)
    }

    private func bubble(_ message: MessageItem) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .font(.ssBody14)
                    .foregroundColor(message.isMine ? .white : AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isMine ? AppColor.primary : AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Text(Fmt.time(message.createdAt))
                    .font(.system(size: 9))
                    .foregroundColor(AppColor.textSecondary)
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("发消息…")
                        .font(.ssBody14)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                }
                GrowingTextView(text: $draft, focused: $inputFocused)
                    .frame(minHeight: 36, maxHeight: 96)
            }
            .padding(.horizontal, 2)
            .background(AppColor.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

            Button {
                send()
            } label: {
                Text(model.sending ? "…" : "发送")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColor.primary.opacity(0.4) : AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColor.surface)
        .overlay(Rectangle().fill(AppColor.outline).frame(height: 0.5), alignment: .top)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            _ = await model.send(text)
        }
    }
}

/// 可自增高的多行输入（iOS 15 无 TextField(axis:)）。
struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = UIFont.systemFont(ofSize: 15)
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.delegate = context.coordinator
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if focused.wrappedValue && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
        uiView.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            textView.invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - 公告

struct AnnouncementsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [NoticeInfo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var detail: NoticeInfo?

    var body: some View {
        NavigationView {
            Group {
                if loading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error, items.isEmpty {
                    ErrorStateView(message: error) { Task { await load() } }
                    Spacer()
                } else if items.isEmpty {
                    EmptyStateView(title: "暂无公告", hint: "门店公告发布后会显示在这里。")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { notice in
                                Button {
                                    open(notice)
                                } label: {
                                    NoticeRow(notice: notice)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("门店公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { if items.isEmpty { await load() } }
            .sheet(item: $detail) { notice in
                NoticeDetailSheet(notice: notice)
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            items = try await NoticeRepository.list()
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    private func open(_ notice: NoticeInfo) {
        detail = notice
        guard !notice.read else { return }
        Task {
            try? await NoticeRepository.markRead(id: notice.id)
            if let index = items.firstIndex(where: { $0.id == notice.id }) {
                items[index].read = true
            }
        }
    }
}

private struct NoticeRow: View {
    let notice: NoticeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if notice.pinned {
                    Text("置顶")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColor.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.primaryContainer)
                        .clipShape(Capsule())
                }
                if notice.important {
                    Text("重要")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Sem.bad)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Sem.badTint)
                        .clipShape(Capsule())
                }
                Text(notice.title.isEmpty ? "门店公告" : notice.title)
                    .font(.ssBody14)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColor.text)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if !notice.read {
                    Circle().fill(AppColor.primary).frame(width: 7, height: 7)
                }
            }
            Text(noticePlainText(notice.body))
                .font(.ssSmall)
                .foregroundColor(AppColor.textSecondary)
                .lineLimit(2)
            Text([notice.publisher, Fmt.dateTime(notice.publishAt)]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct NoticeDetailSheet: View {
    let notice: NoticeInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(notice.title.isEmpty ? "门店公告" : notice.title)
                        .font(.ssTitle3)
                        .foregroundColor(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([notice.publisher, Fmt.dateTime(notice.publishAt)]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    Divider().background(AppColor.outline)
                    Text(noticePlainText(notice.body))
                        .font(.ssBody)
                        .foregroundColor(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("公告详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private func noticePlainText(_ html: String) -> String {
    var text = html
    text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&#39;": "'"
    ]
    for (key, value) in entities {
        text = text.replacingOccurrences(of: key, with: value)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
