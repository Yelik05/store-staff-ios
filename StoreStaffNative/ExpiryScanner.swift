import SwiftUI
import AVFoundation
import UIKit

// MARK: - 扫码结果

struct QrResult {
    var raw: String
    var name: String
    var date: String
    var time: String
    var timeError: String
    var material: ExpiryMaterial?
}

// MARK: - 解析器（对齐安卓 QrParser：URL 参数 / JSON / 文本 / 时间戳）

enum QrParser {
    static func parse(_ raw: String, materials: [ExpiryMaterial]) -> QrResult? {
        let text = normalizeDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var name = ""
        var date = ""
        var time = ""
        var timeError = ""

        // 1) JSON：优先取 expirationTime / 到期字段，开封与生产时间不参与到期日。
        if let data = text.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? JSON {
            name = firstValue(object, keys: [
                "name", "productName", "materialName", "itemName",
                "product", "material", "品名", "物料名称", "物料", "名称", "产品名称"
            ])
            date = firstValue(object, keys: [
                "expirationTime", "expiration_time", "expiration", "expiryTime", "expiry",
                "expire", "expireDate", "due", "validUntil", "有效期至", "有效期", "到期时间", "到期", "效期"
            ])
            time = firstValue(object, keys: ["time", "时间"])
            if !date.isEmpty { date = normalizeDateValue(date) }
        }

        // 2) URL 查询参数
        if let index = text.firstIndex(of: "?") {
            let query = String(text[text.index(after: index)...])
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0]).lowercased()
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                if name.isEmpty && ["name", "productname", "materialname", "itemname", "product", "material", "品名", "物料", "名称"].contains(key) {
                    name = value
                }
                if date.isEmpty && ["expirationtime", "expiration_time", "expiration", "expirytime", "expiry", "expire", "due", "validuntil", "有效期", "到期", "效期"].contains(key) {
                    date = value
                }
                if time.isEmpty && ["time", "时间"].contains(key) {
                    time = value
                }
            }
        }

        if !date.isEmpty { date = normalizeDateValue(date) }

        if name.isEmpty {
            for pattern in [
                "(?:品名|物料名称|物料|名称|productName|materialName|itemName|product|name)\\s*[:：]\\s*([^;；,\\n\\r]+)",
                "([^;；,\\n\\r]{1,24})\\s*(?:有效期|到期|效期)"
            ] {
                if let groups = Fmt.regexGroups(pattern, text), groups.count > 1 {
                    name = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { break }
                }
            }
        }

        // 3) 显式日期：优先到期标签，开封/生产时间不得作为到期日
        let labeledPatterns = [
            "(?:expirationtime|expiration_time|expiration|expirytime|expiry|expire|exp|due|有效期至|有效期|保质期至|到期时间|到期|效期)\\s*[\"'=:：]?\\s*(20\\d{2}[-/.年]\\d{1,2}[-/.月]\\d{1,2}日?)",
            "(?:expirationtime|expiration_time|expiration|expirytime|expiry|expire|exp|due)\\s*[\"'=:：]?\\s*(\\d{10,13})"
        ]
        for pattern in labeledPatterns where date.isEmpty {
            if let groups = Fmt.regexGroups(pattern, text), groups.count > 1 {
                let raw = groups[1]
                date = raw.count >= 10 ? dateFromTimestamp(raw) : normalizeDate(raw)
            }
        }
        if date.isEmpty && !hasProductionMarker(text) {
            if let groups = Fmt.regexGroups("(20\\d{2}[-/.年]\\d{1,2}[-/.月]\\d{1,2}日?)", text), groups.count > 1 {
                date = normalizeDate(groups[1])
            }
        }

        // 4) 时间
        let timePatterns = [
            "(?:有效期至|到期|效期|时间|至|到)\\s*[:：]?\\s*(?:20\\d{2}[-/.年]\\d{1,2}[-/.月]\\d{1,2}日?)?\\s*([0-2]?\\d):([0-5]\\d)",
            "(?:[ T])([0-2]?\\d):([0-5]\\d)"
        ]
        for pattern in timePatterns where time.isEmpty {
            if let groups = Fmt.regexGroups(pattern, text), groups.count > 2, let hour = Int(groups[1]) {
                if hour > 23 {
                    timeError = "识别到异常时间 \(groups[1]):\(groups[2])"
                } else {
                    time = String(format: "%02d:%@", hour, groups[2])
                }
            }
        }
        if time.isEmpty && date.isEmpty {
            // 5) Unix 时间戳：10 位秒 / 13 位毫秒；11—12 位视为异常
            if let groups = Fmt.regexGroups("(?<!\\d)(\\d{10,14})(?!\\d)", text), groups.count > 1 {
                let digits = groups[1]
                if digits.count == 10 || digits.count == 13 {
                    let seconds = digits.count == 13 ? (Double(digits) ?? 0) / 1000 : (Double(digits) ?? 0)
                    let stamp = Date(timeIntervalSince1970: seconds)
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                    formatter.dateFormat = "yyyy-MM-dd"
                    let year = Calendar.current.component(.year, from: stamp)
                    if year >= 2000 && year <= 2100 {
                        date = formatter.string(from: stamp)
                        formatter.dateFormat = "HH:mm"
                        time = formatter.string(from: stamp)
                    }
                } else {
                    timeError = "识别到 \(digits.count) 位数字串，不是标准效期时间戳"
                }
            }
        }
        if date.isEmpty && !hasProductionMarker(text) {
            // 6) 8 位紧凑日期
            if let groups = Fmt.regexGroups("(?<!\\d)(20\\d{6})(?!\\d)", text), groups.count > 1 {
                date = normalizeDate(groups[1])
            }
        }

        var parsed = QrResult(raw: text, name: name, date: date, time: time, timeError: timeError, material: nil)
        parsed.material = match(name: name, materials: materials)
        if parsed.date.isEmpty && parsed.name.isEmpty && parsed.time.isEmpty && parsed.timeError.isEmpty {
            return nil
        }
        return parsed
    }

    static func match(name: String, materials: [ExpiryMaterial]) -> ExpiryMaterial? {
        let target = normalizeName(name)
        guard !target.isEmpty else { return nil }
        if let exact = materials.first(where: { normalizeName($0.name) == target }) {
            return exact
        }
        let candidates = materials.filter {
            let normalized = normalizeName($0.name)
            return !normalized.isEmpty && (target.contains(normalized) || normalized.contains(target))
        }
        return candidates.max { normalizeName($0.name).count < normalizeName($1.name).count }
    }

    static func normalizeName(_ text: String) -> String {
        var value = normalizeDigits(text).lowercased()
        value = value.replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: "　", with: "")
        let remove = CharacterSet(charactersIn: "()（）[]【】{}<>《》,，;；:：-_/\\|·.。")
        value = value.components(separatedBy: remove).joined()
        return value
    }

    private static func normalizeDigits(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.value >= 0xFF10 && scalar.value <= 0xFF19 {
                if let ascii = UnicodeScalar(scalar.value - 0xFF10 + 0x30) {
                    result.unicodeScalars.append(ascii)
                }
            } else if scalar.value == 0xFF1A {
                result.append(":")
            } else if scalar.value == 0xFF0F {
                result.append("/")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func normalizeDate(_ raw: String) -> String {
        guard let groups = Fmt.regexGroups("(20\\d{2})[-/.年]?(\\d{1,2})[-/.月]?(\\d{1,2})日?", raw),
              groups.count >= 4,
              let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]) else {
            return ""
        }
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func normalizeDateValue(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.count == 10 || value.count == 13, value.allSatisfy({ $0.isNumber }) {
            return dateFromTimestamp(value)
        }
        let normalized = normalizeDate(value)
        return normalized.isEmpty ? value : normalized
    }

    private static func dateFromTimestamp(_ raw: String) -> String {
        let digits = normalizeDigits(raw).filter { $0.isNumber }
        guard (digits.count == 10 || digits.count == 13), let value = Double(digits) else { return "" }
        let seconds = digits.count == 13 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        let year = Calendar.current.component(.year, from: date)
        return (year >= 2000 && year <= 2100) ? formatter.string(from: date) : ""
    }

    /// 出现开封/生产等标签时，不再用无标签日期兜底，避免把开封日当成到期日。
    private static func hasProductionMarker(_ text: String) -> Bool {
        Fmt.regexGroups("(?:开封|开启|生产日期|生产|open|production|mfg|manufactured)", text) != nil
    }

    private static func firstValue(_ object: JSON, keys: [String]) -> String {
        let wanted = Set(keys.map { normalizeKey($0) })
        for (key, value) in object {
            guard wanted.contains(normalizeKey(key)) else { continue }
            if let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return ""
    }

    private static func normalizeKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

// MARK: - 相机控制器

final class ScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var hint = "将效期标签二维码放入框内"
    let session = AVCaptureSession()

    var onCode: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "ss.scanner.session")
    private var configured = false
    private var device: AVCaptureDevice?
    private var lastEmit = Date.distantPast
    private var lastValue = ""

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.configureAndRun()
                } else {
                    DispatchQueue.main.async { self.hint = "未获得相机权限，可在系统设置中开启后重试" }
                }
            }
        default:
            hint = "相机权限被拒绝，请在系统设置中开启"
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func resume() {
        lastEmit = Date.distantPast
        lastValue = ""
    }

    func toggleTorch() -> Bool {
        guard let device = device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            let on = device.torchMode == .on
            device.unlockForConfiguration()
            return on
        } catch {
            return false
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1920x1080
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.hint = "无法访问后置摄像头" }
                    return
                }
                self.session.addInput(input)
                self.device = device

                let metadata = AVCaptureMetadataOutput()
                if self.session.canAddOutput(metadata) {
                    self.session.addOutput(metadata)
                    metadata.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    let wanted: [AVMetadataObject.ObjectType] = [.qr, .ean13, .code128, .pdf417, .dataMatrix]
                    metadata.metadataObjectTypes = wanted.filter { metadata.availableMetadataObjectTypes.contains($0) }
                }

                self.configured = true
                self.session.commitConfiguration()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: 二维码

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        for object in metadataObjects {
            if let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue, !value.isEmpty {
                emit(value)
                return
            }
        }
    }

    // MARK: 仅二维码，不做文字识别

    private func emit(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let now = Date()
        if value == lastValue && now.timeIntervalSince(lastEmit) < 2.5 { return }
        lastValue = value
        lastEmit = now
        DispatchQueue.main.async { [weak self] in
            self?.onCode?(value)
        }
    }
}

