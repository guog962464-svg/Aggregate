# Aggregate Android 适配规划

> 规划日期：2026-11-10。状态：方案与技术探针计划，尚未实现或在 Android 真机验证。
> 本文响应本轮 Android 目标；[原 macOS 方案](architecture.md)中的“本版仅 macOS”是上一阶段范围，不限制本轮规划。桌面界面背景见 [UI 设计](ui-design.md)，当前连接首页见[阶段 5](phase5-contextual-ui.md)。

## 1. 先明确“在手机上运行 CLI”的三个层次

| 层次 | 例子 | Android 首版建议 |
| --- | --- | --- |
| App 自带的 JavaScript 功能 | 随 APK 打包、经验证的 JS 模块 | 可以用嵌入 Node 探针验证；也可以优先用 Dart/Android API 实现。 |
| 用户在设备上安装 npm 包并运行其 CLI | `npm install -g @music163/ncm-cli` | 不承诺通用支持；先验证纯 JS 包、安装脚本、可执行入口及版本管理。 |
| 任意本机 CLI、TUI、stdio MCP | Git、Python Server、mpv 等 | 默认通过配对的桌面 Host 执行；本地只开放经逐项适配和真机验证的能力。 |

这三个层次不能由“Node.js 可以启动”推导为“npm 与所有 CLI 可用”。当前 macOS `MacRuntime` 用 `Process.start`、PTY、系统可执行文件、钥匙串和本机路径；Android 需要另一套适配器。现有 `RuntimePort.features` 可准确报告该运行端支持的连接类型和终端能力，公共页面应继续依赖它，而不是根据手机外形推断执行能力。

## 2. `nodejs-mobile` + JNI/FFI 的判断

**结论：可作为“内嵌 JS 运行器”的验证路线，不能直接作为“完整 npm/CLI 环境”的交付方案。** `nodejs-mobile` 官方提供 Android `libnode.so`，原生示例通过 JNI 调用 `node::Start`。Android 侧建议用 Kotlin/Java 负责生命周期和平台通道、C++ JNI 薄层调用 Node；Dart FFI 只有在导出稳定的 C ABI 后才接入，不直接绑定 C++ `node::Start`。优先在独立的 Android `:node` Service 进程中运行，以隔离 Node 崩溃和单实例限制，再通过 Binder/平台通道向 `AndroidRuntimePort` 传递请求与事件；是否需要本机回环服务留给探针比较。

对原设想的修正：

1. `libnode.so` 必须按 ABI 打包，并核查其头文件、链接方式、许可证、来源与校验值。不能只复制 `.so` 后假定 `dlopen` 能找到并调用 C++ 入口。
2. Node 应在工作线程启动，应用需要明确初始化、就绪、超时、退出、重启和 App 后台行为。官方 FAQ 说明同一进程通常只能启动一个 Node 实例。
3. JS 入口和已锁定的纯 JS 依赖在构建时打包；`esbuild` 可以减少文件数量，但动态 `require`、资源文件、原生 `.node` 扩展和外部命令不能假定都能压入单文件。
4. npm **包依赖可在开发机安装并随 App 发货**，这不等于 Android 设备具备可交互的 npm CLI 或能在手机上执行安装脚本。设备端安装包要另外验证下载、完整性、依赖脚本、二进制插件、存储和升级回滚；首版不把它作为基础能力。
5. Android 10 起，面向 API 29+ 的 App 不能直接 `execve()` 执行可写 App 私有目录中的文件；`child_process.spawn/fork` 也被 `nodejs-mobile` 列为移动端易受权限限制的 API。将 `node` 嵌入 App 并不会让 shell、Git、Python、ffmpeg 或 mpv 自动可用。
6. `nodejs-mobile` 当前公开 Android 预编译版本为 Node 18.20.4；Node 18 已结束维护。原生库还须在真实 Android 16 KB 页设备上检查 ELF 和 APK 对齐。**若无法取得可维护且符合目标设备/分发要求的构建，不把这条路线用于正式发布。**

传输优先级：进程内 JNI/消息队列，或独立进程的 Binder；若使用 `127.0.0.1`，随机端口、一次性令牌、仅回环绑定、就绪握手和关闭清理都必须验证。不要固定 `8080`，也不要将本地服务暴露到网络接口。

## 3. 路线比较与推荐组合

