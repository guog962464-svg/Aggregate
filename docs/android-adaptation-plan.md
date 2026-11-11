# Aggregate Android 适配规划

> 修订日期：2026-11-10；依据提交 `bf8db69`（A0 后新增连接向导、草稿预检、独立账号配置和 CLI 自动检测）。状态：A0 已完成；A1–A8 尚未实施，Android 仍无宿主工程或真机运行结果。
> 本文响应本轮 Android 目标；[原 macOS 方案](architecture.md)中的“本版仅 macOS”是上一阶段范围，不限制本轮规划。桌面界面背景见 [UI 设计](ui-design.md)，当前连接首页见[阶段 5](phase5-contextual-ui.md)。

**统一开发原则：仍然只有一套 Flutter/Dart App。** macOS 和 Android 共同使用 `app/lib/` 中的 `AggregateApp`、路由、页面、Widget、主题、领域模型及 `RuntimePort` 契约；按窗口宽度和输入方式调整同一套 Widget 的布局。`app/android/` 只承载 Flutter 的 Android 宿主、构建配置和确有必要的系统桥接代码，不另写一套 Kotlin/Compose 页面。Android 的 Kotlin/C++/JNI 只负责 Node 共享库、Service、凭证/文件等平台能力，结果经 Dart 适配器返回现有 Flutter 界面。macOS 继续使用现有原生适配层。

~~~text
同一套 Flutter 页面 / 主题 / 交互
             ↓ RuntimePort（Dart 契约）
   macOS 适配器          Android 适配器（Dart）
   现有 MacRuntime       ├─ HTTP MCP（Dart）
                       ├─ Node 系统桥（Kotlin/C++，仅运行能力）
                       └─ Mac Host 客户端（Dart）
~~~

## 1. 先明确“在手机上运行 CLI”的三个层次

| 层次 | 例子 | Android 首版建议 |
| --- | --- | --- |
| App 自带的 JavaScript 功能 | 随 APK 打包、经验证的 JS 模块 | 可以用嵌入 Node 探针验证；也可以优先用 Dart/Android API 实现。 |
| 用户在设备上安装 npm 包并运行其 CLI | `npm install -g @music163/ncm-cli` | 不承诺通用支持；先验证纯 JS 包、安装脚本、可执行入口及版本管理。 |
| 任意本机 CLI、TUI、stdio MCP | Git、Python Server、mpv 等 | 默认通过配对的桌面 Host 执行；本地只开放经逐项适配和真机验证的能力。 |

这三个层次不能由“Node.js 可以启动”推导为“npm 与所有 CLI 可用”。当前 macOS `MacRuntime` 用 `Process.start`、PTY、系统可执行文件、钥匙串和本机路径；Android 需要另一套适配器。现有 `RuntimePort.features` 可准确报告该运行端支持的连接类型和终端能力，公共页面应继续依赖它，而不是根据手机外形推断执行能力。

## 2. `nodejs-mobile` + JNI/FFI 的判断

**结论：可作为“内嵌 JS 运行器”的验证路线，不能直接作为“完整 npm/CLI 环境”的交付方案。** `nodejs-mobile` 官方提供 Android `libnode.so`，原生示例通过 JNI 调用 `node::Start`。Android 原生层仅承担运行时桥接：用 Kotlin/Java 负责生命周期和平台通道、C++ JNI 薄层调用 Node；Dart FFI 只有在导出稳定的 C ABI 后才接入，不直接绑定 C++ `node::Start`。优先在独立的 Android `:node` Service 进程中运行，以隔离 Node 崩溃和单实例限制，再通过 Binder/平台通道向 Dart `AndroidRuntimePort` 传递请求与事件，最终仍由共用 Flutter 页面呈现；是否需要本机回环服务留给探针比较。

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

### A0 后源码变化对计划的影响

