import SwiftUI
import PhotosUI
import UIKit

// MARK: - 筛选与归档

enum TaskFilter: String, CaseIterable, Identifiable {
    case all, daily, weekly, monthly, once, mine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .daily: return "日"
        case .weekly: return "周"
        case .monthly: return "月"
        case .once: return "次"
        case .mine: return "个人"
        }
    }

    var cycle: String? {
        switch self {
        case .all, .mine: return nil
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .once: return "once"
        }
    }
}

enum ArchiveKind {
    case overdue, completed
}

struct ArchiveState: Identifiable {
    let id = UUID()
    var kind: ArchiveKind
    var loading = true
    var items: [TaskItem] = []
    var counts: [String: Int] = [:]
    var date = Fmt.today()
    var today = Fmt.today()
    var error: String?
}

// MARK: - ViewModel

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var loading = true
    @Published var refreshing = false
    @Published var overview: TaskOverview?
    @Published var error: String?

    @Published var filter: TaskFilter = .all
    @Published var expanded: Set<String> = []
    @Published var visibleCount = 10
    @Published var actionBusy = false
    @Published var uploadDone = 0
    @Published var uploadTotal = 0
    @Published var contacts: [TaskContact]?
    @Published var contactsLoading = false
    @Published var flash: Flash?
    @Published var completedSignal = 0
    @Published var focusEntryKey: String?
    @Published var archive: ArchiveState?

    private var listInFlight = false
    private var focusRef: String = ""
    private var focusHint: String = ""
    private var archiveTask: Task<Void, Never>?

    func load(refresh: Bool = false) async {
        if listInFlight { return }
        listInFlight = true
        if overview == nil { loading = true }
        refreshing = refresh
        error = nil
        do {
            let fresh = try await TaskRepository.overview()
            let target = focusTarget(fresh, ref: focusRef, titleHint: focusHint)
            overview = fresh
            expanded.formUnion(target.keys)
            if let key = target.entryKey { focusEntryKey = key }
            loading = false
            refreshing = false
        } catch is SessionExpiredError {
            loading = false
            refreshing = false
        } catch {
            loading = false
            refreshing = false
            self.error = ErrText.readable(error)
        }
        listInFlight = false
    }

    func silentRefresh() async {
        guard let fresh = try? await TaskRepository.overview() else { return }
        overview = fresh
    }

    func setFilter(_ value: TaskFilter) {
        filter = value
        visibleCount = 10
    }

    func toggleExpanded(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
    }

    func collapseAll() {
        expanded = []
    }

    func loadMore() {
        visibleCount += 10
    }

    func focusTask(ref: String, titleHint: String = "") {
        let target = overview.map { focusTarget($0, ref: ref, titleHint: titleHint) }
        filter = .all
        visibleCount = 9999
        if let target = target {
            expanded.formUnion(target.keys)
            focusEntryKey = target.entryKey
        }
        focusRef = ref
        focusHint = titleHint
    }

    func clearFlash() {
        flash = nil
    }

    // MARK: 操作

    func completeConfirm(_ item: TaskItem) async {
        guard !actionBusy else { return }
        actionBusy = true
        do {
            try await TaskRepository.submit(id: item.id, imageKeys: [])
            actionSucceeded("任务已完成")
        } catch {
            actionFailed(error)
        }
    }

    func manageComplete(_ item: TaskItem) async {
        guard !actionBusy else { return }
        actionBusy = true
        do {
            try await TaskRepository.manageComplete(id: item.id)
            actionSucceeded("已代完成，记录已保存")
        } catch {
            actionFailed(error)
        }
    }

    func completeWithImages(_ item: TaskItem, images: [UIImage]) async {
        guard !actionBusy else { return }
        guard !images.isEmpty else {
            flash = Flash(text: "请至少选择 1 张返图", error: true)
            return
        }
        actionBusy = true
        uploadTotal = images.count
        uploadDone = 0
        do {
            var keys: [String] = []
            for (index, image) in images.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.85) else {
                    throw APIError(code: "UPLOAD_FAIL", message: "图片处理失败，请重新选择")
                }
                let filename = "task_\(Int(Date().timeIntervalSince1970))_\(index).jpg"
                let key = try await UploadRepository.uploadImage(data: data, filename: filename)
                keys.append(key)
                uploadDone = index + 1
            }
            try await TaskRepository.submit(id: item.id, imageKeys: keys)
            actionSucceeded("返图已提交，等待审核")
        } catch {
            actionFailed(error)
        }
        uploadTotal = 0
        uploadDone = 0
    }

    func loadContacts() async {
        if contacts != nil || contactsLoading { return }
        contactsLoading = true
        do {
            contacts = try await TaskRepository.contacts()
            contactsLoading = false
        } catch is SessionExpiredError {
            contactsLoading = false
        } catch {
            contactsLoading = false
            flash = Flash(text: "员工列表加载失败，请重试", error: true)
        }
    }

    func reassign(id: Int?, groupId: String?, assigneeId: String, assigneeName: String) async {
        guard !actionBusy else { return }
        actionBusy = true
        do {
            try await TaskRepository.reassign(id: id, groupId: groupId, assigneeId: assigneeId)
            actionSucceeded("已指派给 \(assigneeName)")
        } catch {
            actionFailed(error)
        }
    }

    // MARK: 逾期 / 已完成

    func openArchive(_ kind: ArchiveKind) {
        let today = (overview?.today.isEmpty == false ? overview!.today : Fmt.today())
        archive = ArchiveState(kind: kind, loading: true, date: today, today: today)
        fetchArchive(kind: kind, date: today)
    }

    func closeArchive() {
        archiveTask?.cancel()
        archive = nil
    }

    func archiveRetry() {
        guard let archive = archive else { return }
        fetchArchive(kind: archive.kind, date: archive.date)
    }

    func shiftArchiveDate(_ days: Int) {
        guard var archive = archive else { return }
        guard let todayDate = Fmt.date(from: archive.today), let current = Fmt.date(from: archive.date) else { return }
        let target = Calendar.current.date(byAdding: .day, value: days, to: current) ?? current
        if target > todayDate { return }
        if let earliest = Calendar.current.date(byAdding: .day, value: -30, to: todayDate), target < earliest { return }
        archive.date = Fmt.localDateString(target)
        archive.loading = true
        archive.error = nil
        self.archive = archive
        fetchArchive(kind: archive.kind, date: archive.date)
    }

    private func fetchArchive(kind: ArchiveKind, date: String) {
        archiveTask?.cancel()
        archiveTask = Task {
            do {
                let result = kind == .overdue ? try await TaskRepository.overdue() : try await TaskRepository.completed(date: date)
                guard var current = archive, current.kind == kind, current.date == date else { return }
                current.loading = false
                current.items = result.items
                current.counts = result.counts
                current.error = nil
                archive = current
            } catch is SessionExpiredError {
                if var current = archive {
                    current.loading = false
                    archive = current
                }
            } catch {
                guard var current = archive, current.kind == kind else { return }
                current.loading = false
                current.error = ErrText.readable(error)
                archive = current
            }
        }
    }

    // MARK: 内部

    private func actionSucceeded(_ text: String) {
        actionBusy = false
        flash = Flash(text: text)
        completedSignal += 1
        Task {
            await load(refresh: true)
            if let archive = archive {
                fetchArchive(kind: archive.kind, date: archive.date)
            }
        }
    }

    private func actionFailed(_ error: Error) {
        actionBusy = false
        flash = Flash(text: ErrText.readable(error), error: true)
    }

    private struct FocusTarget {
        var keys: Set<String> = []
        var entryKey: String?
    }

    private func focusTarget(_ overview: TaskOverview, ref: String, titleHint: String) -> FocusTarget {
        guard !ref.isEmpty || !titleHint.isEmpty else { return FocusTarget() }
        let number = Int(ref)

        func matchesId(_ task: TaskItem) -> Bool {
            if let number = number { return task.id == number }
            return !ref.isEmpty && task.templateId == ref
        }
        func matchesHint(_ task: TaskItem) -> Bool {
            guard !titleHint.isEmpty else { return false }
            return task.title.contains(titleHint) || titleHint.contains(task.title)
        }

        if let item = overview.items.first(where: { matchesId($0) }) {
            return FocusTarget(keys: ["t:\(item.id)"], entryKey: "t:\(item.id)")
        }
        if let item = overview.items.first(where: { matchesHint($0) }) {
            return FocusTarget(keys: ["t:\(item.id)"], entryKey: "t:\(item.id)")
        }
        for group in overview.groups {
            let groupHit = (number == nil && !ref.isEmpty && group.parentId == ref)
                || group.children.contains(where: { matchesId($0) })
                || (!titleHint.isEmpty && (group.title.contains(titleHint) || titleHint.contains(group.title)))
                || group.children.contains(where: { matchesHint($0) })
            if groupHit {
                var keys: Set<String> = ["g:\(group.parentId)|\(group.periodDate)"]
                if let child = group.children.first(where: { matchesId($0) }) ?? group.children.first(where: { matchesHint($0) }) {
                    keys.insert("t:\(child.id)")
                }
                return FocusTarget(keys: keys, entryKey: "g:\(group.parentId)|\(group.periodDate)")
            }
        }
        return FocusTarget()
    }
}

