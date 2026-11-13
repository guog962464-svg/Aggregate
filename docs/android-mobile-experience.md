# Aggregate Android 移动场景与流程（A7.1）

> 日期：2026-11-14
>
> 状态：A7.1 流程基线，供 A7.2–A7.6 实施与验收使用。
>
> 关联：[Android 适配计划](android-adaptation-plan.md)、[执行目标契约](android-a1-contract.md)、[Host 设计与实现记录](android-a5-host-design.md)。

## 产品任务与能力边界

手机端的首要任务是快速找到一个功能，确认它在哪台设备上执行，再完成输入、授权、运行和结果查看。导航围绕这些任务组织，不把桌面侧栏和宽表格直接压缩到窄屏。

- Android 本机当前可用的是 HTTP MCP；Host CLI、stdio MCP、账号和 PTY 在配对 Mac 上执行，并通过已配对 Host/WSS 路由。
- `ExecutionTarget` 和来源在连接、功能、授权、运行及结果界面保持可辨认。Host 离线时保留 Host 来源并提示恢复连接，绝不改在手机上执行。
- A4 未开放任意本地 npm/CLI 产品能力；A4.6 的 `ncm-cli` 真机动作受非 TTY、缺少子进程工具和命令不匹配等问题阻断。手机连接向导不展示本地 CLI 安装或“本机 TUI”入口。
- 网易云 Host 流程由 Mac 保存 profile、执行 CLI 并输出声音；Android 当前负责搜索、账号入口和远程控制。不能标成手机本地出声。
- 当前活动记录只保存状态、时间和运行 ID，不保存参数或结果正文。重新打开活动指向功能定义，开始的是一次新运行；不会恢复旧表单、重放副作用或伪称恢复结果。

## 一级导航与页面结构

手机窄屏建议使用四个固定底部目的地：**功能、连接、活动、设置**。默认进入“功能”全局目录；搜索全部可见来源，避免有连接时仍被固定在单个连接首页。连接详情保留 CLI/MCP 列表或网易云专用界面，作为连接页下一级路由。Mac 继续使用现有桌面 `AppShell`。

| 入口/页面 | 手机职责 | 关键内容与动作 |
| --- | --- | --- |
| 功能 | 跨手机与获准 Host 搜索能力 | 搜索优先；收藏、最近、结果列表；每行显示功能名、连接来源和执行端。 |
| 连接 | 查看本机/Host 连接并启动添加流程 | 连接状态、目标设备、刷新、添加；从此处管理已配对 Mac。 |
| 连接详情 | 了解一个连接提供什么 | CLI 命令、MCP tools/resources/prompts，或网易云播放器；Host 状态和诊断就近显示。 |
| 运行 | 执行单个功能并读取反馈 | 参数、来源/目标、权限说明、进度、取消、成功/失败/未知状态及结果。 |
| 活动 | 找回近期操作上下文 | 最近状态与时间、来源、脱敏诊断；“重新打开功能”与“再次运行”保持为两步。 |
| 终端 | 交互控制 Host PTY | 会话输出、软键盘、Ctrl/Esc/Tab/方向键、复制/粘贴、中断和断线状态。 |
| 网易云 | 搜索、账号和播放控制 | 登录状态、搜索、队列和播放状态；Host 模式明确声音从配对 Mac 输出。 |
| 设置 | 外观、本机数据和应用信息 | 保留既有设置；Mac 配对与授权管理入口从连接区可达，避免把连接操作藏进系统偏好。 |

连接详情、运行、终端、活动详情和向导均使用 Android 原生返回栈语义。底部导航只用于一级目的地，不和系统返回手势争夺方向边缘。

~~~mermaid
flowchart TD
  App[功能：全局搜索] --> Capability[功能详情与参数]
  Capability --> Permission{需要执行授权？}
  Permission -->|是，先确认| Run[运行中]
  Permission -->|否| Run
  Run -->|成功| Result[本次结果]
  Run -->|失败/取消/超时| Recovery[修复、重试或取消]
  Run -->|结果未知| Unknown[显示结果待确认，不自动重放]
  App --> Connections[连接]
  Connections --> Detail[连接详情]
  Detail --> Capability
  Connections --> Setup[选执行端 → 适配器 → 填写 → 预检 → 保存]
  Connections --> Pair[管理已配对 Mac]
  App --> Activity[活动记录]
  Activity --> RunSummary[状态、时间、来源、脱敏诊断]
  RunSummary -->|重新打开| Capability
  Detail -->|Host CLI| Terminal[Host 终端 PTY]
  App --> Settings[设置]
  Detail --> Music[网易云连接详情]
