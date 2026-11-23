import Foundation

// MARK: - 首页

struct HomeSnapshot {
    var displayName: String = ""
    var position: String = ""
    var employmentType: String = ""
    var empNo: String = ""
    var feishuEmpNo: String = ""
    var avatar: String = ""
    var storeName: String = ""
    var today: String = ""
    var shift: ShiftToday?
    var unread: Int = 0
    var todayPending: Int = 0
    var overdue: Int = 0
}

// MARK: - 排班

struct ShiftSegment {
    var segmentNo: Int = 1
    var startTime: String = ""
    var endTime: String = ""
    var stationName: String = ""
    var task: String = ""
}

struct ShiftToday {
    var date: String = ""
    var segments: [ShiftSegment] = []
    var reminder: String = ""
}

struct ShiftSlot {
    var date: String = ""
    var start: String = ""
    var end: String = ""
}

struct ShiftRequestItem {
    var id: String = ""
    var month: String = ""
    var slots: [ShiftSlot] = []
    var note: String = ""
    var status: String = ""
    var createdAt: String = ""
    var reviewedBy: String = ""
    var reviewedAt: String = ""
    var rejectReason: String = ""
    var cancelRequested: Bool = false
}

struct ShiftSummary {
    var month: String = ""
    var list: [ShiftRequestItem] = []
    var pendingSlots: Int = 0
    var approvedSlots: Int = 0
}

// MARK: - 排休

struct LeaveItem {
    var id: String = ""
    var date: String = ""
    var type: String = ""
    var reason: String = ""
    var status: String = ""
    var manual: Bool = false
    var createdAt: String = ""
    var reviewedBy: String = ""
    var reviewedAt: String = ""
    var rejectReason: String = ""
    var cancelRequested: Bool = false
    var forceReason: String = ""
}

struct LeaveSummary {
    var month: String = ""
    var quota: Double = 0
    var used: Int = 0
    var pending: Int = 0
    var remaining: Double = 0
    var unused: Double = 0
    var byType: [String: Int] = [:]
    var list: [LeaveItem] = []
}

struct LeaveDayStats {
    var date: String = ""
    var approved: Int = 0
    var pending: Int = 0
    var total: Int = 0
    var storeLimit: Int = 0
    var storeRemaining: Int = 0
    var positionLimit: Int = 0
    var positionRemaining: Int = 0
    var remaining: Int = 0
}

// MARK: - 任务

struct TaskItem: Identifiable {
    var id: Int = 0
    var templateId: String = ""
    var parentId: String = ""
    var title: String = ""
    var content: String = ""
    var cycle: String = ""
    var cycleLabel: String = ""
    var periodDate: String = ""
    var deadlineText: String = ""
    var status: String = ""
    var statusLabel: String = ""
    var assigneeId: String = ""
    var assigneeDisplayName: String = ""
    var assigneeSource: String = ""
    var completionMode: String = "upload"
    var completionScope: String = "any"
    var progressText: String = ""
    var missingNames: [String] = []
    var sampleImages: [String] = []
    var images: [String] = []
    var rejectReason: String = ""
    var groupTitle: String = ""
    var kindId: String = ""
    var kindName: String = ""
    var submitterName: String = ""
    var mySubmitted: Bool = false
}

struct TaskGroup {
    var parentId: String = ""
    var title: String = ""
    var content: String = ""
    var cycle: String = ""
    var cycleLabel: String = ""
    var periodDate: String = ""
    var defaultAssigneeId: String = ""
    var defaultAssigneeDisplayName: String = ""
    var progressText: String = ""
    var done: Bool = false
    var overdue: Int = 0
    var total: Int = 0
    var children: [TaskItem] = []
}

struct TaskOverview {
    var items: [TaskItem] = []
    var groups: [TaskGroup] = []
    var counts: [String: Int] = [:]
    var today: String = ""
    var todayPending: Int = 0
    var overdueCount: Int = 0
    var myStaffId: String = ""
    var canManage: Bool = false
}

struct TaskArchive {
    var items: [TaskItem] = []
    var counts: [String: Int] = [:]
    var date: String = ""
    var today: String = ""
}

struct TaskContact: Identifiable {
    var id: String = ""
    var displayName: String = ""
    var position: String = ""
}

// MARK: - 效期

struct ExpiryRecord: Identifiable {
    var id: String = ""
    var materialId: String = ""
    var categoryId: String = ""
    var materialName: String = ""
    var categoryName: String = ""
    var checkDate: String = ""
    var dueAt: String = ""
    var note: String = ""
    var status: String = "normal"
    var processedBy: String = ""
    var processedAt: String = ""
    var createdBy: String = ""

    var isProcessed: Bool { status == "processed" }
    var isScrapped: Bool { status == "scrapped" }
}

struct ExpiryMaterial: Identifiable {
    var id: String = ""
    var categoryId: String = ""
    var name: String = ""
    var defaultMode: String = ""
    var defaultHours: Double = 0
    var defaultTime: String = ""
    var closeDue: Bool = false
    var remark: String = ""
    var record: ExpiryRecord?
}

struct ExpiryCategory: Identifiable {
    var id: String = ""
    var name: String = ""
    var materials: [ExpiryMaterial] = []
}

struct ExpiryCheckData {
    var date: String = ""
    var closeTime: String = "23:00"
    var categories: [ExpiryCategory] = []

    var materials: [ExpiryMaterial] { categories.flatMap { $0.materials } }
}

// MARK: - 消息

struct MessageItem: Identifiable {
    var id: String = ""
    var type: String = ""
    var title: String = ""
    var body: String = ""
    var link: String = ""
    var refId: String = ""
    var read: Bool = false
    var createdAt: String = ""
    var threadId: String = ""
    var isMine: Bool = false
}

