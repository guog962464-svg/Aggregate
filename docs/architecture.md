# Aggregate：macOS 首版实施方案与跨端架构预留

> 版本：v8 · 2026-11-10
> 当前阶段：阶段 5 连接即空间的 UI 改版，仍只在当前 Mac 实施；新入口与适配规则见[阶段 5 UI 改版](phase5-contextual-ui.md)。阶段 4 公共层准备见[阶段 4 实施记录](phase4-common-layer.md)。阶段 3 当前 Mac 预览的未完成验收仍以[阶段 2/3 本机验收](phase23-acceptance.md)和[阶段 3 进度](phase3-progress.md)为准。网易云在 Aggregate App 内的稳定播放、播控和实际出声已获用户人工验收。
> 本版交付范围：仅 macOS App。未来可扩展到 Windows、Linux、Android、iOS、Web；这些端本版不开发、不构建、不验收。  
> 产品：一个极简 App，统一发现、搜索、调用与管理 CLI、MCP 的功能。网易云音乐只是首个示例连接器。

## 1. 核心决定

采用 **Flutter + Dart** 开发 macOS App。页面、状态、连接目录、动态表单和结果展示保持平台无关的业务结构，为将来用同一 App 代码扩展其他端留出接口。本版只设计、实现和验证 macOS。Flutter 官方支持多种部署平台，但这些平台的兼容性须在对应版本单独验证。[^flutter-platforms][^flutter-adaptive]

运行 CLI 和本地 stdio MCP 的能力由同一仓库里的 **Dart Runtime** 提供，本版只在 Mac 本机运行。RuntimePort 保留远程实现的接口位置；独立 Host、设备配对和远程调用在后续版本决定并实现。

**“一套代码”在本版的落实方式是：**业务模型、Flutter 页面和 Runtime 接口都不写成 macOS 专用版本；实际系统接线只实现 macOS 的 PTY、钥匙串与文件访问。

### 为未来保留的运行边界

Dart 的进程与文件 I/O 属于非 Web 平台能力。[^dart-libraries] 因此公共契约和 Flutter 页面不能直接依赖 dart:io；本版由 macOS LocalRuntimePort 执行本机 CLI/MCP。未来手机和 Web 若需调用 Mac 上的工具，将接入独立 Host。此边界在本版以静态依赖检查和接口设计验证，不要求构建其他端。

## 2. 用户看到的产品

~~~text
┌─────────────────────────────────────────────────────────┐
│ Aggregate       搜索所有功能…  ⌘K              ＋ 添加连接 │
├────────────┬────────────────────────────────────────────┤
│ 连接       │ 最近 / 收藏 / 搜索结果                      │
│            │ 功能名称                       来源 · 状态  │
│ 网易云 CLI │ 参数表单                         [运行]     │
│ Git CLI    │                                            │
│ MCP        │                                            │
├────────────┴────────────────────────────────────────────┤
│ 结果抽屉 · 进度 · 原始输出 · 连接来源            │
└─────────────────────────────────────────────────────────┘
~~~

阶段 5 的界面有 **6 个页面层级：连接首页、所有功能、功能运行、连接管理、活动记录、设置**。连接首页按能力元数据选择音乐播放器、CLI 命令与动作、MCP 工具/资源/提示；功能运行保留高级参数和原始结果入口。侧栏优先列出连接，“所有功能”提供跨连接搜索。窗口变窄时侧栏可折叠。

网易云音乐账号面板是播放器内的次级界面，不增加全局页面。共用 Dart 层的可选 `ConnectionAccountPort` 返回类型化账号快照，并提供登录终端和退出操作；macOS `MacRuntime` 只对核对过 npm 包身份的 `@music163/ncm-cli` 连接实现它。账号状态和退出结果由 CLI 的 `login --check` 二次查询确认；本机 CLI 不提供账号身份查询，因此当前适配器不显示昵称。登录二维码由 CLI 临时链接在 App 内绘制，凭证、链接及原始输出不写入活动记录。普通 CLI 与 MCP 不显示此账号入口。详见[账号管理规划与实现边界](netease-account-management-plan.md)。