| 路线 | 能做什么 | 主要限制 | 计划中的位置 |
| --- | --- | --- | --- |
| 纯 Dart/Android Runtime | 远程 HTTP MCP、连接目录、表单、结果、Android 文件与凭证适配 | 不能直接运行桌面 CLI | **首个可交付基础**，先做通。 |
| 内嵌 `nodejs-mobile` | 经验证的本地纯 JS 模块、部分不启动子进程的 Node 能力 | Node 版本/16 KB、单实例、原生插件和 `spawn` 限制 | **并行技术探针**，通过门槛后才接入产品。 |
| 配对 macOS Host | 任意已登记的 Mac CLI、TUI、stdio MCP 和现有网易云路径 | 需要在线 Mac、配对协议和跨设备权限 | **通用 CLI 的默认扩展路径**；复用现有执行语义。 |
| 安卓本地命令环境或第三方终端 | 有机会覆盖更多真实 CLI | ABI、可执行文件、沙箱、依赖、分发与生命周期均复杂 | 研究分支，不作为首版承诺。 |

推荐的产品表述是“Android 可连接远程 MCP，并可使用已适配的本地功能；通用 CLI 由配对 Host 运行”。连接详情必须明确显示“在手机执行”或“在 Mac 执行”，并根据运行端能力显示可用功能。跨端同名能力继续使用来源 ID 区分。

## 4. 阶段计划与验收门槛

### A0：基线和兼容矩阵

- 固定 Flutter/Dart、Gradle、AGP、NDK、`mcp_dart`、`flutter_pty2`、`terminal_view` 的实际版本；创建 Android 工程前记录最低 API、目标 API、ABI、4 KB/16 KB 页设备范围。当前仓库尚无 `app/android/`。
- 盘点 `app/lib/main.dart` 的 macOS 固定接线、`MacRuntime` 的进程/PTY/凭证/路径调用、`RuntimePort` 的所有能力，以及 `ncm-cli` 的执行依赖。保留 `contracts`、`domain` 和通用 Widget 无平台 API 的边界。
- 确定 Android 首版分发方式与验收范围；Google Play 动态代码政策和原生库要求在选型前核对。对具体目标手机使用真机，不用模拟器代替。

**交付/门槛：**有逐项能力矩阵和当前依赖清单；未验证项标“未知”，不以 macOS 结果外推 Android。

### A1：最小 Android App 与无 Node 基础能力

- 创建 `app/android/`，让 Flutter App 使用平台工厂选择 `AndroidRuntimePort`；macOS 继续接原 `LocalRuntimePort`。
- 先实现远程 HTTP MCP、连接/活动持久化、Android 凭证存储和文件选择；`RuntimeFeatures` 如实隐藏尚未接入的本机 CLI、stdio、终端及文件定位。
- 用真实 HTTP MCP 完成发现、调用、取消、异常与恢复；真机冷启动和重启后恢复。

**门槛：**Android 真机可完成“添加远程 MCP → 搜索能力 → 表单调用 → 查看结果”，macOS 回归不受影响。

### A2：Node 技术探针，独立于主流程

- 建最小 `:node` 进程：加载 `libnode.so`、运行 `console`/`fs`/`net` 探针，向 Flutter 回送事件；测冷启动、内存、崩溃隔离、反复启动、App 退后台和进程重建。
- 用一个锁定版本的纯 JS npm 包验证构建时安装、打包、资产读取、私有目录写入；再用一个需外部可执行文件或原生模块的包验证明确失败路径。
- 检查预编译库或自建库的 ABI、Node 维护状态、`readelf` ELF 对齐、APK/AAB 对齐；在 16 KB 页真机实际加载。测不同 Android 系统版本与目标 ABI。
- 验证 Node 不能可靠完成的 `child_process`、npm 安装脚本、CLI `bin`、stdio 进程与 PTY；如某项成功，记录精确设备/API/包版本，不泛化。

**停止条件：**无法取得可维护且符合 16 KB/分发要求的 Node 构建，或无法可靠清理/重启实例时，停止产品化接入；保留 A1 + Host 路线。**通过条件：**至少一个真实纯 JS 包在目标真机稳定运行并完成请求/取消/重启；这只证明“受控 JS 包”可用。

### A3：通用 CLI / stdio MCP 执行路径

- 为 macOS Runtime 增加独立 Host 协议，Android 实现 `RemoteRuntimePort`；按现有 `RunId`、事件、取消、权限、结果不确定状态和终端会话设计协议，不复制桌面逻辑到 Widget。
- 配对与网络连接要验证设备身份、传输加密、Host 用户授权、命令参数数组、能力范围和断线恢复。外部写入的调用不得在断线后自动重放。
- 若 A2 通过，可给“已验证纯 JS 包”增加 Android 本地执行器，但不将任意 CLI 或 stdio MCP 自动标记为本地可用。

**门槛：**Android 真机经配对 Host 运行普通 CLI、交互式 TUI 和 stdio MCP，能中断并清理；Host 离线时 UI 准确提示执行位置与状态。

