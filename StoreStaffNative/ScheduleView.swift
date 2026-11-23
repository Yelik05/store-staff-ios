import SwiftUI

// MARK: - ViewModel

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var today: ShiftToday?
    @Published var leave: LeaveSummary?
    @Published var shifts: ShiftSummary?
    @Published var loading = true
    @Published var refreshing = false
    @Published var error: String?
    @Published var flash: Flash?
    @Published var actionBusy = false
    @Published var dayStats: LeaveDayStats?
    @Published var dayStatsLoading = false

    private var inFlight = false

    func load(refresh: Bool = false) async {
        if inFlight { return }
        inFlight = true
        if today == nil && leave == nil { loading = true }
        refreshing = refresh
        error = nil
        let month = Fmt.currentMonth()
        do {
            async let todayTask = ShiftRepository.today()
            async let leaveTask = LeaveRepository.my(month: month)
            async let shiftTask = ShiftRepository.my(month: month)
            let (freshToday, freshLeave, freshShifts) = try await (todayTask, leaveTask, shiftTask)
            today = freshToday
            leave = freshLeave
            shifts = freshShifts
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
        inFlight = false
    }

    func loadDayStats(date: String) async {
        dayStatsLoading = true
        do {
            dayStats = try await LeaveRepository.dayStats(date: date)
        } catch {
            dayStats = nil
        }
        dayStatsLoading = false
    }

    func applyLeave(date: String, type: String, reason: String) async -> Bool {
        guard !actionBusy else { return false }
        actionBusy = true
        do {
            try await LeaveRepository.apply(date: date, type: type, reason: reason)
            actionBusy = false
            flash = Flash(text: "排休申请已提交，等待审批")
            await load(refresh: true)
            return true
        } catch {
            actionBusy = false
            flash = Flash(text: ErrText.readable(error), error: true)
            return false
        }
    }

    func applyShift(slots: [ShiftSlot], note: String) async -> Bool {
        guard !actionBusy else { return false }
        actionBusy = true
        do {
            try await ShiftRepository.apply(slots: slots, note: note)
            actionBusy = false
            flash = Flash(text: "排班申请已提交，等待审批")
            await load(refresh: true)
            return true
        } catch {
            actionBusy = false
            flash = Flash(text: ErrText.readable(error), error: true)
            return false
        }
    }

    func cancelRecord(kind: ScheduleRecordKind, id: String, action: String) async {
        guard !actionBusy else { return }
        actionBusy = true
        do {
            if kind == .leave {
                try await LeaveRepository.cancel(id: id, action: action)
            } else {
                try await ShiftRepository.cancel(id: id, action: action)
            }
            actionBusy = false
            flash = Flash(text: action == "withdraw" ? "已撤回申请" : "已提交取消申请")
            await load(refresh: true)
        } catch {
            actionBusy = false
            flash = Flash(text: ErrText.readable(error), error: true)
        }
    }

    func clearFlash() { flash = nil }
}

// MARK: - 合并记录

enum ScheduleRecordKind {
    case leave, shift
}

struct ScheduleRecord: Identifiable {
    let id: String
    let kind: ScheduleRecordKind
    let rawId: String
    let date: String
    let title: String
    let detail: String
    let status: String
    let rejectReason: String
    let cancelRequested: Bool
    let manual: Bool
}