~~~

## 主要任务流程

### 1. 快速找到并运行功能

~~~mermaid
flowchart LR
  Open[打开功能] --> Search[搜索关键词]
  Search --> Empty{有匹配功能？}
  Empty -->|否| Refine[清除筛选或改关键词]
  Refine --> Search
  Empty -->|是| Select[选择功能]
  Select --> Target[核对来源与执行端]
  Target --> Form[填写参数]
  Form --> Gate{只读还是有副作用？}
  Gate -->|写入/未知| Confirm[展示权限、目标和参数摘要并确认]
  Gate -->|只读| Start[开始运行]
  Confirm --> Start
  Start --> Progress[进度与取消]
  Progress --> Result[本次结果]
  Progress --> Failure[可恢复错误 / 结果未知]
~~~

触发运行前，功能名与参数属于当前能力；来源标明连接名，并用“这台手机”或明确的 Mac 名称标识执行端。资源读取、提示预览和 CLI/MCP 调用可以使用不同结果视图，但共用运行状态语义。未知结果不自动重试，用户需要先回到来源或活动确认状态。

### 2. 添加并测试连接

~~~mermaid
flowchart LR
  Connections[连接] --> Add[添加连接]
  Add --> Target{选择执行端}
  Target -->|这台手机| LocalAdapters[本机允许的适配器]
  Target -->|已配对 Mac| HostAdapters[该 Mac 允许的适配器]
  Target -->|Mac 离线| Offline[重连 / 保留草稿退出；不切换本机]
  LocalAdapters --> Fields[填写连接字段]
  HostAdapters --> Fields
  Fields --> Test[运行端预检]
  Test --> Checks{逐项检查}
  Checks -->|可保存| Save[保存连接]
  Checks -->|actionRequired| SaveNext[显示待办，保存后继续账号/授权动作]
  Checks -->|失败| Repair[显示失败原因，修改后重新预检]
  Fields -->|取消 / 返回| Discard[丢弃当前草稿]
  Save --> Detail[连接详情]
  SaveNext --> Detail
~~~

先选择执行设备再显示适配器和字段；字段所属设备、秘密输入、文档 URI/文件来源在对应表单里说明。`actionRequired` 是明确的后续待办，不显示绿色完成。Host 草稿过期或连接中断时提示重新测试；未保存秘密不能静默持久化。Host 离线时不允许把连接草稿转成本机配置。

### 3. 从活动查看或继续

活动列表按运行状态与时间呈现来源。选中一条记录后显示运行 ID、功能、来源、执行端、状态及脱敏诊断。当前合同没有运行参数或结果正文，因此按钮文案是“重新打开功能”；它只打开当前能力的空白/默认参数页，不声称还原上次输入。

后续 A7.4 要为运行中的项目设计重新订阅或可见的持续运行入口：离开功能页不能让运行状态无处可见；仍运行的任务应可取消；已完成的任务如无持久化正文，只显示活动摘要。任何重新执行都必须是用户新触发。活动清理需注明范围；Android 清理只删除本机历史，不调用 Mac 全局清理。

### 4. 控制配对 Mac 上的终端

从 Host CLI 功能显式选择“在终端运行”，先确认 Mac 来源与执行权限，再进入独立终端页。页面提供横向触控工具栏，输出保留在滚动区；键盘、工具栏、旋转和分屏变化共同更新 PTY 尺寸。网络/Host/PTY 断开时结束会话并将已有输出保留为只读，给出“重新打开终端”入口，不自动在手机重启命令。离开活动 PTY 前要告知关闭会话会结束进程；如平台允许从 Host 可靠恢复，需另行设计而不能伪造续接。

### 5. 网易云 Host 播放