### A4：网易云样本与发布验证

- 先检查 `@music163/ncm-cli` 真实依赖。目前 npm 包 0.1.7 要求 Node >=18，并依赖 `fluent-ffmpeg`、`ffprobe-static`；现有 macOS 诊断还要求 `mpv`。因此不能将 Mac 上的播放器验收结果视为 Android 本地播放证明。
- 首版可经 Host 复用已验证的 `ncm-cli` 路径；若产品需要手机本地播放，单独验证服务 API、授权、音频 URL 与 Android Media3/MediaSession 方案，明确与现有 CLI 行为的差异。账号、搜索权限与播放能力逐项验收。
- 发布前检查原生库升级/漏洞响应、APK 体积、签名包安装/升级、4 KB/16 KB 真机、横竖屏/分屏、后台任务、TalkBack、网络切换和权限撤销。

**门槛：**至少一台目标 Android 真机完成 Android 主流程；若声明手机本地音乐播放，则必须在手机扬声器/耳机真实出声并由 Android 播控，不能以远端 Mac 出声代替。

## 5. 手机 UI 适配

保持现有“连接即首页”的信息结构和主题令牌，在窄屏改为单栏：顶部显示当前连接与切换入口；一级入口保留“连接 / 所有功能 / 活动 / 设置”，可用底部导航或菜单呈现，具体以手机实测选择。功能运行页占满屏幕，表单与结果上下排列；长输出与终端使用独立全屏页。宽屏/平板再恢复侧栏和并列面板。按**可用窗口宽度**而不是 Android/平板设备类型切换。

首轮重点检查：键盘弹出后的输入和运行按钮、状态栏/手势导航栏安全区、Android 返回手势、终端软键盘的 Ctrl/Esc/Tab/中断入口、动态 schema 长字段与 JSON 输入、音乐迷你播放器和底部导航同时存在时的遮挡、文字放大和 TalkBack 朗读顺序。所有来源标签和错误文案要显示真实执行设备。当前 `AppShell` 已有 760 逻辑像素的抽屉断点和单套 Widget，但手机上仍需重新评估信息密度；`TerminalPage` 的现有终端视图可以复用显示层，底层 PTY 能否运行本地命令须另验。

**UI 验收样本：**至少覆盖一台窄屏手机、一台大屏/分屏状态，浅深色、中文长名称、复杂表单、运行失败、离线 Host、终端输入、系统字体放大及 TalkBack。截图测试检查布局，真机操作检查输入、返回和可访问性。

## 6. Skillpilot 结果如何取舍

本轮调用 Skillpilot 的 `plan`，选了 review、security、docs、design、testing、strategy。它给出的 CodeRabbit、Semgrep、Context7 可作为后续评审/文档候选，设备自动化项目 `callstack/agent-device` 可研究；均未安装。其 React/Tailwind 设计工具、Playwright 网页测试、Stripe、Vercel、商业分析与本 Flutter 原生工程不匹配，不进入任务清单，也不需要 `TWENTY_FIRST_API_KEY`。验证优先使用 Flutter 测试、Android 真机、NDK 检查和真实 CLI/MCP 样本。

## 依据与待验证事实

- 当前源码：`app/lib/main.dart`、`app/lib/platform/macos/mac_runtime.dart`、`app/lib/app/app_shell.dart`、`app/lib/features/invocation/terminal_page.dart`、`packages/aggregate_contracts/lib/src/runtime_port.dart`；历史阶段见[公共层准备](phase4-common-layer.md)。
- [nodejs-mobile 官方仓库与发布包](https://github.com/nodejs-mobile/nodejs-mobile)、[官方 FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)、[Android JNI 示例](https://github.com/JaneaSystems/nodejs-mobile-samples/blob/master/android/native-gradle/README.md)。
- [Android 10 可执行文件限制](https://developer.android.com/about/versions/10/behavior-changes-10)、[16 KB 页要求](https://developer.android.com/guide/practices/page-sizes)、[动态代码加载建议](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)、[Google Play 开发者政策](https://support.google.com/googleplay/android-developer/answer/18265346)。
- [Node.js 版本维护状态](https://nodejs.org/en/about/previous-releases)、[Flutter 自适应布局](https://docs.flutter.dev/ui/adaptive-responsive/general)、[Media3 后台播放](https://developer.android.com/media/media3/session/background-playback)、[flutter_pty2 支持情况](https://pub.dev/packages/flutter_pty2)。
- [网易云 CLI npm 包](https://www.npmjs.com/package/%40music163/ncm-cli)的版本/依赖来自 2026-11-10 的 `npm view @music163/ncm-cli version engines dependencies bin --json`；真实 Android 运行行为尚未验证。
