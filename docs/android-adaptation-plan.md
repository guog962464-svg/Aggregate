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

## 4. 阶段关系与交付边界

~~~text
A0 范围与基线 ─→ A1 契约、Android 壳和手机导航 ─→ A2 Android HTTP MCP
                         │                                  │
                         ├─→ A3 Node 原生桥探针 ─→ A4 npm/CLI 兼容性门槛
                         │                                  │
                         └─→ A5 macOS Host ──────────────→ A6 Android 执行路由与终端
                                                              │
                                     A4 通过的本地能力 ──────→ A6
                                                              ↓
                                                A7 UI/网易云整合 ─→ A8 发布验收
~~~

A3/A4 是手机本地 Node 路线，A5/A6 是通用 CLI 的 Host 路线；A5 可以在 A3 进行时开始。A4 未通过时，A6 仍可交付 Host 功能。若产品验收条件是“任意 npm CLI 都必须脱离 Host 在手机运行”，而 A4 无法证明该能力，**Android 版本不能按此条件验收**，需要重新确定产品范围或继续研究本地执行环境。

每阶段结束都记录实际设备、Android/API/ABI、依赖版本、通过与失败的样本，以及仍未知的项目。每个阶段的改动要单独验证并按仓库约定提交；不把探针成功写成完整产品能力。

### A0：确定范围、样本和技术基线

**前置：**现有 macOS 工程与两份历史方案。

- [ ] A0.1 记录当前 Flutter/Dart、Android SDK、Gradle、AGP、NDK 和锁定依赖版本；检查 `mcp_dart`、`flutter_pty2`、`terminal_view` 的 Android 构建条件。当前仓库尚无 `app/android/`。
- [ ] A0.2 逐个列出 `RuntimePort` 方法的 Android 去向：手机本地、Host、暂不支持。另列 `ConnectionAccountPort`、文件导入导出、凭证、通知、活动记录和终端。
- [ ] A0.3 定义验收样本：一个远程 HTTP MCP、一个普通 CLI、一个交互式 TUI、一个 stdio MCP、一个不启动子进程的纯 JS npm 包、一个依赖原生/外部程序的 npm 包，以及网易云样本。
- [ ] A0.4 定义设备矩阵：至少一台窄屏 Android 真机；如计划分发到 16 KB 页设备，准备可实际测试的 16 KB 真机。记录目标 API、最低 API、ABI、4 KB/16 KB 页和是否走 Google Play。
- [ ] A0.5 把“npm 支持”拆为构建时随包提供、手机上安装纯 JS 包、手机上安装任意包三档；明确 Android 首版希望承诺哪一档。

**交付物：**能力矩阵、样本清单、设备/版本矩阵、Android 首版范围与不支持项。**通过门槛：**每项能力有负责人层（Dart、Android 原生、Node 或 Host）与可观察的验收结果；未知项保留为未知。

### A1：契约和 Android App 骨架

**依赖：**A0。此阶段只建立 Android 入口与可浏览的页面，不把假数据当系统能力。

- [ ] A1.1 创建 Flutter Android 工程；在 `app/lib/main.dart` 改为平台工厂接线，macOS 继续使用当前 `LocalRuntimePort`，Android 接新适配器。
- [ ] A1.2 确定多运行端模型：连接/能力保存执行目标与 Host 身份；调用、权限、终端、活动记录沿用同一目标。现有全局 `RuntimeFeatures` 继续表示当前运行端能力；若 Android 要同时展示手机与 Host 能力，增加每连接可用能力或路由层，不能用一个全局布尔值掩盖差异。
- [ ] A1.3 建 `AndroidRuntimePort` 的明确未支持响应与预览数据；本地 CLI、stdio、终端、文件定位在未实现前不出现在可操作入口。
- [ ] A1.4 复用主题、连接首页、所有功能、运行页、连接管理、活动和设置；手机单栏导航基于可用窗口宽度，保留宽屏侧栏分支。
- [ ] A1.5 完成 Android 返回行为、状态栏/手势导航栏安全区、输入法遮挡、触控目标和最基本的 TalkBack 名称检查。

**交付物：**可安装的 Android 开发包、平台工厂、执行目标契约草案、手机导航骨架。**通过门槛：**真机可启动并浏览各页，返回/键盘不造成死路或遮挡；公共包与通用 Widget 保持平台无关；macOS 构建与现有主流程回归通过。

### A2：Android 本地基础运行端与 HTTP MCP