从连接列表进入网易云专用页。首页先标明账号与连接状态，搜索结果提供播放/队列操作；首次副作用按当前授权流程确认。Host 模式始终提示“声音由配对 Mac 输出”。登录二维码由 Mac 终端生成；同一手机显示二维码时需要另一台设备扫码，目前不宣称支持同机应用跳转。Host 离线时禁用远程动作并保留歌曲/账号展示边界，不能显示虚假的“正在手机播放”。播放中离开页面时，迷你播放器放在一级导航上方；软键盘弹出时隐藏迷你播放器或在当前播放流程中避让，保证输入与提交操作可达。

## 执行端、网络与恢复规则

| 场景 | 执行端/网络 | 页面反馈与恢复 |
| --- | --- | --- |
| Android 本机 HTTP MCP | Android 本地 Runtime；访问 MCP 服务器需要网络 | 显示服务器连接状态；错误给出连接设置入口，不显示本机 CLI 能力。 |
| Host CLI、stdio MCP、网易云 | 指定 Mac Host；配对 WSS/LAN 可达 | 显示 Mac 名称和在线状态；离线保持 Host 目标，允许重连，不在本地回退执行。 |
| Host 审批/写入授权 | Mac 用户审批与逐连接 grant | 手机展示待授权/拒绝；按 Host 端新的权限决定可用操作。 |
| 连接预检失败 | 对应本机或 Host | 保留当前可编辑字段，逐条显示可执行修复；修改后重新预检。 |
| 运行网络中断 | 由原执行端决定，可能处于未知结果 | 标记为结果未知；不自动重放写入、登录、音乐或终端输入。 |
| Host PTY 断线 | 远端 PTY 归属原 Host | 保留当前输出并只读，关闭本地映射；用户显式重新打开命令。 |
| 活动中功能失效/撤销 | 刷新当前来源目录 | 告知功能不可用；保留脱敏记录，不重新执行。 |
| 网易云未登录 | 账号归属 Mac profile | 显示登录动作与外部扫码说明；不在 Android 建立第二个本地账号 profile。 |

## 屏幕、输入与视觉方向

### 响应式导航建议

按**可用逻辑窗口宽度**选择布局，而不是依据设备型号或仅看方向：

| 可用宽度 | 导航与内容 |
| --- | --- |
| `< 600 dp` | 四项底部导航；页面单列、详情走返回栈；运行/向导主按钮停靠在系统输入法上方。 |
| `600–839 dp` | NavigationRail + 单一内容列；连接/活动详情可替换列表，但保持明显返回入口。 |
| `≥ 840 dp` | Rail/侧栏 + 列表详情双栏；功能表单与结果可并列。分屏、折叠屏仍按实际可用窗口宽度和安全区调整。 |

横屏不强制切成桌面页面；只让列表/结果获得更多空间。IME 打开时使用 `viewInsets` 调整可视区，字段和主按钮保持可见，不能让底部导航或迷你播放器占据键盘上方的操作位。系统栏、安全区、手势导航条和返回边缘都纳入布局。按钮触控面至少 48 dp，状态有图标/文字而不只靠颜色。TalkBack 应先读功能，再读来源/执行端、权限和状态；动态状态改变时有语义播报。

### 视觉计划（沿用 Aggregate 令牌，重排手机层级）

- **颜色：**继续使用 `AggregateTheme`。浅色底 `#F5F7F8`、表面 `#FFFFFF`、正文 `#1B2833`、次要文字 `#546270`、主操作蓝 `#245F89`、焦点蓝 `#2F7EA9`。深色延续 `#151B20` / `#1C252B` / `#E8F0F3` / `#A8B8C1` / `#78B7DF` / `#88C8EA`。状态颜色仍由主题派生并配文本。
- **字体：**正文与导航使用系统无衬线字体和 Material text styles，响应 Android 字号设置；只有 CLI 命令、路径、运行 ID 和终端内容用等宽字。不要把小型协议标签全做成等宽微字。
- **布局：**内容从左上对齐；功能搜索是最先看到的输入控件。窄屏以分组标题、留白与分隔组织结果，不铺同尺寸卡片墙。运行/设置表单使用可滚动单列与清晰的固定底部操作条。
- **识别点：**最重要的视觉提示是“在哪台设备运行”的来源/目标标记，它会随能力进入运行与结果流程。搜索、来源和权限用相同词汇，不让图标颜色承担完整语义。
- **约束：**沿用现有安静的工作台配色和清晰文字，不增加与手机能力无关的渐变、营销式大标题或装饰统计卡片。桌面版页面组合保持不变。

