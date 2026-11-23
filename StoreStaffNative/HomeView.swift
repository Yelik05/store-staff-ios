import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var loading = true
    @Published var refreshing = false
    @Published var snapshot: HomeSnapshot?
    @Published var error: String?

    private var inFlight = false

    func load(refresh: Bool = false) async {
        if inFlight { return }
        inFlight = true
        if snapshot == nil { loading = true }
        refreshing = refresh
        error = nil
        do {
            snapshot = try await HomeRepository.load()
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

    /// 轮询时静默刷新，不打断用户。
    func silentRefresh() async {
        if inFlight { return }
        guard let fresh = try? await HomeRepository.load() else { return }
        snapshot = fresh
    }
}

struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    let unreadCount: Int
    let onOpenSchedule: () -> Void
    let onOpenProfile: () -> Void
    let onOpenMessages: () -> Void
    let onOpenFeature: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                    .padding(.top, 10)

                if model.loading && model.snapshot == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let snapshot = model.snapshot {
                    ShiftTodayCardView(
                        shift: snapshot.shift,
                        dateText: snapshot.today,
                        onTap: onOpenSchedule
                    )
                    MetricsRow(snapshot: snapshot)
                    QuickActions(onOpenSchedule: onOpenSchedule, onOpenFeature: onOpenFeature)
                } else {
                    ErrorStateView(message: model.error ?? "加载失败") {
                        Task { await model.load(refresh: true) }
                    }
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .background(AppColor.background.ignoresSafeArea())
        .task {
            if model.snapshot == nil {
                await model.load()
            }
        }
        .refreshable {
            await model.load(refresh: true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onOpenProfile) {
                Group {
                    if let key = model.snapshot?.avatar, !key.isEmpty {
                        RemoteImage(key: key, corner: 21, contentMode: .fill)
                    } else {
                        Circle()
                            .fill(AppColor.primaryContainer)
                            .overlay(
                                Text(String(displayName.prefix(1)))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppColor.primary)
                            )
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppColor.outline.opacity(0.7), lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting)，\(displayName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColor.text)
                    .lineLimit(1)
                Text(storeName)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if model.refreshing {
                ProgressView().scaleEffect(0.8)
            } else {
                Button {
                    Task { await model.load(refresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .foregroundColor(AppColor.textSecondary)
                        .frame(width: 40, height: 40)
                }
            }

            Button(action: onOpenMessages) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 19))
                        .foregroundColor(AppColor.textSecondary)
                        .frame(width: 40, height: 40)
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Sem.bad)
                            .clipShape(Capsule())
                            .offset(x: -2, y: 3)
                    }
                }
            }
        }
    }

    private var displayName: String {
        let name = model.snapshot?.displayName ?? ""
        return name.isEmpty ? "门店伙伴" : name
    }

    private var storeName: String {
        let name = model.snapshot?.storeName ?? ""
        return name.isEmpty ? "塔斯汀门店" : name
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour <= 11 { return "早上好" }
        if hour >= 12 && hour <= 17 { return "下午好" }
        return "晚上好"
    }
}

private struct MetricsRow: View {
    let snapshot: HomeSnapshot

    var body: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "待办任务",
                value: "\(snapshot.todayPending)",
                hint: snapshot.overdue > 0 ? "逾期 \(snapshot.overdue) 项" : "今日到期",
                hintColor: snapshot.overdue > 0 ? Sem.bad : AppColor.textSecondary
            )
            MetricCard(
                title: "未读通知",
                value: "\(snapshot.unread)",
                hint: "私信与公告",
                hintColor: AppColor.textSecondary
            )
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let hint: String
    let hintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.ssSmall)
                .foregroundColor(AppColor.textSecondary)
            Text(value)
                .font(.ssHeadline)
                .foregroundColor(AppColor.text)
                .padding(.top, 6)
            Text(hint)
                .font(.ssCaption)
                .foregroundColor(hintColor)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct QuickActions: View {
    let onOpenSchedule: () -> Void
    let onOpenFeature: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("全部功能")
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
            HStack(spacing: 12) {
                QuickTile(title: "排休 / 排班", hint: "申请与审批进度", action: onOpenSchedule)
                QuickTile(title: "我的考勤", hint: "月度工时与异常", action: { onOpenFeature("attendance") })
            }
            HStack(spacing: 12) {
                QuickTile(title: "我的薪资", hint: "工资单与发放状态", action: { onOpenFeature("salary") })
                QuickTile(title: "量化分", hint: "维度得分与加减分", action: { onOpenFeature("score") })
            }
            HStack(spacing: 12) {
                QuickTile(title: "我的报销", hint: "提交与审批进度", action: { onOpenFeature("reimburse") })
                QuickTile(title: "门店通讯录", hint: "同事电话与私信", action: { onOpenFeature("contacts") })
            }
            HStack(spacing: 12) {
                QuickTile(title: "我的日程", hint: "个人与门店日程", action: { onOpenFeature("agenda") })
                QuickTile(title: "通知公告 / 信箱", hint: "公告与私信会话", action: { onOpenFeature("messages") })
            }
        }
        .padding(.top, 4)
    }
}

private struct QuickTile: View {
    let title: String
    let hint: String
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.ssBody14)
                .foregroundColor(AppColor.text)
            Text(hint)
                .font(.ssCaption)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