// MARK: - 列表项

enum TaskEntry: Identifiable {
    case group(TaskGroup)
    case item(TaskItem)

    var id: String {
        switch self {
        case .group(let group): return "g:\(group.parentId)|\(group.periodDate)"
        case .item(let item): return "t:\(item.id)"
        }
    }

    var periodDate: String {
        switch self {
        case .group(let group): return group.periodDate
        case .item(let item): return item.periodDate
        }
    }

    var title: String {
        switch self {
        case .group(let group): return group.title
        case .item(let item): return item.title
        }
    }
}

func buildEntries(_ overview: TaskOverview, filter: TaskFilter) -> [TaskEntry] {
    let myId = overview.myStaffId
    let today = overview.today.isEmpty ? Fmt.today() : overview.today
    let groups = overview.groups.filter { group in
        // 已完成分组整组隐藏；服务端只返回当前及最近一期，无需按日期硬切。
        guard !group.done else { return false }
        switch filter {
        case .all:
            return true
        case .mine:
            return group.children.contains { !$0.assigneeId.isEmpty && $0.assigneeId == myId }
        default:
            return group.cycle == filter.cycle || group.children.contains { $0.cycle == filter.cycle }
        }
    }
    let items = overview.items.filter { item in
        // 未到执行日与已完成/已提交的单任务不进入主列表，历史记录走归档。
        guard item.periodDate <= today, !taskCompleted(item.status) else { return false }
        return taskMatches(item, filter: filter, myId: myId)
    }
    let entries = groups.map { TaskEntry.group($0) } + items.map { TaskEntry.item($0) }
    return entries.sorted { left, right in
        if left.periodDate == right.periodDate { return left.title < right.title }
        return left.periodDate > right.periodDate
    }
}