### 设计自审

桌面 `AppShell` 缩窄后仍会优先展示单个连接首页和抽屉；跨来源搜索因此多一步，Host 目标也容易退到列表次级信息。手机入口改为全局“功能”，连接列表独立呈现，执行端标记贯穿选择、授权与运行。能力列表保持按任务分组并露出来源，保证用户选择命令前就能判断它在哪台设备运行。这个取舍服务当前已开放的手机 HTTP MCP 与远程 Mac Host 路径，并给 A7.2 一个可直接实施的判断基线。

窄屏骨架草图：

~~~text
┌ 系统状态栏 ─────────────────┐
│ 功能                          │
│ [搜索所有连接中的功能       ⌕] │
│ 最近 / 收藏 / 类型筛选         │
│ 命令或工具                     │
│ 功能名                         │
│ 来源：工作 Mac · Mac 上执行    │
│ ───────────────────────────── │
│ 功能       连接       活动 设置 │
└ 系统手势区 ─────────────────┘
~~~

运行页草图：

~~~text
┌ 返回  功能名                     │
│ 来源：项目 MCP · 这台手机        │
│ 执行权限：只读 / 需确认           │
│ 参数表单（随内容滚动）            │
│ 运行状态与本次输出                │
│ [运行] 或 [取消]（键盘上方）      │
└ 输入法 / 系统手势区               │
~~~

## A7.2–A7.6 实施交接

1. 建立 Android 专用 shell/导航树：四个主目的地；全局搜索直接进入“功能”；桌面 `AppShell` 和 macOS 路由不变，`RuntimePort`/领域模型继续共用。
2. 把当前连接向导包装成窄屏全页流程，保留 target-first、安全草稿及逐项检查语义；测试/保存操作避开 IME。
3. 运行详情显示执行端、权限和可恢复状态；用 shell 级 run coordinator 管理离开页面后的长任务/取消/活动重新订阅，并明确结果正文当前不持久化。
4. 连接、活动与音乐页按四个窄屏任务重组；播放器/迷你播放器与导航、IME、安全区协调。手机本地音频仍是独立路线，未验收前隐藏本机出声能力声明。
5. A7.6 用真实连接名、schema、错误 Token、Host 离线、Node 不可用和大输出，在竖/横屏、分屏、浅/深色、大字体和 TalkBack 下走完整任务，并存实际设备截图。A6.5 widget 测试不替代真实 Android IME/远程 PTY 验收。

### A7.2 导航与页面组合验收（2026-11-14）

- Android/iOS 手机壳以“功能、连接、活动、设置”为一级目的地，启动后进入全局功能工作台；新增连接后仍留在连接列表。既有 macOS 壳仍按连接首页、抽屉/侧栏方式工作。
- `<600 dp` 使用 Material `NavigationBar`，键盘弹出时隐藏底部导航和迷你播放器；`600–839 dp` 使用带标签的 `NavigationRail`；`≥840 dp` 使用扩展 Rail。连接列表可推入连接专属工作区，网易云连接进入播放器；普通连接工作区保留可见的迷你播放器入口。
- 全量 Flutter 168 项通过，`flutter analyze --no-pub` 无问题，Android arm64 Debug APK 与 macOS Debug app 构建通过。LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机安装并启动，`MainActivity` 位于前台，设备截图确认全局功能页与四项底部导航可见；Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过。
- 连接详情导航、Android phone/tablet 断点、IME 隐藏和 macOS 桌面回归由 Widget 测试覆盖；本轮未连接 production WSS Host，也没有 16 KB 实体设备，不能据此认定真实远程 Host 流程或 16 KB 运行验收通过。

### A7.3 手机连接向导验收（2026-11-14）

