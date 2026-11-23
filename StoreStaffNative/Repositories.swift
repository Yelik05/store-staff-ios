import Foundation
import UIKit

// MARK: - 认证

enum AuthRepository {
    @discardableResult
    static func login(phone: String, password: String) async throws -> JSON {
        let data = try await APIClient.shared.post("auth.appLogin", [
            "phone": phone,
            "password": password,
            "platform": AppConfig.platform,
            "deviceName": UIDevice.current.model,
            "appVersion": AppConfig.version
        ])

        let account = data.dict("account") ?? [:]
        let staff = data.dict("staff") ?? [:]
        let store = data.dict("store") ?? [:]
        let staffName = staff.str("displayName").isEmpty ? staff.str("name") : staff.str("displayName")

        SessionStore.shared.save(
            token: data.str("token"),
            expiresAt: data.str("expiresAt"),
            accountName: account.str("name"),
            role: account.str("role"),
            staffName: staffName,
            position: staff.str("position"),
            empNo: staff.str("empNo"),
            storeName: store.str("name"),
            phone: account.str("phone"),
            lastLoginAt: account.str("lastLoginAt"),
            avatar: staff.str("avatar"),
            feishuEmpNo: staff.str("feishuEmpNo")
        )
        return data
    }

    /// 启动时用 Token 校验会话，同时刷新本地缓存的姓名 / 门店等信息。
    @discardableResult
    static func session() async throws -> JSON {
        let data = try await APIClient.shared.post("auth.appSession")
        let account = data.dict("account")
        let staff = data.dict("staff")
        let store = data.dict("store")
        let staffName = staff.map { $0.str("displayName").isEmpty ? $0.str("name") : $0.str("displayName") } ?? ""

        SessionStore.shared.updateProfile(
            accountName: account?.str("name") ?? SessionStore.shared.accountName,
            role: account?.str("role") ?? SessionStore.shared.role,
            staffName: staffName.isEmpty ? SessionStore.shared.staffName : staffName,
            position: staff?.str("position") ?? SessionStore.shared.position,
            empNo: staff?.str("empNo") ?? SessionStore.shared.empNo,
            storeName: store?.str("name") ?? SessionStore.shared.storeName,
            phone: account?.str("phone"),
            lastLoginAt: account?.str("lastLoginAt"),
            avatar: staff?.str("avatar"),
            feishuEmpNo: staff?.str("feishuEmpNo")
        )
        return data
    }

    /// 退出：先尝试撤销服务端 Token，失败也清本地。
    static func logout() async {
        _ = try? await APIClient.shared.post("auth.appLogout")
        SessionStore.shared.clear()
    }
}

// MARK: - 首页

enum HomeRepository {
    static func load() async throws -> HomeSnapshot {
        async let staffTask = APIClient.shared.post("staff.me")
        async let feedTask = APIClient.shared.post("notify.feed")
        let shiftTask = Task { try? await ShiftRepository.today() }

        let staff = try await staffTask
        let feed = try await feedTask
        let shift = await shiftTask.value
        let counts = feed.dict("counts") ?? [:]

        let displayName = staff.str("displayName").isEmpty ? staff.str("name") : staff.str("displayName")
        let position = staff.str("position")
        let empNo = staff.str("empNo")
        let feishuEmpNo = staff.str("feishuEmpNo")
        let avatar = staff.str("avatar")

        SessionStore.shared.updateProfile(
            accountName: SessionStore.shared.accountName,
            role: SessionStore.shared.role,
            staffName: displayName.isEmpty ? SessionStore.shared.staffName : displayName,
            position: position,
            empNo: empNo,
            storeName: SessionStore.shared.storeName,
            avatar: avatar,
            feishuEmpNo: feishuEmpNo
        )

        let shiftDate = shift?.date ?? ""
        return HomeSnapshot(
            displayName: displayName.isEmpty ? SessionStore.shared.staffName : displayName,
            position: position,
            employmentType: staff.str("employmentType"),
            empNo: empNo,
            feishuEmpNo: feishuEmpNo,
            avatar: avatar,
            storeName: SessionStore.shared.storeName,
            today: shiftDate.isEmpty ? Fmt.today() : shiftDate,
            shift: shift,
            unread: counts.intVal("unreadMessages"),
            todayPending: counts.intVal("todayPending"),
            overdue: counts.intVal("overdue")
        )
    }
}

