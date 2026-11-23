import SwiftUI

// MARK: - ViewModel

@MainActor
final class ExpiryViewModel: ObservableObject {
    enum Tab {
        case check, due, day
    }

    @Published var tab: Tab = .check
    @Published var date = Fmt.today()
    @Published var check: ExpiryCheckData?
    @Published var dueList: [ExpiryRecord] = []
    @Published var dayList: [ExpiryRecord] = []
    @Published var loading = true
    @Published var refreshing = false
    @Published var error: String?
    @Published var flash: Flash?
    @Published var actionBusy = false

    private var inFlight = false

    var materials: [ExpiryMaterial] { check?.materials ?? [] }

    func load(refresh: Bool = false) async {
        if inFlight { return }
        inFlight = true
        if check == nil { loading = true }
        refreshing = refresh
        error = nil
        do {
            async let checkTask = ExpiryRepository.checkData(date: date)
            async let dueTask = ExpiryRepository.dueList(date: date)
            async let dayTask = ExpiryRepository.dayList(date: date)
            let (freshCheck, freshDue, freshDay) = try await (checkTask, dueTask, dayTask)
            check = freshCheck
            dueList = freshDue
            dayList = freshDay
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

    func changeDate(_ value: Date) async {
        date = Fmt.localDateString(value)
        check = nil
        dueList = []
        dayList = []
        await load()
    }

    /// 保存登记；dueAt 由调用方按「日期 / 日期+时间」组装。
    func save(material: ExpiryMaterial, dueAt: String, scrap: Bool) async -> Bool {
        guard !actionBusy else { return false }
        actionBusy = true
        do {
            try await ExpiryRepository.checkSave(date: date, materialId: material.id, dueAt: dueAt, scrap: scrap)
            actionBusy = false
            flash = Flash(text: scrap ? "已按报废登记" : "已登记 \(material.name) 的效期")
            await load(refresh: true)
            return true
        } catch {
            actionBusy = false
            flash = Flash(text: ErrText.readable(error), error: true)
            return false
        }
    }

    func process(_ record: ExpiryRecord) async {
        guard !actionBusy else { return }
        actionBusy = true
        do {
            _ = try await ExpiryRepository.process(id: record.id)
            actionBusy = false
            flash = Flash(text: "已标记处理")
            await load(refresh: true)
        } catch {
            actionBusy = false
            flash = Flash(text: ErrText.readable(error), error: true)
        }
    }

    func clearFlash() { flash = nil }

    func dueDate(_ record: ExpiryRecord) -> Date? {
        let parts = Fmt.dueParts(record.dueAt)
        let time = parts.time.isEmpty ? (check?.closeTime ?? "23:00") : parts.time
        return Fmt.combine(date: record.dueAt, time: time)
    }
}

// MARK: - 页面

struct ExpiryView: View {
    @ObservedObject var model: ExpiryViewModel
    let autoOpenScanner: Bool
    let onAutoOpenConsumed: () -> Void

    @State private var showDatePicker = false
    @State private var pickerDate = Date()
    @State private var showScanner = false
    @State private var editorTarget: EditorTarget?
    @State private var scrapTarget: ScrapTarget?
    @State private var processTarget: ExpiryRecord?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                tabRow
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
            if model.check == nil { await model.load() }
        }
        .onAppear {
            if autoOpenScanner {
                DispatchQueue.main.async {
                    showScanner = true
                    onAutoOpenConsumed()
                }
            }
        }
        .onChange(of: autoOpenScanner) { value in
            if value {
                showScanner = true
                onAutoOpenConsumed()
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(date: $pickerDate, maximum: Date()) {
                showDatePicker = false
                Task { await model.changeDate(pickerDate) }
            } onCancel: {
                showDatePicker = false
            }
        }
        .sheet(item: $editorTarget) { target in
            ExpiryEditorSheet(
                material: target.material,
                checkDate: model.date,
                closeTime: model.check?.closeTime ?? "23:00",
                saving: model.actionBusy
            ) { dueDate, dueTime in
                submit(material: target.material, date: dueDate, time: dueTime)
            } onCancel: {
                if !model.actionBusy { editorTarget = nil }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ExpiryScannerView(
                materials: model.materials,
                closeTime: model.check?.closeTime ?? "23:00"
            ) { result in
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    applyScan(result)
                }
            } onClose: {
                showScanner = false
            }
        }
        .alert("该效期已过期", isPresented: Binding(
            get: { scrapTarget != nil },
            set: { if !$0 { scrapTarget = nil } }
        )) {
            Button("返回修改", role: .cancel) { scrapTarget = nil }
            Button("确认已报废", role: .destructive) {
                if let target = scrapTarget {
                    scrapTarget = nil
                    Task {
                        _ = await model.save(material: target.material, dueAt: target.dueAt, scrap: true)
                    }
                }
            }
        } message: {
            Text("该效期已过期，请按报废流程处理。确认后该物料将标记为已报废，不再参与临期提醒。")
        }
        .alert("标记已处理", isPresented: Binding(
            get: { processTarget != nil },
            set: { if !$0 { processTarget = nil } }
        )) {
            Button("取消", role: .cancel) { processTarget = nil }
            Button("确认已处理") {
                if let record = processTarget {
                    processTarget = nil
                    Task { await model.process(record) }
                }
            }
        } message: {
            Text("确认将「\(processTarget?.materialName ?? "")」标记为已处理？该操作不可撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("效期检查")
                    .font(.ssTitle)
                    .foregroundColor(AppColor.text)
                Text("登记、当天到期与总览")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer(minLength: 0)

            Button {
                pickerDate = Fmt.date(from: model.date) ?? Date()
                showDatePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                    Text(Fmt.execDate(model.date))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppColor.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.load(refresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
                    .foregroundColor(AppColor.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ExpiryTabButton(title: "效期检查", selected: model.tab == .check) { model.tab = .check }
            ExpiryTabButton(title: "当天到期", selected: model.tab == .due) { model.tab = .due }
            ExpiryTabButton(title: "效期总览", selected: model.tab == .day) { model.tab = .day }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.check == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.check == nil {
            ErrorStateView(message: model.error ?? "加载失败") {
                Task { await model.load(refresh: true) }
            }
        } else {
            switch model.tab {
            case .check:
                checkContent
            case .due:
                dueContent
            case .day:
                dayContent
            }
        }
    }

    // MARK: 效期检查

    private var checkContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        showScanner = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                            Text("扫码录入")
                        }
                        .font(.ssBody14)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if model.refreshing {
                        ProgressView().scaleEffect(0.7)
                    }
                    Spacer()
                }

                let categories = model.check?.categories ?? []
                if categories.isEmpty {
                    EmptyStateView(title: "暂无物料配置", hint: "请先在后台维护效期物料。")
                }
                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.name)
                            .font(.ssTitle4)
                            .foregroundColor(AppColor.text)
                        ForEach(category.materials) { material in
                            MaterialRow(material: material) {
                                editorTarget = EditorTarget(material: material)
                            }
                        }
                    }
                    .padding(14)
                    .cardSurface()
                }
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .refreshable { await model.load(refresh: true) }
    }