- 连接向导分成“第 1 步 · 选择执行设备”和“第 2 步 · 配置连接”。目标列表展示设备名称与执行位置；选中后表单再次显示确认过的目标，并在同一页选择适配器、填写字段、预检和保存。无可用目标时显示连接 Host/检查运行端的恢复提示；目标加载期间禁用重复打开。
- 表单以 `Form` 和 `TextFormField` 做字段级校验：名称、HTTP/HTTPS MCP 地址、绝对程序路径、Host 短期 opaque 引用、JSON 字符串参数及 adapter 必填字段均就近提示；HTTP 地址使用 URL 键盘，密钥字段使用密码键盘且关闭自动建议。Android 不显示设备程序/路径文件选择器；Host 的可执行程序仍由 Host 查找并保留为 opaque 引用。
- 检查行同时用语义状态文字、图标与 live-region 播报表达“已通过 / 待完成 / 未通过”；`actionRequired` 可以按报告规则继续保存，但不被展示为通过。测试/保存主操作停在手机固定底部区；系统 IME 出现后操作仍在键盘上方，关闭入口保持可见。测试过程中可返回，迟到的可保存草稿会被丢弃；保存进行中阻止系统返回，结果未知时不重试。
- Flutter 全量 172 项通过，`flutter analyze --no-pub` 无问题，Android arm64 Debug APK 与 macOS Debug app 构建通过。LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机实际打开目标页和配置页，提交空表单后确认两个字段错误贴近控件；打开系统键盘后检查/保存操作仍可见；系统返回关闭键盘与向导，最终 MainActivity 回到前台，最近 500 条 Android/Flutter 崩溃日志为空。Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过。
- Widget 覆盖目标加载防重复、无目标恢复状态、Host 目标信息与命令引用、actionRequired 语义、字段级校验、测试/保存按钮可达、返回时草稿清理、保存中系统返回保护、窗口方向/大字体以及 macOS 连接回归。未连接 production WSS Host；未做 TalkBack 手工走查，也无 16 KB 实体设备，因此不据此声明 Host 远端连接或 16 KB 运行验收通过。

### A7.4 手机调用与结果体验验收（2026-11-14）

- 调用页持续显示能力来源、执行端和权限级别；执行端异步确认前显示“执行端待确认”，查不到来源时显示“执行端未知”，避免误标成本机。确认弹窗补充执行端、权限解释及脱敏后的 JSON 参数。运行期间锁定表单，使用 `viewInsets` 将运行/取消等操作保持在软键盘上方；运行状态以 live region 和进度条反馈。
- 复杂 JSON 输入支持多行、格式化和展开；超过 1600 字符的结果先显示可选中的有界预览，可展开滚动查看全文，复制仍复制完整结果。表单密钥和常见 CLI Token/密码参数在确认内容、运行摘要及终端标题中隐藏。
- 未知结果不自动重跑，提供检查活动和手动确认重试的副作用提示。错误按错误码解释下一步恢复方式。离开运行页后，活动页可筛选运行中/结果待确认任务；可以重新打开并订阅运行、请求取消，不会重放调用。终端显示来源、执行端及权限，保留 Ctrl/Esc/Tab/方向键等手机控制键。
- 本轮四个 A7.4 Widget 测试文件通过：调用页、表单 JSON、活动恢复/取消和终端脱敏；完整 Flutter 测试集 181 项通过，`flutter analyze --no-pub` 与四个公共包的 15 项测试通过。覆盖异步执行端信息的未确认与 Host 结果状态。旧桌面主题测试原先按隐藏的“深色”文本定位控件，已改为按当前“深色主题”无障碍语义定位。Android arm64 Debug APK、macOS Debug app 构建和 Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机安装启动成功；真机检查了手机活动页以及“运行中/结果待确认”筛选入口，未见 Flutter/Android 崩溃。设备没有连接 production WSS Host，因此本轮没有在真机实际执行远端调用、终端命令，也未手工验收实体 IME 和 TalkBack；没有 16 KB 实体设备，APK 静态对齐不代表 16 KB 系统运行通过。以上缺项转入 A7.6/A8 的最终验收记录。

### A7.5 手机播放器与迷你播放器验收（2026-11-14）

