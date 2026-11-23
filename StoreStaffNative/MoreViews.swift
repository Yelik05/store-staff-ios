import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 考勤数据

struct AttendanceTagInfo {
    var text = ""
    var cls = ""
}

struct AttendanceSegmentInfo {
    var segmentNo = 1
    var plannedIn = ""
    var plannedOut = ""
    var plannedWorkHours = 0.0
    var mealHours = 0.0
    var clockIn = ""
    var clockOut = ""
    var confirmIn = ""
    var confirmOut = ""
    var actualHours = 0.0
    var hourDiff = 0.0
    var tags: [AttendanceTagInfo] = []
}

struct AttendanceDayInfo: Identifiable {
    var date = ""
    var totalHours = 0.0
    var abnormal = false
    var segments: [AttendanceSegmentInfo] = []
    var id: String { date }
}

struct AttendanceSummaryInfo {
    var workDays = 0
    var totalHours = 0.0
    var abnormalCount = 0
}

struct AttendanceMonthInfo {
    var month = ""
    var summary = AttendanceSummaryInfo()
    var days: [AttendanceDayInfo] = []
}

enum AttendanceRepo {
    static func my(month: String) async throws -> AttendanceMonthInfo {
        let data = try await APIClient.shared.post("attendance.my", ["month": month])
        let summary = data.dict("summary") ?? [:]
        let days = data.objects("days").map { day in
            AttendanceDayInfo(
                date: day.str("date"),
                totalHours: day.doubleVal("totalHours"),
                abnormal: day.boolVal("abnormal"),
                segments: day.objects("segments").map { segment in
                    AttendanceSegmentInfo(
                        segmentNo: segment.intVal("segmentNo"),
                        plannedIn: segment.str("plannedIn"),
                        plannedOut: segment.str("plannedOut"),
                        plannedWorkHours: segment.doubleVal("plannedWorkHours"),
                        mealHours: segment.doubleVal("mealHours"),
                        clockIn: segment.str("clockIn"),
                        clockOut: segment.str("clockOut"),
                        confirmIn: segment.str("confirmIn"),
                        confirmOut: segment.str("confirmOut"),
                        actualHours: segment.doubleVal("actualHours"),
                        hourDiff: segment.doubleVal("hourDiff"),
                        tags: segment.objects("tags").map { AttendanceTagInfo(text: $0.str("text"), cls: $0.str("cls")) }
                    )
                }
            )
        }
        return AttendanceMonthInfo(
            month: data.str("month").isEmpty ? month : data.str("month"),
            summary: AttendanceSummaryInfo(
                workDays: summary.intVal("workDays"),
                totalHours: summary.doubleVal("totalHours"),
                abnormalCount: summary.intVal("abnormalCount")
            ),
            days: days
        )
    }
}

// MARK: - 薪资数据

struct SalaryInfo {
    var month = ""
    var payStatus = ""
    var payDate = ""
    var publishAt = ""
    var remark = ""
    var shouldDays = 0.0
    var actualDays = 0.0
    var totalHours = 0.0
    var baseSalary = 0.0
    var postAllowance = 0.0
    var performancePay = 0.0
    var fullAttendance = 0.0
    var dailyOvertimePay = 0.0
    var statutoryHolidayPay = 0.0
    var mealSubsidy = 0.0
    var transportSubsidy = 0.0
    var attendanceSubsidy = 0.0
    var socialSubsidy = 0.0
    var commission = 0.0
    var grossPay = 0.0
    var inventoryDeduction = 0.0
    var lateDeduction = 0.0
    var attendanceDiff = 0.0
    var leaveDeduction = 0.0
    var disciplineDeduction = 0.0
    var otherDeduction = 0.0
    var insurance = 0.0
    var tax = 0.0
    var deductionTotal = 0.0
    var netPay = 0.0
}

enum SalaryRepo {
    static func myMonths() async throws -> [String] {
        let data = try await APIClient.shared.post("salary.myMonths")
        return data.strList("list")
    }

    static func get(month: String) async throws -> SalaryInfo? {
        let data = try await APIClient.shared.post("salary.get", ["month": month])
        if data.isEmpty { return nil }
        if data.str("month").isEmpty && data["netPay"] == nil { return nil }
        return SalaryInfo(
            month: data.str("month"),
            payStatus: data.str("payStatus"),
            payDate: data.str("payDate"),
            publishAt: data.str("publishAt"),
            remark: data.str("remark"),
            shouldDays: data.doubleVal("shouldDays"),
            actualDays: data.doubleVal("actualDays"),
            totalHours: data.doubleVal("totalHours"),
            baseSalary: data.doubleVal("baseSalary"),
            postAllowance: data.doubleVal("postAllowance"),
            performancePay: data.doubleVal("performancePay"),
            fullAttendance: data.doubleVal("fullAttendance"),
            dailyOvertimePay: data.doubleVal("dailyOvertimePay"),
            statutoryHolidayPay: data.doubleVal("statutoryHolidayPay"),
            mealSubsidy: data.doubleVal("mealSubsidy"),
            transportSubsidy: data.doubleVal("transportSubsidy"),
            attendanceSubsidy: data.doubleVal("attendanceSubsidy"),
            socialSubsidy: data.doubleVal("socialSubsidy"),
            commission: data.doubleVal("commission"),
            grossPay: data.doubleVal("grossPay"),
            inventoryDeduction: data.doubleVal("inventoryDeduction"),
            lateDeduction: data.doubleVal("lateDeduction"),
            attendanceDiff: data.doubleVal("attendanceDiff"),
            leaveDeduction: data.doubleVal("leaveDeduction"),
            disciplineDeduction: data.doubleVal("disciplineDeduction"),
            otherDeduction: data.doubleVal("otherDeduction"),
            insurance: data.doubleVal("insurance"),
            tax: data.doubleVal("tax"),
            deductionTotal: data.doubleVal("deductionTotal"),
            netPay: data.doubleVal("netPay")
        )
    }
}

// MARK: - 量化分数据

struct ScoreDimensionInfo {
    var key = ""
    var name = ""
    var full = 0.0
    var score = 0.0
}

struct ScoreAdjustInfo: Identifiable {
    var reason = ""
    var score = 0.0
    var id = UUID()
}

struct ScoreRecordInfo {
    var month = ""
    var total = 0.0
    var grade = ""
    var dims: [ScoreDimensionInfo] = []
    var adjust: [ScoreAdjustInfo] = []
    var publishAt = ""
    var updatedAt = ""
}

struct ScoreDimensionDefInfo {
    var key = ""
    var name = ""
    var desc = ""
}

enum ScoreRepo {
    static func my() async throws -> [ScoreRecordInfo] {
        let data = try await APIClient.shared.post("score.my")
        return data.objects("list").map { parse($0) }
    }

    static func get(month: String) async throws -> ScoreRecordInfo? {
        let data = try await APIClient.shared.post("score.get", ["month": month])
        if data.isEmpty { return nil }
        if data.str("month").isEmpty && data["total"] == nil { return nil }
        return parse(data)
    }

    static func dimensions() async throws -> [ScoreDimensionDefInfo] {
        let data = try await APIClient.shared.post("settings.dimensions")
        return data.objects("list").map {
            ScoreDimensionDefInfo(key: $0.str("key"), name: $0.str("name"), desc: $0.str("desc"))
        }
    }

    private static func parse(_ data: JSON) -> ScoreRecordInfo {
        ScoreRecordInfo(
            month: data.str("month"),
            total: data.doubleVal("total"),
            grade: data.str("grade"),
            dims: data.objects("dims").map {
                ScoreDimensionInfo(
                    key: $0.str("key"),
                    name: $0.str("name"),
                    full: $0.doubleVal("full"),
                    score: $0.doubleVal("score")
                )
            },
            adjust: data.objects("adjust").map {
                ScoreAdjustInfo(reason: $0.str("reason"), score: $0.doubleVal("score"))
            },
            publishAt: data.str("publishAt"),
            updatedAt: data.str("updatedAt")
        )
    }
}

// MARK: - 报销数据

struct ReimburseClaimInfo: Identifiable {
    var id = ""
    var categoryName = ""
    var amount = 0.0
    var reason = ""
    var attachments: [String] = []
    var payeeType = ""
    var payeeAccount = ""
    var payeeBank = ""
    var payeeHolder = ""
    var status = ""
    var reviewedBy = ""
    var reviewedAt = ""
    var rejectReason = ""
    var paidAt = ""
    var createdAt = ""
}

