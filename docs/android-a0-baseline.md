# Android A0：技术基线与能力矩阵

> 2026-11-10；依据仓库提交 `9398aa1559326553b77714a5b22c99651f02c5b0`、本机工具链和只读真机信息。A0 是盘点与范围定义，尚无 Android 工程、构建或 App 真机运行结果。
> 下一阶段按 [Android 适配规划](android-adaptation-plan.md)的 A1 执行。macOS 旧版实现只能作为契约基线，不能证明 Android 可用。

## 1. 产品目标与本阶段决定

用户提出的目标是**在 Android 设备上嵌入 npm 和 CLI 并可正常使用**，且继续只有一套 Flutter/Dart App。A0 将设备本地执行保留为目标，不把 Mac Host 执行算成目标已实现。由 A3/A4 的真实探针判定本地可交付范围；Host 是通用 CLI 的独立备选路径。

| npm/CLI 层级 | 可观察的完成条件 | A0 结论 |
| --- | --- | --- |
| T1：构建时安装、随 App 打包的 JS 包 | Android 真机从 Node 入口调用锁定包，能传参、返回结果、取消和重启 | A3/A4 首先验证，当前未知。 |
| T2：手机上安装纯 JS npm 包 | App 内下载、校验、安装、升级和卸载；包的 `bin` 入口可用 | A4 单独验证，当前未知。 |
| T3：用户可运行此前未知的 npm CLI/本地 CLI | 含依赖脚本、外部可执行文件、原生扩展、TUI 和 stdio 服务的真实样本在目标真机通过 | 目标能力，不承诺已可行；A4 未通过则不能以“完整本地 npm/CLI”验收。 |