- 手机宽度 `<600 dp` 的迷你播放器改为两行：第一行曲名、执行端输出位置、打开完整播放器、更多操作和收起；第二行提供上一首/播放/下一首。停止播放与刷新状态收进更多菜单，减少控制按钮挤压曲目文本。完整播放器入口按当前音乐连接路由；桌面宽度继续保留一行直接控制布局。
- Host 音乐连接打开播放器时显示“声音由配对 Mac 输出”；`MusicSession` 按已解析的 `ExecutionTarget` 更新输出位置，连接确认期间读屏不会误报本机。手机迷你栏显示短标签“Mac 输出”，对应无障碍语义保留完整输出说明。Android 输入法打开时迷你栏收起；完整音乐页依靠可滚动视口将搜索框移到键盘可见区，一级导航与 IME 不叠放。没有新增手机本地音频或后台播放能力。
- `music_mini_player_test.dart` 覆盖 320 dp 长曲名/多控制、主控与更多菜单、Host 输出语义、IME 隐藏、完整播放器路由及桌面直控；Android 导航测试覆盖音乐搜索框在 IME 下可滚动可见；Host 账号场景测试检查 `MusicSession` 输出目标标记。完整 Flutter 测试 185 项通过，`flutter analyze --no-pub` 无问题；Android arm64 Debug APK、macOS Debug app 与 Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机重新安装并启动，`MainActivity` resumed，最近 500 条 AndroidRuntime/Flutter 崩溃过滤日志为空。设备没有 Host/真实网易云账号，未在实体设备打开远端播放器或实际播放；这些 Widget/fake runtime 结果不算真实账号或 Mac 音频闭环。没有 16 KB 实体设备；静态对齐不等同于 16 KB 系统运行验收。

### A7.6 真机与可访问性验收（2026-11-14）

- UI 矩阵：长中英文连接名、长功能标题、复杂 object/array/enum schema、错误 Token（`authenticationRequired`）、Mac Host 离线（`connectionFailed`）、Host CLI/Node 缺失（`executableMissing`）及大输出均有对应运行时或结果页测试。调用页在浅色/深色主题、320×720、393×852、700×900、900×900、844×390 dp、200% 字体的 10 种主题/窗口组合下无溢出；覆盖小屏、大屏、双栏分屏尺寸和横屏。下拉框启用全宽布局，长选项单行省略，修复 320dp+200% 字体下 3.1px 横向溢出。
- 可访问性：主题主/次正文对比度检查通过；来源、执行端、权限语义标签能区分并按视觉顺序排列；调用主按钮和迷你播放器上一首/暂停/下一首/打开/更多/收起的语义节点点击区域均至少 48×48 dp。Android/iOS 主题为按钮设置 48dp 最小高度及标准视觉密度，`macOS` 主题原样返回以保持桌面尺寸。设备用户 0 未安装 TalkBack，故只验 Flutter 语义树和目标尺寸，未执行实体 TalkBack 朗读。
- 真机：LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页，安装新 APK 后启动；依次打开执行设备选择、HTTP MCP 配置页，在名称字段输入长英文连接名并拉起系统 IME，底部测试/保存按钮仍高于键盘。之后丢弃未保存草稿。临时把系统字体从 100% 调到 150%，页面可读且无裁切；已恢复 100%。临时切换浅色/深色模式截图后恢复深色。未启用模拟器。
- 全量 Flutter 测试 189 项、`flutter analyze --no-pub`、格式和 diff 检查通过；Android arm64 Debug APK、macOS Debug app 构建与 Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过。真实设备未配置 production WSS Host，故错误 Token/Host 离线/Node 缺失由测试桩与 HTTP/Host 运行时集成测试覆盖，未在真机连接真实服务；没有实际进入 Android 多窗口，分屏布局以 900dp 双栏窗口和其余窗口约束进行 Widget 测试。
- 真机截图： [功能页深色](screenshots/android-a7.6/01-functions-dark.png)、[执行设备选择深色](screenshots/android-a7.6/02-target-selection-dark.png)、[连接配置深色](screenshots/android-a7.6/03-connection-form-dark.png)、[长名称与 IME 深色](screenshots/android-a7.6/04-long-name-ime-dark.png)、[连接页浅色](screenshots/android-a7.6/05-connections-light.png)、[150% 字体深色](screenshots/android-a7.6/06-large-font-dark.png)、[150% 字体浅色](screenshots/android-a7.6/07-large-font-light.png)。

### A8.1 稳定性与迁移验收（2026-11-14）