| 已落地的 macOS / 共享能力 | Android 计划调整 |
| --- | --- |
| `ConnectionSetupPort` 提供适配器目录、程序检测、草稿测试、保存和丢弃；`ConnectionsPage` 已优先打开共享 `ConnectionSetupDialog`。 | A1 不再从零设计连接向导。先补齐执行位置、平台能力和文件来源语义；A2 Android HTTP 实现同一测试/保存流程，A5 Host 透传该流程。 |
| `ConnectionSetupDialog` 目前是宽 520 的 `AlertDialog`；非 HTTP 类型展示“程序绝对路径”，文件按钮取 `file.path`。 | A1/A7 把同一 Widget 做手机全屏/窄屏布局；仅在真正拥有文件的运行端显示程序路径，Android 文档 URI 与 Mac 文件路径不能互用。 |
| `ConnectionSetupDraft.values` 可能含私钥，约定只在内存中；测试成功后 UI 清空密文字段。 | A1/A2/A5 明确测试与保存时的秘密归属、传输、草稿 TTL 和取消清理；Android 生命周期恢复不得序列化敏感草稿。 |
| macOS 网易云在独立 `profileId` 下配置 CLI，测试后登录与搜索权限可处于 `actionRequired`；自动检测只查 Mac 上的官方 `ncm-cli`。 | A4 不继承 macOS 可运行结论；A5 Host 模式把检测和配置留在 Mac，A6 按连接显示执行设备、配置所在设备和未完成检查。 |

这些变动只改变 A1 起的实施顺序与接口设计，不推翻 [A0 技术基线](android-a0-baseline.md)中的设备、依赖和 T1/T2/T3 目标。当前共享向导的测试覆盖 macOS 流程；Android HTTP、Host 与手机本地 CLI 均未验证。

## 4. 阶段关系与交付边界

~~~text
A0 范围与基线 → A1 Flutter Android 宿主与共享导航
                    ├→ A2 Android HTTP MCP + 连接预检 ─┐
                    ├→ A3 Node 原生桥 → A4 npm/CLI 门槛 ─┤（A4 通过的本地能力才接入）
                    └→ A5 macOS Host + 向导协议 ────────┤
                                                       ↓
                                          A6 Android 执行路由与终端/账号
                                                       ↓
                                          A7 共享 UI/网易云整合 → A8 发布验收
~~~

A3/A4 是手机本地 Node 路线，A5/A6 是通用 CLI 的 Host 路线；A5 可以在 A3 进行时开始。A4 未通过时，A6 仍可交付 Host 功能，但不算 T3 已完成。若产品验收条件是“任意 npm CLI 都必须脱离 Host 在手机运行”，而 A4 无法证明该能力，**Android 版本不能按此条件验收**，需要重新确定产品范围或继续研究本地执行环境。

每阶段结束都记录实际设备、Android/API/ABI、依赖版本、通过与失败的样本，以及仍未知的项目。每个阶段的改动要单独验证并按仓库约定提交；不把探针成功写成完整产品能力。

### A0：确定范围、样本和技术基线

**前置：**现有 macOS 工程与两份历史方案。
**状态：**已完成静态盘点与设备信息采集；证据、版本和未覆盖项见 [A0 基线报告](android-a0-baseline.md)。

- [x] A0.1 记录当前 Flutter/Dart、Android SDK、锁定依赖版本及 Gradle/AGP/NDK 的缺失状态；检查 `mcp_dart`、`flutter_pty2`、`terminal_view` 的 Android 构建条件。当前仓库尚无 `app/android/`。
- [x] A0.2 逐个列出 `RuntimePort` 方法的 Android 去向：手机本地、Host、暂不支持。另列 `ConnectionAccountPort`、文件导入导出、凭证、通知、活动记录和终端。
- [x] A0.3 定义验收样本：一个远程 HTTP MCP、一个普通 CLI、一个交互式 TUI、一个 stdio MCP、一个不启动子进程的纯 JS npm 包、一个依赖原生/外部程序的 npm 包，以及网易云样本。
- [x] A0.4 定义设备矩阵，记录现有真机、目标/最低 API 候选、ABI、4 KB/16 KB 页与分发渠道待定状态；16 KB 真机列为 A3/A8 前置缺口。
- [x] A0.5 把“npm 支持”拆为构建时随包提供、手机上安装纯 JS 包、手机上运行此前未知的 npm/本地 CLI 三档；以完整本地使用为目标，是否可交付由 A4 验证。