// MARK: - 预览层

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - 扫码页

struct ExpiryScannerView: View {
    let materials: [ExpiryMaterial]
    let closeTime: String
    let onApply: (QrResult) -> Void
    let onClose: () -> Void

    @StateObject private var scanner = ScannerController()
    @State private var result: QrResult?
    @State private var selectedMaterialId = ""
    @State private var message: String?
    @State private var showManual = false
    @State private var torchOn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.05), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                scanFrame
                Spacer()
                if let result = result {
                    confirmPanel(result)
                } else {
                    hintPanel
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            scanner.onCode = { text in handle(text) }
            scanner.start()
        }
        .onDisappear { scanner.stop() }
        .sheet(isPresented: $showManual) {
            ManualScanSheet { text in
                showManual = false
                handle(text)
            } onCancel: {
                showManual = false
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            Text("扫描效期二维码")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                torchOn = scanner.toggleTorch()
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(torchOn ? .yellow : .white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            Button {
                showManual = true
            } label: {
                Text("手动输入")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var scanFrame: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.9), lineWidth: 2)
            .frame(width: 240, height: 240)
            .overlay(
                VStack {
                    if result == nil {
                        Text("正在识别…")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                    }
                }
                .offset(y: 130)
            )
    }

    private var hintPanel: some View {
        VStack(spacing: 8) {
            Text(scanner.hint)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("请让二维码填满取景框，避免反光或褶皱。仅识别二维码，不做文字识别。")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if let message = message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func confirmPanel(_ result: QrResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.date.isEmpty ? "未识别到有效效期" : "识别到：\(result.date) \(result.time)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            if !result.name.isEmpty {
                Text("标签名称：\(result.name)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            if !result.timeError.isEmpty {
                Text(result.timeError)
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
            }

            HStack(spacing: 8) {
                Text("物料")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                if materials.isEmpty {
                    Text("暂无物料配置")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                } else {
                    Picker("", selection: $selectedMaterialId) {
                        Text("请选择物料").tag("")
                        ForEach(materials) { material in
                            Text(material.name).tag(material.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
            }
            if !materials.isEmpty {
                if let matched = materials.first(where: { $0.id == selectedMaterialId }) {
                    Text("已自动匹配：\(matched.name)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                } else {
                    Text("未匹配物料，请手动选择后完成")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                }
            }

            if let message = message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
            }

            HStack(spacing: 10) {
                Button {
                    message = nil
                    self.result = nil
                    scanner.resume()
                } label: {
                    Text("继续扫描")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                        )
                }
                Button {
                    finish(result)
                } label: {
                    Text("完成")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(selectedMaterialId.isEmpty || result.date.isEmpty)
                .opacity(selectedMaterialId.isEmpty || result.date.isEmpty ? 0.55 : 1)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func handle(_ text: String) {
        guard let parsed = QrParser.parse(text, materials: materials) else {
            message = "未识别到效期信息，请对准二维码或改用手动输入"
            return
        }
        if parsed.date.isEmpty && parsed.material == nil {
            message = parsed.timeError.isEmpty ? "未识别到有效期，请重试" : parsed.timeError
            return
        }
        let updated = parsed
        if let material = parsed.material {
            selectedMaterialId = material.id
            message = nil
        } else {
            // 未命中物料时停留在待确认状态，由用户手动选择，不再默认第一项。
            selectedMaterialId = ""
            message = "未匹配到物料，请在下方手动选择"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation {
            result = updated
        }
    }

    private func finish(_ current: QrResult) {
        guard !current.date.isEmpty else {
            message = "未识别到有效期，请重新扫描或手动输入"
            return
        }
        guard let material = materials.first(where: { $0.id == selectedMaterialId }) ?? current.material else {
            message = "请选择要登记的物料"
            return
        }
        var final = current
        final.material = material
        if final.time.isEmpty {
            final.time = closeTime
        }
        onApply(final)
    }
}

// MARK: - 手动输入

struct ManualScanSheet: View {
    let onParse: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("粘贴二维码内容，或输入标签上的有效期（如 2026-11-23 18:00）。")
                        .font(.ssSmall)
                        .foregroundColor(AppColor.textSecondary)
                    TextEditor(text: $text)
                        .font(.ssBody14)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    Button {
                        onParse(text)
                    } label: {
                        Text("识别")
                            .font(.ssBody14)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(text.isEmpty ? AppColor.primary.opacity(0.5) : AppColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }
                    .disabled(text.isEmpty)
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("手动输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
        }
    }
}