原始主流程是：**添加连接 → 搜索能力 → 填写参数 → 运行 → 查看结果**。阶段 5 将连接首页设为主要入口：音乐连接直接显示播放器，普通 CLI/MCP 显示各自功能页；跨连接搜索移到“所有功能”。具体见[阶段 5 UI 改版](phase5-contextual-ui.md)，原始页面职责与设计令牌见[macOS UI 设计](ui-design.md)。

## 3. 能力模型与覆盖范围

| 连接类型 | 加入后的基础能力 | 结构化使用 |
| --- | --- | --- |
| 本地 MCP stdio | 桌面 Runtime 启动 Server，自动发现 tools、resources、resource templates、prompts。 | 根据 schema 生成表单并调用。 |
| 远程 MCP HTTP | Runtime 连接 Server，自动发现其标准能力。 | 与 stdio 使用同一表单和结果视图。 |
| 任意本地 CLI | 用户选择可执行文件，在命令栏输入子命令和参数，用终端视图运行。 | 为常用命令添加动作清单，进入全局搜索。 |
| 交互式 CLI/TUI | 通过 PTY 转发键盘和终端尺寸。 | 可按需再做专用视图。 |

MCP 有能力发现协议，CLI 没有统一的参数描述标准。因此任意 CLI 的**原生命令入口**可以通用；自动生成全部图形化功能需要动作清单或可靠的机器可读元数据。平台应明确展示每个连接器的覆盖程度。

## 4. 单代码库结构

~~~text
Aggregate/
├── app/                         # 唯一 Flutter App
│   ├── lib/
│   │   ├── app/                 # 路由、主题、响应式外壳
│   │   ├── features/
│   │   │   ├── connections/     # 添加、诊断、权限
│   │   │   ├── catalog/         # 全局搜索、收藏、最近
│   │   │   ├── invocation/      # 动态表单、运行、结果
│   │   │   ├── terminal/        # CLI / TUI 终端视图
│   │   │   ├── activity/        # 脱敏调用记录
│   │   │   └── settings/        # 外观、快捷键与数据设置
│   │   ├── widgets/             # 可复用 Widget 与响应式布局
│   │   └── platform/            # 本版只实现 macOS 系统接线
│   └── macos/
│   └── test/
├── packages/
│   ├── aggregate_contracts/     # 连接、能力、调用、事件 schema
│   ├── aggregate_domain/        # 搜索、权限、状态机、结果模型
│   ├── aggregate_runtime/       # CLI、MCP、能力目录与调用编排
│   ├── aggregate_transport/     # 本版 LocalRuntimePort；远程接口预留
│   ├── aggregate_connectors/    # CLI 动作清单与连接器规范
│   └── aggregate_design/        # 主题令牌与自适应布局规则
├── connectors/
│   ├── netease_cli/              # 示例，不进入核心包
│   └── examples/                 # 无关领域 CLI + 标准 MCP 样本
└── docs/
    └── architecture.md
~~~

只创建 macOS 实际需要的包、App 目录和平台工程。其他端的目录、独立 Host 入口和远程连接实现留到后续版本。

### 依赖方向

~~~mermaid
flowchart TD
  App[Flutter App / 唯一 UI] --> Domain[aggregate_domain]
  App --> Transport[aggregate_transport]
  App --> Design[aggregate_design]
  Transport --> Contracts[aggregate_contracts]
  Domain --> Contracts
  Runtime[aggregate_runtime] --> Domain
  Runtime --> Contracts
  Runtime --> Connectors[aggregate_connectors]
  App -->|本版 macOS 本机| Runtime
~~~

**约束：** contracts、domain、design 和通用 Widget 不导入 dart:io，也不依赖 macOS API。本地进程代码放在 Runtime 的 native 实现。当前用依赖检查维持边界，不以 Web 构建作为本版门槛。

## 5. RuntimePort：让页面完全复用

UI 只依赖一个 Dart 接口，不知道功能在本机还是远端：