**交付物：**能力矩阵、样本清单、设备/版本矩阵、Android 首版范围与不支持项。**通过门槛：**每项能力有负责人层（Dart、Android 原生、Node 或 Host）与可观察的验收结果；未知项保留为未知。

### A1：共享契约、连接向导与 Flutter Android 宿主

**状态：**已完成 A1 宿主、契约与 UI 壳；验证见 [A1 实施记录](android-a1-report.md)。

**依赖：**A0。把现有连接向导作为跨端基线；先解决执行位置和文件语义，再连接 Android Runtime。

- [x] A1.1 记录 A0 后接口增量并为 `ConnectionSetupPort`、`ConnectionSpec.profileId`、`ConnectionAccountPort` 制作 Android/Host 去向表；明确 `profileId` 只标识运行端自有配置，不是可跨设备使用的文件路径。
- [x] A1.2 设计连接的执行目标（手机/指定 Host）、连接级能力与稳定 ID；测试、保存、调用、终端、活动、账号和清理必须指向同一目标。定义已有连接 JSON 的迁移与缺失目标时的处理，避免单个全局 `RuntimeFeatures` 把 Host 能力误报给手机连接。
- [x] A1.3 扩展/约束连接适配器目录：只列出当前目标可用的类型；程序检测返回值与“程序绝对路径”只属于拥有该程序的设备；文件字段区分 Android 文档 URI、内存内容与 Host 路径。`ConnectionSetupDialog` 仍是一份 Flutter Widget，不在手机上让用户挑选 Mac 可执行文件。
- [x] A1.4 定义草稿状态机：输入变化、关闭、超时、进程重启、保存失败和重复保存时怎样失效/清理；敏感 `values` 和 Token 只短暂驻留内存，错误/日志/活动不得包含其内容；Host 草稿 ID 需绑定配对设备和执行目标。
- [x] A1.5 创建 `app/android/` Flutter 宿主，安装并锁定首次构建所需 NDK，记录 Gradle/AGP/ABI；`main.dart` 用平台工厂连接 `LocalRuntimePort` 或 `AndroidRuntimePort`，继续共用 `AggregateApp`、路由和主题。
- [x] A1.6 让同一套导航、连接页和向导在窄屏可浏览：表单改为手机可滚动页面/全屏弹层，处理系统返回、状态/手势栏、输入法、安全区、触控与 TalkBack。未实现的本地 CLI/stdio/终端不出现在可操作入口。

**交付物：**Android 开发包、执行目标与文件语义契约、草稿生命周期表、共享 UI 的手机布局。**通过门槛：**现有 API 35 真机能启动并浏览同一套路由；连接向导不溢出或被输入法挡住；仅可用适配器可选；已有 macOS 连接/向导测试不回退。此阶段不宣称 Android MCP/CLI 已可用。

### A2：Android HTTP MCP 与共享连接预检闭环

**依赖：**A1。Android Runtime 实现 `RuntimePort` 和 `ConnectionSetupPort` 的 HTTP 子集，无需 Node 或 Mac。