struct ReimburseCategoryInfo: Identifiable {
    var id = ""
    var name = ""
}

struct ReimbursePayeeInfo: Identifiable {
    var id = ""
    var type = ""
    var account = ""
    var bankName = ""
    var holderName = ""
    var isDefault = false
}

struct ReimburseAttachmentInfo: Identifiable {
    var key = ""
    var name = ""
    var id: String { key }
}

enum ReimburseRepo {
    static func my(status: String?) async throws -> [ReimburseClaimInfo] {
        var payload: JSON = [:]
        if let status = status, !status.isEmpty { payload["status"] = status }
        let data = try await APIClient.shared.post("reimburse.my", payload)
        return data.objects("list").map { claim in
            ReimburseClaimInfo(
                id: claim.str("id"),
                categoryName: claim.str("categoryName"),
                amount: claim.doubleVal("amount"),
                reason: claim.str("reason"),
                attachments: claim.strList("attachments"),
                payeeType: claim.str("payeeType"),
                payeeAccount: claim.str("payeeAccount"),
                payeeBank: claim.str("payeeBank"),
                payeeHolder: claim.str("payeeHolder"),
                status: claim.str("status"),
                reviewedBy: claim.str("reviewedBy"),
                reviewedAt: claim.str("reviewedAt"),
                rejectReason: claim.str("rejectReason"),
                paidAt: claim.str("paidAt"),
                createdAt: claim.str("createdAt")
            )
        }
    }

    static func categories() async throws -> [ReimburseCategoryInfo] {
        let data = try await APIClient.shared.post("reimburse.categories")
        return data.objects("list").map { ReimburseCategoryInfo(id: $0.str("id"), name: $0.str("name")) }
    }

    static func payees() async throws -> [ReimbursePayeeInfo] {
        let data = try await APIClient.shared.post("reimburse.payees")
        return data.objects("list").map {
            ReimbursePayeeInfo(
                id: $0.str("id"),
                type: $0.str("type"),
                account: $0.str("account"),
                bankName: $0.str("bankName"),
                holderName: $0.str("holderName"),
                isDefault: $0.boolVal("isDefault")
            )
        }
    }

    static func create(
        categoryId: String,
        amount: Double,
        reason: String,
        attachments: [String],
        payeeId: String?,
        type: String,
        account: String,
        bankName: String,
        holderName: String
    ) async throws {
        var payload: JSON = [
            "categoryId": categoryId,
            "amount": amount,
            "reason": reason,
            "attachments": attachments,
            "type": type,
            "account": account,
            "bankName": bankName,
            "holderName": holderName
        ]
        if let payeeId = payeeId, !payeeId.isEmpty { payload["payeeId"] = payeeId }
        _ = try await APIClient.shared.post("reimburse.create", payload)
    }
}

extension UploadRepository {
    static func uploadReimburse(data: Data, filename: String, mime: String) async throws -> ReimburseAttachmentInfo {
        let result = try await APIClient.shared.upload(
            action: "file.upload",
            field: "file",
            filename: filename,
            mime: mime,
            data: data,
            extra: ["type": "reimburse"]
        )
        let key = result.str("key")
        if key.isEmpty { throw APIError(code: "UPLOAD_FAIL", message: "附件上传失败，请重试") }
        let name = result.str("name").isEmpty ? filename : result.str("name")
        return ReimburseAttachmentInfo(key: key, name: name)
    }
}

// MARK: - 通讯录数据

struct ContactInfo: Identifiable {
    var id = ""
    var name = ""
    var nickname = ""
    var position = ""
    var phone = ""
    var empNo = ""
    var feishuEmpNo = ""
    var employmentType = ""
}

enum ContactsRepo {
    static func list() async throws -> ([ContactInfo], String) {
        let data = try await APIClient.shared.post("staff.contacts")
        let list = data.objects("list").map {
            ContactInfo(
                id: $0.str("id"),
                name: $0.str("name"),
                nickname: $0.str("nickname"),
                position: $0.str("position"),
                phone: $0.str("phone"),
                empNo: $0.str("empNo"),
                feishuEmpNo: $0.str("feishuEmpNo"),
                employmentType: $0.str("employmentType")
            )
        }
        return (list, data.dict("store")?.str("name") ?? "")
    }
}

// MARK: - 日程数据

struct AgendaParticipantInfo: Identifiable {
    var id = ""
    var name = ""
}

struct AgendaItemInfo: Identifiable {
    var id = ""
    var title = ""
    var date = ""
    var startTime = ""
    var endTime = ""
    var location = ""
    var remark = ""
    var remindMinutes = 0
    var status = ""
    var isOwner = false
    var isInvited = false
    var creatorName = ""
    var participants: [AgendaParticipantInfo] = []
}

struct AgendaDataInfo {
    var scope = ""
    var canViewAll = false
    var list: [AgendaItemInfo] = []
}

enum AgendaRepo {
    static func list(scope: String) async throws -> AgendaDataInfo {
        let data = try await APIClient.shared.post("schedule.list", ["scope": scope])
        return AgendaDataInfo(
            scope: data.str("scope"),
            canViewAll: data.boolVal("canViewAll"),
            list: data.objects("list").map { item in
                AgendaItemInfo(
                    id: item.str("id"),
                    title: item.str("title"),
                    date: item.str("date"),
                    startTime: item.str("startTime"),
                    endTime: item.str("endTime"),
                    location: item.str("location"),
                    remark: item.str("remark"),
                    remindMinutes: item.intVal("remindMinutes"),
                    status: item.str("status"),
                    isOwner: item.boolVal("isOwner"),
                    isInvited: item.boolVal("isInvited"),
                    creatorName: item.str("creatorName"),
                    participants: item.objects("participants").map {
                        AgendaParticipantInfo(id: $0.str("id"), name: $0.str("name"))
                    }
                )
            }
        )
    }

    static func save(
        id: String?,
        title: String,
        date: String,
        startTime: String,
        endTime: String,
        location: String,
        remark: String,
        remindMinutes: Int
    ) async throws {
        var payload: JSON = [
            "title": title,
            "date": date,
            "startTime": startTime,
            "remindMinutes": remindMinutes
        ]
        if let id = id, !id.isEmpty { payload["id"] = id }
        if !endTime.isEmpty { payload["endTime"] = endTime }
        if !location.isEmpty { payload["location"] = location }
        if !remark.isEmpty { payload["remark"] = remark }
        _ = try await APIClient.shared.post("schedule.save", payload)
    }

    static func remove(id: String) async throws {
        _ = try await APIClient.shared.post("schedule.remove", ["id": id])
    }
}

// MARK: - 月切换工具

func shiftMonth(_ value: String, by delta: Int) -> String {
    let formatter = Fmt.monthFormatter
    guard let date = formatter.date(from: value) else { return value }
    let next = Calendar.current.date(byAdding: .month, value: delta, to: date) ?? date
    return formatter.string(from: next)
}

// MARK: - 考勤页

@MainActor
final class AttendanceViewModel: ObservableObject {
    @Published var month = Fmt.currentMonth()
    @Published var data: AttendanceMonthInfo?
    @Published var loading = true
    @Published var error: String?

    private var inFlight = false