func mergedRecords(leave: LeaveSummary?, shifts: ShiftSummary?) -> [ScheduleRecord] {
    var records: [ScheduleRecord] = []
    if let leave = leave {
        for item in leave.list {
            records.append(
                ScheduleRecord(
                    id: "leave:\(item.id)",
                    kind: .leave,
                    rawId: item.id,
                    date: item.date,
                    title: "排休 · \(item.type.isEmpty ? "事假" : item.type)",
                    detail: item.reason,
                    status: item.status,
                    rejectReason: item.rejectReason,
                    cancelRequested: item.cancelRequested,
                    manual: item.manual
                )
            )
        }
    }
    if let shifts = shifts {
        for item in shifts.list {
            for slot in item.slots {
                records.append(
                    ScheduleRecord(
                        id: "shift:\(item.id):\(slot.date):\(slot.start)",
                        kind: .shift,
                        rawId: item.id,
                        date: slot.date,
                        title: "排班 · \(slot.start)–\(slot.end)",
                        detail: item.note,
                        status: item.status,
                        rejectReason: item.rejectReason,
                        cancelRequested: item.cancelRequested,
                        manual: false
                    )
                )
            }
        }
    }
    return records.sorted { left, right in
        if left.date == right.date { return left.title < right.title }
        return left.date > right.date
    }
}

func scheduleStatusText(_ status: String, cancelRequested: Bool) -> String {
    if cancelRequested { return "待取消" }
    switch status {
    case "pending": return "待审批"
    case "approved": return "已通过"
    case "rejected": return "已驳回"
    case "cancelled": return "已取消"
    default: return status.isEmpty ? "—" : status
    }
}

func scheduleStatusKind(_ status: String, cancelRequested: Bool) -> BadgeKind {
    if cancelRequested { return .info }
    switch status {
    case "pending": return .warn
    case "approved": return .ok
    case "rejected": return .bad
    default: return .neutral
    }
}

// MARK: - 页面

struct ScheduleView: View {
    @ObservedObject var model: ScheduleViewModel

    @State private var showLeaveApply = false
    @State private var showShiftApply = false
    @State private var cancelTarget: ScheduleRecord?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                content
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
            if model.leave == nil { await model.load() }
        }
        .sheet(isPresented: $showLeaveApply) {
            LeaveApplySheet(model: model) { showLeaveApply = false }
        }
        .sheet(isPresented: $showShiftApply) {
            ShiftApplySheet(model: model) { showShiftApply = false }
        }
        .alert("确认操作", isPresented: Binding(
            get: { cancelTarget != nil },
            set: { if !$0 { cancelTarget = nil } }
        )) {
            Button("取消", role: .cancel) { cancelTarget = nil }
            Button("确认") {
                if let target = cancelTarget {
                    cancelTarget = nil
                    let action = target.status == "pending" ? "withdraw" : "cancel"
                    Task { await model.cancelRecord(kind: target.kind, id: target.rawId, action: action) }
                }
            }
        } message: {
            if let target = cancelTarget {
                Text(target.status == "pending"
                     ? "确认撤回「\(target.title)」的申请？撤回后可重新提交。"
                     : "确认申请取消「\(target.title)」？需店长审批后生效。")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("排班与排休")
                    .font(.ssTitle)
                    .foregroundColor(AppColor.text)
                Text(Fmt.monthLabel() + " · 申请与审批进度")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.load(refresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
                    .foregroundColor(AppColor.textSecondary)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.today == nil && model.leave == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.today == nil && model.leave == nil {
            ErrorStateView(message: model.error ?? "加载失败") {
                Task { await model.load(refresh: true) }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ShiftTodayCardView(shift: model.today, dateText: Fmt.today())

                    leaveSummaryCard
                    shiftSummaryCard
                    recordsCard
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 16)
            }
            .refreshable {
                await model.load(refresh: true)
            }
        }
    }

    private var leaveSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的排休")
                    .font(.ssTitle4)
                    .foregroundColor(AppColor.text)
                Spacer()
                Button("申请排休") { showLeaveApply = true }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .buttonStyle(.plain)
            }
            if let leave = model.leave {
                HStack(spacing: 0) {
                    SummaryCell(title: "月度额度", value: Fmt.number(leave.quota))
                    SummaryCell(title: "剩余", value: Fmt.number(leave.remaining))
                    SummaryCell(title: "待审批", value: "\(leave.pending)")
                    SummaryCell(title: "已通过", value: "\(leave.used)")
                }
                if !leave.byType.isEmpty {
                    let text = leave.byType.keys.sorted().map { "\($0) \(leave.byType[$0] ?? 0)" }.joined(separator: " · ")
                    Text(text)
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                }
            } else {
                Text("暂无排休数据")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var shiftSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的排班")
                    .font(.ssTitle4)
                    .foregroundColor(AppColor.text)
                Spacer()
                Button("申请排班") { showShiftApply = true }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColor.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
            }
            if let shifts = model.shifts {
                Text("本月待审批 \(shifts.pendingSlots) 个班段 · 已通过 \(shifts.approvedSlots) 个班段")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            } else {
                Text("暂无排班申请")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            Text("排班仅可申请当月，且不得早于今天；同一天最多两个班段。")
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(14)
        .cardSurface()
    }

    private var recordsCard: some View {
        let records = mergedRecords(leave: model.leave, shifts: model.shifts)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("我的申请")
                    .font(.ssTitle4)
                    .foregroundColor(AppColor.text)
                Spacer()
                Text("\(records.count) 条")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            if records.isEmpty {
                Text("本月还没有排休或排班申请。")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(records) { record in
                    VStack(spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.execDate(record.date) + "  " + record.title)
                                    .font(.ssBody14)
                                    .foregroundColor(AppColor.text)
                                if !record.detail.isEmpty {
                                    Text(record.detail)
                                        .font(.ssCaption)
                                        .foregroundColor(AppColor.textSecondary)
                                        .lineLimit(2)
                                }
                                if !record.rejectReason.isEmpty {
                                    Text("驳回原因：\(record.rejectReason)")
                                        .font(.ssCaption)
                                        .foregroundColor(Sem.bad)
                                }
                            }
                            Spacer(minLength: 0)
                            StatusBadge(
                                text: scheduleStatusText(record.status, cancelRequested: record.cancelRequested),
                                kind: scheduleStatusKind(record.status, cancelRequested: record.cancelRequested)
                            )
                        }
                        HStack(spacing: 8) {
                            Spacer()
                            if !record.manual && !record.cancelRequested && (record.status == "pending" || record.status == "approved") {
                                OutlineSmallButton(title: record.status == "pending" ? "撤回" : "申请取消") {
                                    cancelTarget = record
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    if record.id != records.last?.id {
                        Divider().background(AppColor.outlineVariant)
                    }
                }
            }
        }
        .padding(14)
        .cardSurface()
    }
}