    // MARK: 当天到期

    private var dueContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("仅展示登记日期为到期日前一天、今日到期的记录。")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                if model.dueList.isEmpty {
                    EmptyStateView(title: "今天没有到期物料", hint: "可切换日期查看其他日期。")
                }
                ForEach(model.dueList) { record in
                    DueRecordCard(
                        record: record,
                        highlight: highlightKind(record),
                        busy: model.actionBusy,
                        showStatus: true,
                        onProcess: { processTarget = record }
                    )
                }
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .refreshable { await model.load(refresh: true) }
    }

    // MARK: 效期总览

    private var dayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.dayList.isEmpty {
                    EmptyStateView(title: "当天没有效期记录", hint: "可在「效期检查」中登记物料效期。")
                }
                ForEach(model.dayList) { record in
                    DueRecordCard(
                        record: record,
                        highlight: highlightKind(record),
                        busy: model.actionBusy,
                        showStatus: false,
                        onProcess: nil
                    )
                }
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .refreshable { await model.load(refresh: true) }
    }

    /// 仅未处理记录参与高亮：已过点红色，今日未过点黄色。
    private func highlightKind(_ record: ExpiryRecord) -> DueHighlight {
        guard record.status == "normal" else { return .none }
        guard let due = model.dueDate(record) else { return .none }
        if due <= Date() { return .expired }
        if Fmt.localDateString(due) == model.date { return .soon }
        return .none
    }

    // MARK: 提交

    private func composeDue(_ material: ExpiryMaterial, date: String, time: String) -> String {
        if material.closeDue { return date }
        return time.isEmpty ? date : "\(date) \(time)"
    }

    private func submit(material: ExpiryMaterial, date: String, time: String) {
        let dueAt = composeDue(material, date: date, time: time)
        if let due = Fmt.combine(date: date, time: material.closeDue ? (model.check?.closeTime ?? "23:00") : time), due <= Date() {
            editorTarget = nil
            scrapTarget = ScrapTarget(material: material, dueAt: dueAt)
            return
        }
        Task {
            if await model.save(material: material, dueAt: dueAt, scrap: false) {
                editorTarget = nil
            }
        }
    }

    private func applyScan(_ result: QrResult) {
        guard let material = result.material else {
            model.flash = Flash(text: "未匹配到物料，可重新扫描或手动登记", error: true)
            return
        }
        guard !result.date.isEmpty else {
            model.flash = Flash(text: "未识别到有效效期，请重试", error: true)
            return
        }
        let time = result.time.isEmpty ? (model.check?.closeTime ?? "23:00") : result.time
        submit(material: material, date: result.date, time: time)
    }
}