- [ ] A2.1 在应用私有存储保存连接、偏好与脱敏活动，配置文件保存凭证引用；使用 Android 安全存储处理 Bearer Token，验证写入失败、重启、撤销、删除和迁移。
- [ ] A2.2 `connectionAdapters` 先只发布 `mcp-http`；复用共享向导的“填写 → 测试 → 检查结果 → 保存/丢弃”。测试使用临时 MCP 客户端做握手与发现，保存前不进连接列表；失败报告 `canSave=false`，及时关闭客户端。
- [ ] A2.3 实现草稿过期、输入变更、弹层关闭、后台/进程重启后的清理。保存原子化；重复保存返回明确结果，未保存的凭证和连接不残留。为上述状态转换加契约测试。
- [ ] A2.4 接 `mcp_dart` Streamable HTTP：能力发现、工具、资源、提示、超时、取消、网络切换与认证失败；搜索/运行/活动沿用公共 `RuntimePort` 结果模型。
- [ ] A2.5 用 Android 系统文档选择器处理导入/导出和预览，区分内容读取、URI 授权与可持久化 URI；检查动作清单编辑器和其他 `file.path` 调用。Mac 路径不得在手机上打开。
- [ ] A2.6 在真机用实际可达 HTTP MCP 服务测试“添加 → 预检 → 保存 → 搜索 → 调用 → 结果 → 重启恢复 → 删除”，并测断网、错误 Token、服务器无响应和取消。

**交付物：**不依赖 Host 的 Android HTTP MCP 功能包和真机记录。**通过门槛：**完整闭环通过，预检失败不产生已保存连接/凭证；Android 仅展示 HTTP 适配器；macOS 连接向导回归通过。

### A3：`nodejs-mobile` 原生桥探针

**依赖：**A1，可与 A2、A5 并行。探针保持独立，不先绑定完整 UI。

- [ ] A3.1 核验 `libnode.so` 来源、许可证、校验值、头文件、Node 版本、ABI、NDK/AGP 要求；评估维护中的 Node 构建和 16 KB 页支持。预编译 Node 18 只作实验候选。
- [ ] A3.2 在独立 `:node` Service 进程使用 Kotlin/Java + C++ JNI 薄层加载库、调用 `node::Start`，在工作线程运行；定义启动、就绪、请求、事件、失败和关闭协议。
- [ ] A3.3 通过 Binder/平台通道把 `console`、文件读写、网络请求、异常与取消事件返回 Dart；若试回环服务，比较端口管理与鉴权后再选。
- [ ] A3.4 把运行端能力查询与受控包入口列成桥接协议；此时不把 `ConnectionSetupPort` 的 `cli`/`mcp-stdio` 适配器暴露给用户。验证 Node 进程重启后旧草稿、请求和 profile 引用不会误指向新实例。
- [ ] A3.5 测冷启动耗时、常驻内存、进程崩溃与重连、重复进入/退出、App 退后台、系统杀进程和升级后的资源清理。
- [ ] A3.6 检查 `.so` ELF 与 APK/AAB 的 16 KB 对齐，并在目标 4 KB 与 16 KB 真机加载；记录每个 ABI 的结果。

**交付物：**最小探针、版本/体积/性能表、原生兼容报告。**通过门槛：**目标设备上稳定启动、通信、失败恢复；能取得可维护的原生库且满足分发要求。**停止条件：**维护版本、16 KB、崩溃隔离或生命周期任一关键项无可行方案时，不进入本地 Node 产品化。

### A4：npm 包与 CLI 兼容性实验及选型决定

**依赖：**A3 通过。把“Node 能运行”与“npm/CLI 能运行”分开验收。