func taskCompleted(_ status: String) -> Bool {
    ["approved", "done", "completed", "finished"].contains(status.lowercased())
}

func taskMatches(_ item: TaskItem, filter: TaskFilter, myId: String) -> Bool {
    switch filter {
    case .all:
        return true
    case .mine:
        return !item.assigneeId.isEmpty && item.assigneeId == myId
    default:
        return item.cycle == filter.cycle
    }
}

// MARK: - 任务页

struct TasksView: View {
    @ObservedObject var model: TasksViewModel

    @State private var submitTarget: TaskItem?
    @State private var confirmTarget: TaskItem?
    @State private var reassignTarget: ReassignTarget?
    @State private var previewTarget: PreviewTarget?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let archive = model.archive {
                ArchiveView(
                    archive: archive,
                    myStaffId: model.overview?.myStaffId ?? "",
                    canManage: model.overview?.canManage ?? false,
                    actionBusy: model.actionBusy,
                    onBack: { model.closeArchive() },
                    onRetry: { model.archiveRetry() },
                    onShiftDate: { model.shiftArchiveDate($0) },
                    onComplete: handleComplete,
                    onReassign: openReassign,
                    onPreview: { previewTarget = PreviewTarget(key: $0) },
                    onManage: { item in Task { await model.manageComplete(item) } }
                )
            } else {
                mainList
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
            if model.overview == nil { await model.load() }
        }
        .onChange(of: model.completedSignal) { signal in
            if signal > 0 {
                submitTarget = nil
                confirmTarget = nil
                reassignTarget = nil
            }
        }
        .sheet(item: $submitTarget) { item in
            SubmitDialog(
                item: item,
                busy: model.actionBusy,
                uploadDone: model.uploadDone,
                uploadTotal: model.uploadTotal,
                onCancel: { if !model.actionBusy { submitTarget = nil } },
                onConfirm: { images in
                    Task { await model.completeWithImages(item, images: images) }
                }
            )
        }
        .sheet(item: $reassignTarget) { target in
            ReassignDialog(
                target: target,
                contacts: model.contacts,
                loading: model.contactsLoading,
                busy: model.actionBusy,
                onCancel: { if !model.actionBusy { reassignTarget = nil } },
                onConfirm: { contact in
                    Task { await model.reassign(id: target.taskId, groupId: target.groupId, assigneeId: contact.id, assigneeName: contact.displayName) }
                }
            )
        }
        .sheet(item: $previewTarget) { target in
            ImagePreviewSheet(key: target.key)
        }
        .alert("确认完成", isPresented: Binding(
            get: { confirmTarget != nil },
            set: { if !$0 { confirmTarget = nil } }
        )) {
            Button("取消", role: .cancel) { confirmTarget = nil }
            Button("确认完成") {
                if let item = confirmTarget {
                    confirmTarget = nil
                    Task { await model.completeConfirm(item) }
                }
            }
        } message: {
            Text("确认将「\(confirmTarget?.title ?? "")」标记为完成？该任务无需返图，确认后不可撤销。")
        }
    }

    private var mainList: some View {
        VStack(spacing: 0) {
            header
            filterRow
            if model.loading && model.overview == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.overview == nil {
                ErrorStateView(message: model.error ?? "加载失败") {
                    Task { await model.load(refresh: true) }
                }
            } else {
                taskList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("我的任务")
                    .font(.ssTitle)
                    .foregroundColor(AppColor.text)
                Text("今日待完成 \(model.overview?.todayPending ?? 0) 项" + ((model.overview?.overdueCount ?? 0) > 0 ? " · 逾期 \(model.overview?.overdueCount ?? 0) 项" : ""))
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            EntryChip(
                text: (model.overview?.overdueCount ?? 0) > 0 ? "逾期 \(model.overview?.overdueCount ?? 0)" : "逾期",
                highlight: (model.overview?.overdueCount ?? 0) > 0
            ) { model.openArchive(.overdue) }
            EntryChip(text: "已完成", highlight: false) { model.openArchive(.completed) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskFilter.allCases) { filter in
                    let selected = model.filter == filter
                    Button {
                        model.setFilter(filter)
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selected ? AppColor.primary : AppColor.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? AppColor.primaryContainer : AppColor.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    private var taskList: some View {
        let entries = buildEntries(model.overview ?? TaskOverview(), filter: model.filter)
        let visible = Array(entries.prefix(model.visibleCount))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if visible.isEmpty {
                        EmptyStateView(title: "暂无待完成任务", hint: emptyHint)
                    }
                    ForEach(visible) { entry in
                        switch entry {
                        case .group(let group):
                            GroupCardView(
                                group: group,
                                expanded: model.expanded.contains(entry.id),
                                canManage: model.overview?.canManage ?? false,
                                myStaffId: model.overview?.myStaffId ?? "",
                                actionBusy: model.actionBusy,
                                onToggle: { model.toggleExpanded(entry.id) },
                                onComplete: handleComplete,
                                onReassign: openReassign,
                                onReassignGroup: { openGroupReassign($0) },
                                onPreview: { previewTarget = PreviewTarget(key: $0) },
                                onManage: { item in Task { await model.manageComplete(item) } }
                            )
                            .id(entry.id)
                        case .item(let item):
                            SingleCardView(
                                item: item,
                                expanded: model.expanded.contains(entry.id),
                                canManage: model.overview?.canManage ?? false,
                                myStaffId: model.overview?.myStaffId ?? "",
                                actionBusy: model.actionBusy,
                                onToggle: { model.toggleExpanded(entry.id) },
                                onComplete: handleComplete,
                                onReassign: openReassign,
                                onPreview: { previewTarget = PreviewTarget(key: $0) },
                                onManage: { item in Task { await model.manageComplete(item) } }
                            )
                            .id(entry.id)
                        }
                    }
                    if entries.count > visible.count {
                        LoadMoreRow(remaining: entries.count - visible.count) { model.loadMore() }
                    }
                    Button {
                        Task { await model.load(refresh: true) }
                    } label: {
                        Text(model.refreshing ? "刷新中…" : "刷新")
                            .font(.ssBody14)
                            .foregroundColor(AppColor.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: model.focusEntryKey) { key in
                guard let key = key else { return }
                withAnimation {
                    proxy.scrollTo(key, anchor: .top)
                }
            }
        }
    }

    private var emptyHint: String {
        switch model.filter {
        case .mine: return "当前没有指派给你的个人任务。"
        case .all: return "当前没有待完成任务，或今天的任务都已完成。"
        default: return "「\(model.filter.label)」分类下暂无待完成任务，可切换其他分类查看。"
        }
    }

    private func handleComplete(_ item: TaskItem) {
        if item.completionMode == "confirm" {
            confirmTarget = item
        } else {
            submitTarget = item
        }
    }

    private func openReassign(_ item: TaskItem) {
        Task { await model.loadContacts() }
        reassignTarget = ReassignTarget(
            taskId: item.id,
            groupId: nil,
            currentId: item.assigneeId,
            subject: "任务：\(item.title) · \(Fmt.execDate(item.periodDate)) · 当前指派：\(completerText(item))",
            hint: "指派后该任务的全部未完成期次归新指派人；已提交待审核或已完成的任务不受影响。",
            title: "指派任务"
        )
    }

    private func openGroupReassign(_ group: TaskGroup) {
        Task { await model.loadContacts() }
        reassignTarget = ReassignTarget(
            taskId: nil,
            groupId: group.parentId,
            currentId: group.defaultAssigneeId,
            subject: "分组：\(group.title) · 期间 \(Fmt.execDate(group.periodDate)) · 组默认：\(group.defaultAssigneeDisplayName.isEmpty ? "公共分组" : group.defaultAssigneeDisplayName)",
            hint: "只同步未单独指定的子任务；单独指定过的子任务保持不变。已提交待审核或已完成的期次不受影响。",
            title: "改派整组"
        )
    }
}

// MARK: - 小部件

struct EntryChip: View {
    let text: String
    let highlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(highlight ? Sem.bad : AppColor.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(highlight ? Sem.badTint : AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单任务卡

struct SingleCardView: View {
    let item: TaskItem
    let expanded: Bool
    let canManage: Bool
    let myStaffId: String
    let actionBusy: Bool
    let onToggle: () -> Void
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onPreview: (String) -> Void
    let onManage: (TaskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.title)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StatusBadge(text: statusText(item), kind: statusKind(item.status))
                }
                MetaLine(label: "截止", value: Fmt.deadline(item.deadlineText))
                MetaLine(label: "完成人", value: completerText(item))
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if expanded {
                Divider().background(AppColor.outline)
                SingleDetailView(
                    item: item,
                    myStaffId: myStaffId,
                    canManage: canManage,
                    actionBusy: actionBusy,
                    onComplete: onComplete,
                    onReassign: onReassign,
                    onPreview: onPreview,
                    onManage: onManage
                )
            }
        }
        .cardSurface()
    }
}

struct SingleDetailView: View {
    let item: TaskItem
    let myStaffId: String
    let canManage: Bool
    let actionBusy: Bool
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onPreview: (String) -> Void
    let onManage: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.content.isEmpty {
                Text(item.content)
                    .font(.ssBody14)
                    .foregroundColor(AppColor.text)
            }
            if !item.sampleImages.isEmpty {
                SampleRowView(images: item.sampleImages, onPreview: onPreview)
            }
            let tags = detailTags(item)
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.ssCaption)
                                .foregroundColor(AppColor.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColor.surfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
                        }
                    }
                }
            }
            if item.status == "rejected" {
                Text("驳回原因：\(item.rejectReason.isEmpty ? "未填写" : item.rejectReason)")
                    .font(.ssSmall)
                    .foregroundColor(Sem.bad)
            }
            if item.completionScope == "all" && !item.missingNames.isEmpty {
                let names = item.missingNames.prefix(4).joined(separator: "、")
                    + (item.missingNames.count > 4 ? " 等 \(item.missingNames.count) 人" : "")
                Text("未完成：\(names)")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            if !item.images.isEmpty {
                Text("已提交返图")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.images, id: \.self) { key in
                            RemoteImage(key: key, corner: Radius.badge, onTap: { onPreview(key) })
                                .frame(width: 52, height: 52)
                        }
                    }
                }
            }
            TaskActionRow(
                item: item,
                myStaffId: myStaffId,
                canManage: canManage,
                compact: false,
                actionBusy: actionBusy,
                onComplete: onComplete,
                onReassign: onReassign,
                onManage: onManage
            )
        }
        .padding(14)
    }
}

