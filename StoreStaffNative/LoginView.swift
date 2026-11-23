import SwiftUI

struct LoginView: View {
    let onLoggedIn: () -> Void

    @State private var phone = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case phone, password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 48)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.primary)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text("塔")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                    )

                Text(AppConfig.appName)
                    .font(.ssTitle)
                    .foregroundColor(AppColor.text)
                    .padding(.top, 18)
                Text("员工端 · 原生版")
                    .font(.ssSmall)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("手机号")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    TextField("请输入 11 位手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .phone)
                        .font(.ssBody)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .disabled(loading)
                        .onChange(of: phone) { value in
                            let digits = String(value.filter { $0.isNumber }.prefix(11))
                            if digits != value { phone = digits }
                            error = nil
                        }
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text("密码")
                        .font(.ssCaption)
                        .foregroundColor(AppColor.textSecondary)
                    SecureField("请输入密码", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .font(.ssBody)
                        .padding(12)
                        .background(AppColor.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .disabled(loading)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .onChange(of: password) { _ in error = nil }
                }
                .padding(.top, 14)

                if let error = error {
                    Text(error)
                        .font(.ssSmall)
                        .foregroundColor(Sem.bad)
                        .padding(.top, 12)
                }

                Button(action: submit) {
                    ZStack {
                        if loading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("登录")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(loading ? AppColor.primary.opacity(0.7) : AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                }
                .disabled(loading)
                .padding(.top, 24)

                Text("登录状态由服务器 Token 维持，有效期 30 天")
                    .font(.ssCaption)
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.top, 18)

                Spacer().frame(height: 48)
            }
            .padding(.horizontal, 28)
        }
        .background(AppColor.background.ignoresSafeArea())
        .onTapGesture { focusedField = nil }
    }

    private func submit() {
        guard !loading else { return }
        focusedField = nil
        let phoneOk = phone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil
        if !phoneOk {
            error = "请输入正确的 11 位手机号"
            return
        }
        if password.isEmpty {
            error = "请输入密码"
            return
        }
        loading = true
        error = nil
        Task {
            do {
                try await AuthRepository.login(phone: phone, password: password)
                loading = false
                password = ""
                PushRegistry.registerIfNeeded()
                onLoggedIn()
            } catch {
                loading = false
                self.error = ErrText.readable(error)
            }
        }
    }
}