- [ ] A4.1 在开发机锁定安装一个纯 JS 包，随 App 打包，验证 `require`/`import`、动态加载、资源文件、配置路径与升级；比较原文件树与 esbuild bundle。
- [ ] A4.2 验证其 `package.json` 的 `bin` 脚本能否**以 Node 入口函数方式**执行；记录参数、退出码、stdout/stderr、取消和并发语义，不依赖 shebang 自动执行。
- [ ] A4.3 若纯 JS CLI 样本通过，为“内置包 + 已知入口”定义与绝对可执行文件路径不同的标识和适配器字段；配置与缓存留在 Android 应用私有目录，`profileId` 只引用 Android 自有配置。对测试、保存、丢弃、卸载逐项核对状态清理。
- [ ] A4.4 单独实验“手机上 npm 安装”：包下载、完整性、依赖解析、安装脚本、缓存、断网恢复、升级/卸载；按 Google Play 分发政策和安全模型判断是否可以进入产品。
- [ ] A4.5 用原生 `.node` 扩展、`child_process.spawn/fork`、外部 ffmpeg/ffprobe/mpv、stdio MCP 和交互式 TUI 做失败边界样本；记录确切错误与设备版本。
- [ ] A4.6 对 `@music163/ncm-cli` 0.1.7 逐项试 `--version`、配置/登录、搜索、播放控制、真正出声；标明 `fluent-ffmpeg`、`ffprobe-static`、`mpv` 等依赖在哪一步阻断。不可用时不修改连接器声称支持 Android 本地播放。
- [ ] A4.7 写决策记录：T1/T2/T3 各自的真机结果、可发布的本地能力白名单、需要 Host 的包类型、设备端 npm 是否保留为实验功能，以及 Node 更新/漏洞响应责任。仅向 `connectionAdapters` 发布已通过预检与调用门槛的本地适配器。

**交付物：**包兼容矩阵和明确的“本地 / Host / 不支持”决策。**通过门槛：**至少一个真实纯 JS 包完成调用、取消和重启；每个向用户开放的 npm/CLI 行为都有真机结果。**停止条件：**不能安全、可维护地支持设备端安装时，首版仅提供构建时打包的受控包；任意 CLI 走 Host。

### A5：macOS Host 服务、配对与连接向导协议

**依赖：**A1 的执行目标契约，可与 A3/A4 并行。

- [ ] A5.1 在现有 `MacRuntime` 外增加 Host 服务入口；沿用进程、PTY、MCP 和权限实现，只允许已登记连接与适配器操作，不接收任意 shell 字符串。Mac 继续拥有 CLI 程序、工作目录、独立 profile 和密钥配置。
- [ ] A5.2 定义协议版本与对象：适配器目录、程序检测、草稿测试/保存/丢弃、连接目录、能力、调用参数、`RunId`/事件、取消、终端、账号、文件传输、错误码和执行位置；处理重复请求与外部写入后结果未知。
- [ ] A5.3 在 Host 侧执行 `detectExecutable` 和网易云配置测试；手机显示 Mac 程序位置及检查状态。私钥/Token 只经配对加密通道传送，限制大小并脱敏日志；草稿 ID 绑定设备身份，过期、断线或撤销配对时清理。
- [ ] A5.4 实现首次配对、Mac 上确认、设备身份、密钥轮换/撤销与重连；限制输出、并发、超时和资源占用。连接删除同步清理 Mac 自有的独立配置，不能把 profile 目录复制到手机。
- [ ] A5.5 使用普通 CLI、TUI、stdio MCP、HTTP MCP 与网易云向导检查“检测 → 测试 → 保存 → 调用/登录 → 断线/丢弃”；验证未配对、越权和重复保存。

**交付物：**可由测试客户端连接的 Mac Host、协议文档及配对/草稿失败样本。**通过门槛：**已授权手机能对 Mac 已登记适配器完成向导与调用；Mac 路径只由 Mac 使用；未授权设备和越权命令被拒绝；断线后的草稿/进程可清理，外部写入显示“结果待确认”。

### A6：Android 多运行端路由、Host 连接与账号/终端

**依赖：**A2 + A5；若 A4 通过，可附加白名单本地 JS 执行器。

