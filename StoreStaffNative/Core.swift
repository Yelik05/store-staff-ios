import Foundation
import Security

// MARK: - 全局配置

enum AppConfig {
    static let baseURL = "https://ta0051.jethroy.cn/"
    static let appName = "塔斯汀门店助手"
    static let version = "1.0.0"
    static let platform = "ios"
    static let clientTag = "StoreStaffNative/1.0"
}

typealias JSON = [String: Any]

extension Notification.Name {
    /// Token 失效：根视图收到后回到登录页。
    static let sessionExpired = Notification.Name("ss.sessionExpired")
    /// 通知点击 / 路由跳转。
    static let appOpenRoute = Notification.Name("ss.openRoute")
}

// MARK: - 错误

struct APIError: LocalizedError {
    let code: String
    let message: String
    let status: Int

    init(code: String, message: String, status: Int = 0) {
        self.code = code
        self.message = message
        self.status = status
    }

    var errorDescription: String? { message }
}

struct SessionExpiredError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

// MARK: - 本地会话（Token 存 Keychain，展示信息存 UserDefaults）

enum Keychain {
    private static let service = "com.tastien.storestaff.native"

    static func save(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class SessionStore {
    static let shared = SessionStore()

    private let defaults = UserDefaults.standard
    private let tokenKey = "ss.token"

    var token: String? { Keychain.read(tokenKey) }
    var hasToken: Bool {
        guard let token = token else { return false }
        return !token.isEmpty
    }

    private func value(_ key: String) -> String { defaults.string(forKey: key) ?? "" }

    var expiresAt: String { value("ss.expiresAt") }
    var accountName: String { value("ss.accountName") }
    var role: String { value("ss.role") }
    var staffName: String { value("ss.staffName") }
    var position: String { value("ss.position") }
    var empNo: String { value("ss.empNo") }
    var feishuEmpNo: String { value("ss.feishuEmpNo") }
    var avatar: String { value("ss.avatar") }
    /// 对外展示的工号：优先飞书工号，其次门店工号。
    var displayEmpNo: String {
        let feishu = feishuEmpNo.trimmingCharacters(in: .whitespacesAndNewlines)
        return feishu.isEmpty ? empNo : feishu
    }
    var storeName: String { value("ss.storeName") }
    var phone: String { value("ss.phone") }
    var lastLoginAt: String { value("ss.lastLoginAt") }

    func save(
        token: String,
        expiresAt: String,
        accountName: String,
        role: String,
        staffName: String,
        position: String,
        empNo: String,
        storeName: String,
        phone: String = "",
        lastLoginAt: String = "",
        avatar: String = "",
        feishuEmpNo: String = ""
    ) {
        Keychain.save(token, key: tokenKey)
        defaults.set(expiresAt, forKey: "ss.expiresAt")
        defaults.set(accountName, forKey: "ss.accountName")
        defaults.set(role, forKey: "ss.role")
        defaults.set(staffName, forKey: "ss.staffName")
        defaults.set(position, forKey: "ss.position")
        defaults.set(empNo, forKey: "ss.empNo")
        defaults.set(feishuEmpNo, forKey: "ss.feishuEmpNo")
        defaults.set(avatar, forKey: "ss.avatar")
        defaults.set(storeName, forKey: "ss.storeName")
        defaults.set(phone, forKey: "ss.phone")
        defaults.set(lastLoginAt, forKey: "ss.lastLoginAt")
    }

    func updateProfile(
        accountName: String,
        role: String,
        staffName: String,
        position: String,
        empNo: String,
        storeName: String,
        phone: String? = nil,
        lastLoginAt: String? = nil,
        avatar: String? = nil,
        feishuEmpNo: String? = nil
    ) {
        defaults.set(accountName, forKey: "ss.accountName")
        defaults.set(role, forKey: "ss.role")
        defaults.set(staffName, forKey: "ss.staffName")
        defaults.set(position, forKey: "ss.position")
        defaults.set(empNo, forKey: "ss.empNo")
        defaults.set(storeName, forKey: "ss.storeName")
        if let phone = phone { defaults.set(phone, forKey: "ss.phone") }
        if let lastLoginAt = lastLoginAt { defaults.set(lastLoginAt, forKey: "ss.lastLoginAt") }
        if let avatar = avatar { defaults.set(avatar, forKey: "ss.avatar") }
        if let feishuEmpNo = feishuEmpNo { defaults.set(feishuEmpNo, forKey: "ss.feishuEmpNo") }
    }

    func setAvatar(_ key: String) {
        defaults.set(key, forKey: "ss.avatar")
    }

    func clear() {
        Keychain.delete(tokenKey)
        ["ss.expiresAt", "ss.accountName", "ss.role", "ss.staffName", "ss.position",
         "ss.empNo", "ss.feishuEmpNo", "ss.avatar", "ss.storeName", "ss.phone", "ss.lastLoginAt"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}

// MARK: - JSON 容错读取

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        if let b = self[key] as? Bool { return b ? "1" : "0" }
        return ""
    }

    func intVal(_ key: String) -> Int {
        if let i = self[key] as? Int { return i }
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) ?? 0 }
        return 0
    }