- 运行公共契约/领域/连接器/Runtime 测试 15 项、Flutter Widget 测试 189 项；`flutter analyze --no-pub` 与共享层边界检查通过。Dart tracked-source 格式检查通过。`tool/check.sh` 的合并格式命令还会扫描当前工作树里未提交的 `glass_theme_switch.dart`、`theme_switch_simulation.dart`，它们有 formatter 差异；因此其余门禁独立执行，未格式化或纳入本次提交的主题工作文件。
- `flutter build apk --debug --target-platform android-arm64 --no-pub --build-number=9` 产出 arm64 APK（versionCode 9、versionName 0.3.7）；`zipalign -c -P 16 4` 通过。macOS Debug app 构建成功。Build Tools 36.0.0。16 KB 静态对齐只覆盖 APK 内 `.so` 的 ZIP 布局检查，不作为 16 KB 系统运行证明。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB：已安装 versionCode 8 后用 versionCode 9 覆盖安装，Android Package Manager `Success`，`MainActivity` 冷启动成功；应用配置文件哈希在升级前后相同。随后对连接配置缺少 `executionTarget` 的旧格式 `mcpHttp` 样本冷启动应用，连接页显示该记录且没有 AndroidRuntime 崩溃；契约单测确认旧记录目标默认为此设备。样本使用本机拒绝连接端口，不含 token/密钥，验收后再次 `pm clear` 并冷启动，确认样本被清除、主 Activity resumed。设备原有 Host 列表为 0，因此未迁移真实配对或用户连接；重启验证针对应用进程，未重启整台手机。
- 不使用模拟器。无 16 KB 页真机；未验证 production WSS、真实 Host 撤销、真实 NCM 账号或应用升级后的凭证恢复。测试样本已清除，Android 应用处于空配置首次启动状态。

### A8.2 运行稳定性与页大小验收（2026-11-14）