~~~dart
abstract interface class RuntimePort {
  RuntimeFeatures get features;
  Future<List<Connection>> listConnections();
  Future<List<Capability>> searchCapabilities(SearchQuery query);
  Future<RunHandle> invoke(CapabilityId id, JsonMap arguments);
  Stream<RunEvent> watchRun(RunId id);
  Future<void> cancel(RunId id);
  Future<ResourceResult> readResource(ResourceRef ref);
  Future<PromptResult> getPrompt(PromptRef ref, JsonMap arguments);
  Future<TerminalSession> openTerminal(CliCommand command);
}
~~~

本版只实现 **LocalRuntimePort**：macOS App 调用同机 Dart Runtime；耗时任务放到隔离执行环境。RemoteRuntimePort 只保留接口位置和契约字段，不实现网络连接或设备配对。每个能力 ID 仍带连接来源，避免同名冲突。

阶段 4 在公共契约中增加 `RuntimeFeatures`：运行端显式报告可添加的连接类型、终端、本地文件预览与文件定位能力。通用页面根据运行端能力显示操作；快捷键按显示 UI 的系统选择 Command 或 Ctrl，而不根据运行端所在机器判断。预览样本移入 `app/lib/preview/`，与 macOS 实现分离。契约、当前接线和测试细节见[阶段 4 公共层准备](phase4-common-layer.md)。

### 通用运行生命周期

~~~text
created → validating → awaiting-permission → running
                                            ├→ succeeded
                                            ├→ failed
                                            ├→ cancelled
                                            └→ timed-out
~~~

调用返回 run ID；进度和结果由事件流更新。本版统一错误码、结果内容块、时间戳、权限状态和重试语义。对于可能产生外部写入的调用，断线后不自动重放；状态未知时明确显示“结果待确认”。

## 6. Dart Runtime 的公共层与平台层

### 纯 Dart 公共层

- ConnectionRegistry：连接配置、状态、版本与执行位置。
- CapabilityCatalog：MCP 自动发现能力 + CLI 动作清单，统一搜索和收藏。
- InvocationEngine：校验、授权、执行路由、取消、事件与活动记录。
- ResultModel：保留 MCP 原始内容块，增加文本、JSON、文件等展示信息。
- ConnectorManifest：CLI 参数模板、输入 schema、输出格式、权限和平台支持范围。

### macOS 适配层

- ProcessRunner：用参数数组启动已注册可执行文件，不拼接 shell 字符串。
- PtyRunner：用 macOS PTY 承载交互式 CLI/TUI。
- SecretStore：使用 macOS 钥匙串保存凭证。
- FileAccess：本机路径选择、授权与文件操作。
- SystemIntegration：通知、菜单、开机启动等按本版实际需求接入。

## 7. MCP SDK 选型门槛

Dart 团队的实验性 dart_mcp 包支持 stdio，但其当前说明明确列出 **Streamable HTTP 和授权尚未支持**。[^dart-mcp] 只用它无法满足本平台对任意远程 MCP 的需求。社区 mcp_dart 包声明支持 stdio、Streamable HTTP 和 OAuth；它可作为候选，但需先做互操作、协议版本、分页、取消、认证和异常恢复验证，再锁定版本。[^mcp-dart]

因此先定义自己的 McpClientPort；阶段 0 使用真实 Server 比较候选库。若社区库未通过验证，可在端口后组合 dart_mcp 的 stdio 能力与单独的 HTTP 实现，或延后某些扩展能力。不能把 SDK 的声明直接当作已验证的 App 兼容性。

~~~dart
abstract interface class McpClientPort {
  Future<McpSession> connect(McpConnectionConfig config);
  Future<List<McpTool>> listTools(McpSession session);
  Future<McpResult> callTool(McpSession session, String name, JsonMap args);
  Future<List<McpResource>> listResources(McpSession session);
  Future<McpResourceContent> readResource(McpSession session, Uri uri);
  Future<List<McpPrompt>> listPrompts(McpSession session);
  Future<McpPromptContent> getPrompt(
      McpSession session, String name, JsonMap args);
}
~~~

客户端能力如 sampling、elicitation、roots 应逐项实现并在连接详情显示；未知或未支持的扩展不静默调用。