- [ ] A6.1 实现 `RemoteRuntimePort` 与配对 UI；状态区分在线、离线、认证失效、版本不兼容、权限拒绝、超时和结果未知。
- [ ] A6.2 合并 Android HTTP 与 Host 的适配器目录；先选执行设备，再显示该设备的字段。Host CLI 自动检测经 Host 执行，手机文件选择器不能填 Mac 程序路径；已验证的本地 JS 用 A4 的包入口标识。
- [ ] A6.3 搜索、调用、取消、活动、终端和账号 API 按连接执行目标路由；连接 ID 包含来源。切换目标要创建新连接并重新预检，旧权限不自动复用。
- [ ] A6.4 Host 网易云沿用 Mac 独立 profile 登录及搜索权限检查；`actionRequired` 可见，声音实际由 Mac 输出。文件/URI 跨设备使用时传输内容或明确拒绝，不混用两端路径。
- [ ] A6.5 终端复用 `TerminalPage` 显示 Host PTY 事件；补齐手机软键盘 Ctrl、Esc、Tab、方向键和中断，测尺寸变化、横屏、复制粘贴、断线和进程清理。本地 JS 可用不意味着本地 TUI 可用。

**交付物：**Android 上统一展示手机与 Host 连接的功能包。**通过门槛：**真机可调用本地 HTTP MCP、Host 普通 CLI/TUI/stdio MCP；向导、账号、取消、断线、重连和执行位置正确；若 A4 未通过，本地 CLI 不可选。

### A7：同一套 Flutter UI 的完整手机适配

**依赖：**A2、A6；本地音乐分支还依赖 A4 的单独验证。

- [ ] A7.1 在共用 `AppShell`、连接首页、所有功能、运行、活动和设置 Widget 中按窗口宽度适配单栏/宽屏导航；保持一套页面树，不按设备名分叉。
- [ ] A7.2 把连接向导做成手机可用的长表单：适配器和执行设备先选，再显示字段；测试检查可逐项阅读，`actionRequired` 不误显示为完成；保存、键盘和返回手势不互相遮挡，关闭/更改输入会丢弃临时草稿。
- [ ] A7.3 运行页按来源、权限、参数、进度、结果排列；复杂 JSON、长输出和终端用全屏视图。错误说明运行设备、失败状态和可恢复动作。
- [ ] A7.4 调整播放器与迷你播放器，避免底部导航、输入法和手势条重叠；Host 网易云标注声音由 Mac 输出。若要手机出声，另接 Android 音频/后台控制路径并单列验收。
- [ ] A7.5 用长连接名、复杂 schema、中文/英文、错误 Token、Host 离线、Node 不可用及大输出检查浅深色、小屏/大屏/分屏、字体放大、TalkBack 顺序与触控范围。

**交付物：**共享 Widget 的手机完整流程、截图与真机操作记录。**通过门槛：**主要功能单手触控可达，向导与运行页关键按钮不被输入法遮挡，读屏能区分执行设备和检查状态；Mac 回归截图与操作无明显退化。

### A8：稳定性、发布与文档

**依赖：**A7；发布声明只能包含已过门槛的能力。

- [ ] A8.1 跑公共契约测试、Widget 测试、Android 构建、macOS 回归；在真机上验证安装、升级、清除数据、重启和配置迁移。
- [ ] A8.2 覆盖 4 KB/16 KB 页与目标 ABI、长期运行、网络切换、后台/前台、Host 退出、Node 崩溃、凭证撤销、输出过大和资源清理。
- [ ] A8.3 覆盖连接向导的草稿过期、重复保存、进程被杀、Host 撤销、文件 URI 授权失效与账号 profile 删除；检查没有残留私钥/Token、错误执行端或孤立配置。
- [ ] A8.4 复查原生库与 npm 依赖版本/许可证/漏洞响应、密钥和日志、动态代码分发政策、APK/AAB 体积与签名；发布渠道对应规则以当时官方要求再核对。
- [ ] A8.5 更新用户指南：Android 能力边界、Host 配对、包的安装方式、执行位置、网易云声音输出位置及故障排查；内部记录各项真机通过/未通过证据。