    func doubleVal(_ key: String) -> Double {
        if let d = self[key] as? Double { return d }
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) ?? 0 }
        return 0
    }

    func boolVal(_ key: String) -> Bool {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? NSNumber { return n.boolValue }
        if let s = self[key] as? String {
            return ["1", "true", "yes", "on"].contains(s.lowercased())
        }
        return false
    }

    func dict(_ key: String) -> JSON? { self[key] as? JSON }

    func array(_ key: String) -> [Any]? { self[key] as? [Any] }

    func objects(_ key: String) -> [JSON] {
        (self[key] as? [Any])?.compactMap { $0 as? JSON } ?? []
    }

    func strList(_ key: String) -> [String] {
        guard let items = self[key] as? [Any] else { return [] }
        return items.compactMap { element in
            if let s = element as? String { return s }
            if let d = element as? JSON {
                let key = d.str("key")
                return key.isEmpty ? d.str("url") : key
            }
            return nil
        }
    }
}

// MARK: - 网络层

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// 所有接口 POST api.php?action=xxx，请求体 JSON。
    func post(_ action: String, _ payload: JSON = [:]) async throws -> JSON {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await postOnce(action, payload)
            } catch let error as URLError {
                lastError = error
                if attempt == 1 { break }
            }
        }
        if let error = lastError as? URLError {
            throw APIError(code: "NETWORK_ERROR", message: "网络连接失败，请检查网络后重试", status: error.errorCode)
        }
        throw APIError(code: "NETWORK_ERROR", message: "网络连接失败，请检查网络后重试")
    }

    private func postOnce(_ action: String, _ payload: JSON) async throws -> JSON {
        var request = try makeRequest(action)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try await send(request)
    }

    /// multipart 上传（file.upload）。
    func upload(
        action: String,
        field: String,
        filename: String,
        mime: String,
        data: Data,
        extra: [String: String] = [:]
    ) async throws -> JSON {
        var request = try makeRequest(action)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ text: String) {
            if let data = text.data(using: .utf8) { body.append(data) }
        }

        for (key, value) in extra {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            return try await send(request)
        } catch let error as URLError {
            throw APIError(code: "NETWORK_ERROR", message: "网络连接失败，请检查网络后重试", status: error.errorCode)
        }
    }

    private func makeRequest(_ action: String) throws -> URLRequest {
        guard let url = URL(string: AppConfig.baseURL + "api.php?action=" + action) else {
            throw APIError(code: "BAD_URL", message: "请求地址异常")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConfig.clientTag, forHTTPHeaderField: "X-App-Client")
        if let token = SessionStore.shared.token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-App-Token")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> JSON {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? JSON else {
            if status == 404 {
                throw APIError(code: "ROUTE_MISSING", message: "线上版本暂未开放该功能，请更新服务端后再试", status: 404)
            }
            throw APIError(code: "SERVER_ERROR", message: "服务器返回格式异常，请稍后重试", status: status)
        }

        if (root["ok"] as? Bool) != true {
            let code = root["code"] as? String ?? "ERROR"
            let message = root["error"] as? String ?? "请求失败，请稍后重试"
            if status == 401 || ["TOKEN_INVALID", "TOKEN_EXPIRED", "TOKEN_REVOKED", "UNAUTHORIZED"].contains(code) {
                SessionStore.shared.clear()
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw SessionExpiredError(code: code, message: message)
            }
            throw APIError(code: code, message: message, status: status)
        }

        // 兼容部分接口 data 直接为数组（如 salary.myMonths、settings.dimensions）。
        if let array = root["data"] as? [Any] {
            return ["list": array]
        }
        return root["data"] as? JSON ?? [:]
    }
}

// MARK: - 通用错误文案

enum ErrText {
    static func readable(_ error: Error) -> String {
        if let api = error as? APIError, !api.message.isEmpty { return api.message }
        if let session = error as? SessionExpiredError, !session.message.isEmpty { return session.message }
        let message = error.localizedDescription
        return message.isEmpty ? "网络异常，请稍后重试" : message
    }
}