## 8. macOS 本版运行方案与后续扩展

### 本版：macOS

同一 Flutter App 运行全部页面；LocalRuntimePort 在 Mac 本机接入 CLI、本地 stdio MCP 与远程 HTTP MCP。用户选择程序，Runtime 执行、诊断和清理。macOS 系统钥匙串、文件选择与 PTY 通过平台适配器接入。

先验证 Apple Silicon；Intel 支持和最低 macOS 版本按实际 Flutter/插件兼容性确定。Flutter 官方支持页面已提示 Intel macOS 处于逐步退役过程。[^flutter-platforms]

### 后续版本的接口预留

Windows/Linux 将复用 Flutter 页面和 Dart Runtime，增加路径、PTY/ConPTY、凭证库与打包适配。Android/iOS/Web 将复用页面和领域模型，通过 RemoteRuntimePort 调用配对 Host。这些属于后续产品版本；本版不实现 Host 服务、远程配对、其他端打包或测试。

## 9. 极简设计系统

- 一个 AggregateApp、一个路由表、一套主题令牌；由宽度和输入方式调整布局。
- 本版在 macOS 宽屏显示侧栏、主区和结果抽屉；窄窗口折叠侧栏。手机布局在后续版本设计与验证。
- 全局搜索同时检索连接、工具、资源、提示、CLI 动作和收藏，并标注来源与执行位置。
- 输入 schema 生成通用表单；复杂对象可切换 JSON 编辑；结果按内容类型选择文本、表格、图片、文件或终端视图。
- 浅深色使用语义颜色；系统字体、八点间距尺度、适当的触控目标。macOS 支持 ⌘K 搜索、Enter 打开、⌘↵ 运行、Esc 返回；所有操作也有可见按钮。
- 专用视图是能力的可选呈现。网易云迷你播放器通过公共调用层工作。

Flutter 的自适应设计指南主张在单代码库中按屏幕和输入方式调整体验。[^flutter-adaptive]

本版 UI 设计采用 frontend-design 的审美立场方法，并用 UI/UX Pro Max 检索开发者工具、极简风格、键盘焦点、表单反馈和 Flutter 相关规则。具体取舍记录在 [macOS UI 设计](ui-design.md)；其中未采用设计知识库自动生成的 FAQ 落地页结构。

## 10. 安全与权限

| 风险 | 统一策略 |
| --- | --- |
| 任意程序执行 | 只执行用户登记的 CLI；显示程序路径与执行设备；动作使用参数数组；终端模式为显式会话。 |
| MCP Server 越权 | 显示 Server 来源与发现的能力；权限按读取、本地控制、外部写入和未知效果分层。 |
| 远程访问 | 本版不启用 Host 网络入口；macOS App 仅在本机执行。 |
| 凭证泄漏 | 桌面系统凭证库和移动安全存储；配置只保留引用；日志与诊断脱敏。 |
| 不可信输出 | 所有内容按类型安全渲染；不直接执行返回的脚本或 HTML。 |
| 资源耗尽 | CLI/MCP 调用设超时、输出上限、并发上限；支持取消与进程树清理。 |
| 文件访问 | 显示本机文件路径与操作目标；读取/写入按能力授权。 |
| 状态失真 | 每次调用保留 run ID 和真实结果；断线不把“请求已发送”显示为“执行成功”。 |

## 11. 网易云音乐示例

官方 npm 包为 @music163/ncm-cli，命令名为 ncm-cli；它提供搜索、播放控制和 TUI，使用网易云开放平台凭证、登录及本机 mpv。[^ncm-npm][^netease-skills]

它先作为通用 CLI 在 macOS 接入：运行原生命令与 TUI；随后通过动作清单加入搜索、播放、暂停、下一首等结构化功能；最后用共用 Widget 做迷你播放器。本版在 Mac 本机显示相同能力和播放状态。歌曲 ID、可播字段、命令参数与输出格式必须在目标机器实测。

除网易云之外，验收至少使用一个无关领域 CLI 和一个标准 MCP Server，证明平台内核没有音乐特例。

## 12. 实施阶段与任务清单