**交付物：**Android 发布候选包、能力矩阵最终版、验收报告与用户文档。**通过门槛：**声明的每条主流程均在目标真机通过；未通过的 npm/CLI/本地播放能力不进入发布说明或可操作入口。

## 5. UI 验收矩阵

| 场景 | 重点 | 首次检查阶段 | 最终验收 |
| --- | --- | --- | --- |
| 窄屏竖屏 / 横屏 | 连接切换、导航、全局搜索、返回 | A1 | A7 |
| 连接向导 | 执行设备先选、字段与文件来源正确、测试/保存/丢弃、`actionRequired` | A1/A2 | A7/A8 |
| 大屏 / 分屏 | 侧栏、表单与结果并列、窗口变化 | A1 | A7 |
| 输入法和手势导航 | 表单提交、终端输入、迷你播放器不遮挡 | A1/A6 | A7 |
| 长文本与复杂数据 | 路径、MCP schema、JSON、大输出不溢出 | A2 | A7 |
| 可访问性 | TalkBack、字体放大、状态与执行位置朗读 | A1 | A7/A8 |
| 离线与故障 | Host 离线、Node 失败、权限拒绝、结果未知 | A2/A6 | A8 |

当前 `AppShell` 有 760 逻辑像素抽屉断点，`TerminalPage` 已复用 `terminal_view`；这只是复用起点。Android 的实际断点、导航方式和终端输入控件必须按真机可用窗口与交互结果确定，不能仅用桌面窄窗口截图验收。

## 6. Skillpilot 结果如何取舍

本次修订重新调用 Skillpilot `plan`（review、security、docs、design、testing、strategy）。它推荐 CodeRabbit、Semgrep、Context7 作为可选工具；均未安装，项目现有测试与源码核对优先。它的 UI/测试清单里“真实设备、表单状态、秘密不入库、失败路径、能力回归”可用于 A1/A2/A7/A8。返回的 React/CSS 组件、Playwright 浏览器测试、Stripe、Vercel 和商业分析是通用模板，不适用于此 Flutter/Android 工程；无需其 `TWENTY_FIRST_API_KEY`。完整可执行的阶段任务、依赖和门槛以本文件 A0–A8 为准。

## 依据与待验证事实

- 当前源码：`app/lib/main.dart`、`app/lib/platform/macos/mac_runtime.dart`、`app/lib/features/connections/connection_setup_dialog.dart`、`app/lib/features/connections/connections_page.dart`、`app/lib/app/app_shell.dart`、`app/lib/features/invocation/terminal_page.dart`、`packages/aggregate_contracts/lib/src/connection_setup.dart`、`packages/aggregate_contracts/lib/src/runtime_port.dart`；历史阶段见[公共层准备](phase4-common-layer.md)。
- [nodejs-mobile 官方仓库与发布包](https://github.com/nodejs-mobile/nodejs-mobile)、[官方 FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)、[Android JNI 示例](https://github.com/JaneaSystems/nodejs-mobile-samples/blob/master/android/native-gradle/README.md)。
- [Android 10 可执行文件限制](https://developer.android.com/about/versions/10/behavior-changes-10)、[16 KB 页要求](https://developer.android.com/guide/practices/page-sizes)、[动态代码加载建议](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)、[Google Play 开发者政策](https://support.google.com/googleplay/android-developer/answer/18265346)。
- [Node.js 版本维护状态](https://nodejs.org/en/about/previous-releases)、[Flutter 自适应布局](https://docs.flutter.dev/ui/adaptive-responsive/general)、[Media3 后台播放](https://developer.android.com/media/media3/session/background-playback)、[flutter_pty2 支持情况](https://pub.dev/packages/flutter_pty2)。
- [网易云 CLI npm 包](https://www.npmjs.com/package/%40music163/ncm-cli)的版本/依赖来自 2026-11-10 的 `npm view @music163/ncm-cli version engines dependencies bin --json`；真实 Android 运行行为尚未验证。
