import SwiftUI

// MARK: - 轻提示

struct Flash: Equatable {
    var text: String
    var error: Bool = false
}

struct ToastBanner: View {
    let flash: Flash

    var body: some View {
        Text(flash.text)
            .font(.ssBody14)
            .foregroundColor(flash.error ? Sem.bad : AppColor.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColor.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(flash.error ? Sem.bad.opacity(0.4) : AppColor.outline, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
    }
}

// MARK: - 状态徽章

enum BadgeKind {
    case ok, warn, info, bad, neutral

    var foreground: Color {
        switch self {
        case .ok: return Sem.ok
        case .warn: return Sem.warn
        case .info: return Sem.info
        case .bad: return Sem.bad
        case .neutral: return Sem.neutral
        }
    }

    var background: Color {
        switch self {
        case .ok: return Sem.okTint
        case .warn: return Sem.warnTint
        case .info: return Sem.infoTint
        case .bad: return Sem.badTint
        case .neutral: return Sem.neutralTint
        }
    }
}

struct StatusBadge: View {
    let text: String
    let kind: BadgeKind

    var body: some View {
        Text(text)
            .font(.ssCaption)
            .foregroundColor(kind.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(kind.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous))
            .lineLimit(1)
    }
}

// MARK: - 空态 / 错误态 / 加载更多

struct EmptyStateView: View {
    let title: String
    var hint: String = ""

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.ssTitle4)
                .foregroundColor(AppColor.text)
                .multilineTextAlignment(.center)
            if !hint.isEmpty {
                Text(hint)
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 24)
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("加载失败")
                .font(.ssTitle4)
                .foregroundColor(AppColor.onPrimaryContainer)
            Text(message)
                .font(.ssSmall)
                .foregroundColor(AppColor.onPrimaryContainer)
            Button("重试", action: onRetry)
                .font(.ssBody14)
                .foregroundColor(AppColor.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppColor.primaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(16)
    }
}

struct LoadMoreRow: View {
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("加载更多（剩余 \(remaining) 项）")
                .font(.ssBody14)
                .foregroundColor(AppColor.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - 图片

func fileURL(_ key: String) -> URL? {
    let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return nil }
    if value.hasPrefix("http://") || value.hasPrefix("https://") { return URL(string: value) }
    if value.hasPrefix("demo/") { return nil }
    if value.hasPrefix("uploads/") { return URL(string: AppConfig.baseURL + value) }
    return URL(string: AppConfig.baseURL + "uploads/" + value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
}

struct RemoteImage: View {
    let key: String
    var corner: CGFloat = Radius.badge
    var contentMode: ContentMode = .fill
    var onTap: (() -> Void)?

    var body: some View {
        ZStack {
            AppColor.surfaceVariant
            if let url = fileURL(key) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        Text("图片")
                            .font(.ssCaption)
                            .foregroundColor(AppColor.textSecondary)
                    case .empty:
                        ProgressView().scaleEffect(0.6)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Text("图片")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

struct Dot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - 今日排班卡

struct ShiftTodayCardView: View {
    let shift: ShiftToday?
    let dateText: String
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("今日排班")
                    .font(.ssTitle4)
                    .foregroundColor(AppColor.text)
                Spacer(minLength: 0)
                Text(Fmt.execDate(dateText.isEmpty ? (shift?.date ?? "") : dateText))
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                if onTap != nil {
                    Text("查看")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.primary)
                }
            }

            let segments = shift?.segments ?? []
            if segments.isEmpty {
                Text("今日暂无排班")
                    .font(.ssBody14)
                    .foregroundColor(AppColor.textSecondary)
            } else {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    if index > 0 {
                        Divider().background(AppColor.outlineVariant)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.startTime)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColor.text)
                            Text("至 \(segment.endTime)")
                                .font(.ssCaption)
                                .foregroundColor(AppColor.textSecondary)
                        }
                        .frame(width: 64, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.stationName.isEmpty ? "岗位待定" : segment.stationName)
                                .font(.ssBody)
                                .foregroundColor(AppColor.text)
                            if !segment.task.isEmpty {
                                Text(segment.task)
                                    .font(.ssSmall)
                                    .foregroundColor(AppColor.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            let reminder = shift?.reminder ?? ""
            if !reminder.isEmpty {
                Divider().background(AppColor.outlineVariant)
                Text(reminder)
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - 通用分组标题

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ssTitle4)
            .foregroundColor(AppColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