macOS 首版原定阶段 0–3；阶段 4 是随后单独批准的跨端公共层准备，仍只在当前 Mac 构建和验收。其他端开发不进入本轮任务清单。

### 阶段 0：技术可行性与契约定稿

**目标：**先证实 macOS Flutter App、Dart Runtime、两类 MCP 传输和 PTY 的关键路径。

- [x] 0.1 记录开发机上的 Flutter、Dart、Xcode、macOS 版本，运行 Flutter 诊断；确定首发 macOS 架构和最低系统版本的候选范围。
- [x] 0.2 建立最小 Flutter macOS App：验证桌面窗口、窄窗口布局、主题和基本导航。
- [x] 0.3 划定平台边界：公共模型、Widget 和 RuntimePort 不导入 dart:io；进程和 PTY 代码仅放在 macOS native 实现。通过静态依赖检查验证。
- [x] 0.4 用独立 Python MCP Server 的 stdio 与本机 Streamable HTTP 端点，真实验证初始化、工具调用、资源和提示。
- [x] 0.5 记录 Dart MCP 候选库的协议版本及分页、结构化输出、通知、取消、超时、认证和恢复的实测/未实测状态；选定阶段 1 候选。
- [x] 0.6 用普通 CLI 与交互式 TUI 验证 macOS 子进程、PTY、输入转发、窗口尺寸、退出、中断及进程组清理。
- [x] 0.7 定义 RuntimePort、McpClientPort、连接器清单、连接 ID、能力 ID、运行事件、错误码和权限级别；形成契约 v1。
- [x] 0.8 写架构决策记录：SDK 选型、PTY 方案、Flutter 状态管理与路由方案，以及被验证的限制。
- [x] 0.9 定稿五页信息架构、审美立场、色彩/字体令牌与工作台、功能运行、连接管理线框；以长路径、长工具名和错误文案检验最小壳布局。

**交付物：**可编译的 macOS 最小 App、可重复运行的 CLI/MCP 探针、契约 v1、选型记录和环境记录。  
**通过门槛：**macOS App 构建成功；stdio 和 HTTP MCP 各完成真实调用；PTY 能运行并清理交互程序；公共包无 macOS 系统 API 依赖。

### 阶段 1：公共层与 App 骨架

**目标：**让 macOS 所有页面通过同一模型、路由和 RuntimePort 工作，同时保留公共层边界。

- [x] 1.1 在 Aggregate 建立 Flutter App 与 Dart workspace；创建根 AGENTS.md 项目约定、单一依赖锁文件、分析规则和基础构建命令。
- [x] 1.2 实现 aggregate_contracts：连接、能力、资源、提示、调用、终端会话、运行事件、错误、权限与协议版本的模型和序列化。
- [x] 1.3 实现 aggregate_domain：连接状态机、运行状态机、目录索引、搜索/筛选、收藏、最近使用和结果归一化。
- [x] 1.4 实现 aggregate_connectors 的清单 schema、参数占位符校验与平台支持字段；提供一个与网易云无关的示例。
- [x] 1.5 实现 RuntimePort 和 macOS LocalRuntimePort 的预览后端；用契约样本验证连接、能力、调用、事件与错误语义。真实系统执行在阶段 2 接入。
- [x] 1.6 建立 Flutter 路由表、主题令牌、macOS 桌面/窄窗口布局、连接列表、空状态、错误状态和加载状态。
- [x] 1.7 用预览数据跑通“搜索能力 → 打开详情 → 填参数 → 运行 → 看结果”，保证页面不直接引用 dart:io 或具体 MCP SDK。
- [x] 1.8 建立基础 CI 配置：格式检查、静态分析、公共层测试和 macOS 构建；检查公共包的平台依赖边界。本机全套通过，远端 CI 尚未触发。
- [x] 1.9 实现工作台、功能运行、连接、活动、设置的页面骨架与共享组件；用预览数据走通搜索、表单、结果、空状态和键盘打开。

**交付物：**单套 Flutter 页面骨架、公共包、契约测试与构建流水线。  
**通过门槛：**功能页面只依赖 RuntimePort；macOS 构建与公共层测试通过；连接器清单非法输入被拒绝。