// MARK: - 子视图

struct ExpiryTabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? AppColor.primary : AppColor.textSecondary)
                Rectangle()
                    .fill(selected ? AppColor.primary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum DueHighlight {
    case none, soon, expired
}

struct MaterialRow: View {
    let material: ExpiryMaterial
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(material.name)
                        .font(.ssBody14)
                        .foregroundColor(AppColor.text)
                    if let record = material.record {
                        Text("到期 \(Fmt.shortDue(record.dueAt))" + (record.note.isEmpty ? "" : " · \(record.note)"))
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    } else {
                        Text("未登记")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let record = material.record {
                    if record.isProcessed {
                        StatusBadge(text: "已处理", kind: .ok)
                    } else if record.isScrapped {
                        StatusBadge(text: "已报废", kind: .bad)
                    }
                }
                Text(material.record == nil ? "登记" : "更新")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColor.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                            .stroke(AppColor.primary.opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DueRecordCard: View {
    let record: ExpiryRecord
    let highlight: DueHighlight
    let busy: Bool
    let showStatus: Bool
    var onProcess: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if highlight != .none {
                Rectangle()
                    .fill(markerColor)
                    .frame(width: 3)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.materialName)
                    .font(.ssBody14)
                    .foregroundColor(AppColor.text)
                    .lineLimit(1)
                if !record.categoryName.isEmpty {
                    Text(record.categoryName)
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                }
                dueLine
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if showStatus {
                    StatusBadge(text: statusText, kind: statusKind)
                } else if record.isProcessed {
                    StatusBadge(text: "已处理", kind: .ok)
                } else if record.isScrapped {
                    StatusBadge(text: "已报废", kind: .bad)
                }
                if let onProcess = onProcess, record.status == "normal" {
                    Button {
                        onProcess()
                    } label: {
                        Text("标记已处理")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var dueLine: some View {
        let parts = Fmt.dueParts(record.dueAt)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.date)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(highlight == .expired ? Sem.bad : AppColor.textSecondary)
            if !parts.time.isEmpty {
                Text(parts.time)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(highlight == .expired ? Sem.bad : AppColor.text)
            }
            if record.isProcessed && !record.processedAt.isEmpty {
                Text("处理于 \(Fmt.shortDue(record.processedAt))")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
    }

    private var statusText: String {
        if record.isProcessed { return "已处理" }
        if record.isScrapped { return "已报废" }
        return "未处理"
    }

    private var statusKind: BadgeKind {
        if record.isProcessed { return .ok }
        if record.isScrapped { return .bad }
        return .warn
    }

    private var markerColor: Color {
        switch highlight {
        case .expired: return Sem.bad
        case .soon: return Sem.warn
        case .none: return Color.clear
        }
    }

    private var background: Color {
        switch highlight {
        case .expired: return Sem.badTint
        case .soon: return Sem.warnTint
        case .none: return AppColor.surface
        }
    }
}

// MARK: - 日期选择

struct DatePickerSheet: View {
    @Binding var date: Date
    let maximum: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack {
                DatePicker("", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                Spacer()
            }
            .padding(.top, 8)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定", action: onConfirm)
                }
            }
        }
    }

    private var range: ClosedRange<Date> {
        let start = Calendar.current.date(byAdding: .year, value: -5, to: maximum) ?? maximum
        return start...maximum
    }
}

// MARK: - 效期编辑

struct EditorTarget: Identifiable {
    let id = UUID()
    let material: ExpiryMaterial
}

struct ScrapTarget: Identifiable {
    let id = UUID()
    let material: ExpiryMaterial
    let dueAt: String
}

struct ExpiryEditorSheet: View {
    let material: ExpiryMaterial
    let checkDate: String
    let closeTime: String
    let saving: Bool
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var dueDate = Date()
    @State private var dueTime = Date()
    @State private var didInit = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(material.name)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                    if !material.remark.isEmpty {
                        Text(material.remark)
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    if material.closeDue {
                        Text("该物料按打烊时间到期，只需选择日期（门店打烊 \(closeTime)）。")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    }

                    DatePicker("到期日期", selection: $dueDate, displayedComponents: .date)
                        .font(.ssSmall)
                    if !material.closeDue {
                        DatePicker("到期时间", selection: $dueTime, displayedComponents: .hourAndMinute)
                            .font(.ssSmall)
                    }

                    Text("到期：\(Fmt.localDateString(dueDate)) " + (material.closeDue ? closeTime : timeText(dueTime)))
                        .font(.ssBody14)
                        .foregroundColor(AppColor.text)

                    Button {
                        onSave(Fmt.localDateString(dueDate), material.closeDue ? closeTime : timeText(dueTime))
                    } label: {
                        Text(saving ? "保存中…" : "保存效期")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(saving ? AppColor.primary.opacity(0.6) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(saving)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("登记效期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(saving)
                }
            }
            .onAppear(perform: initialize)
        }
    }

    private func initialize() {
        guard !didInit else { return }
        didInit = true
        let base = Fmt.date(from: checkDate) ?? Date()
        if let record = material.record, let due = Fmt.combine(date: record.dueAt, time: Fmt.dueParts(record.dueAt).time) {
            dueDate = due
            dueTime = due
            return
        }
        if material.closeDue {
            dueDate = base
            dueTime = Fmt.combine(date: checkDate, time: closeTime) ?? Date()
            return
        }
        if !material.defaultTime.isEmpty, let combined = Fmt.combine(date: checkDate, time: material.defaultTime) {
            dueDate = combined
            dueTime = combined
            return
        }
        let hours = material.defaultHours > 0 ? material.defaultHours : 24
        let target = Date().addingTimeInterval(hours * 3600)
        dueDate = target
        dueTime = target
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