**依赖：**A1。先实现无需 Node 或外部进程的闭环。

- [ ] A2.1 接入 Android 应用私有存储，保存连接、偏好与脱敏活动；写入失败、损坏配置和升级迁移有明确恢复方式。
- [ ] A2.2 通过 Android 安全存储保存 HTTP MCP 凭证，配置文件只保存引用；验证重启、撤销和删除连接后的清理。
- [ ] A2.3 复用或封装现有 `mcp_dart` 的 Streamable HTTP 客户端，跑通初始化、能力发现、工具调用、资源/提示、分页或协议差异、超时、取消与断线处理。
- [ ] A2.4 让文件导入/导出使用 Android 系统文件选择与 URI；检查现有清单编辑器、结果文件和权限撤销后的错误提示。
- [ ] A2.5 用真实 HTTP MCP 验证“添加连接 → 搜索 → 填参 → 运行 → 查看结果 → 重启恢复”；离线和认证失败不显示成功。

**交付物：**无需 Mac 的 Android HTTP MCP 功能包与真机验收记录。**通过门槛：**上述闭环在真机通过；本地 CLI/stdio/终端仍按能力声明禁用；macOS 行为不回退。

### A3：`nodejs-mobile` 原生桥探针

**依赖：**A1，可与 A2、A5 并行。探针保持独立，不先绑定完整 UI。

- [ ] A3.1 核验 `libnode.so` 来源、许可证、校验值、头文件、Node 版本、ABI、NDK/AGP 要求；评估维护中的 Node 构建和 16 KB 页支持。预编译 Node 18 只作实验候选。
- [ ] A3.2 在独立 `:node` Service 进程使用 Kotlin/Java + C++ JNI 薄层加载库、调用 `node::Start`，在工作线程运行；定义启动、就绪、请求、事件、失败和关闭协议。
- [ ] A3.3 通过 Binder/平台通道把 `console`、文件读写、网络请求、异常与取消事件返回 Dart；若试回环服务，比较端口管理与鉴权后再选。
- [ ] A3.4 测冷启动耗时、常驻内存、进程崩溃与重连、重复进入/退出、App 退后台、系统杀进程和升级后的资源清理。
- [ ] A3.5 检查 `.so` ELF 与 APK/AAB 的 16 KB 对齐，并在目标 4 KB 与 16 KB 真机加载；记录每个 ABI 的结果。

**交付物：**最小探针、版本/体积/性能表、原生兼容报告。**通过门槛：**目标设备上稳定启动、通信、失败恢复；能取得可维护的原生库且满足分发要求。**停止条件：**维护版本、16 KB、崩溃隔离或生命周期任一关键项无可行方案时，不进入本地 Node 产品化。

### A4：npm 包与 CLI 兼容性实验及选型决定

**依赖：**A3 通过。把“Node 能运行”与“npm/CLI 能运行”分开验收。

- [ ] A4.1 在开发机锁定安装一个纯 JS 包，随 App 打包，验证 `require`/`import`、动态加载、资源文件、配置路径与升级；比较原文件树与 esbuild bundle。
- [ ] A4.2 验证其 `package.json` 的 `bin` 脚本能否**以 Node 入口函数方式**执行；记录参数、退出码、stdout/stderr、取消和并发语义，不依赖 shebang 自动执行。
- [ ] A4.3 单独实验“手机上 npm 安装”：包下载、完整性、依赖解析、安装脚本、缓存、断网恢复、升级/卸载；按 Google Play 分发政策和安全模型判断是否可以进入产品。
- [ ] A4.4 用原生 `.node` 扩展、`child_process.spawn/fork`、外部 ffmpeg/ffprobe/mpv、stdio MCP 和交互式 TUI 做失败边界样本；记录确切错误与设备版本。
- [ ] A4.5 对 `@music163/ncm-cli` 0.1.7 逐项试 `--version`、配置/登录、搜索、播放控制、真正出声；标明 `fluent-ffmpeg`、`ffprobe-static`、`mpv` 等依赖在哪一步阻断。不可用时不修改连接器声称支持 Android 本地播放。
- [ ] A4.6 写决策记录：可发布的本地能力白名单、需要 Host 的包类型、设备端 npm 是否保留为实验功能，以及 Node 更新/漏洞响应责任。