private struct SummaryCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColor.text)
            Text(title)
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 排休申请

struct LeaveApplySheet: View {
    @ObservedObject var model: ScheduleViewModel
    let onClose: () -> Void

    @State private var date = Date()
    @State private var type = "事假"
    @State private var reason = ""
    @State private var submitting = false
    @State private var error: String?
    @State private var showConfirm = false

    private let types = ["事假", "病假"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("休息日期")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    DatePicker("", selection: $date, in: dateRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: date) { value in
                            error = nil
                            Task { await model.loadDayStats(date: Fmt.localDateString(value)) }
                        }

                    if model.dayStatsLoading {
                        ProgressView().scaleEffect(0.7)
                    } else if let stats = model.dayStats {
                        Text(dayStatsText(stats))
                            .font(.ssSmall)
                            .foregroundColor(stats.remaining <= 0 ? Sem.bad : AppColor.textSecondary)
                    }

                    Text("请假类型")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(types, id: \.self) { value in
                            Button {
                                type = value
                            } label: {
                                Text(value)
                                    .font(.ssBody14)
                                    .foregroundColor(type == value ? AppColor.primary : AppColor.textSecondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 9)
                                    .background(type == value ? AppColor.primaryContainer : AppColor.surfaceVariant)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("请假事由")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 4)
                    TextField("选填，简要说明", text: $reason)
                        .font(.ssBody14)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

                    if let error = error {
                        Text(error)
                            .font(.ssSmall)
                            .foregroundColor(Sem.bad)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(submitting ? "提交中…" : "提交申请")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(submitting ? AppColor.primary.opacity(0.6) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(submitting)
                    .padding(.top, 6)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("申请排休")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onClose).disabled(submitting)
                }
            }
            .alert("连续休息提示", isPresented: $showConfirm) {
                Button("返回修改", role: .cancel) {}
                Button("仍要提交") { performSubmit() }
            } message: {
                Text("提交后若连续休息超过 4 天，可能需要店长确认。确定继续提交吗？")
            }
            .task {
                await model.loadDayStats(date: Fmt.localDateString(date))
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let monthComps = calendar.dateComponents([.year, .month], from: Date())
        let first = calendar.date(from: monthComps) ?? start
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) ?? start
        return start...max(start, end)
    }