// MARK: - 分组卡

struct GroupCardView: View {
    let group: TaskGroup
    let expanded: Bool
    let canManage: Bool
    let myStaffId: String
    let actionBusy: Bool
    let onToggle: () -> Void
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onReassignGroup: (TaskGroup) -> Void
    let onPreview: (String) -> Void
    let onManage: (TaskItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(group.title)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if group.done {
                        StatusBadge(text: "已完成", kind: .ok)
                    } else {
                        StatusBadge(text: "进度 \(group.progressText.isEmpty ? "0/\(group.total)" : group.progressText)", kind: .warn)
                    }
                }
                MetaLine(label: "截止", value: groupDeadline(group))
                MetaLine(label: "完成人", value: group.defaultAssigneeDisplayName.isEmpty ? "公共任务" : group.defaultAssigneeDisplayName)
                if !group.children.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(group.children.prefix(3)) { child in
                            HStack(spacing: 6) {
                                Dot(color: AppColor.outline, size: 4)
                                Text("\(child.title) · \(statusText(child))")
                                    .font(.ssSmall)
                                    .foregroundColor(AppColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        if group.children.count > 3 {
                            Text("等 \(group.children.count) 项子任务")
                                .font(.ssCaption)
                                .foregroundColor(Sem.neutral)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if expanded {
                Divider().background(AppColor.outline)
                VStack(alignment: .leading, spacing: 8) {
                    if !group.content.isEmpty {
                        Text(group.content)
                            .font(.ssBody14)
                            .foregroundColor(AppColor.text)
                    }
                    let busy = group.children.contains { unfinishedStatus.contains($0.status) }
                    if canManage && busy {
                        Button {
                            onReassignGroup(group)
                        } label: {
                            Text("改派整组")
                                .font(.ssBody14)
                                .foregroundColor(AppColor.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                        .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if group.children.isEmpty {
                        Text("该分组暂无可执行子任务。")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    } else {
                        ForEach(group.children.indices, id: \.self) { index in
                            if index > 0 {
                                Divider().background(AppColor.outlineVariant)
                            }
                            ChildRowView(
                                child: group.children[index],
                                myStaffId: myStaffId,
                                canManage: canManage,
                                actionBusy: actionBusy,
                                onComplete: onComplete,
                                onReassign: onReassign,
                                onPreview: onPreview,
                                onManage: onManage
                            )
                        }
                    }
                }
                .padding(14)
            }
        }
        .cardSurface()
    }
}

struct ChildRowView: View {
    let child: TaskItem
    let myStaffId: String
    let canManage: Bool
    let actionBusy: Bool
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onPreview: (String) -> Void
    let onManage: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(child.title)
                    .font(.ssBody)
                    .foregroundColor(AppColor.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(text: statusText(child), kind: statusKind(child.status))
            }
            Text("截止 \(Fmt.deadline(child.deadlineText)) · 完成人 \(completerText(child))")
                .font(.ssSmall)
                .foregroundColor(AppColor.textSecondary)
            if !child.content.isEmpty {
                Text(child.content)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.text)
            }
            if !child.sampleImages.isEmpty {
                SampleRowView(images: child.sampleImages, onPreview: onPreview)
            }
            TaskActionRow(
                item: child,
                myStaffId: myStaffId,
                canManage: canManage,
                compact: true,
                actionBusy: actionBusy,
                onComplete: onComplete,
                onReassign: onReassign,
                onManage: onManage
            )
        }
    }
}

// MARK: - 操作行

struct TaskActionRow: View {
    let item: TaskItem
    let myStaffId: String
    let canManage: Bool
    let compact: Bool
    let actionBusy: Bool
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onManage: (TaskItem) -> Void

    @State private var confirmingManage = false

    private var unfinished: Bool { unfinishedStatus.contains(item.status) }
    private var isMine: Bool { item.assigneeId.isEmpty || item.assigneeId == myStaffId }
    private var canManageComplete: Bool { canManage && unfinished && !isMine && !item.assigneeId.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if canManage && unfinished {
                OutlineSmallButton(title: item.assigneeId.isEmpty ? "指派" : "改派") { onReassign(item) }
            }
            if canManageComplete {
                OutlineSmallButton(title: "代完成") { confirmingManage = true }
            }
            if unfinished && isMine {
                Button {
                    onComplete(item)
                } label: {
                    Text(completeButtonTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(actionBusy)
            } else if unfinished && !canManageComplete {
                Text("已指派给 \(item.assigneeDisplayName.isEmpty ? "其他同事" : item.assigneeDisplayName)")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            } else if item.status == "submitted" {
                Text("已由 \(item.submitterName.isEmpty ? "同事" : item.submitterName) 提交，待审核")
                    .font(.ssSmall)
                    .foregroundColor(Sem.info)
            } else if !unfinished {
                Text("已完成")
                    .font(.ssSmall)
                    .foregroundColor(Sem.ok)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, compact ? 6 : 4)
        .alert("代完成任务", isPresented: $confirmingManage) {
            Button("取消", role: .cancel) {}
            Button("确认代完成") {
                onManage(item)
            }
        } message: {
            Text("确认将「\(item.title)」标记为完成？代完成不进入审核，会记录操作人与原执行人\(item.assigneeDisplayName.isEmpty ? "" : "（\(item.assigneeDisplayName)）")。")
        }
    }

    private var completeButtonTitle: String {
        if item.completionMode == "confirm" { return "标记完成" }
        if item.status == "overdue" { return "补交返图" }
        if item.status == "rejected" { return "重新提交" }
        return "上传返图"
    }
}

struct OutlineSmallButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColor.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 逾期 / 已完成

struct ArchiveView: View {
    let archive: ArchiveState
    let myStaffId: String
    let canManage: Bool
    let actionBusy: Bool
    let onBack: () -> Void
    let onRetry: () -> Void
    let onShiftDate: (Int) -> Void
    let onComplete: (TaskItem) -> Void
    let onReassign: (TaskItem) -> Void
    let onPreview: (String) -> Void
    let onManage: (TaskItem) -> Void

    @State private var expandedId: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColor.text)
                        .frame(width: 40, height: 40)
                }
                Text(archive.kind == .overdue ? "逾期任务" : "已完成任务")
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.text)
                Spacer()
                Text("共 \(archive.items.count) 项")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.trailing, 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if archive.kind == .completed {
                HStack {
                    Button("前一天") { onShiftDate(-1) }
                        .font(.ssBody14)
                        .foregroundColor(AppColor.primary)
                    Spacer()
                    Text(Fmt.execDate(archive.date) + (archive.date == archive.today ? "（今天）" : ""))
                        .font(.ssBody14)
                        .foregroundColor(AppColor.text)
                    Spacer()
                    Button("后一天") { onShiftDate(1) }
                        .font(.ssBody14)
                        .foregroundColor(archive.date < archive.today ? AppColor.primary : AppColor.textSecondary.opacity(0.5))
                        .disabled(archive.date >= archive.today)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            if archive.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = archive.error {
                ErrorStateView(message: error, onRetry: onRetry)
                Spacer()
            } else if archive.items.isEmpty {
                EmptyStateView(
                    title: archive.kind == .overdue ? "没有逾期任务" : "当天没有已完成任务",
                    hint: archive.kind == .overdue ? "已过截止时间且未完成的任务会出现在这里。" : "可切换日期查看其他日期的完成记录。"
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(archive.items) { item in
                            SingleCardView(
                                item: item,
                                expanded: expandedId == item.id,
                                canManage: canManage,
                                myStaffId: myStaffId,
                                actionBusy: actionBusy,
                                onToggle: { expandedId = expandedId == item.id ? nil : item.id },
                                onComplete: onComplete,
                                onReassign: onReassign,
                                onPreview: onPreview,
                                onManage: onManage
                            )
                        }
                        Spacer().frame(height: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - 指派弹窗

struct ReassignTarget: Identifiable {
    let id = UUID()
    var taskId: Int?
    var groupId: String?
    var currentId: String
    var subject: String
    var hint: String
    var title: String
}

struct ReassignDialog: View {
    let target: ReassignTarget
    let contacts: [TaskContact]?
    let loading: Bool
    let busy: Bool
    let onCancel: () -> Void
    let onConfirm: (TaskContact) -> Void

    @State private var selectedId = ""

    private var candidates: [TaskContact] {
        (contacts ?? []).filter { $0.id != target.currentId }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(target.subject)
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if candidates.isEmpty {
                        Text("没有可指派的其他在职员工")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    } else {
                        ForEach(candidates) { contact in
                            Button {
                                selectedId = contact.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedId == contact.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedId == contact.id ? AppColor.primary : AppColor.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.displayName)
                                            .font(.ssBody14)
                                            .foregroundColor(AppColor.text)
                                        if !contact.position.isEmpty {
                                            Text(contact.position)
                                                .font(.ssCaption)
                                                .foregroundColor(AppColor.textSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(target.hint)
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 6)
                    Button {
                        if let contact = candidates.first(where: { $0.id == selectedId }) {
                            onConfirm(contact)
                        }
                    } label: {
                        Text(busy ? "提交中…" : "确认")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(selectedId.isEmpty || busy ? AppColor.primary.opacity(0.5) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(selectedId.isEmpty || busy)
                    .padding(.top, 10)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(busy)
                }
            }
        }
    }
}

// MARK: - 返图提交

struct SubmitDialog: View {
    let item: TaskItem
    let busy: Bool
    let uploadDone: Int
    let uploadTotal: Int
    let onCancel: () -> Void
    let onConfirm: ([UIImage]) -> Void

    @State private var selected: [UIImage] = []
    @State private var showPicker = false
    @State private var confirming = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                    if !item.content.isEmpty {
                        Text(item.content)
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    if !item.sampleImages.isEmpty {
                        SampleRowView(images: item.sampleImages, onPreview: { _ in })
                    }
                    Text("最多 9 张，支持 JPG / PNG / WEBP / GIF，单张不超过 20MB。")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 4)

                    Button {
                        showPicker = true
                    } label: {
                        Text(selected.isEmpty ? "选择图片" : "继续添加（\(selected.count)/9）")
                            .font(.ssBody14)
                            .foregroundColor(AppColor.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                    .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || selected.count >= 9)

                    if !selected.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selected.indices, id: \.self) { index in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selected[index])
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
                                        Button {
                                            selected.remove(at: index)
                                        } label: {
                                            Text("×")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(width: 18, height: 18)
                                                .background(Color.black.opacity(0.55))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(busy)
                                    }
                                }
                            }
                        }
                    }

                    if busy {
                        Text(uploadTotal > 0 ? "正在上传 \(uploadDone)/\(uploadTotal)…" : "提交中…")
                            .font(.ssSmall)
                            .foregroundColor(Sem.info)
                    }

                    Button {
                        confirming = true
                    } label: {
                        Text("提交")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(selected.isEmpty || busy ? AppColor.primary.opacity(0.5) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(selected.isEmpty || busy)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(submitTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(busy)
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPicker(limit: max(1, 9 - selected.count)) { images in
                    showPicker = false
                    selected.append(contentsOf: images.prefix(9 - selected.count))
                }
            }
            .alert("确认提交", isPresented: $confirming) {
                Button("再检查一下", role: .cancel) {}
                Button("确认提交") { onConfirm(selected) }
            } message: {
                Text("确认提交 \(selected.count) 张返图？提交后将进入待审核，截止前不可重复提交。")
            }
        }
    }

    private var submitTitle: String {
        if item.status == "overdue" { return "补交返图" }
        if item.status == "rejected" { return "重新提交" }
        return "上传返图"
    }
}

// MARK: - 图片选择与预览

struct PhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    let onPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = limit
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([UIImage]) -> Void

        init(onPicked: @escaping ([UIImage]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            let lock = NSLock()
            var images: [UIImage] = []

            for result in results where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        images.append(image)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.onPicked(images)
            }
        }
    }
}

struct PreviewTarget: Identifiable {
    let id = UUID()
    let key: String
}

struct ImagePreviewSheet: View {
    let key: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            RemoteImage(key: key, corner: Radius.card, contentMode: .fit)
                .padding(12)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - 通用小部件

struct MetaLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.ssSmall)
                .foregroundColor(AppColor.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct SampleRowView: View {
    let images: [String]
    let onPreview: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("拍摄示例")
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(images, id: \.self) { key in
                        RemoteImage(key: key, corner: Radius.badge, onTap: { onPreview(key) })
                            .frame(width: 52, height: 52)
                    }
                }
            }
        }
    }
}