### 阶段 2：macOS 通用平台 MVP

**目标：**用户能在 Mac 上自行添加此前未知的 CLI 与 MCP，并从同一 App 调用。

- [x] 2.1 连接管理：选择 CLI 程序路径、填写 stdio 启动命令或 HTTP URL；显示来源、版本、状态、本机路径或远程 MCP 地址及诊断信息。
- [x] 2.2 CLI 执行器：使用参数数组运行已登记程序，设置工作目录、环境白名单、超时、输出上限、并发和取消；记录退出码。
- [x] 2.3 PTY 终端：命令栏输入子命令和参数，支持交互输入、TUI、颜色输出、终端尺寸变化、中断和关闭清理。
- [x] 2.4 MCP 客户端：连接 stdio 与 HTTP Server，完成握手、能力发现、目录刷新、工具调用、资源读取和提示获取。
- [x] 2.5 能力目录：为重名功能加来源标识；搜索工具、资源、提示和 CLI 动作；支持连接失效后的目录状态更新。
- [x] 2.6 动态表单：根据 MCP inputSchema 和 CLI 动作 schema 生成输入；复杂对象提供 JSON 编辑；运行前双层校验。
- [x] 2.7 结果面板：显示进度、结构化内容、原始文本、文件或图片、isError、运行耗时以及取消后的终态；文件需显式点击并受格式和大小限制。
- [x] 2.8 权限和凭证：程序路径授权、外部写入提示、系统凭证库存取、活动日志脱敏；界面不能绕过 Runtime 调用系统进程。当前 HTTP 认证范围为静态 Bearer Token，浏览器 OAuth 留待后续。
- [x] 2.9 用三个真实样本验收：普通 CLI、TUI、同时提供工具/资源/提示的 MCP；覆盖成功、非法参数、断线和超时。
- [x] 2.10 生成可安装的 macOS 开发包，在本机隔离 HOME 的空配置下验证首次启动、程序发现和退出清理；独立系统用户与其他设备归入 3.8。
- [x] 2.11 用真实 CLI/MCP 样本走查五页：长名称、复杂 schema、终端输出、连接故障和权限确认；本机原生窗口和 36 张自动截图均已检查，真实 VoiceOver 归入 3.10。

**交付物：**可安装的 macOS MVP、连接器清单格式、三个样本的验收记录。  
**通过门槛：**新增未知 CLI/MCP 不修改平台核心；终端与结构化调用均可用；权限阻断和进程清理有实际验证。

### 阶段 3：macOS 产品化与网易云示例

**目标：**把通用 MVP 打磨为稳定的日常工具，并用网易云证明专用视图可建在公共层上。

- [x] 3.1 CLI 动作编辑器：创建、修改、导入/导出动作；表单预览参数模板和最终参数数组；连接器清单版本迁移有明确错误。
- [x] 3.2 个人使用能力：收藏、最近使用、连接排序、全局快捷搜索、调用活动记录和隐私清理。
- [x] 3.3 连接诊断：缺失可执行文件、认证过期、MCP 协议不兼容、网络断开、权限不足分别提示处理步骤。
- [x] 3.4 网易云环境检查：确认 Node、npm、mpv、开放平台配置和登录状态；仅当本机 npm 包名与 `bin` 入口对应 `@music163/ncm-cli` 时自动启用专用动作，同名但不匹配的程序保留为普通 CLI。网络超时会标为登录状态未确认；本地元数据匹配不证明 npm 包内容未被篡改，密钥不进入 App 日志。
- [x] 3.5 网易云动作清单：已实测搜索、播放、加入下一首、暂停、恢复、切歌、音量、状态的命令与输出，并处理加密/原始 ID、不可播歌曲和真实错误；播放命令返回空内容时不自动重放，只轮询状态。`playing` 但队列为空视为待确认。用户在当前 Mac 上通过 Aggregate App 人工验收了稳定播放、播控和实际出声；早先自动探针曾遇到守护进程断连，作为回归风险保留在验收记录中。
- [x] 3.6 迷你播放器：由通用调用结果驱动歌曲与状态 UI，不在 Widget 中直接调用本地 CLI。
- [x] 3.7 稳定性：长任务取消/超时、重复调用、异常退出、MCP 重连、CLI 输出过大、HTTP 401/403 和 App 重启后的配置/钥匙串恢复均有自动或本机实测；打包 App 的普通 CLI 使用独立进程组，取消、超时和退出时的子进程清理已在本机测试。
- [ ] 3.8 当前 Mac 预览验收：浅深色、键盘与辅助功能检查；本机首次启动、已有配置读取和退出清理。Intel Mac、macOS 12 与独立用户矩阵暂不纳入本轮通过门槛，另行验收。当前无法取得 Developer ID，正式签名与公证不作为本版预览验收条件，且预览包不得称为正式发布包。
- [x] 3.9 编写用户文档：添加 CLI/MCP、权限解释、网易云配置、故障排查和连接器作者指南。
- [ ] 3.10 完成浅色/深色和 800×600、1024×768、1440×900 窗口截图评审；验证键盘、焦点、对比度、表单错误、减少动态效果与网易云迷你播放器。