    private func dayStatsText(_ stats: LeaveDayStats) -> String {
        var parts: [String] = []
        parts.append("当日已休 \(stats.approved) 人，待审批 \(stats.pending) 人")
        if stats.storeLimit > 0 {
            parts.append("门店剩余 \(stats.storeRemaining)/\(stats.storeLimit)")
        }
        if stats.positionLimit > 0 {
            parts.append("岗位剩余 \(stats.positionRemaining)/\(stats.positionLimit)")
        }
        if stats.remaining <= 0 {
            parts.append("当日名额已满")
        }
        return parts.joined(separator: " · ")
    }

    private func submit() {
        let today = Calendar.current.startOfDay(for: Date())
        if date < today {
            error = "不能申请过去的日期"
            return
        }
        if Fmt.monthFormatter.string(from: date) != Fmt.currentMonth() {
            error = "仅可申请当月日期"
            return
        }
        if let stats = model.dayStats, stats.remaining <= 0 {
            error = "当日排休名额已满，请选择其他日期"
            return
        }
        if statsNeedsConfirm() {
            showConfirm = true
            return
        }
        performSubmit()
    }

    private func statsNeedsConfirm() -> Bool {
        guard let stats = model.dayStats else { return false }
        return stats.approved + stats.pending >= 3
    }

    private func performSubmit() {
        submitting = true
        error = nil
        let day = Fmt.localDateString(date)
        Task {
            let ok = await model.applyLeave(date: day, type: type, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            submitting = false
            if ok {
                onClose()
            } else {
                error = model.flash?.text ?? "提交失败，请重试"
            }
        }
    }
}

// MARK: - 排班申请

struct ShiftDraft: Identifiable {
    let id = UUID()
    var day: Date
    var start: Date
    var end: Date
}

struct ShiftApplySheet: View {
    @ObservedObject var model: ScheduleViewModel
    let onClose: () -> Void

    @State private var drafts: [ShiftDraft] = []
    @State private var note = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("仅可申请当月，且日期不得早于今天；同一天最多两个班段。")
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)