// MARK: - 口径

let unfinishedStatus: Set<String> = ["pending", "rejected", "overdue"]

func statusText(_ item: TaskItem) -> String {
    if item.status == "rejected" { return "已驳回 · 未重提" }
    return item.statusLabel.isEmpty ? item.status : item.statusLabel
}

func statusKind(_ status: String) -> BadgeKind {
    switch status {
    case "approved": return .ok
    case "submitted": return .info
    case "rejected", "overdue": return .bad
    default: return .warn
    }
}

func completerText(_ item: TaskItem) -> String {
    if item.assigneeId.isEmpty { return "公共任务" }
    let who = item.assigneeDisplayName.isEmpty ? "同事" : item.assigneeDisplayName
    switch item.assigneeSource {
    case "self": return "\(who)（单独指派）"
    case "inherit": return "\(who)（继承）"
    default: return who
    }
}

func groupDeadline(_ group: TaskGroup) -> String {
    let raws = group.children.map { $0.deadlineText }.filter { !$0.isEmpty }
    guard let raw = raws.min() else { return "—" }
    return Fmt.deadline(raw)
}

func detailTags(_ item: TaskItem) -> [String] {
    var tags: [String] = []
    if !item.kindId.isEmpty && item.kindId != "sys" && !item.kindName.isEmpty {
        tags.append(item.kindName)
    }
    if item.completionMode == "confirm" { tags.append("仅需确认") }
    if item.completionScope == "all" {
        tags.append("全员 \(item.progressText.isEmpty ? "0/0" : item.progressText) 已完成")
    }
    if !item.periodDate.isEmpty { tags.append("执行日 \(Fmt.execDate(item.periodDate))") }
    if !item.groupTitle.isEmpty { tags.append("分组：\(item.groupTitle)") }
    return tags
}