// MARK: - 任务

enum TaskRepository {
    static func overview() async throws -> TaskOverview {
        let data = try await APIClient.shared.post("task.employee.list")
        var counts: [String: Int] = [:]
        if let raw = data.dict("counts") {
            raw.keys.forEach { counts[$0] = raw.intVal($0) }
        }
        return TaskOverview(
            items: data.objects("list").map { Parse.taskItem($0) },
            groups: data.objects("groups").map { Parse.taskGroup($0) },
            counts: counts,
            today: data.str("today"),
            todayPending: data.intVal("todayPending"),
            overdueCount: data.intVal("overdueCount"),
            myStaffId: data.str("myStaffId"),
            canManage: data.boolVal("canManage")
        )
    }

    static func submit(id: Int, imageKeys: [String]) async throws {
        var payload: JSON = ["id": id]
        if !imageKeys.isEmpty { payload["images"] = imageKeys }
        _ = try await APIClient.shared.post("task.employee.submit", payload)
    }

    static func reassign(id: Int?, groupId: String?, assigneeId: String) async throws {
        var payload: JSON = ["assigneeId": assigneeId]
        if let id = id, id > 0 { payload["id"] = id }
        if let groupId = groupId, !groupId.isEmpty { payload["groupId"] = groupId }
        _ = try await APIClient.shared.post("task.reassign", payload)
    }

    /// 管理岗（店长 / 店助）代完成他人任务，不进审核并留痕。
    static func manageComplete(id: Int) async throws {
        _ = try await APIClient.shared.post("task.manage.complete", ["id": id])
    }

    static func overdue() async throws -> TaskArchive {
        let data = try await APIClient.shared.post("task.employee.overdue")
        var counts: [String: Int] = [:]
        if let raw = data.dict("counts") {
            raw.keys.forEach { counts[$0] = raw.intVal($0) }
        }
        return TaskArchive(
            items: data.objects("list").map { Parse.taskItem($0) },
            counts: counts,
            date: data.str("date"),
            today: data.str("today")
        )
    }

    static func completed(date: String) async throws -> TaskArchive {
        let data = try await APIClient.shared.post("task.completed", ["date": date])
        var counts: [String: Int] = [:]
        if let raw = data.dict("counts") {
            raw.keys.forEach { counts[$0] = raw.intVal($0) }
        }
        return TaskArchive(
            items: data.objects("list").map { Parse.taskItem($0) },
            counts: counts,
            date: data.str("date"),
            today: data.str("today")
        )
    }

    static func contacts() async throws -> [TaskContact] {
        let data = try await APIClient.shared.post("staff.contacts")
        return data.objects("list").map {
            TaskContact(
                id: $0.str("id"),
                displayName: $0.str("displayName").isEmpty ? $0.str("name") : $0.str("displayName"),
                position: $0.str("position")
            )
        }
    }
}

// MARK: - 排班

enum ShiftRepository {
    static func today() async throws -> ShiftToday {
        let data = try await APIClient.shared.post("shift.today")
        return Parse.shiftToday(data)
    }

    static func my(month: String) async throws -> ShiftSummary {
        let data = try await APIClient.shared.post("shift.my", ["month": month])
        return ShiftSummary(
            month: data.str("month"),
            list: data.objects("list").map { Parse.shiftRequest($0) },
            pendingSlots: data.intVal("pendingSlots"),
            approvedSlots: data.intVal("approvedSlots")
        )
    }

    static func apply(slots: [ShiftSlot], note: String) async throws {
        let payload: JSON = [
            "slots": slots.map { ["date": $0.date, "start": $0.start, "end": $0.end] },
            "note": note
        ]
        _ = try await APIClient.shared.post("shift.apply", payload)
    }

    /// action=withdraw 撤回待审批；action=cancel 申请取消已通过。
    static func cancel(id: String, action: String) async throws {
        _ = try await APIClient.shared.post("shift.cancel", ["id": id, "action": action])
    }
}

// MARK: - 排休

enum LeaveRepository {
    static func my(month: String) async throws -> LeaveSummary {
        let data = try await APIClient.shared.post("leave.my", ["month": month])
        var byType: [String: Int] = [:]
        if let raw = data.dict("byType") {
            raw.keys.forEach { byType[$0] = raw.intVal($0) }
        }
        return LeaveSummary(
            month: data.str("month"),
            quota: data.doubleVal("quota"),
            used: data.intVal("used"),
            pending: data.intVal("pending"),
            remaining: data.doubleVal("remaining"),
            unused: data.doubleVal("unused"),
            byType: byType,
            list: data.objects("list").map { Parse.leaveItem($0) }
        )
    }