    func load() async {
        if inFlight { return }
        inFlight = true
        loading = data == nil
        error = nil
        do {
            data = try await AttendanceRepo.my(month: month)
            loading = false
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
        inFlight = false
    }

    func prevMonth() {
        month = shiftMonth(month, by: -1)
        data = nil
        Task { await load() }
    }

    func nextMonth() {
        let next = shiftMonth(month, by: 1)
        if next > Fmt.currentMonth() { return }
        month = next
        data = nil
        Task { await load() }
    }
}

struct AttendanceView: View {
    @ObservedObject var model: AttendanceViewModel
    let onBack: () -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "考勤", subtitle: "月度出勤与异常明细", onBack: onBack)
            monthBar
            content
        }
        .background(AppColor.background.ignoresSafeArea())
        .task {
            if model.data == nil { await model.load() }
        }
    }

    private var monthBar: some View {
        HStack {
            Button("‹") { model.prevMonth() }
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(AppColor.primary)
                .frame(width: 44, height: 36)
            Text(model.month)
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
                .frame(maxWidth: .infinity)
            Button("›") { model.nextMonth() }
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(model.month < Fmt.currentMonth() ? AppColor.primary : AppColor.textSecondary.opacity(0.4))
                .frame(width: 44, height: 36)
                .disabled(model.month >= Fmt.currentMonth())
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        AttendanceStat(value: "\(data.summary.workDays)", label: "出勤天数", color: AppColor.text)
                        Divider().frame(height: 34)
                        AttendanceStat(value: fmtHours(data.summary.totalHours), label: "总工时", color: AppColor.text)
                        Divider().frame(height: 34)
                        AttendanceStat(
                            value: "\(data.summary.abnormalCount)",
                            label: "异常次数",
                            color: data.summary.abnormalCount > 0 ? Sem.bad : Sem.ok
                        )
                    }
                    .padding(.vertical, 16)
                    .cardSurface()

                    if data.days.isEmpty {
                        EmptyStateView(title: "本月暂无考勤记录", hint: "有打卡记录后会自动显示在这里。")
                    }
                    ForEach(data.days) { day in
                        dayCard(day)
                    }
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        } else if let error = model.error {
            ErrorStateView(message: error) {
                Task { await model.load() }
            }
            Spacer()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dayCard(_ day: AttendanceDayInfo) -> some View {
        let isOpen = expanded.contains(day.date)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(day.date)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                    Spacer()
                    StatusBadge(text: day.abnormal ? "异常" : "正常", kind: day.abnormal ? .bad : .ok)
                }
                Text("工时 \(fmtHours(day.totalHours)) 小时 · \(day.segments.count) 个时段")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                if isOpen { expanded.remove(day.date) } else { expanded.insert(day.date) }
            }

            if isOpen {
                Divider().background(AppColor.outline)
                VStack(alignment: .leading, spacing: 8) {
                    if day.segments.isEmpty {
                        Text("无时段记录")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    ForEach(day.segments.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().background(AppColor.outlineVariant)
                        }
                        segmentBlock(day.segments[index])
                    }
                }
                .padding(14)
            }
        }
        .cardSurface()
    }

    private func segmentBlock(_ segment: AttendanceSegmentInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("时段 \(segment.segmentNo)")
                    .font(.ssBody)
                    .foregroundColor(AppColor.text)
                Spacer()
                if segment.hourDiff != 0 {
                    Text((segment.hourDiff > 0 ? "+" : "") + fmtHours(segment.hourDiff) + "h")
                        .font(.ssCaption)
                        .foregroundColor(segment.hourDiff < 0 ? Sem.bad : Sem.ok)
                }
            }
            Text("计划 \(timeRange(segment.plannedIn, segment.plannedOut)) · 计薪 \(fmtHours(segment.plannedWorkHours))h")
                .font(.ssSmall)
                .foregroundColor(AppColor.textSecondary)
            if segment.mealHours != 0 {
                Text("用餐扣除 \(fmtHours(segment.mealHours))h")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            Text("打卡 \(timeRange(segment.clockIn, segment.clockOut)) · 实计 \(fmtHours(segment.actualHours))h")
                .font(.ssSmall)
                .foregroundColor(AppColor.textSecondary)
            if !segment.confirmIn.isEmpty || !segment.confirmOut.isEmpty {
                Text("确认 \(timeRange(segment.confirmIn, segment.confirmOut))")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            if !segment.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(segment.tags.indices, id: \.self) { index in
                            StatusBadge(text: segment.tags[index].text, kind: tagKind(segment.tags[index].cls))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct AttendanceStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 薪资页

@MainActor
final class SalaryViewModel: ObservableObject {
    @Published var months: [String] = []
    @Published var selectedMonth: String?
    @Published var detail: SalaryInfo?
    @Published var loading = true
    @Published var detailLoading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        do {
            let list = try await SalaryRepo.myMonths().sorted(by: >)
            months = list
            loading = false
            if let first = list.first {
                selectedMonth = first
                await select(first)
            }
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    func select(_ month: String) async {
        selectedMonth = month
        detailLoading = true
        error = nil
        do {
            detail = try await SalaryRepo.get(month: month)
            detailLoading = false
        } catch {
            detailLoading = false
            self.error = ErrText.readable(error)
        }
    }
}

struct SalaryView: View {
    @ObservedObject var model: SalaryViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "薪资", subtitle: "月度工资与扣款明细", onBack: onBack)
            content
        }
        .background(AppColor.background.ignoresSafeArea())
        .task {
            if model.months.isEmpty { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.months.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.months.isEmpty {
            if let error = model.error {
                ErrorStateView(message: error) { Task { await model.load() } }
            } else {
                EmptyStateView(title: "暂无薪资记录", hint: "薪资发布后会显示在这里。")
            }
            Spacer()
        } else {
            monthBar
            if model.detailLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = model.detail {
                salaryBody(detail)
            } else if let error = model.error {
                ErrorStateView(message: error) {
                    if let month = model.selectedMonth { Task { await model.select(month) } }
                }
            } else {
                EmptyStateView(title: "该月薪资尚未发布", hint: "薪资发布后会显示在这里。")
                Spacer()
            }
        }
    }

    private var monthBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.months, id: \.self) { month in
                    let active = month == model.selectedMonth
                    Button {
                        Task { await model.select(month) }
                    } label: {
                        Text(month)
                            .font(.ssSmall)
                            .foregroundColor(active ? AppColor.primary : AppColor.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(active ? AppColor.primaryContainer : AppColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    private func salaryBody(_ detail: SalaryInfo) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("实发工资")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                        Spacer()
                        StatusBadge(text: payLabel(detail.payStatus), kind: payKind(detail.payStatus))
                    }
                    Text(money(detail.netPay))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppColor.text)
                    Text("应发 \(money(detail.grossPay))")
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)
                    if detail.deductionTotal > 0 {
                        Text("扣款合计 \(money(detail.deductionTotal))")
                            .font(.ssSmall)
                            .foregroundColor(Sem.bad)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

                if detail.shouldDays > 0 || detail.actualDays > 0 || detail.totalHours > 0 {
                    HStack(spacing: 0) {
                        AttendanceStat(value: fmtHours(detail.shouldDays) + " 天", label: "应出勤", color: AppColor.text)
                        AttendanceStat(value: fmtHours(detail.actualDays) + " 天", label: "实出勤", color: AppColor.text)
                        AttendanceStat(value: fmtHours(detail.totalHours) + " h", label: "总工时", color: AppColor.text)
                    }
                    .padding(.vertical, 14)
                    .cardSurface()
                }

                MoneyGroupView(
                    title: "收入明细",
                    rows: [
                        ("基本工资", detail.baseSalary),
                        ("岗位津贴", detail.postAllowance),
                        ("绩效工资", detail.performancePay),
                        ("全勤奖", detail.fullAttendance),
                        ("日常加班", detail.dailyOvertimePay),
                        ("法定节假日加班", detail.statutoryHolidayPay),
                        ("餐补", detail.mealSubsidy),
                        ("交通补贴", detail.transportSubsidy),
                        ("出勤补贴", detail.attendanceSubsidy),
                        ("社保补贴", detail.socialSubsidy),
                        ("提成", detail.commission),
                        ("应发合计", detail.grossPay)
                    ],
                    emptyHint: "暂无收入项",
                    deduction: false
                )

                MoneyGroupView(
                    title: "扣款明细",
                    rows: [
                        ("盘点扣款", detail.inventoryDeduction),
                        ("迟到扣款", detail.lateDeduction),
                        ("考勤差异", detail.attendanceDiff),
                        ("事假/病假扣款", detail.leaveDeduction),
                        ("违纪扣款", detail.disciplineDeduction),
                        ("其他扣款", detail.otherDeduction),
                        ("社保个人部分", detail.insurance),
                        ("个人所得税", detail.tax),
                        ("扣款合计", detail.deductionTotal)
                    ],
                    emptyHint: "本月无扣款",
                    deduction: true
                )

                if !detail.payDate.isEmpty || !detail.publishAt.isEmpty || !detail.remark.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !detail.payDate.isEmpty {
                            DetailLine(label: "发放日期", value: detail.payDate)
                        }
                        if !detail.publishAt.isEmpty {
                            DetailLine(label: "发布时间", value: Fmt.dateTime(detail.publishAt))
                        }
                        if !detail.remark.isEmpty {
                            Text("备注").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                            Text(detail.remark).font(.ssSmall).foregroundColor(AppColor.text)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }
                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct MoneyGroupView: View {
    let title: String
    let rows: [(String, Double)]
    let emptyHint: String
    let deduction: Bool

    var body: some View {
        let visible = rows.filter { $0.1 != 0 }
        return VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
                .padding(.bottom, 6)
            if visible.isEmpty {
                Text(emptyHint)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.vertical, 6)
            }
            ForEach(visible.indices, id: \.self) { index in
                if index > 0 {
                    Divider().background(AppColor.outlineVariant)
                }
                HStack {
                    Text(visible[index].0)
                        .font(.ssBody14)
                        .foregroundColor(AppColor.textSecondary)
                    Spacer()
                    Text(money(visible[index].1))
                        .font(.ssBody14)
                        .foregroundColor(deduction ? Sem.bad : AppColor.text)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - 量化分页

@MainActor
final class ScoreViewModel: ObservableObject {
    @Published var months: [String] = []
    @Published var selectedMonth: String?
    @Published var record: ScoreRecordInfo?
    @Published var dimensions: [ScoreDimensionDefInfo] = []
    @Published var loading = true
    @Published var detailLoading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        let dimsTask = Task { try? await ScoreRepo.dimensions() }
        do {
            let records = try await ScoreRepo.my()
            months = records.map { $0.month }.filter { !$0.isEmpty }.sorted(by: >)
            loading = false
            dimensions = await dimsTask.value ?? []
            if let first = months.first {
                selectedMonth = first
                await select(first)
            }
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    func select(_ month: String) async {
        selectedMonth = month
        detailLoading = true
        error = nil
        do {
            record = try await ScoreRepo.get(month: month)
            detailLoading = false
        } catch {
            detailLoading = false
            self.error = ErrText.readable(error)
        }
    }
}

struct ScoreView: View {
    @ObservedObject var model: ScoreViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "量化分", subtitle: "维度得分与加减分明细", onBack: onBack)
            content
        }
        .background(AppColor.background.ignoresSafeArea())
        .task {
            if model.months.isEmpty { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.months.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.months.isEmpty {
            if let error = model.error {
                ErrorStateView(message: error) { Task { await model.load() } }
            } else {
                EmptyStateView(title: "暂无量化分记录", hint: "月度量化分发布后会显示在这里。")
            }
            Spacer()
        } else {
            monthBar
            if model.detailLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let record = model.record {
                ScrollView {
                    VStack(spacing: 12) {
                        scoreCard(record)
                        dimsCard(record)
                        adjustCard(record)
                        if !record.publishAt.isEmpty || !record.updatedAt.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                if !record.publishAt.isEmpty {
                                    Text("发布 \(Fmt.dateTime(record.publishAt))")
                                }
                                if !record.updatedAt.isEmpty {
                                    Text("更新 \(Fmt.dateTime(record.updatedAt))")
                                }
                            }
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer().frame(height: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            } else {
                EmptyStateView(title: "该月暂无量化分", hint: "可切换其他月份查看。")
                Spacer()
            }
        }
    }

    private var monthBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.months, id: \.self) { month in
                    let active = month == model.selectedMonth
                    Button {
                        Task { await model.select(month) }
                    } label: {
                        Text(month)
                            .font(.ssSmall)
                            .foregroundColor(active ? AppColor.primary : AppColor.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(active ? AppColor.primaryContainer : AppColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    private func scoreCard(_ record: ScoreRecordInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 2) {
                Text(fmtScore(record.total))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppColor.primary)
                Text("/100")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.bottom, 5)
                Spacer()
                StatusBadge(text: record.grade.isEmpty ? gradeLabel(record.total) : record.grade, kind: gradeKind(record.total))
            }
            ProgressBarView(ratio: record.total / 100)
        }
        .padding(18)
        .cardSurface()
    }

    private func dimsCard(_ record: ScoreRecordInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("维度得分")
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
            if record.dims.isEmpty {
                Text("暂无维度得分")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            ForEach(record.dims.indices, id: \.self) { index in
                let dim = record.dims[index]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dim.name.isEmpty ? dim.key : dim.name)
                            .font(.ssBody14)
                            .foregroundColor(AppColor.text)
                        Spacer()
                        Text("\(fmtScore(dim.score))/\(fmtScore(dim.full))")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    ProgressBarView(ratio: dim.full <= 0 ? 0 : dim.score / dim.full)
                    let desc = dimensionDesc(dim)
                    if !desc.isEmpty {
                        Text(desc)
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                if index < record.dims.count - 1 {
                    Divider().background(AppColor.outlineVariant)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func adjustCard(_ record: ScoreRecordInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("加减分明细")
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
            if record.adjust.isEmpty {
                Text("本月无加减分")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
            }
            ForEach(record.adjust.indices, id: \.self) { index in
                let item = record.adjust[index]
                HStack {
                    Text(item.reason.isEmpty ? "调整" : item.reason)
                        .font(.ssBody14)
                        .foregroundColor(AppColor.text)
                    Spacer()
                    Text((item.score >= 0 ? "+" : "") + fmtScore(item.score))
                        .font(.ssBody14)
                        .foregroundColor(item.score >= 0 ? Sem.ok : Sem.bad)
                }
                .padding(.vertical, 6)
                if index < record.adjust.count - 1 {
                    Divider().background(AppColor.outlineVariant)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func dimensionDesc(_ dim: ScoreDimensionInfo) -> String {
        if let item = model.dimensions.first(where: { !dim.key.isEmpty && $0.key == dim.key }) {
            return item.desc
        }
        return model.dimensions.first(where: { $0.name == dim.name })?.desc ?? ""
    }
}

// MARK: - 报销页

enum ReimburseFilter: String, CaseIterable, Identifiable {
    case all, pending, approved, rejected, paid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .pending: return "待审核"
        case .approved: return "已通过"
        case .rejected: return "已驳回"
        case .paid: return "已发放"
        }
    }

    var status: String? { self == .all ? nil : rawValue }
}

@MainActor
final class ReimburseViewModel: ObservableObject {
    @Published var claims: [ReimburseClaimInfo] = []
    @Published var categories: [ReimburseCategoryInfo] = []
    @Published var payees: [ReimbursePayeeInfo] = []
    @Published var loading = true
    @Published var error: String?
    @Published var filter: ReimburseFilter = .all
    @Published var page = 1
    @Published var detail: ReimburseClaimInfo?
    @Published var showCreate = false
    @Published var submitting = false
    @Published var uploading = false
    @Published var attachments: [ReimburseAttachmentInfo] = []
    @Published var formError: String?
    @Published var flash: Flash?

    func load() async {
        loading = claims.isEmpty
        error = nil
        do {
            if categories.isEmpty {
                async let cat = ReimburseRepo.categories()
                async let pay = ReimburseRepo.payees()
                categories = (try? await cat) ?? []
                payees = (try? await pay) ?? []
            }
            claims = try await ReimburseRepo.my(status: filter.status)
            loading = false
            page = 1
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    func setFilter(_ value: ReimburseFilter) async {
        filter = value
        page = 1
        await load()
    }

    func openCreate() {
        formError = nil
        showCreate = true
    }

    func closeCreate() {
        if submitting || uploading { return }
        showCreate = false
        attachments = []
        formError = nil
    }

    func addAttachment(images: [UIImage]) async {
        guard !images.isEmpty else { return }
        uploading = true
        do {
            for (index, image) in images.enumerated() {
                guard attachments.count < 5 else { break }
                guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
                if data.count > 10 * 1024 * 1024 {
                    throw APIError(code: "FILE_TOO_LARGE", message: "单个附件不能超过 10MB")
                }
                let name = "receipt_\(Int(Date().timeIntervalSince1970))_\(index).jpg"
                let uploaded = try await UploadRepository.uploadReimburse(data: data, filename: name, mime: "image/jpeg")
                attachments.append(uploaded)
            }
            uploading = false
        } catch {
            uploading = false
            formError = ErrText.readable(error)
        }
    }

    func addAttachment(url: URL) async {
        guard attachments.count < 5 else {
            formError = "最多上传 5 个附件"
            return
        }
        uploading = true
        do {
            let data = try Data(contentsOf: url)
            if data.count > 10 * 1024 * 1024 {
                throw APIError(code: "FILE_TOO_LARGE", message: "单个附件不能超过 10MB")
            }
            let ext = url.pathExtension.lowercased()
            let mime: String
            if ext == "pdf" {
                mime = "application/pdf"
            } else if ext == "png" {
                mime = "image/png"
            } else if ext == "webp" {
                mime = "image/webp"
            } else {
                mime = "image/jpeg"
            }
            let uploaded = try await UploadRepository.uploadReimburse(data: data, filename: url.lastPathComponent, mime: mime)
            attachments.append(uploaded)
            uploading = false
        } catch {
            uploading = false
            formError = ErrText.readable(error)
        }
    }

    func removeAttachment(_ key: String) {
        attachments.removeAll { $0.key == key }
    }

    func submit(
        categoryId: String,
        amountText: String,
        reason: String,
        payeeType: String,
        account: String,
        bankName: String,
        holderName: String,
        payeeId: String?
    ) async {
        let amount = Double(amountText) ?? 0
        if categoryId.isEmpty {
            formError = "请选择报销分类"
            return
        }
        if amount <= 0 {
            formError = "请输入正确的报销金额"
            return
        }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            formError = "报销事由至少 2 个字"
            return
        }
        if account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formError = "请填写收款账号"
            return
        }
        if holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formError = "请填写收款人姓名"
            return
        }
        if payeeType == "bank" && bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formError = "请填写开户行"
            return
        }
        submitting = true
        formError = nil
        do {
            try await ReimburseRepo.create(
                categoryId: categoryId,
                amount: amount,
                reason: reason,
                attachments: attachments.map { $0.key },
                payeeId: payeeId,
                type: payeeType,
                account: account,
                bankName: payeeType == "bank" ? bankName : "",
                holderName: holderName
            )
            submitting = false
            showCreate = false
            attachments = []
            flash = Flash(text: "报销申请已提交，等待店长审核")
            await load()
        } catch {
            submitting = false
            formError = ErrText.readable(error)
        }
    }

    func clearFlash() { flash = nil }
}

struct ReimburseView: View {
    @ObservedObject var model: ReimburseViewModel
    let onBack: () -> Void

    @State private var previewTarget: PreviewTarget?

    private let pageSize = 20

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                filterRow
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
            if model.claims.isEmpty { await model.load() }
        }
        .sheet(isPresented: $model.showCreate) {
            ReimburseCreateSheet(model: model)
        }
        .sheet(item: $model.detail) { claim in
            ReimburseDetailSheet(claim: claim) { previewTarget = PreviewTarget(key: $0) }
        }
        .sheet(item: $previewTarget) { target in
            ImagePreviewSheet(key: target.key)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("我的报销")
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.text)
                Text(model.claims.isEmpty ? "提交与审批进度" : "当前 \(model.claims.count) 条记录")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
            Button {
                model.openCreate()
            } label: {
                Text("新建")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ReimburseFilter.allCases) { filter in
                    let active = model.filter == filter
                    Button {
                        Task { await model.setFilter(filter) }
                    } label: {
                        Text(filter.label)
                            .font(.ssCaption)
                            .foregroundColor(active ? AppColor.primary : AppColor.textSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(active ? AppColor.primaryContainer : AppColor.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.claims.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.claims.isEmpty {
            ErrorStateView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.claims.isEmpty {
            EmptyStateView(
                title: model.filter == .all ? "还没有报销申请" : "暂无该状态的报销",
                hint: model.filter == .all ? "点击右上角「新建」提交报销，审批进度会显示在这里。" : "可切换其他状态查看。"
            )
            Spacer()
        } else {
            claimList
        }
    }

    private var claimList: some View {
        let pageCount = max(1, (model.claims.count + pageSize - 1) / pageSize)
        let page = min(max(1, model.page), pageCount)
        let start = (page - 1) * pageSize
        let visible = Array(model.claims.dropFirst(start).prefix(pageSize))
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visible) { claim in
                        claimCard(claim)
                    }
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            if pageCount > 1 {
                HStack {
                    Button("上一页") { model.page = max(1, page - 1) }
                        .font(.ssSmall)
                        .foregroundColor(page > 1 ? AppColor.primary : AppColor.textSecondary.opacity(0.4))
                        .disabled(page <= 1)
                    Spacer()
                    Text("第 \(page)/\(pageCount) 页 · 共 \(model.claims.count) 条")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    Spacer()
                    Button("下一页") { model.page = min(pageCount, page + 1) }
                        .font(.ssSmall)
                        .foregroundColor(page < pageCount ? AppColor.primary : AppColor.textSecondary.opacity(0.4))
                        .disabled(page >= pageCount)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func claimCard(_ claim: ReimburseClaimInfo) -> some View {
        Button {
            model.detail = claim
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(claim.categoryName.isEmpty ? "报销" : claim.categoryName)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusBadge(text: reimburseStatusLabel(claim.status), kind: reimburseStatusKind(claim.status))
                }
                Text(money(claim.amount))
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.primary)
                if !claim.reason.isEmpty {
                    Text(claim.reason)
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(2)
                }
                Text(Fmt.time(claim.createdAt))
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                if claim.status == "rejected" && !claim.rejectReason.isEmpty {
                    Text("驳回原因：\(claim.rejectReason)")
                        .font(.ssSmall)
                        .foregroundColor(Sem.bad)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ReimburseCreateSheet: View {
    @ObservedObject var model: ReimburseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var categoryId = ""
    @State private var amountText = ""
    @State private var reason = ""
    @State private var payeeType = "alipay"
    @State private var payeeId: String?
    @State private var account = ""
    @State private var bankName = ""
    @State private var holderName = ""
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        Text("报销分类").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        if model.categories.isEmpty {
                            Text("加载分类中…").font(.ssSmall).foregroundColor(AppColor.textSecondary)
                        } else {
                            Picker("报销分类", selection: $categoryId) {
                                ForEach(model.categories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColor.primary)
                        }

                        Text("金额（元）").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.ssBody)
                            .padding(12)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: amountText) { value in
                                var filtered = String(value.filter { $0.isNumber || $0 == "." }.prefix(10))
                                if filtered.filter({ $0 == "." }).count > 1 {
                                    filtered = String(filtered.dropLast())
                                }
                                if filtered != value { amountText = filtered }
                            }

                        Text("报销事由").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextEditor(text: $reason)
                            .font(.ssBody14)
                            .frame(minHeight: 70)
                            .padding(8)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: reason) { value in
                                if value.count > 200 { reason = String(value.prefix(200)) }
                            }
                    }

                    Group {
                        if !model.payees.isEmpty {
                            Text("常用收款账户").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(model.payees) { payee in
                                        Button {
                                            payeeId = payee.id
                                            payeeType = payee.type.isEmpty ? "alipay" : payee.type
                                            account = payee.account
                                            bankName = payee.bankName
                                            holderName = payee.holderName
                                        } label: {
                                            Text(payeeLabel(payee))
                                                .font(.ssCaption)
                                                .foregroundColor(payeeId == payee.id ? AppColor.primary : AppColor.textSecondary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(payeeId == payee.id ? AppColor.primaryContainer : AppColor.surface)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Text("收款方式").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        HStack(spacing: 8) {
                            ForEach([("alipay", "支付宝"), ("bank", "银行卡")], id: \.0) { item in
                                Button {
                                    payeeType = item.0
                                } label: {
                                    Text(item.1)
                                        .font(.ssSmall)
                                        .foregroundColor(payeeType == item.0 ? AppColor.primary : AppColor.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(payeeType == item.0 ? AppColor.primaryContainer : AppColor.surface)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("收款账号").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextField(payeeType == "bank" ? "银行卡号" : "支付宝账号", text: $account)
                            .font(.ssBody14)
                            .padding(12)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: account) { _ in payeeId = nil }

                        if payeeType == "bank" {
                            Text("开户行").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                            TextField("如：中国工商银行 XX 支行", text: $bankName)
                                .font(.ssBody14)
                                .padding(12)
                                .background(AppColor.surfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                                .onChange(of: bankName) { _ in payeeId = nil }
                        }

                        Text("收款人姓名").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextField("收款人姓名", text: $holderName)
                            .font(.ssBody14)
                            .padding(12)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: holderName) { _ in payeeId = nil }
                    }

                    Group {
                        Text("附件").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        HStack(spacing: 8) {
                            Button {
                                showImagePicker = true
                            } label: {
                                Text(model.attachments.isEmpty ? "选择图片" : "添加图片（\(model.attachments.count)/5）")
                                    .font(.ssSmall)
                                    .foregroundColor(AppColor.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                            .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.uploading || model.attachments.count >= 5)

                            Button {
                                showDocumentPicker = true
                            } label: {
                                Text("选择 PDF")
                                    .font(.ssSmall)
                                    .foregroundColor(AppColor.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                            .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.uploading || model.attachments.count >= 5)

                            if model.uploading {
                                ProgressView().scaleEffect(0.7)
                            }
                        }
                        Text("支持 JPG / PNG / WEBP / PDF，单个不超过 10MB，最多 5 个。")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)

                        ForEach(model.attachments) { attachment in
                            HStack {
                                Text(attachment.name)
                                    .font(.ssSmall)
                                    .foregroundColor(AppColor.text)
                                    .lineLimit(1)
                                Spacer()
                                Button("移除") { model.removeAttachment(attachment.key) }
                                    .font(.ssSmall)
                                    .foregroundColor(Sem.bad)
                            }
                        }

                        if let error = model.formError {
                            Text(error)
                                .font(.ssSmall)
                                .foregroundColor(Sem.bad)
                        }

                        Button {
                            Task {
                                await model.submit(
                                    categoryId: categoryId,
                                    amountText: amountText,
                                    reason: reason,
                                    payeeType: payeeType,
                                    account: account,
                                    bankName: bankName,
                                    holderName: holderName,
                                    payeeId: payeeId
                                )
                                if !model.showCreate { dismiss() }
                            }
                        } label: {
                            Text(model.submitting ? "提交中…" : "提交")
                                .font(.ssBody14)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(model.submitting ? AppColor.primary.opacity(0.6) : AppColor.primary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        }
                        .disabled(model.submitting || model.uploading)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("新建报销")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.closeCreate(); dismiss() }
                        .disabled(model.submitting)
                }
            }
            .onAppear {
                if categoryId.isEmpty { categoryId = model.categories.first?.id ?? "" }
                if model.payees.count == 1, let payee = model.payees.first {
                    payeeId = payee.id
                    payeeType = payee.type.isEmpty ? "alipay" : payee.type
                    account = payee.account
                    bankName = payee.bankName
                    holderName = payee.holderName
                }
            }
            .sheet(isPresented: $showImagePicker) {
                PhotoPicker(limit: max(1, 5 - model.attachments.count)) { images in
                    showImagePicker = false
                    Task { await model.addAttachment(images: images) }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    showDocumentPicker = false
                    Task { await model.addAttachment(url: url) }
                }
            }
        }
        .interactiveDismissDisabled(model.submitting || model.uploading)
    }
}

struct ReimburseDetailSheet: View {
    let claim: ReimburseClaimInfo
    let onPreview: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(money(claim.amount))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppColor.primary)
                        StatusBadge(text: reimburseStatusLabel(claim.status), kind: reimburseStatusKind(claim.status))
                    }
                    Group {
                        DetailLine(label: "提交时间", value: Fmt.time(claim.createdAt))
                        DetailLine(label: "事由", value: claim.reason.isEmpty ? "—" : claim.reason)
                        DetailLine(label: "收款方式", value: claim.payeeType == "bank" ? "银行卡" : "支付宝")
                        DetailLine(label: "收款账号", value: claim.payeeAccount.isEmpty ? "—" : claim.payeeAccount)
                        if !claim.payeeBank.isEmpty {
                            DetailLine(label: "开户行", value: claim.payeeBank)
                        }
                        DetailLine(label: "收款人", value: claim.payeeHolder.isEmpty ? "—" : claim.payeeHolder)
                        if !claim.reviewedBy.isEmpty {
                            DetailLine(label: "审核人", value: claim.reviewedBy + (claim.reviewedAt.isEmpty ? "" : " · " + Fmt.time(claim.reviewedAt)))
                        }
                        if !claim.paidAt.isEmpty {
                            DetailLine(label: "发放时间", value: Fmt.time(claim.paidAt))
                        }
                        if !claim.rejectReason.isEmpty {
                            Text("驳回原因：\(claim.rejectReason)")
                                .font(.ssSmall)
                                .foregroundColor(Sem.bad)
                                .padding(.top, 6)
                        }
                    }
                    if !claim.attachments.isEmpty {
                        Text("附件")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                            .padding(.top, 10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(claim.attachments, id: \.self) { key in
                                    AttachmentThumbView(key: key) { onPreview(key) }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(claim.categoryName.isEmpty ? "报销详情" : claim.categoryName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct AttachmentThumbView: View {
    let key: String
    let onTap: () -> Void

    var body: some View {
        if key.lowercased().hasSuffix(".pdf") {
            Button {
                if let url = fileURL(key) { UIApplication.shared.open(url) }
            } label: {
                Text("PDF 附件")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(AppColor.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            RemoteImage(key: key, corner: Radius.badge, onTap: onTap)
                .frame(width: 64, height: 64)
        }
    }
}

// MARK: - 通讯录页

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var list: [ContactInfo] = []
    @Published var storeName = ""
    @Published var loading = true
    @Published var error: String?
    @Published var query = ""
    @Published var page = 1
    @Published var detail: ContactInfo?
    @Published var sending = false
    @Published var sendError: String?
    @Published var flash: Flash?

    func load() async {
        loading = true
        error = nil
        do {
            let (data, store) = try await ContactsRepo.list()
            list = data
            storeName = store
            loading = false
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    func setQuery(_ value: String) {
        query = value
        page = 1
    }

    func sendPrivate(to staff: ContactInfo, body: String) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            sendError = "请输入私信内容"
            return false
        }
        sending = true
        sendError = nil
        do {
            _ = try await MessageRepository.send(toStaffId: staff.id, body: text)
            sending = false
            detail = nil
            flash = Flash(text: "私信已发送给 \(staff.name)")
            return true
        } catch {
            sending = false
            sendError = ErrText.readable(error)
            return false
        }
    }

    func clearFlash() { flash = nil }
}

struct ContactsView: View {
    @ObservedObject var model: ContactsViewModel
    let onBack: () -> Void

    private let pageSize = 20

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                searchBox
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
            if model.list.isEmpty { await model.load() }
        }
        .sheet(item: $model.detail) { staff in
            ContactDetailSheet(model: model, staff: staff)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("门店通讯录")
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.text)
                Text(model.storeName.isEmpty ? "点击同事查看电话与私信" : model.storeName)
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
            if !model.list.isEmpty {
                Text("\(model.list.count) 人")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 4)
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(AppColor.textSecondary)
            TextField("搜索姓名 / 岗位 / 手机号 / 工号", text: Binding(
                get: { model.query },
                set: { model.setQuery($0) }
            ))
            .font(.ssBody14)
            if !model.query.isEmpty {
                Button {
                    model.setQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.list.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.list.isEmpty {
            ErrorStateView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.list.isEmpty {
            EmptyStateView(title: "暂无通讯录数据", hint: "门店在职员工信息会显示在这里。")
            Spacer()
        } else if filtered.isEmpty {
            EmptyStateView(title: "没有匹配的同事", hint: "试试更换姓名、岗位或工号关键词。")
            Spacer()
        } else {
            staffList
        }
    }

    private var filtered: [ContactInfo] {
        let keyword = model.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return model.list }
        return model.list.filter { staff in
            [staff.name, staff.nickname, staff.position, staff.phone, staff.empNo, staff.feishuEmpNo]
                .joined(separator: " ")
                .lowercased()
                .contains(keyword)
        }
    }

    private var staffList: some View {
        let pageCount = max(1, (filtered.count + pageSize - 1) / pageSize)
        let page = min(max(1, model.page), pageCount)
        let visible = Array(filtered.dropFirst((page - 1) * pageSize).prefix(pageSize))
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visible) { staff in
                        staffCard(staff)
                    }
                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if pageCount > 1 {
                HStack {
                    Button("上一页") { model.page = max(1, page - 1) }
                        .font(.ssSmall)
                        .foregroundColor(page > 1 ? AppColor.primary : AppColor.textSecondary.opacity(0.4))
                        .disabled(page <= 1)
                    Spacer()
                    Text("第 \(page)/\(pageCount) 页 · 共 \(filtered.count) 人")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    Spacer()
                    Button("下一页") { model.page = min(pageCount, page + 1) }
                        .font(.ssSmall)
                        .foregroundColor(page < pageCount ? AppColor.primary : AppColor.textSecondary.opacity(0.4))
                        .disabled(page >= pageCount)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func staffCard(_ staff: ContactInfo) -> some View {
        Button {
            model.detail = staff
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColor.primaryContainer)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(staff.name.prefix(1)))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColor.primary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(staff.name.isEmpty ? "同事" : staff.name)
                            .font(.ssTitle4)
                            .foregroundColor(AppColor.text)
                        if !staff.nickname.isEmpty {
                            Text("（\(staff.nickname)）")
                                .font(.ssCaption)
                                .foregroundColor(AppColor.textSecondary)
                        }
                    }
                    Text(staff.position.isEmpty ? "员工" : staff.position)
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)
                    let meta = [staff.phone.isEmpty ? nil : "电话 \(staff.phone)", staff.empNo.isEmpty ? nil : "工号 \(staff.empNo)"]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColor.textSecondary)
            }
            .padding(14)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ContactDetailSheet: View {
    @ObservedObject var model: ContactsViewModel
    let staff: ContactInfo
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    DetailLine(label: "岗位", value: staff.position.isEmpty ? "—" : staff.position)
                    DetailLine(label: "手机号", value: staff.phone.isEmpty ? "—" : staff.phone)
                    DetailLine(label: "工号", value: staff.empNo.isEmpty ? "—" : staff.empNo)
                    if !staff.feishuEmpNo.isEmpty { DetailLine(label: "飞书工号", value: staff.feishuEmpNo) }
                    if !staff.employmentType.isEmpty { DetailLine(label: "用工类型", value: staff.employmentType) }
                    if !staff.nickname.isEmpty { DetailLine(label: "昵称", value: staff.nickname) }

                    Text("发私信")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 12)
                    TextEditor(text: $message)
                        .font(.ssBody14)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .onChange(of: message) { value in
                            if value.count > 500 { message = String(value.prefix(500)) }
                        }
                    if let error = model.sendError {
                        Text(error)
                            .font(.ssSmall)
                            .foregroundColor(Sem.bad)
                    }

                    HStack(spacing: 10) {
                        Button {
                            if !staff.phone.isEmpty, let url = URL(string: "tel://\(staff.phone)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("拨打电话")
                                .font(.ssBody14)
                                .foregroundColor(AppColor.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                                        .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(staff.phone.isEmpty)

                        Button {
                            Task {
                                let ok = await model.sendPrivate(to: staff, body: message)
                                if ok { dismiss() }
                            }
                        } label: {
                            Text(model.sending ? "发送中…" : "发送私信")
                                .font(.ssBody14)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColor.primary.opacity(0.4) : AppColor.primary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(staff.name.isEmpty ? "同事" : staff.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 日程页

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published var scope = "mine"
    @Published var canViewAll = false
    @Published var items: [AgendaItemInfo] = []
    @Published var loading = true
    @Published var error: String?
    @Published var showEditor = false
    @Published var editing: AgendaItemInfo?
    @Published var saving = false
    @Published var deletingId = ""
    @Published var formError: String?
    @Published var flash: Flash?

    func load() async {
        loading = items.isEmpty
        error = nil
        do {
            let data = try await AgendaRepo.list(scope: scope)
            canViewAll = data.canViewAll
            items = data.list
            loading = false
        } catch is SessionExpiredError {
            loading = false
        } catch {
            loading = false
            self.error = ErrText.readable(error)
        }
    }

    func setScope(_ value: String) async {
        scope = value
        items = []
        await load()
    }

    func startCreate() {
        editing = nil
        formError = nil
        showEditor = true
    }

    func startEdit(_ item: AgendaItemInfo) {
        editing = item
        formError = nil
        showEditor = true
    }

    func closeEditor() {
        if saving { return }
        showEditor = false
        editing = nil
        formError = nil
    }

    func save(title: String, date: String, startTime: String, endTime: String, location: String, remark: String, remindMinutes: Int) async {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formError = "请填写日程标题"
            return
        }
        if date.isEmpty || startTime.isEmpty {
            formError = "请选择日期与开始时间"
            return
        }
        saving = true
        formError = nil
        do {
            try await AgendaRepo.save(
                id: editing?.id,
                title: title,
                date: date,
                startTime: startTime,
                endTime: endTime,
                location: location,
                remark: remark,
                remindMinutes: remindMinutes
            )
            saving = false
            showEditor = false
            editing = nil
            flash = Flash(text: "日程已保存")
            await load()
        } catch {
            saving = false
            formError = ErrText.readable(error)
        }
    }

    func remove(_ item: AgendaItemInfo) async {
        deletingId = item.id
        do {
            try await AgendaRepo.remove(id: item.id)
            deletingId = ""
            flash = Flash(text: "日程已删除")
            await load()
        } catch {
            deletingId = ""
            flash = Flash(text: ErrText.readable(error), error: true)
        }
    }

    func clearFlash() { flash = nil }
}

struct AgendaView: View {
    @ObservedObject var model: AgendaViewModel
    let onBack: () -> Void

    @State private var deleteTarget: AgendaItemInfo?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                if model.canViewAll { scopeTabs }
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
            if model.items.isEmpty { await model.load() }
        }
        .sheet(isPresented: $model.showEditor) {
            AgendaEditorSheet(model: model)
        }
        .alert("删除日程", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除", role: .destructive) {
                if let target = deleteTarget {
                    deleteTarget = nil
                    Task { await model.remove(target) }
                }
            }
        } message: {
            Text("确认删除「\(deleteTarget?.title ?? "该日程")」？删除后不可恢复。")
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
            VStack(alignment: .leading, spacing: 2) {
                Text("日程")
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.text)
                Text(model.scope == "all" ? "门店全部日程" : "我的日程")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
            Button {
                model.startCreate()
            } label: {
                Text("新建")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }

    private var scopeTabs: some View {
        HStack(spacing: 8) {
            ForEach([("mine", "我的"), ("all", "全部")], id: \.0) { item in
                let active = model.scope == item.0
                Button {
                    Task { await model.setScope(item.0) }
                } label: {
                    Text(item.1)
                        .font(.ssSmall)
                        .foregroundColor(active ? AppColor.primary : AppColor.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(active ? AppColor.primaryContainer : AppColor.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.items.isEmpty {
            ErrorStateView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.items.isEmpty {
            EmptyStateView(
                title: model.scope == "all" ? "暂无门店日程" : "还没有日程",
                hint: model.scope == "all" ? "门店创建的公共日程会显示在这里。" : "点击右上角「新建」添加个人日程。"
            )
            Spacer()
        } else {
            agendaList
        }
    }

    private var agendaList: some View {
        let today = Fmt.today()
        let todayItems = model.items.filter { $0.date == today }.sorted { $0.startTime < $1.startTime }
        let futureItems = model.items.filter { $0.date > today }.sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
        let pastItems = model.items.filter { $0.date < today }.sorted { ($0.date, $0.startTime) > ($1.date, $1.startTime) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !todayItems.isEmpty {
                    GroupHeaderView(text: "今天")
                    ForEach(todayItems) { item in agendaCard(item) }
                }
                if !futureItems.isEmpty {
                    GroupHeaderView(text: "未来")
                    ForEach(futureItems) { item in agendaCard(item) }
                }
                if !pastItems.isEmpty {
                    GroupHeaderView(text: "过去")
                    ForEach(pastItems) { item in agendaCard(item) }
                }
                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func agendaCard(_ item: AgendaItemInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agendaDateLabel(item.date))
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    Text(item.startTime.isEmpty ? "--:--" : item.startTime)
                        .font(.ssTitle4)
                        .foregroundColor(AppColor.primary)
                    if !item.endTime.isEmpty {
                        Text("至 \(item.endTime)")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "未命名日程" : item.title)
                        .font(.ssBody)
                        .foregroundColor(AppColor.text)
                        .lineLimit(2)
                    if !item.location.isEmpty {
                        Text("地点：\(item.location)")
                            .font(.ssSmall)
                            .foregroundColor(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                    Text("创建人 \(item.creatorName.isEmpty ? "—" : item.creatorName)" + (item.isInvited ? " · 邀请我参与" : ""))
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !item.remark.isEmpty {
                Text(item.remark)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.text)
                    .lineLimit(3)
            }
            if !item.participants.isEmpty {
                Text("参与人：\(item.participants.map { $0.name }.joined(separator: "、"))")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                    .lineLimit(1)
            }
            if item.isOwner {
                HStack(spacing: 8) {
                    OutlineSmallButton(title: "编辑") { model.startEdit(item) }
                    Button {
                        deleteTarget = item
                    } label: {
                        Text(model.deletingId == item.id ? "删除中…" : "删除")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Sem.bad)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.deletingId == item.id)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct GroupHeaderView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ssTitle4)
            .foregroundColor(AppColor.text)
            .padding(.top, 6)
    }
}

struct AgendaEditorSheet: View {
    @ObservedObject var model: AgendaViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var day = Date()
    @State private var start = Date()
    @State private var end: Date?
    @State private var location = ""
    @State private var remark = ""
    @State private var remindMinutes = 0

    private let remindOptions: [(Int, String)] = [
        (-1, "不提醒"), (0, "准时"), (5, "提前5分钟"), (15, "提前15分钟"), (30, "提前30分钟"), (60, "提前1小时")
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        Text("标题").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextField("如：周会 / 团建 / 盘点", text: $title)
                            .font(.ssBody14)
                            .padding(12)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: title) { value in
                                if value.count > 60 { title = String(value.prefix(60)) }
                            }

                        Text("日期").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        DatePicker("", selection: $day, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()

                        Text("时间").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        HStack(spacing: 12) {
                            DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                                .font(.ssSmall)
                            if end != nil {
                                DatePicker("结束", selection: Binding(
                                    get: { end ?? start },
                                    set: { end = $0 }
                                ), displayedComponents: .hourAndMinute)
                                .font(.ssSmall)
                            }
                        }
                        Button {
                            if end == nil {
                                end = Calendar.current.date(byAdding: .hour, value: 1, to: start)
                            } else {
                                end = nil
                            }
                        } label: {
                            Text(end == nil ? "添加结束时间（选填）" : "清除结束时间")
                                .font(.ssCaption)
                                .foregroundColor(AppColor.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Group {
                        Text("地点").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextField("选填", text: $location)
                            .font(.ssBody14)
                            .padding(12)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))

                        Text("备注").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        TextEditor(text: $remark)
                            .font(.ssBody14)
                            .frame(minHeight: 70)
                            .padding(8)
                            .background(AppColor.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            .onChange(of: remark) { value in
                                if value.count > 200 { remark = String(value.prefix(200)) }
                            }

                        Text("提醒").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(remindOptions, id: \.0) { option in
                                    Button {
                                        remindMinutes = option.0
                                    } label: {
                                        Text(option.1)
                                            .font(.ssCaption)
                                            .foregroundColor(remindMinutes == option.0 ? AppColor.primary : AppColor.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(remindMinutes == option.0 ? AppColor.primaryContainer : AppColor.surface)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Group {
                        if let editing = model.editing, !editing.participants.isEmpty {
                            Text("参与人").font(.ssCaption).foregroundColor(AppColor.textSecondary)
                            Text(editing.participants.map { $0.name }.joined(separator: "、"))
                                .font(.ssSmall)
                                .foregroundColor(AppColor.textSecondary)
                        }

                        if let error = model.formError {
                            Text(error)
                                .font(.ssSmall)
                                .foregroundColor(Sem.bad)
                        }

                        Button {
                            Task {
                                await model.save(
                                    title: title,
                                    date: Fmt.localDateString(day),
                                    startTime: timeText(start),
                                    endTime: end.map { timeText($0) } ?? "",
                                    location: location,
                                    remark: remark,
                                    remindMinutes: remindMinutes
                                )
                                if !model.showEditor { dismiss() }
                            }
                        } label: {
                            Text(model.saving ? "保存中…" : "保存")
                                .font(.ssBody14)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(model.saving ? AppColor.primary.opacity(0.6) : AppColor.primary)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        }
                        .disabled(model.saving)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(model.editing == nil ? "新建日程" : "编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.closeEditor(); dismiss() }
                        .disabled(model.saving)
                }
            }
            .onAppear(perform: initialize)
        }
        .interactiveDismissDisabled(model.saving)
    }

    private func initialize() {
        guard let editing = model.editing else {
            start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            return
        }
        title = editing.title
        day = Fmt.date(from: editing.date) ?? Date()
        start = Fmt.combine(date: editing.date, time: editing.startTime) ?? Date()
        if !editing.endTime.isEmpty {
            end = Fmt.combine(date: editing.date, time: editing.endTime)
        }
        location = editing.location
        remark = editing.remark
        remindMinutes = editing.remindMinutes
    }

    private func timeText(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }
}

// MARK: - 通用小部件

struct DetailHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.text)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ssTitle3)
                    .foregroundColor(AppColor.text)
                Text(subtitle)
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.ssSmall)
                .foregroundColor(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

struct ProgressBarView: View {
    let ratio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.surfaceVariant)
                Capsule()
                    .fill(AppColor.primary)
                    .frame(width: proxy.size.width * CGFloat(min(max(ratio, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

// MARK: - 格式化

func money(_ value: Double) -> String {
    String(format: "¥%.2f", value)
}

func fmtHours(_ value: Double) -> String {
    if value == value.rounded() { return String(Int(value)) }
    return String(format: "%.1f", value)
}

func fmtScore(_ value: Double) -> String {
    if value == value.rounded() { return String(Int(value)) }
    return String(format: "%.1f", value)
}

func timeRange(_ start: String, _ end: String) -> String {
    if start.isEmpty && end.isEmpty { return "—" }
    return (start.isEmpty ? "—" : start) + "–" + (end.isEmpty ? "—" : end)
}

func tagKind(_ cls: String) -> BadgeKind {
    let key = cls.lowercased()
    if key.contains("bad") || key.contains("danger") || key.contains("error") { return .bad }
    if key.contains("warn") { return .warn }
    if key.contains("ok") || key.contains("good") || key.contains("success") { return .ok }
    if key.contains("info") { return .info }
    return .neutral
}

func payLabel(_ status: String) -> String {
    switch status {
    case "paid": return "已发放"
    case "published": return "已发布"
    default: return status.isEmpty ? "未发布" : status
    }
}

func payKind(_ status: String) -> BadgeKind {
    switch status {
    case "paid": return .ok
    case "published": return .info
    default: return .neutral
    }
}

func gradeLabel(_ total: Double) -> String {
    if total >= 90 { return "优秀" }
    if total >= 80 { return "良好" }
    if total >= 70 { return "中等" }
    if total >= 60 { return "合格" }
    return "待提升"
}

func gradeKind(_ total: Double) -> BadgeKind {
    if total >= 90 { return .ok }
    if total >= 70 { return .info }
    if total >= 60 { return .warn }
    return .bad
}

func reimburseStatusLabel(_ status: String) -> String {
    switch status {
    case "pending": return "待审核"
    case "approved": return "已通过"
    case "rejected": return "已驳回"
    case "paid": return "已发放"
    default: return status.isEmpty ? "待审核" : status
    }
}

func reimburseStatusKind(_ status: String) -> BadgeKind {
    switch status {
    case "approved": return .ok
    case "paid": return .info
    case "rejected": return .bad
    default: return .warn
    }
}

func payeeLabel(_ payee: ReimbursePayeeInfo) -> String {
    let type = payee.type == "bank" ? "银行卡" : "支付宝"
    let tail = String(payee.account.suffix(4))
    return tail.isEmpty ? type : "\(type) · \(tail)"
}

func agendaDateLabel(_ date: String) -> String {
    if date.isEmpty { return "" }
    if date == Fmt.today() { return "今天" }
    if date.count >= 10 { return String(date.dropFirst(5)).replacingOccurrences(of: "-", with: "/") }
    return date
}
