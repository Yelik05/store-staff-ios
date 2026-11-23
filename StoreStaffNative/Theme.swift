import SwiftUI
import UIKit

// MARK: - 颜色令牌（对齐安卓原生与网页 theme.css）

extension UIColor {
    convenience init(rgb: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension Color {
    init(rgb: UInt, alpha: Double = 1) {
        self.init(uiColor: UIColor(rgb: rgb, alpha: CGFloat(alpha)))
    }

    /// 跟随系统深浅色自动切换。
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

enum AppColor {
    static let primary = Color(light: 0xE10600, dark: 0xFF6B5E)
    static let primaryPressed = Color(light: 0xB90500, dark: 0xFF8A7E)
    static let primaryContainer = Color(light: 0xFDECEA, dark: 0x3A1512)
    static let onPrimary = Color.white
    static let onPrimaryContainer = Color(light: 0x5C0400, dark: 0xFFDAD6)

    static let background = Color(light: 0xF5F4F2, dark: 0x0F0F0F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x181818)
    static let surfaceVariant = Color(light: 0xFAF9F7, dark: 0x1F1F1F)
    static let text = Color(light: 0x121212, dark: 0xF2F1EF)
    static let textSecondary = Color(light: 0x787878, dark: 0x8C8A86)
    static let outline = Color(light: 0xE5E3DF, dark: 0x2A2A2A)
    static let outlineVariant = Color(light: 0xEFEDEA, dark: 0x242424)
}

/// 语义色：成功 / 提醒 / 信息 / 异常 / 中性。
enum Sem {
    static let ok = Color(light: 0x1E7A4C, dark: 0x6FBF8E)
    static let okTint = Color(light: 0xE7F2EB, dark: 0x20332A)
    static let warn = Color(light: 0x8E6209, dark: 0xD9A44B)
    static let warnTint = Color(light: 0xF6EEDD, dark: 0x342B18)
    static let info = Color(light: 0x2F5F8A, dark: 0x8AB4D8)
    static let infoTint = Color(light: 0xE8EEF4, dark: 0x1E2A33)
    static let bad = Color(light: 0xB3261E, dark: 0xF07B70)
    static let badTint = Color(light: 0xF8E7E5, dark: 0x36201E)
    static let neutral = Color(light: 0x787878, dark: 0x8C8A86)
    static let neutralTint = Color(light: 0xF0EEE9, dark: 0x232322)
}

// MARK: - 圆角与卡片

enum Radius {
    static let badge: CGFloat = 6
    static let field: CGFloat = 10
    static let card: CGFloat = 16
    static let sheet: CGFloat = 20
}

extension View {
    /// 卡片背景：纸白底 + 暖描边（对齐安卓 Card）。
    func cardSurface(radius: CGFloat = Radius.card) -> some View {
        self
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppColor.outline, lineWidth: 0.7)
            )
    }

    func screenBackground() -> some View {
        self.background(AppColor.background.ignoresSafeArea())
    }
}

// MARK: - 文本样式

extension Font {
    static let ssHeadline = Font.system(size: 24, weight: .semibold)
    static let ssTitle = Font.system(size: 20, weight: .semibold)
    static let ssTitle3 = Font.system(size: 18, weight: .semibold)
    static let ssTitle4 = Font.system(size: 16, weight: .semibold)
    static let ssBody = Font.system(size: 15)
    static let ssBody14 = Font.system(size: 14)
    static let ssSmall = Font.system(size: 12)
    static let ssCaption = Font.system(size: 11)
    static let ssMono = Font.system(size: 13, design: .monospaced)
}

// MARK: - 格式化工具

enum Fmt {
    static func regexGroups(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }

    static func allRegexGroups(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func today() -> String { dayFormatter.string(from: Date()) }
    static func currentMonth() -> String { monthFormatter.string(from: Date()) }

    static func monthLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy年M月"
        return f.string(from: Date())
    }

    static func date(from string: String) -> Date? {
        guard string.count >= 10 else { return nil }
        return dayFormatter.date(from: String(string.prefix(10)))
    }

    /// 截止时间：2026-11-23 18:00:00 → 11-23 18:00。
    static func deadline(_ raw: String) -> String {
        let s = raw.replacingOccurrences(of: "截止", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = regexGroups("(\\d{4})-(\\d{1,2})-(\\d{1,2})[ T](\\d{1,2}):(\\d{2})", s),
              g.count >= 6, let mo = Int(g[2]), let d = Int(g[3]), let h = Int(g[4]) else {
            return s.isEmpty ? "—" : s
        }
        return String(format: "%02d-%02d %02d:%@", mo, d, h, g[5])
    }

    /// 今天只显示时分，昨天显示「昨天 HH:mm」，其余 MM-dd HH:mm。
    static func time(_ raw: String) -> String {
        if raw.isEmpty { return "" }
        let value = raw.replacingOccurrences(of: " ", with: "T")
        let date = String(value.prefix(10))
        let parts = value.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        let time = parts.count > 1 ? String(parts[1].prefix(5)) : ""
        let today = Fmt.today()
        let yesterday = dayFormatter.string(from: Date().addingTimeInterval(-86400))
        if date == today { return time }
        if date == yesterday { return "昨天 \(time)" }
        if date.count >= 10 { return String(date.dropFirst(5)) + " " + time }
        return value
    }

    static func execDate(_ date: String) -> String {
        date.count >= 10 ? String(date.dropFirst(5)) : date
    }

    static func dateTime(_ raw: String) -> String {
        guard let g = regexGroups("(\\d{4})-(\\d{1,2})-(\\d{1,2})[ T](\\d{1,2}):(\\d{2})", raw),
              g.count >= 6, let mo = Int(g[2]), let d = Int(g[3]), let h = Int(g[4]) else {
            return raw
        }
        return String(format: "%@-%02d-%02d %02d:%@", g[1], mo, d, h, g[5])
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// 效期短格式：有则 MM-dd HH:mm，无则 MM-dd。
    static func shortDue(_ raw: String) -> String {
        if raw.isEmpty { return "" }
        guard let g = regexGroups("(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ T](\\d{1,2}):(\\d{2}))?", raw),
              g.count >= 6, let mo = Int(g[2]), let d = Int(g[3]) else {
            return raw
        }
        if g[4].isEmpty {
            return String(format: "%02d-%02d", mo, d)
        }
        if let h = Int(g[4]) {
            return String(format: "%02d-%02d %02d:%@", mo, d, h, g[5])
        }
        return raw
    }

    /// 效期日期 + 时间分两行排版时使用。
    static func dueParts(_ raw: String) -> (date: String, time: String) {
        guard let g = regexGroups("(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ T](\\d{1,2}):(\\d{2}))?", raw),
              g.count >= 6, let mo = Int(g[2]), let d = Int(g[3]) else {
            return (raw, "")
        }
        let date = String(format: "%04d年%02d月%02d日", Int(g[1]) ?? 0, mo, d)
        guard let h = Int(g[4]) else { return (date, "") }
        return (date, String(format: "%02d:%@", h, g[5]))
    }

    static func localDateString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func combine(date: String, time: String = "00:00") -> Date? {
        guard let day = dayFormatter.date(from: String(date.prefix(10))) else { return nil }
        let parts = time.split(separator: ":")
        let hour = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