                    ForEach(drafts.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("班段 \(index + 1)")
                                    .font(.ssBody14)
                                    .foregroundColor(AppColor.text)
                                Spacer()
                                if drafts.count > 1 {
                                    Button {
                                        drafts.remove(at: index)
                                    } label: {
                                        Text("删除")
                                            .font(.ssCaption)
                                            .foregroundColor(Sem.bad)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            DatePicker("日期", selection: bindingDay(index), in: dateRange, displayedComponents: .date)
                                .font(.ssSmall)
                            HStack(spacing: 12) {
                                DatePicker("开始", selection: bindingStart(index), displayedComponents: .hourAndMinute)
                                    .font(.ssSmall)
                                DatePicker("结束", selection: bindingEnd(index), displayedComponents: .hourAndMinute)
                                    .font(.ssSmall)
                            }
                            Text("时段：\(timeText(drafts[index].start))–\(timeText(drafts[index].end))")
                                .font(.ssCaption)
                                .foregroundColor(AppColor.textSecondary)
                        }
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }

                    Button {
                        if drafts.count < 2 {
                            drafts.append(makeDraft(day: drafts.first?.day ?? Date(), startHour: 13))
                        }
                    } label: {
                        Text("添加第二个班段（断班）")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(drafts.count >= 2)

                    Text("备注")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    TextField("选填，例如换班原因", text: $note)
                        .font(.ssBody14)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

                    if let error = error {
                        Text(error)
                            .font(.ssSmall)
                            .foregroundColor(Sem.bad)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(submitting ? "提交中…" : "提交排班")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(submitting ? AppColor.primary.opacity(0.6) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(submitting)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("申请排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onClose).disabled(submitting)
                }
            }
            .task {
                if drafts.isEmpty {
                    drafts = [makeDraft(day: Date(), startHour: 9)]
                }
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let first = calendar.date(from: comps) ?? start
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) ?? start
        return start...max(start, end)
    }

    private func makeDraft(day: Date, startHour: Int) -> ShiftDraft {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(bySettingHour: startHour + 9, minute: 0, second: 0, of: day) ?? day
        return ShiftDraft(day: day, start: start, end: end)
    }

    private func bindingDay(_ index: Int) -> Binding<Date> {
        Binding(
            get: { drafts[index].day },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                let calendar = Calendar.current
                let old = drafts[index]
                let startComps = calendar.dateComponents([.hour, .minute], from: old.start)
                let endComps = calendar.dateComponents([.hour, .minute], from: old.end)
                drafts[index].day = value
                drafts[index].start = calendar.date(bySettingHour: startComps.hour ?? 9, minute: startComps.minute ?? 0, second: 0, of: value) ?? value
                drafts[index].end = calendar.date(bySettingHour: endComps.hour ?? 18, minute: endComps.minute ?? 0, second: 0, of: value) ?? value
            }
        )
    }

    private func bindingStart(_ index: Int) -> Binding<Date> {
        Binding(
            get: { drafts[index].start },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                drafts[index].start = value
                if drafts[index].end <= value {
                    drafts[index].end = Calendar.current.date(byAdding: .hour, value: 8, to: value) ?? value
                }
            }
        )
    }

    private func bindingEnd(_ index: Int) -> Binding<Date> {
        Binding(
            get: { drafts[index].end },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                drafts[index].end = value
            }
        )
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func submit() {
        let today = Calendar.current.startOfDay(for: Date())
        var slots: [ShiftSlot] = []
        for draft in drafts {
            let day = Calendar.current.startOfDay(for: draft.day)
            if day < today {
                error = "排班日期不能早于今天"
                return
            }
            if Fmt.monthFormatter.string(from: day) != Fmt.currentMonth() {
                error = "仅可申请当月排班"
                return
            }
            if timeText(draft.start) == timeText(draft.end) {
                error = "班段开始与结束时间不能相同"
                return
            }
            slots.append(ShiftSlot(date: Fmt.localDateString(day), start: timeText(draft.start), end: timeText(draft.end)))
        }
        let grouped = Dictionary(grouping: slots, by: { $0.date })
        for (_, daySlots) in grouped where daySlots.count > 2 {
            error = "同一天最多两个班段"
            return
        }
        if hasOverlap(slots) {
            error = "同一员工同一天的两个班段不能重叠"
            return
        }
        submitting = true
        error = nil
        Task {
            let ok = await model.applyShift(slots: slots, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            submitting = false
            if ok {
                onClose()
            } else {
                error = model.flash?.text ?? "提交失败，请重试"
            }
        }
    }

    private func hasOverlap(_ slots: [ShiftSlot]) -> Bool {
        let grouped = Dictionary(grouping: slots, by: { $0.date })
        for (_, daySlots) in grouped where daySlots.count > 1 {
            let sorted = daySlots.sorted { $0.start < $1.start }
            for index in 1..<sorted.count {
                if sorted[index].start < sorted[index - 1].end {
                    return true
                }
            }
        }
        return false
    }
}