**交付物：**macOS 预览包、网易云示例连接器、使用文档与预览验收记录。

**本轮通过门槛：**在当前已授权且 mpv 可用的 Mac 上真实出声和播控；无关 CLI/MCP 继续正常工作；本机隔离配置的首次启动、已有配置读取、辅助功能与减少动态效果通过验证。Intel Mac、macOS 12、独立系统用户及正式分发另行验收。

### 阶段 4：跨端公共层准备（当前任务）

**目标：**使共用 Flutter 页面能根据运行端能力和 UI 设备选择操作入口，同时保留现有 macOS 接线。

- [x] 4.1 给 `RuntimePort` 增加版本化 `RuntimeFeatures`；定义连接类型、终端、文件预览和文件定位能力，未知连接类型按解析错误处理。
- [x] 4.2 macOS 实现和预览 Runtime 提供能力描述；页面按能力过滤添加连接、终端与文件操作，避免向不支持的运行端提供入口。
- [x] 4.3 将 Command/Ctrl 搜索和运行快捷键集中成一套公共规则，界面提示与实际按键一致。
- [x] 4.4 把预览数据从 macOS 适配目录移到公共 Flutter 预览目录；边界检查覆盖预览目录，禁止公共 UI 导入 macOS 适配。
- [x] 4.5 用 HTTP-only、无添加权限与 Windows 键盘模拟测试公共页面；在当前 Mac 完成完整检查和 macOS 截图回归。

**交付物：**公共运行端能力契约、按能力显示的共用页面、独立预览工厂、回归测试与[阶段 4 实施记录](phase4-common-layer.md)。

**通过门槛：**公共代码保持无 macOS 适配依赖；受限运行端不暴露本地操作；现有 macOS 构建、测试与截图回归通过。模拟 Windows 键盘只验证公共逻辑，不代表 Windows App 兼容性或交付。

### 阶段 5：连接即空间的 UI 改版

**目标：**让连接后的用户直接进入该连接的主要功能界面，减少通用能力列表的首屏负担。

- [x] 5.1 用公开的 `Capability.presentation` 和连接类型选择音乐、CLI、MCP 首页；不按连接名称猜测类型。
- [x] 5.2 音乐首页整合当前播放、播控、歌曲搜索、搜索结果播放与队列操作；运行仍经过 `RuntimePort`。
- [x] 5.3 侧栏以连接为主，添加后打开新连接；保留跨连接“所有功能”、连接管理、活动和设置。
- [x] 5.4 保存上次选中的连接；旧偏好文件缺少该字段时按音乐优先、否则第一个连接回退。
- [x] 5.5 在当前 Mac 的 Widget 环境覆盖各类首页、搜索与播放路径，并更新多尺寸浅深色截图。

**范围与验证：**见[阶段 5 UI 改版](phase5-contextual-ui.md)。原生窗口中文排版、VoiceOver 完整朗读与真实音乐播放仍按各自验收记录核对；本轮不构建其他端。