    static func dayStats(date: String) async throws -> LeaveDayStats {
        let data = try await APIClient.shared.post("leave.dayStats", ["date": date])
        return LeaveDayStats(
            date: data.str("date"),
            approved: data.intVal("approved"),
            pending: data.intVal("pending"),
            total: data.intVal("total"),
            storeLimit: data.intVal("storeLimit"),
            storeRemaining: data.intVal("storeRemaining"),
            positionLimit: data.intVal("positionLimit"),
            positionRemaining: data.intVal("positionRemaining"),
            remaining: data.intVal("remaining")
        )
    }

    static func apply(date: String, type: String, reason: String) async throws {
        _ = try await APIClient.shared.post("leave.apply", ["date": date, "type": type, "reason": reason])
    }

    static func cancel(id: String, action: String) async throws {
        _ = try await APIClient.shared.post("leave.cancel", ["id": id, "action": action])
    }
}

// MARK: - 效期

enum ExpiryRepository {
    static func checkData(date: String) async throws -> ExpiryCheckData {
        let data = try await APIClient.shared.post("expiry.checkData", ["date": date])
        let categories = data.objects("categories").map { category in
            ExpiryCategory(
                id: category.str("id"),
                name: category.str("name"),
                materials: category.objects("materials").map { material in
                    ExpiryMaterial(
                        id: material.str("id"),
                        categoryId: material.str("categoryId"),
                        name: material.str("name"),
                        defaultMode: material.str("defaultMode"),
                        defaultHours: material.doubleVal("defaultHours"),
                        defaultTime: material.str("defaultTime"),
                        closeDue: material.boolVal("closeDue"),
                        remark: material.str("remark"),
                        record: material.dict("record").map { Parse.expiryRecord($0) }
                    )
                }
            )
        }
        return ExpiryCheckData(
            date: data.str("date").isEmpty ? date : data.str("date"),
            closeTime: data.str("closeTime").isEmpty ? "23:00" : data.str("closeTime"),
            categories: categories
        )
    }

    /// 单条即时保存：打烊到期只提交日期，服务端补打烊时刻；已过期需显式按报废登记。
    static func checkSave(date: String, materialId: String, dueAt: String, scrap: Bool) async throws {
        var item: JSON = ["materialId": materialId, "dueAt": dueAt]
        if scrap { item["scrap"] = true }
        _ = try await APIClient.shared.post("expiry.checkSave", ["date": date, "items": [item]])
    }

    /// 当天到期：前一日登记、今日到期的记录。
    static func dueList(date: String) async throws -> [ExpiryRecord] {
        let data = try await APIClient.shared.post("expiry.dueList", ["date": date])
        return data.objects("list").map { Parse.expiryRecord($0) }
    }

    /// 效期总览：指定登记日期的全部记录。
    static func dayList(date: String) async throws -> [ExpiryRecord] {
        let data = try await APIClient.shared.post("expiry.dayList", ["date": date])
        return data.objects("list").map { Parse.expiryRecord($0) }
    }

    static func process(id: String) async throws -> ExpiryRecord? {
        let data = try await APIClient.shared.post("expiry.process", ["id": id])
        return data.dict("record").map { Parse.expiryRecord($0) }
    }
}

// MARK: - 消息

enum MessageRepository {
    /// scope 取 system / task；分页由服务端完成，默认每页 5 条。
    static func list(scope: String, page: Int) async throws -> MessagePage {
        let data = try await APIClient.shared.post("message.list", [
            "scope": scope,
            "page": page,
            "pageSize": 5
        ])
        let unread = data.dict("unread")
        return MessagePage(
            items: data.objects("list").map { Parse.message($0) },
            total: data.intVal("total"),
            page: max(1, data.intVal("page")),
            pageSize: data.intVal("pageSize") <= 0 ? 5 : data.intVal("pageSize"),
            totalPages: max(1, data.intVal("totalPages")),
            unreadAll: unread?.intVal("all") ?? 0,
            unreadSystem: unread?.intVal("system") ?? 0,
            unreadTask: unread?.intVal("task") ?? 0
        )
    }