**交付物：**包兼容矩阵和明确的“本地 / Host / 不支持”决策。**通过门槛：**至少一个真实纯 JS 包完成调用、取消和重启；每个向用户开放的 npm/CLI 行为都有真机结果。**停止条件：**不能安全、可维护地支持设备端安装时，首版仅提供构建时打包的受控包；任意 CLI 走 Host。

### A5：macOS Host 服务与配对协议

**依赖：**A1 的执行目标契约，可与 A3/A4 并行。

- [ ] A5.1 在现有 macOS Runtime 外增加 Host 服务入口；沿用当前进程、PTY、MCP 和权限实现，不让手机直接发送未登记的 shell 字符串。
- [ ] A5.2 定义协议版本与对象：连接目录、能力、调用参数、`RunId`/事件、取消、终端输入与尺寸、结果、错误码、执行位置；处理重复请求和外部写入后结果未知。
- [ ] A5.3 实现首次配对、设备身份、用户在 Mac 上确认、密钥轮换/撤销、加密传输和仅授权设备访问；服务地址变化后可重新连接。
- [ ] A5.4 加入输出大小、并发、超时、资源占用与日志脱敏限制；Host 退出、断网和手机取消时清理进程/PTY。
- [ ] A5.5 使用无关领域普通 CLI、交互 TUI、stdio MCP 与远程 HTTP MCP 检查协议，避免网易云特例污染核心。

**交付物：**可由测试客户端连接的 Mac Host、协议文档和权限/失败样本。**通过门槛：**Mac 上真实执行、取消和清理都可验证；未配对设备无法调用；断线后的外部写入显示“结果待确认”。

### A6：Android 多运行端路由、Host 连接和终端

**依赖：**A2 + A5；若 A4 通过，可附加白名单本地 JS 执行器。

- [ ] A6.1 实现 `RemoteRuntimePort` 与配对 UI；连接状态区分在线、离线、认证失效、版本不兼容和权限拒绝。
- [ ] A6.2 实现 Android 运行路由：HTTP MCP 在手机、Host CLI/stdio MCP 在 Mac、获准的 JS 包在手机。连接 ID 与活动记录绑定执行目标；切换目标不复用旧权限。
- [ ] A6.3 终端用现有 `TerminalPage` 显示 Host PTY 事件；补齐手机软键盘的 Ctrl、Esc、Tab、方向键和中断操作，测横屏、复制/粘贴、字体缩放与连接中断。
- [ ] A6.4 连接详情显示执行位置、程序路径所属设备、可用能力和 Host 离线后的替代操作；文件/URI 在手机与 Mac 之间明确传输或不可用，不能把 Mac 路径当手机路径打开。
- [ ] A6.5 若开放本地 JS 包，接入 A4 白名单、版本与错误语义；不能把 `RuntimeFeatures.terminal` 设为 true 来暗示任意本地 TUI 可用。

**交付物：**Android 上统一展示手机与 Host 连接的功能包。**通过门槛：**真机可调用本地 HTTP MCP、Host 普通 CLI、Host TUI 和 Host stdio MCP；取消、断线、重连和执行位置显示正确。

### A7：手机 UI 完整适配与网易云示例

**依赖：**A2、A6；本地音乐分支还依赖 A4 的单独验证。

- [ ] A7.1 保持“连接即首页”：窄屏单栏、当前连接切换、所有功能、连接管理、活动和设置；按可用窗口宽度切换侧栏/底部或抽屉导航，不按设备名判断。
- [ ] A7.2 运行页把来源、权限、表单、进度和结果按手机阅读顺序排列；复杂 JSON、长输出和终端用全屏视图。运行中、取消中、失败和结果待确认状态可见。
- [ ] A7.3 调整播放器与迷你播放器，避免底部导航、输入法和手势条互相遮挡；手机本地播放若未通过 A4，不显示“在手机播放”的承诺。
- [ ] A7.4 网易云 Host 模式沿用现有真实登录/搜索/播控能力，并核查声音实际由 Mac 输出；若要声音从手机输出，另接 Android Media3/MediaSession 路径，验证授权、音频来源和后台播控，单列验收。
- [ ] A7.5 用真实长连接名、长路径、复杂 schema、中文/英文混排、离线 Host、认证失败和大输出检查浅深色、小屏/大屏/分屏；核对返回手势、字体放大和 TalkBack 顺序。

**交付物：**完整手机流程、截图与真机操作记录。**通过门槛：**主要功能单手触控可达，输入法不挡关键按钮，屏幕阅读器能识别操作及执行设备；Mac 回归截图与操作无明显退化。