### 后续路线图（不属于本版）

阶段 4 之后再决定 Windows/Linux 适配、独立 Host、远程配对及 Android/iOS/Web 发布顺序。后续阶段须单独制定平台兼容矩阵和验收任务；当前只准备 RuntimePort、连接器契约和平台适配边界，不实现这些端的代码。

### 横向工作：贯穿本版

- [ ] 每次新增能力同步更新契约、连接器 schema、错误文案和使用文档。
- [ ] 检查公共包是否意外导入 macOS 系统 API；系统代码只放在平台适配层。
- [ ] 对权限、凭证、进程生命周期和外部 MCP 调用做重点审查。
- [ ] 记录实际测试的 macOS 版本、架构、设备与未覆盖范围。

## 13. 本版验收标准

### 架构边界

- 只有一个 Flutter macOS App 的功能页面、路由和主题；UI 通过 RuntimePort 调用能力。
- contracts、domain 和通用 Widget 不依赖 macOS 系统 API；进程、PTY、凭证和文件访问集中在 macOS 适配层。
- RuntimePort、McpClientPort 和连接器清单有明确契约及真实样本验证。
- 本版不以 Web、Windows、Linux、Android 或 iOS 构建成功作为交付条件。

### macOS 功能

- 用户可添加并运行此前未知的本机 CLI；交互型命令可在终端视图使用。
- 用户可添加 stdio 与 HTTP MCP，发现 tools、resources、prompts，并实际调用或读取。
- 全局搜索、动态表单、结果、取消、活动记录与权限形成完整流程。
- 工作台、功能运行、连接管理、活动记录、设置五个页面职责清楚；终端、资源、提示和播放器复用功能运行框架。
- macOS 界面在 800×600、1024×768、1440×900 窗口及浅深色下可用；键盘焦点、表单错误与运行状态清楚可见。
- 网易云在已授权且 mpv 可用的 Mac 上实际播放；失败时显示真实错误。
- 关闭 App 后清理本 App 的子进程和连接；凭证不进入日志。
- macOS 安装包在约定的系统版本和架构上完成首次安装、升级与异常恢复验证。

### 后续扩展准备

- 公共模型与 Widget 没有写入 macOS 专属逻辑；LocalRuntimePort 可被另一实现替换而无需改功能页面。
- 连接器清单包含平台支持范围，未来新增端能判断哪些连接器可用。
- 对未来独立 Host、远程传输和移动端的需求只保留接口记录，不把未实现能力显示为本版可用。

## 14. Skillpilot 结果与选型说明

按 Flutter/Dart 单代码库重新运行了 Skillpilot。它仍推荐设计、代码审查、安全、文档和 UI 测试辅助工具，但返回了 React/CSS、Stripe 支付和 Web 云部署等通用模板内容。这些模板不作为 Flutter 实施步骤。实现时采用 Flutter 官方自适应布局指导、Dart 包的实际兼容性验证和本版 macOS 契约测试。尚未安装 Skillpilot 推荐的 MCP 工具。

此前的 Electron + React Native 分端方案已被本次“单套代码运行多端”的要求取代；保留 Runtime 与平台适配的边界，但 UI 技术栈统一为 Flutter/Dart。

## 参考资料

[^flutter-platforms]: [Flutter 官方支持平台](https://docs.flutter.dev/reference/supported-platforms)。
[^flutter-adaptive]: [Flutter 自适应与响应式设计](https://docs.flutter.dev/ui/adaptive-responsive)。
[^dart-libraries]: [Dart 核心库与 Web 可用性](https://dart.dev/libraries)。
[^dart-mcp]: [Dart 团队 dart_mcp 包说明](https://pub.dev/packages/dart_mcp)。
[^mcp-dart]: [mcp_dart 包说明](https://pub.dev/packages/mcp_dart)。
[^ncm-npm]: [网易云音乐官方 CLI npm 包](https://www.npmjs.com/package/%40music163/ncm-cli)。
[^netease-skills]: [网易云音乐官方 Agent Skills](https://github.com/NetEase/skills)。