struct MessagePage {
    var items: [MessageItem] = []
    var total: Int = 0
    var page: Int = 1
    var pageSize: Int = 5
    var totalPages: Int = 1
    var unreadAll: Int = 0
    var unreadSystem: Int = 0
    var unreadTask: Int = 0
}

struct ThreadItem: Identifiable {
    var id: String = ""
    var peerId: String = ""
    var peerName: String = ""
    var lastText: String = ""
    var lastAt: String = ""
    var lastIsMine: Bool = false
    var unread: Int = 0
}

struct MessageThread {
    var peerId: String = ""
    var peerName: String = ""
    var messages: [MessageItem] = []
}

// MARK: - 解析

enum Parse {
    static func shiftToday(_ data: JSON) -> ShiftToday {
        ShiftToday(
            date: data.str("date"),
            segments: data.objects("records").map { record in
                ShiftSegment(
                    segmentNo: record.intVal("segmentNo"),
                    startTime: record.str("startTime"),
                    endTime: record.str("endTime"),
                    stationName: record.str("stationName"),
                    task: record.str("task")
                )
            },
            reminder: data.str("reminder")
        )
    }

    static func taskItem(_ r: JSON) -> TaskItem {
        var sample = r.strList("effectiveSampleImages")
        if sample.isEmpty { sample = r.strList("sampleImages") }
        return TaskItem(
            id: r.intVal("id"),
            templateId: r.str("templateId"),
            parentId: r.str("parentId"),
            title: r.str("title"),
            content: r.str("content"),
            cycle: r.str("cycle"),
            cycleLabel: r.str("cycleLabel"),
            periodDate: r.str("periodDate"),
            deadlineText: r.str("deadlineText").isEmpty ? r.str("deadlineAt") : r.str("deadlineText"),
            status: r.str("status"),
            statusLabel: r.str("statusLabel"),
            assigneeId: r.str("assigneeId"),
            assigneeDisplayName: r.str("assigneeDisplayName"),
            assigneeSource: r.str("assigneeSource"),
            completionMode: r.str("completionMode").isEmpty ? "upload" : r.str("completionMode"),
            completionScope: r.str("completionScope").isEmpty ? "any" : r.str("completionScope"),
            progressText: r.str("progressText"),
            missingNames: r.strList("missingNames"),
            sampleImages: sample,
            images: r.strList("images"),
            rejectReason: r.str("rejectReason"),
            groupTitle: r.str("groupTitle"),
            kindId: r.str("kindId"),
            kindName: r.str("kindName"),
            submitterName: r.str("submitterName"),
            mySubmitted: r.boolVal("mySubmitted")
        )
    }

    static func taskGroup(_ g: JSON) -> TaskGroup {
        TaskGroup(
            parentId: g.str("parentId"),
            title: g.str("title"),
            content: g.str("content"),
            cycle: g.str("cycle"),
            cycleLabel: g.str("cycleLabel"),
            periodDate: g.str("periodDate"),
            defaultAssigneeId: g.str("defaultAssigneeId"),
            defaultAssigneeDisplayName: g.str("defaultAssigneeDisplayName"),
            progressText: g.str("progressText"),
            done: g.boolVal("done"),
            overdue: g.intVal("overdue"),
            total: g.intVal("total"),
            children: g.objects("children").map { Parse.taskItem($0) }
        )
    }

    static func expiryRecord(_ r: JSON) -> ExpiryRecord {
        ExpiryRecord(
            id: r.str("id"),
            materialId: r.str("materialId"),
            categoryId: r.str("categoryId"),
            materialName: r.str("materialName"),
            categoryName: r.str("categoryName"),
            checkDate: r.str("checkDate"),
            dueAt: r.str("dueAt"),
            note: r.str("note"),
            status: r.str("status").isEmpty ? "normal" : r.str("status"),
            processedBy: r.str("processedBy"),
            processedAt: r.str("processedAt"),
            createdBy: r.str("createdBy")
        )
    }

    static func leaveItem(_ r: JSON) -> LeaveItem {
        LeaveItem(
            id: r.str("id"),
            date: r.str("date"),
            type: r.str("type"),
            reason: r.str("reason"),
            status: r.str("status"),
            manual: r.boolVal("manual"),
            createdAt: r.str("createdAt"),
            reviewedBy: r.str("reviewedBy"),
            reviewedAt: r.str("reviewedAt"),
            rejectReason: r.str("rejectReason"),
            cancelRequested: r.boolVal("cancelRequested"),
            forceReason: r.str("forceReason")
        )
    }

    static func shiftRequest(_ r: JSON) -> ShiftRequestItem {
        ShiftRequestItem(
            id: r.str("id"),
            month: r.str("month"),
            slots: r.objects("slots").map {
                ShiftSlot(date: $0.str("date"), start: $0.str("start"), end: $0.str("end"))
            },
            note: r.str("note"),
            status: r.str("status"),
            createdAt: r.str("createdAt"),
            reviewedBy: r.str("reviewedBy"),
            reviewedAt: r.str("reviewedAt"),
            rejectReason: r.str("rejectReason"),
            cancelRequested: r.boolVal("cancelRequested")
        )
    }

    static func message(_ m: JSON) -> MessageItem {
        MessageItem(
            id: m.str("id"),
            type: m.str("type"),
            title: m.str("title"),
            body: m.str("body"),
            link: m.str("link"),
            refId: m.str("refId"),
            read: m.boolVal("read"),
            createdAt: m.str("createdAt"),
            threadId: m.str("threadId"),
            isMine: m.boolVal("isMine")
        )
    }
}