### A8：稳定性、发布与文档

**依赖：**A7；发布声明只能包含已过门槛的能力。

- [ ] A8.1 跑公共契约测试、Widget 测试、Android 构建、macOS 回归；在真机上验证安装、升级、清除数据、重启和配置迁移。
- [ ] A8.2 覆盖 4 KB/16 KB 页与目标 ABI、长期运行、网络切换、后台/前台、Host 退出、Node 崩溃、凭证撤销、输出过大和资源清理。
- [ ] A8.3 复查原生库与 npm 依赖版本/许可证/漏洞响应、密钥和日志、动态代码分发政策、APK/AAB 体积与签名；发布渠道对应规则以当时官方要求再核对。
- [ ] A8.4 更新用户指南：Android 能力边界、Host 配对、包的安装方式、执行位置、网易云声音输出位置及故障排查；内部记录各项真机通过/未通过证据。

**交付物：**Android 发布候选包、能力矩阵最终版、验收报告与用户文档。**通过门槛：**声明的每条主流程均在目标真机通过；未通过的 npm/CLI/本地播放能力不进入发布说明或可操作入口。

## 5. UI 验收矩阵

| 场景 | 重点 | 首次检查阶段 | 最终验收 |
| --- | --- | --- | --- |
| 窄屏竖屏 / 横屏 | 连接切换、导航、全局搜索、返回 | A1 | A7 |
| 大屏 / 分屏 | 侧栏、表单与结果并列、窗口变化 | A1 | A7 |
| 输入法和手势导航 | 表单提交、终端输入、迷你播放器不遮挡 | A1/A6 | A7 |
| 长文本与复杂数据 | 路径、MCP schema、JSON、大输出不溢出 | A2 | A7 |
| 可访问性 | TalkBack、字体放大、状态与执行位置朗读 | A1 | A7/A8 |
| 离线与故障 | Host 离线、Node 失败、权限拒绝、结果未知 | A2/A6 | A8 |

当前 `AppShell` 有 760 逻辑像素抽屉断点，`TerminalPage` 已复用 `terminal_view`；这只是复用起点。Android 的实际断点、导航方式和终端输入控件必须按真机可用窗口与交互结果确定，不能仅用桌面窄窗口截图验收。

## 6. Skillpilot 结果如何取舍

本轮调用 Skillpilot 的 `plan`，选了 review、security、docs、design、testing、strategy。它给出的 CodeRabbit、Semgrep、Context7 可作为后续评审/文档候选，设备自动化项目 `callstack/agent-device` 可研究；均未安装。其 React/Tailwind 设计工具、Playwright 网页测试、Stripe、Vercel、商业分析与本 Flutter 原生工程不匹配，不进入任务清单，也不需要 `TWENTY_FIRST_API_KEY`。验证优先使用 Flutter 测试、Android 真机、NDK 检查和真实 CLI/MCP 样本。

## 依据与待验证事实

- 当前源码：`app/lib/main.dart`、`app/lib/platform/macos/mac_runtime.dart`、`app/lib/app/app_shell.dart`、`app/lib/features/invocation/terminal_page.dart`、`packages/aggregate_contracts/lib/src/runtime_port.dart`；历史阶段见[公共层准备](phase4-common-layer.md)。
- [nodejs-mobile 官方仓库与发布包](https://github.com/nodejs-mobile/nodejs-mobile)、[官方 FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)、[Android JNI 示例](https://github.com/JaneaSystems/nodejs-mobile-samples/blob/master/android/native-gradle/README.md)。
- [Android 10 可执行文件限制](https://developer.android.com/about/versions/10/behavior-changes-10)、[16 KB 页要求](https://developer.android.com/guide/practices/page-sizes)、[动态代码加载建议](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)、[Google Play 开发者政策](https://support.google.com/googleplay/android-developer/answer/18265346)。
- [Node.js 版本维护状态](https://nodejs.org/en/about/previous-releases)、[Flutter 自适应布局](https://docs.flutter.dev/ui/adaptive-responsive/general)、[Media3 后台播放](https://developer.android.com/media/media3/session/background-playback)、[flutter_pty2 支持情况](https://pub.dev/packages/flutter_pty2)。
- [网易云 CLI npm 包](https://www.npmjs.com/package/%40music163/ncm-cli)的版本/依赖来自 2026-11-10 的 `npm view @music163/ncm-cli version engines dependencies bin --json`；真实 Android 运行行为尚未验证。