本轮先用**开发包在已连接真机验证**；正式分发渠道尚未由用户指定，记为待定。若选择 Google Play，按 2026-11-10 的[官方要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)，手机 App 新版需以 API 36+ 为目标；动态加载代码另按[Play 政策](https://support.google.com/googleplay/android-developer/answer/18265346?hl=en)核查。该条件不会用降低 target API 的方式绕过。

## 2. 本机与真机基线

| 项目 | A0 实测/检查结果 | 后续用途 |
| --- | --- | --- |
| Flutter / Dart | stable 3.47.8 / 3.13.7；Flutter revision `0efc2569fa` | A1 Android 宿主与共用 Widget。 |
| Java | Temurin 17.0.21 | Android Gradle 构建。 |
| Android SDK | 路径 `/Users/guo/Library/Android/sdk`；已装 Platform 30、32、33、34、36、37.0；Build Tools 30.0.3、34.0.0、36.0.0；ADB 37.0.2；`flutter doctor -v` 的 Android toolchain 通过 | A1 可先以 API 36 编译；实际版本由生成的 Android 工程锁定。 |
| Gradle / AGP | **仓库未定义**，因为 `app/android/` 尚不存在；系统命令中也无独立 Gradle | A1 生成宿主后记录 wrapper 与 AGP；不能把插件示例的 AGP 误当本项目版本。 |
| NDK / CMake | `sdkmanager --list_installed` 未列 NDK/CMake，SDK 中未找到 NDK 目录 | `flutter_pty2` 的 Android native-assets 构建钩子已在当前依赖中；A1 首次 Android 构建前就要安装并锁定兼容 NDK，优先评估 r28+。CMake 是否为后续 Node 桥所需由 A3 构建方案决定。 |
| Node / npm（开发 Mac） | Node 24.14.1 / npm 11.11.0；主机有 `ncm-cli`、`mpv`、Git 2.54.0 和 Python 3.15.2 | 只说明开发机可准备样本，不说明 Android 已有这些命令。 |
| 当前真机 | LGE AN10；Android 15 / API 35；`arm64-v8a`，4 KB 内存页；物理分辨率 1312×2848 | A1/A2 的首台真实设备；未安装或启动模拟器。 |
| 16 KB 页真机 | 当前 ADB 未连接此类设备 | A3 原生库和 A8 发布门槛的验证缺口，届时须取得真机或明确缩小已验证范围。 |

**候选支持范围：**`minSdk` 先按 API 24 设计，因为 [Flutter 3.47 支持 Android API 24–37](https://docs.flutter.dev/reference/supported-platforms)，锁定的 `flutter_secure_storage` 与 `file_selector_android` Android 工程均要求 `minSdk 24`。首台设备只覆盖 arm64/API 35/4 KB；`armeabi-v7a`、`x86_64` 与 16 KB 页均未实际验证。若走 Play，`targetSdk` 候选为 API 36+；最终值由 A1 工程和分发渠道确认。Android 官方对原生库的 [16 KB 页指南](https://developer.android.com/guide/practices/page-sizes)建议 AGP 8.5.1+、NDK r28+ 并检查预编译 `.so`，A3 需逐项验证。

`flutter doctor -v` 另报 Xcode 无法列出 Simulator runtimes；这是 iOS/macOS 工具提示，不能据此判定 Android toolchain 失败。本轮不启动模拟器。

## 3. 锁定依赖的 Android 条件

以下为 `pubspec.lock` 与已缓存包源码的静态检查；**声明支持不等于本 App 已在 Android 构建或运行**。

| 依赖 | 锁定版本与静态证据 | A1/A2/A3 要验证的事 |
| --- | --- | --- |
| `mcp_dart` | 2.4.3；包 `pubspec.yaml` 声明 Android，依赖 Dart `http`/`crypto` | A2 在真机验证 Streamable HTTP；当前 macOS stdio/HTTP 探针不能外推。 |
| `flutter_pty2` | 3.0.0；native-assets 构建钩子对 Android 带 `-Wl,-z,max-page-size=16384`；其 README 只报告 API 35 模拟器的部分输入/输出集成测试 | A3/A6 检查 NDK 构建和真机；其 PTY 仍需实际可执行程序，不能由插件支持推出任意 Android CLI 可运行。 |
| `terminal_view` | 0.5.0；Flutter/Dart Widget，当前 `TerminalPage` 已使用 | A1/A6 检查软键盘、IME、触控、文字选择与 Host 输出。 |
| `file_selector` / `file_selector_android` | 1.1.0 / 0.5.2+11；Android 实现要求 Flutter >=3.44、Java 17、`minSdk 24` | A2 检查 Android URI 与现有使用 `file.path` 的清单导入/导出是否相容。 |
| `flutter_secure_storage` | 11.2.0；Android 插件要求 Java 17、`minSdk 24` | A2 真机验证凭证保存、重启、删除和迁移。 |

## 4. `RuntimePort` 逐项去向

下表中的“手机”是 Android Dart 适配器提供的能力，“Host”是未来 Mac 执行端，“JS”仅指通过 A4 白名单验证的包。所有页面仍使用共用 Flutter `RuntimePort`。当前 `RuntimeFeatures` 是**运行端级**声明；手机与 Host 并列展示时，A1 需增加连接级执行位置/能力或路由约束。

| 方法 / 属性 | Android 去向 | 首次实施 | 契约注意点 |
| --- | --- | --- | --- |
| `isPreview` | 共用 Dart | A1 | 真实 Android Runtime 返回 false。 |
| `features` | 手机 + Host 路由 | A1/A6 | 不得以一个全局 `terminal=true` 误标所有手机连接。 |
| `startupNotices` | 手机汇总，Host 状态附加 | A1/A6 | 诊断需注明执行设备。 |
| `loadPreferences` | 手机本地持久化 | A2 | 保留现有 JSON schema。 |
| `savePreferences` | 手机本地持久化 | A2 | 保存失败需可回滚。 |
| `clearActivity` | 手机记录；Host 记录另处理 | A2/A6 | 不能只清手机记录却显示 Host 已清。 |
| `listConnections` | 手机 HTTP + Host 合并 | A2/A6 | 连接 ID 包含来源，避免重名冲突。 |
| `addConnection` | HTTP 手机；CLI/stdio Host 或经验证 JS | A2/A6 | `ConnectionSpec.executable` 为 Mac 绝对路径时不得当手机路径。 |
| `removeConnection` | 按连接归属路由 | A2/A6 | 同步清理凭证、能力和 Host 引用。 |
| `moveConnection` | 手机排序/合并列表 | A2/A6 | 跨来源排序由 UI 偏好控制。 |
| `refreshConnection` | 按归属重连/诊断 | A2/A6 | 不可用原因区分网络、授权、程序缺失。 |
| `loadActionManifest` | Host CLI；JS 白名单可本地 | A6/A4 | 不给普通 Android HTTP 连接显示 CLI 动作编辑。 |
| `readActionManifestFile` | 手机文件选择的本地文件或 Host 文件 | A2/A6 | 现有 String 路径需核对 Android URI 语义。 |
| `saveActionManifest` | 按 CLI/JS 归属路由 | A6/A4 | 保存目标与权限属于执行端。 |
| `exportActionManifest` | 手机系统文件选择 | A2/A6 | Host 清单导出时应复制内容，不暴露 Host 路径。 |
| `searchCapabilities` | 手机 + Host 目录合并 | A2/A6 | 能力 ID 保留连接来源。 |
| `invoke` | HTTP 手机；CLI/stdio Host；JS 白名单本地 | A2/A6/A4 | 运行记录绑定执行目标，外部写入断线不自动重放。 |
| `watchRun` | 同 `invoke` | A2/A6/A4 | 事件流断线与终态可区分。 |
| `listRecentRuns` | 手机本地/Host 记录汇总 | A2/A6 | 脱敏和结果未知状态一致。 |
| `cancel` | 同 `invoke` | A2/A6/A4 | 返回取消请求不等于远端已停止。 |
| `readResource` | HTTP 手机或 Host MCP | A2/A6 | 资源 URI 与连接来源成对保存。 |
| `getPrompt` | HTTP 手机或 Host MCP | A2/A6 | 结果结构与错误码一致。 |
| `previewLocalFile` | 手机沙箱/系统 URI；Host 文件须传输 | A2/A6 | 当前路径接口可能需扩展，Mac 路径不能直接在手机打开。 |
| `revealLocalFile` | 先明确 unsupported；可评估 Android 系统文件选择器 | A1/A2 | Android 无 Finder 式“定位文件”同义行为。 |
| `openTerminal` | Host PTY；本地 JS 终端须 A4 单独证明 | A6/A4 | 不能把渲染控件可用误认为本机 PTY 可用。 |
| `watchTerminal` | Host 事件流或获准本地会话 | A6/A4 | 输出上限与断线状态。 |
| `writeTerminal` | Host/获准本地会话 | A6/A4 | 软键盘的 Ctrl/Esc/Tab 映射。 |
| `resizeTerminal` | Host/获准本地会话 | A6/A4 | 横竖屏与输入法尺寸变化。 |
| `interruptTerminal` | Host/获准本地会话 | A6/A4 | SIGINT 与会话关闭不同。 |
| `closeTerminal` | Host/获准本地会话 | A6/A4 | 关闭后清理进程/连接。 |

额外接口和系统能力：`ConnectionAccountPort` 的 `readAccount`、`beginAccountLogin`、`waitAccountLogin`、`logoutAccount` 当前只在核对过身份的 macOS 网易云连接实现；Android 的 Host 模式应在 A6/A7 透传，手机本地模式必须另验，不自动启用。凭证存储从 macOS Keychain 换为 Android 插件；文件导入导出从桌面路径改为 Android 文档访问；当前没有已完成的跨端通知能力。`app/lib/main.dart` 固定创建 `LocalRuntimePort`，A1 需改为平台接线。`ConnectionsPage` 和动作编辑器直接使用 `file.path`，是 A2 的具体兼容性检查点。

## 5. 可重复验收样本

| 类型 | A0 选定样本 | 预期观察与边界 |
| --- | --- | --- |
| HTTP MCP | `spikes/phase0/fixture_server.py http --port 8765`；仓库记录所需 Python `mcp==2.3.0` | `add` 工具、`memo://phase0/readme` 资源、`welcome` 提示；当前只绑定 Mac 回环地址，A2 真机可用 ADB reverse 做协议探针，真实远程 TLS/认证另验。 |
| stdio MCP | 同一 `fixture_server.py stdio` | A5/A6 经 Mac Host 启动，验证发现/调用/取消/进程清理；不是 Android 本地服务能力证据。 |
| 普通 CLI | `connectors/examples/git-status.json` 的 `/usr/bin/git status --short` | 清单当前只声明 `macos`；A5/A6 验证 Host，A4 若研究本地 Git 需另准备 Android ABI 构建。 |
| 交互 TUI | `spikes/phase0/tui_fixture.py` | `READY`、输入回显、尺寸变化和 `quit`；A5/A6 测 Host PTY，Android 本地 TUI 须 A4 另证。 |
| 纯 JS npm/CLI 候选 | `semver@7.7.3` | npm 元数据：Node >=10、无列明依赖、`bin/semver.js`；A4 先测模块 API，再测 `bin` 参数/输出/退出与取消，当前未在 Android 运行。 |
| 外部程序依赖 | `@music163/ncm-cli@0.1.7` | npm 元数据要求 Node >=18，依赖 `fluent-ffmpeg`、`ffprobe-static`；当前 Mac Runtime 还检查 `mpv`。用作 CLI 不等于 Node 可用的反例及网易云真实样本。 |

样本版本/文件是测试输入，不是发布许可或 Android 兼容保证。A4 需给每个包记录依赖树、安装脚本、原生文件和真实失败结果。

## 6. A0 完成判定与 A1 输入

- A0.1 已记录当前工具链与依赖；Gradle/AGP 尚无项目版本，NDK 尚未安装，作为 A1 首次 Android 构建的显式前置。
- A0.2 已覆盖 `RuntimePort` 的全部属性/方法、账号扩展、文件、凭证和终端，并标注执行端。
- A0.3 已选出 HTTP/stdio MCP、普通 CLI、TUI、纯 JS npm CLI 与外部程序依赖样本。
- A0.4 已建立设备矩阵：现有 API 35/arm64/4 KB 真机；16 KB 真机和其他 ABI 缺口明确；发行渠道尚未知，但 Play 条件已列明。
- A0.5 已把设备端 npm 目标分为 T1/T2/T3。用户希望的完整本地 npm/CLI 对应 T3，能否达到须以 A4 证据决定。

**A1 可开始：**复用单套 Flutter 页面建立 Android 宿主，先以 API 24 作为最低版本候选，以 API 36 作为 Play 条件下的目标版本候选；生成工程后锁定 Gradle/AGP，安装并锁定用于 `flutter_pty2` 的 NDK，再执行首次 Android 构建。A1 不要求先取得 16 KB 真机，但 A3 原生方案与 A8 正式发布必须解决该验证缺口。本轮没有修改 App 代码或真机配置。