    static func threads() async throws -> ([ThreadItem], Int) {
        let data = try await APIClient.shared.post("message.threads")
        let list = data.objects("list").map {
            ThreadItem(
                id: $0.str("id"),
                peerId: $0.str("peerId"),
                peerName: $0.str("peerName"),
                lastText: $0.str("lastText"),
                lastAt: $0.str("lastAt"),
                lastIsMine: $0.boolVal("lastIsMine"),
                unread: $0.intVal("unread")
            )
        }
        return (list, data.intVal("unreadCount"))
    }

    /// 进入会话即标记已读，返回时间正序消息。
    static func thread(peerId: String) async throws -> MessageThread {
        let data = try await APIClient.shared.post("message.thread", ["peerId": peerId])
        let info = data.dict("thread")
        return MessageThread(
            peerId: info?.str("peerId") ?? peerId,
            peerName: info?.str("peerName") ?? "",
            messages: data.objects("messages").map { Parse.message($0) }
        )
    }

    static func send(toStaffId: String, body: String) async throws -> MessageItem? {
        let data = try await APIClient.shared.post("message.send", ["toStaffId": toStaffId, "body": body])
        return data.dict("message").map { Parse.message($0) }
    }

    static func markRead(id: String) async throws {
        _ = try await APIClient.shared.post("message.read", ["id": id])
    }

    static func markAllRead() async throws {
        _ = try await APIClient.shared.post("message.readAll")
    }

    static func unreadCount() async throws -> Int {
        let data = try await APIClient.shared.post("message.unread")
        return data.intVal("unreadCount")
    }
}

// MARK: - 上传与账号

enum UploadRepository {
    static func uploadImage(
        data: Data,
        filename: String,
        mime: String = "image/jpeg",
        type: String = "task"
    ) async throws -> String {
        let result = try await APIClient.shared.upload(
            action: "file.upload",
            field: "file",
            filename: filename,
            mime: mime,
            data: data,
            extra: ["type": type]
        )
        let key = result.str("key")
        if key.isEmpty {
            throw APIError(code: "UPLOAD_FAIL", message: "图片上传失败，请重试")
        }
        return key
    }
}

enum ProfileRepository {
    /// 服务端 staff.saveMe 支持 avatar（file.upload 返回的 key）。
    static func saveAvatar(key: String) async throws {
        _ = try await APIClient.shared.post("staff.saveMe", ["avatar": key])
    }
}

enum AccountRepository {
    /// 规则与服务端一致：6—20 位且包含字母和数字。
    static func changePassword(oldPassword: String, newPassword: String, confirmPassword: String) async throws {
        _ = try await APIClient.shared.post("accounts.changePassword", [
            "oldPassword": oldPassword,
            "newPassword": newPassword,
            "confirmPassword": confirmPassword
        ])
    }
}

// MARK: - 公告

struct NoticeInfo: Identifiable {
    var id = ""
    var category = ""
    var title = ""
    var body = ""
    var publisher = ""
    var publishAt = ""
    var publishedAt = ""
    var createdAt = ""
    var important = false
    var pinned = false
    var read = false
}

enum NoticeRepository {
    static func list() async throws -> [NoticeInfo] {
        let data = try await APIClient.shared.post("notice.employee.list")
        return data.objects("list").map { parse($0) }
    }

    static func get(id: String) async throws -> NoticeInfo? {
        guard !id.isEmpty else { return nil }
        let data = try await APIClient.shared.post("notice.employee.get", ["id": id])
        return data.isEmpty ? nil : parse(data)
    }

    static func markRead(id: String) async throws {
        guard !id.isEmpty else { return }
        _ = try await APIClient.shared.post("notice.markRead", ["id": id])
    }

    static func parse(_ n: JSON) -> NoticeInfo {
        let published = n.str("publishedAt").isEmpty ? n.str("publishAt") : n.str("publishedAt")
        return NoticeInfo(
            id: n.str("id"),
            category: n.str("category"),
            title: n.str("title"),
            body: n.str("body"),
            publisher: n.str("publisher"),
            publishAt: published,
            publishedAt: published,
            createdAt: n.str("createdAt"),
            important: n.boolVal("important"),
            pinned: n.boolVal("pinned"),
            read: n.boolVal("read")
        )
    }
}
