# StoreStaffNative（iOS 原生版）

塔斯汀门店助手员工端 iOS 原生实现，使用 SwiftUI + URLSession + AVFoundation + Vision，功能与 `app/native/android` 的 Kotlin/Compose 版本对齐。数据全部调用线上 PHP 接口，不加载网页、不内置前端资源。

## 基本信息

| 项 | 值 |
| --- | --- |
| 显示名称 | 塔斯汀门店助手 |
| Bundle ID | `com.tastien.storestaff.native` |
| 最低系统 | iOS 15.0 |
| 设备 | iPhone（竖屏） |
| 后端 | `https://ta0051.jethroy.cn/` |
| 鉴权 | `auth.appLogin` 换取 Token，请求头 `X-App-Token`，30 天有效 |
| 登录失效 | HTTP 401 + `TOKEN_INVALID` / `TOKEN_EXPIRED` / `TOKEN_REVOKED` |

## 页面范围（与安卓一致）

- 登录：手机号 + 密码，失败提示服务端文案。
- 首页：头像进入「我的」、右上角铃铛进入消息（未读数角标）、今日排班（断班两段）、待办/未读概览、快捷入口。
- 任务：全部 / 日 / 周 / 月 / 次 / 个人筛选；分组母任务整组展示；卡片展开显示要求、示例图、返图、驳回原因；两种完成方式（上传返图 / 仅需确认）；改派、整组改派、管理岗代完成；逾期与已完成独立列表，已完成支持日期切换。
- 排班与排休：今日排班、月度额度、申请排休（事假/病假、当日名额统计）、申请排班（当月、断班两段、防重叠）、合并记录按日期降序、撤回/申请取消。
- 效期：效期检查（分类物料、单条登记、按打烊到期）、当天到期（标记已处理）、效期总览（到期时间着色，未处理行不占位）、扫码录入（二维码 + Vision 文字识别兜底 + 手动输入）、连续扫描、过期报废确认。
- 消息：全部 / 系统 / 任务 / 私信四个筛选（数字角标、分页每页 5 条、固定在底部）、全部已读、消息详情、公告/任务跳转、私信会话（单滚动、气泡换行、多行输入、发送后即时追加）。
- 考勤：按月切换、出勤天数/总工时/异常统计、每天分段（计划与实际打卡、差异、标签）。
- 薪资：月份列表、工资单详情（应发/实发、发放状态、明细与扣款）。
- 量化分：月份切换、总分与等级、维度得分进度、加减分明细。
- 报销：状态筛选、分页、新建（分类/金额/事由/收款方式/最多 5 个附件，支持相册与 PDF）、详情与审批状态。
- 通讯录：门店在职员工、姓名/岗位/手机号/工号搜索、分页、详情电话拨打与私信。
- 日程：我的/全部范围、今天/未来/过去分组、新建编辑（日期、时间、提醒）、删除。
- 我的：账号资料、修改密码、通知开关与免打扰、退出登录。
- 通知：本地通知 + 前台 5 分钟轮询 + BGAppRefresh 30 分钟兜底；7 天去重；默认 22:00–08:00 免打扰；点击通知直达对应页面；APNs 预留可插拔接入点。

## 目录

```
app/native/ios/
├── StoreStaffNative.xcodeproj/        # 手写 Xcode 工程（含共享 Scheme）
├── StoreStaffNative/
│   ├── StoreStaffApp.swift            # App 入口 + AppDelegate 挂载
│   ├── Theme.swift                    # 设计令牌、圆角、格式化
│   ├── Core.swift                     # 配置、Keychain 会话、APIClient、JSON 容错
│   ├── Models.swift                   # 数据模型与解析
│   ├── Repositories.swift             # 接口封装
│   ├── Components.swift               # 徽章、图片、今日排班卡、Toast
│   ├── AppRootView.swift              # 根导航、四格底栏、我的
│   ├── LoginView.swift
│   ├── HomeView.swift
│   ├── TasksView.swift
│   ├── ScheduleView.swift
│   ├── ExpiryView.swift
│   ├── ExpiryScanner.swift            # 扫码 + OCR + 解析
│   ├── MessagesView.swift             # 消息 / 私信会话
│   ├── MoreViews.swift                # 考勤 / 薪资 / 量化分 / 报销 / 通讯录 / 日程
│   ├── Notify.swift                   # 本地通知、轮询、APNs/BGTask
│   ├── Assets.xcassets                # AppIcon / LaunchPlate
│   ├── LaunchScreen.storyboard
│   └── Info.plist
└── README.md
```

## 本机构建（macOS）

```bash
cd app/native/ios
xcodebuild \
  -project StoreStaffNative.xcodeproj \
  -scheme StoreStaffNative \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机包（未签名，供后续自签）：

```bash
xcodebuild \
  -project StoreStaffNative.xcodeproj \
  -scheme StoreStaffNative \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/StoreStaffNative.app Payload/
zip -qry StoreStaffNative-unsigned.ipa Payload
```

Windows 无法编译 Swift，请使用仓库根目录的 GitHub Actions 工作流：

```
.github/workflows/ios-unsigned-ipa.yml
```

产物为 `StoreStaffNative-unsigned.ipa`（未签名），下载后按 `deliverables/ios-native/交付说明.md` 自签安装。

## 通知与 APNs

- 本地通知默认可用：任务到期/逾期、私信、审批结果、今日排班、生日关怀、系统通知。
- 前台每 5 分钟拉取一次 `notify.feed`；进入后台后由 `BGAppRefreshTask` 每 30 分钟兜底（系统调度不保证准时）。
- 免打扰：默认 22:00–08:00，静默期内不弹也不标记已读，解除后补发。
- 去重：`notify.seen.<eventId>`，保留 7 天。
- APNs 默认关闭（`IOSPushProvider.enabled = false`）。正式接入需为 Bundle ID 开启 Push Notifications、配置描述文件与 `aps-environment`，然后把 `enabled` 改为 `true`，并在 Apple Developer 生成 APNs Key 配置到服务端；服务端 `push.register` / `push_send_apns` 已预留。

## 说明

- 未签名 IPA 不能直接安装，需 Sideloadly / AltStore 用 Apple ID 重签；免费账号签名 7 天有效，最多 3 个 App。
- 自签后 Bundle ID 可在 Sideloadly 中改为自己的唯一 ID（如 `com.yourname.storestaff.native`），描述文件由工具自动生成，不需要手工提供。
- 需要长期使用或远程推送时，使用 Apple Developer Program（付费）创建 App ID 与 Provisioning Profile，并开启 Push Notifications。