- 当前工作树全量 Flutter 测试 196 项通过（新增主题实验测试也包含在内）；`flutter analyze --no-pub`、公共层边界、tracked-source Dart 格式、`git diff --check` 通过；Android arm64 与 macOS Debug 构建成功。A8.1 的合并 `tool/check.sh` 格式步骤仍会扫描未提交主题文件并报告格式差异，其他门禁已独立通过；没有格式化或提交这些工作区主题文件。
- 普通 Aggregate APK 只包含 `arm64-v8a`；Android NDK 28.2.13676358 抽出的 7 个 `.so`，以及仅 Debug 固定 Node 探针 APK 抽出的 10 个 `.so`，各自 `PT_LOAD` 对齐均至少 16 KB、offset/virtual-address 页内余数一致；所有 GNU_RELRO 边界符合 16 KB 规则；两种 APK 均通过 Build Tools 36.0.0 `zipalign -c -P 16 4`。普通 APK 不含 `libnode.so`/Node JNI 桥。Android 官方指南要求同时检查 ELF `LOAD`/RELRO 与 APK 中原生库 ZIP 对齐，[指南](https://developer.android.com/guide/practices/page-sizes)。
- LGE AN10 / Android 15 / API 35 / arm64 的实际 `getconf PAGE_SIZE` 为 4096。没有 16 KB 设备，故 ELF/RELRO/ZIP 静态通过不表示 16 KB 系统启动或运行通过；没有构建 32 位或 x86 产品 ABI。
- 真机 Node Debug 探针仅运行固定 `a3-fixed` 入口：普通包“探针不可用”通过；启用探针后，固定脚本正常调用/事件、异常、取消、运行中 crash 后 `outcomeUnknown` 与下一代恢复、20 次连续新代际调用均通过。70 秒请求在 JS ready 后退到 HOME，等待 60 秒再回前台，原请求成功完成；完成后未发现遗留 Aggregate/`:node` 进程。此探针仍明确为 `npm=false`、`cli=false`、`profiles=false`，不代表产品包开放 Node/npm/任意 CLI。
- 真机 Wi‑Fi 开/关专项使用 Mac 同网段的临时本机 MCP 服务（无用户凭证）：关 Wi‑Fi 后已保存连接刷新为不可用，恢复 Wi‑Fi 后连接重新 ready 并再次调用成功。另 4 项 Android HTTP MCP 真机集成测试通过：凭证安全存储往返/删除且 Token 不进入 JSON、取消后的结果未知、401 脱敏、静默服务超时和测试后移除临时连接。测试运行器卸载了临时包；随后普通 `versionCode=10` arm64 APK 已安装、清数据并启动，Wi‑Fi 恢复开启。
- Host 退出、远端终端清理、设备撤销和权限撤销由 Android 配对/Host WSS 运行时测试覆盖，未在实体设备配对生产 Mac Host；大结果折叠/展开由 Android 调用页 Widget 测试覆盖。Node 后台样本最长 70 秒、重复 20 次，不等于长时数小时或真实 LMK 压力；无 production WSS/NCM 账号，也未做 16 KB 系统运行验收。

### A8.3 草稿、授权和 profile 清理验收（2026-11-14）

- 检查锁定的 `file_selector_android 0.5.2+11` 后发现，Android 通用文件选择插件会把 `content://` 文档复制到应用 cache 再返回 `XFile`；原来的 Host 私钥字段读取完成后未清理这份副本。Android Host 文件内容字段现改用 Flutter 调用的窄原生通道：系统 `ACTION_OPEN_DOCUMENT` 结果直接经 `ContentResolver` 流式读取到最多 32 KiB 的内存缓冲区，不申请持久 URI grant、不落盘、不保留 URI；读失败时仅返回脱敏错误。Secret 输入在测试成功或向导关闭时清空。其他平台继续走原有 `file_selector` 路径。
- 草稿与副作用：Android HTTP 草稿过期、后台、运行时重开后不可保存；重复保存只保存一次，第二次失败；保存中丢弃回滚凭证。另在真机建立含测试 Token 的未保存 MCP 草稿后执行 `am force-stop`；强停后的 app 私有 `files/` 仅有验收 marker 和 Flutter 安装标记，没有 `connections.json` 或 connector profile 文件。Android Host 撤权 Runtime 测试显示远端连接仍标记 Host 执行目标、状态为认证失效、调用失败且不会调用本机 Runtime；Mac Pairing Authority/WSS 撤销测试覆盖 grant 清除与活动会话失效。
- profile/凭证边界：Android `testConnectionSetup` 拒绝非设备执行目标和任意 `profileId`，失败不创建连接 JSON、凭证或 profile 目录；Mac NCM Runtime 测试覆盖丢弃临时 profile、仅保存已测试配置、连接删除后递归 profile 目录清理及私钥临时文件不落盘。Android HTTP 真机用例覆盖 Token 安全存储/删除，启动时孤立凭证清理仍由 Android Runtime 测试覆盖。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机通过系统文档选择器选择无敏感测试文件；Integration Test 收到字节内容，随后扫描 Aggregate app cache 未发现测试文本。测试文件已从 Downloads 删除；A8.3 后普通 versionCode 11、targetSdk 36 APK 重新安装、清数据并启动，Activity 回到前台，未见 AndroidRuntime/Flutter 崩溃日志。文件选择在读取结束后立即丢弃 URI；本轮没有模拟外部 provider 主动撤销读取期间授权，应用也不会保留该授权供后续访问。
- 验证：全量 Flutter 测试 200 项、共享 contracts/domain/connectors/runtime 测试 15 项、`flutter analyze --no-pub`、公共层边界检查、`git diff --check`、Android arm64 Debug 与 macOS Debug 构建通过。A8.3 改动的 Dart 文件格式通过；全跟踪文件格式检查仍报告既有 `app/integration_test/android_node_probe_test.dart` 有 formatter 差异，工作树另有未提交主题切换文件会阻挡整合格式门禁；均未纳入或格式化用户主题修改。受控进程终止测试由 ADB 强停，Flutter 集成测试框架因此报告测试未完成；强停前 marker 确认草稿已经测试，强停后检查应用私有文件目录通过。
- 范围限制：没有在本阶段连接 production Mac Host；撤权跨端行为由 Host 协议/WSS 测试和 Android Runtime fake 覆盖。真机有 4 KB 页，未有 16 KB 设备；未据此声称 16 KB 系统运行通过。内存中的 Dart 字符串不做底层 RAM 擦除保证，验收针对的是文件/凭证/URI 持久化与逻辑生命周期。
