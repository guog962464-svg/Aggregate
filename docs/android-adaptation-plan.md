# Aggregate Android 适配规划

> 修订日期：2026-11-14。状态：A0–A2 已完成；A3 进行中；A4 Debug 兼容性评估与能力选型已完成（A4.1–A4.6 固定样本已运行；A4.6 的 Android 本地 ncm-cli 业务链路因平台依赖、非 TTY 配置和缺少 mpv 判为不支持；A4.7 已明确本地/Host/不支持边界；A3.6 产品化门槛仍开放，Debug 样本不构成发布资格）；A5 进行中（A5.1–A5.3 已有本地实现；A5.4 的 Mac WSS/Bonjour、Android 配对客户端及 NSD 实现已通过自动化和 4 KB 真机基础启动检查。2026-11-14 同网段真机以原始邀请验证 NSD 匹配、已授权设备 WSS/host.hello/只读 connection.list；随后以隔离 Android App/Keystore 身份验证直接 LAN 首次申请、Mac 只读审批、NSD、WSS、host.hello、只读 connection.list、grant 撤销及撤销后拒绝；隔离包 Android Keystore 别名轮换通过；随后在真机短暂关闭/恢复 Wi-Fi，Android NSD 重新发现 1 个 Host endpoint，WSS 重连和只读 connection.list 再次通过。A5.4 仍未关闭：未轮换日常 Android App 身份，且无 16 KB 实体设备；Mac TLS 身份轮换已在独立临时 macOS Keychain 完成真实集成验收，登录 Keychain 状态已恢复且当前用户身份未轮换；A5.5 通用 CLI/TUI/MCP/网易云远程流程和 Release 权限仍开放；Android 全局身份轮换 UI 另有 fake/Widget 覆盖）；A6.1–A6.5 已完成代码及本地/4 KB 真机启动验收；A6.2 的本地 JS 产品入口仍受 A3.6/A4.3 门槛约束，production WSS 网易云真实账号/音频闭环未完成；A7.1–A7.6 已实现，A7.6 通过 189 项全量 Flutter 测试、analyze、两种主题×五类窗口宽度×200% 字体的 UI 矩阵、Android/macOS Debug 构建、16 KB 静态对齐检查及 LGE AN10 真机连接向导/IME/150% 系统字体冒烟，并保存浅深色截图；设备未安装 TalkBack，已验证 Flutter 语义标签/逻辑顺序/触控范围，未做实体 TalkBack 朗读；没有 production WSS Host、实际音乐账号或 16 KB 真机，因此相关实体端到端仍未验收。A8.1–A8.3 已通过既有验收；本轮已完成 A8.4 的 MCP 安全缓解、Release APK/AAB 构建、Bundletool 与静态对齐检查，A8.5 指南也已完成。A8 仍未达到 Android 分发验收：Release 保持未签名，且缺 16 KB 真机及 production Host/音乐闭环。详见 [A8 验收记录](android-a8-acceptance.md)。Android HTTP MCP 本轮回环真机用例通过，外部 HTTPS 环境用例因未配置测试 endpoint 而跳过；受限纯 JS/npm 样本仅通过部分门槛，设备端 npm 稳定性/产品资格、通用 CLI 和 Host 尚未完成验收。
> 本文响应本轮 Android 目标；[原 macOS 方案](architecture.md)中的“本版仅 macOS”是上一阶段范围，不限制本轮规划。桌面界面背景见 [UI 设计](ui-design.md)，当前连接首页见[阶段 5](phase5-contextual-ui.md)。

**统一开发原则：仍然只有一个 Flutter/Dart 工程。** macOS 和 Android 共用领域模型、`RuntimePort` 契约、业务状态及适合复用的设计元素和 Widget；手机端可以按实际使用场景在 Flutter 中重新设计信息架构、导航、页面结构和操作流程，无须与桌面保持同一页面树。`AggregateApp` 仍是共同入口，可按平台能力与窗口形态组装不同 Flutter 界面。`app/android/` 只承载 Flutter 宿主、构建配置和必要的系统桥接，不另写 Kotlin/Compose 页面；Kotlin/C++/JNI 负责 Node、Service、凭证/文件等平台能力，结果经 Dart 适配器进入手机界面。macOS 继续使用现有界面与原生适配层。

~~~text
一个 Flutter 工程 + 共享领域/状态/设计元素
       ├─ macOS 场景界面（Flutter）
       └─ Android 场景界面（Flutter）
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

**结论：可作为“内嵌 JS 运行器”的验证路线，不能直接作为“完整 npm/CLI 环境”的交付方案。** `nodejs-mobile` 官方提供 Android `libnode.so`，原生示例通过 JNI 调用 `node::Start`。Android 原生层仅承担运行时桥接：用 Kotlin/Java 负责生命周期和平台通道、C++ JNI 薄层调用 Node；Dart FFI 只有在导出稳定的 C ABI 后才接入，不直接绑定 C++ `node::Start`。优先在独立的 Android `:node` Service 进程中运行，以隔离 Node 崩溃和单实例限制，再通过 Binder/平台通道向 Dart `AndroidRuntimePort` 传递请求与事件，最终由 Flutter 手机界面呈现；是否需要本机回环服务留给探针比较。

对原设想的修正：

1. `libnode.so` 必须按 ABI 打包，并核查其头文件、链接方式、许可证、来源与校验值。不能只复制 `.so` 后假定 `dlopen` 能找到并调用 C++ 入口。
2. Node 应在工作线程启动，应用需要明确初始化、就绪、超时、退出、重启和 App 后台行为。官方 FAQ 说明同一进程通常只能启动一个 Node 实例。
3. JS 入口和已锁定的纯 JS 依赖在构建时打包；`esbuild` 可以减少文件数量，但动态 `require`、资源文件、原生 `.node` 扩展和外部命令不能假定都能压入单文件。
4. npm **包依赖可在开发机安装并随 App 发货**，这不等于 Android 设备具备可交互的 npm CLI 或能在手机上执行安装脚本。设备端安装包要另外验证下载、完整性、依赖脚本、二进制插件、存储和升级回滚；首版不把它作为基础能力。
5. Android 10 起，面向 API 29+ 的 App 不能直接 `execve()` 执行可写 App 私有目录中的文件。当前 fogtape Node 24.22.1-0 真机样本能导入 `child_process`，且 `spawn('/system/bin/sh', ...)` 成功；但启动 app-private JS 的 `app_process64` 子进程和 `fork()` 均因 `Error changing dalvik-cache ownership : Permission denied` 以 `SIGABRT` 结束。nodejs-mobile 文档将 `child_process` 列为不支持，与该样本的部分行为不一致，需按具体构建继续验证。将 `node` 嵌入 App 并不会让 Git、Python、ffmpeg 或 mpv 自动可用。
6. `nodejs-mobile` 官方仓库的 Android 预编译版仍为 Node 18.20.4，已结束维护；A3 当前 Debug 探针使用 fogtape fork 的 Node 24.22.1 预发布，arm64 在 4 KB 真机运行，arm64/x86_64 成品原生库与 APK/AAB 静态 16 KB 对齐通过。预发布状态、完整分发许可与真实 16 KB 页设备仍须验收。**若无法取得稳定维护且符合目标设备/分发要求的构建，不把这条路线用于正式发布。**

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
| `ConnectionSetupDialog` 原为宽 520 的 `AlertDialog`；非 HTTP 类型展示“程序绝对路径”，文件按钮取 `file.path`。 | A1 已提供可浏览的手机全屏表单；A7 可按手机连接场景重组向导页面和步骤。仅在真正拥有文件的运行端显示程序路径，Android 文档 URI 与 Mac 文件路径不能互用。 |
| `ConnectionSetupDraft.values` 可能含私钥，约定只在内存中；测试成功后 UI 清空密文字段。 | A1/A2/A5 明确测试与保存时的秘密归属、传输、草稿 TTL 和取消清理；Android 生命周期恢复不得序列化敏感草稿。 |
| macOS 网易云在独立 `profileId` 下配置 CLI，测试后登录与搜索权限可处于 `actionRequired`；自动检测只查 Mac 上的官方 `ncm-cli`。 | A4 不继承 macOS 可运行结论；A5 Host 模式把检测和配置留在 Mac，A6 按连接显示执行设备、配置所在设备和未完成检查。 |

这些变动只改变 A1 起的实施顺序与接口设计，不推翻 [A0 技术基线](android-a0-baseline.md)中的设备、依赖和 T1/T2/T3 目标。当前共享向导的测试覆盖 macOS 流程；Android HTTP、Host 与手机本地 CLI 均未验证。

## 4. 阶段关系与交付边界

~~~text
A0 范围与基线 → A1 Flutter Android 宿主与可浏览的手机界面壳
                    ├→ A2 Android HTTP MCP + 连接预检 ─┐
                    ├→ A3 Node 原生桥 → A4 npm/CLI 门槛 ─┤（A4 通过的本地能力才接入）
                    └→ A5 macOS Host + 向导协议 ────────┤
                                                       ↓
                                          A6 Android 执行路由与终端/账号
                                                       ↓
                                          A7 手机场景界面/网易云整合 → A8 发布验收
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

**交付物：**Android 开发包、执行目标与文件语义契约、草稿生命周期表、手机可浏览的共享界面壳。**通过门槛：**现有 API 35 真机能启动并浏览基础界面；手机尺寸的向导测试无溢出；仅可用适配器可选；已有 macOS 连接/向导测试不回退。实际输入法与 TalkBack 的人工验收归入 A7；A2 已验证键盘 inset 下按钮可见。A1 的页面结构只是启动和能力验证基线，不限制 A7 重新设计手机界面；此阶段不宣称 Android MCP/CLI 已可用。

### A2：Android HTTP MCP 与共享连接预检闭环

**状态：**已完成；实现与验证范围见 [A2 验收记录](android-a2-progress.md)。

**依赖：**A1。Android Runtime 实现 `RuntimePort` 和 `ConnectionSetupPort` 的 HTTP 子集，无需 Node 或 Mac。

- [x] A2.1 在应用私有存储保存连接、偏好与脱敏活动，配置文件保存凭证引用；使用 Android 安全存储处理 Bearer Token，验证写入失败、重启、撤销、删除和迁移。
- [x] A2.2 `connectionAdapters` 先只发布 `mcp-http`；复用共享向导的“填写 → 测试 → 检查结果 → 保存/丢弃”。测试使用临时 MCP 客户端做握手与发现，保存前不进连接列表；失败报告 `canSave=false`，及时关闭客户端。
- [x] A2.3 实现草稿过期、输入变更、弹层关闭、后台/进程重启后的清理。保存与删除串行化；保存中丢弃回滚连接和凭证，重复保存明确失败。状态转换有契约测试。
- [x] A2.4 接 `mcp_dart` Streamable HTTP：能力发现、工具、资源、提示、超时、取消、断网与恢复、认证失败；搜索/运行/活动沿用公共 `RuntimePort` 结果模型。
- [x] A2.5 审计 Android 当前开放的文件入口：HTTP 向导无文件字段，CLI 动作清单编辑器及本地结果预览/显示被能力开关关闭，Mac 路径不会在手机上打开。Android 当前没有文档导入/导出/预览功能；未来首次开放此类功能时须先实现系统文档选择器及内容 URI/授权语义，不能直接传 `file.path`。
- [x] A2.6 在真机用本机回环和外部可达 HTTPS MCP 服务测试连接、预检、保存、搜索、调用、结果、重启恢复和删除，并测 Wi-Fi 断开/恢复、错误 Token、服务器无响应和调用取消。

真机无 SIM，本次网络验收是同一 Wi-Fi 的断开与恢复，未覆盖 Wi-Fi 与蜂窝网络之间切换。向导的键盘安全区由手机尺寸 Widget 测试验证；TalkBack 实机朗读顺序和整套手机场景 UI 仍属于 A7 验收。调用取消表示客户端停止等待，远端执行结果仍可能未知。

**交付物：**不依赖 Host 的 Android HTTP MCP 功能包和真机记录。**通过门槛：**完整闭环通过，预检失败不产生已保存连接/凭证；Android 仅展示 HTTP 适配器；macOS 连接向导回归通过。

### A3：`nodejs-mobile` 原生桥探针

**状态：**进行中；候选库核验、4 KB 真机 Service/JNI 实验及可选 Flutter Debug 通道见 [A3 探针记录](android-a3-probe.md)。固定 JS 脚本的就绪、事件、取消、入口校验、60 秒运行中后台、20 次重入、后台 `am kill` 后重启及升级后陈旧文件替换已在真机通过；真实 LMK、可发布原生库与 16 KB 真机仍未验收。2026-11-13 的 arm64 Debug APK/AAB 静态检查通过；三 ABI 实验确认 armeabi-v7a 的 `libc++_shared.so` 仍是 4 KB 对齐。仓库 NodeProbe 仍锁定 fogtape 24.22.1-0 预发布包；Node 24.22.3 是本机重建候选且其 `process.versions.mobile` 仍报告 24.22.1-0。A3.6 保持开放。详见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。

**依赖：**A1，可与 A2、A5 并行。探针保持独立，不先绑定完整 UI。

- [x] A3.1 核验 `libnode.so` 来源、许可证、校验值、头文件、Node 版本、ABI、NDK/AGP 要求；评估维护中的 Node 构建和 16 KB 页支持。旧 Node 18 和 digidem 24.20.0 保留历史基线；仓库 Debug 探针仍使用 fogtape 24.22.1 预发布；本机 24.22.3 重建只作为审查候选，不能代替维护方发布。稳定维护/分发审查与 16 KB 真机验证仍是 A3.6 门槛。
- [x] A3.2 在独立 `:node` Service 进程使用 Kotlin/Java + C++ JNI 薄层加载库、调用 `node::Start`，在工作线程运行；为固定探针定义启动、就绪、请求、事件、失败和关闭协议。尚未支持任意包入口。
- [x] A3.3 通过 Binder/平台通道把固定探针的 `console`、文件读写、网络请求、异常与取消事件返回 Dart。实验用应用私有 JSONL 文件在 Service 内转发事件，不对外开放回环通信端口；进程级取消仍报告结果未知。
- [x] A3.4 把固定探针的运行端能力查询与唯一受控入口列成桥接协议；不把 `ConnectionSetupPort` 的 `cli`/`mcp-stdio` 适配器暴露给用户。新 Service 代际拒绝旧代际请求及任何草稿/profile 引用；真实包与 profile 语义留待 A4。
- [x] A3.5 在现有 4 KB arm64 真机测冷启动与内存单次样本、进程崩溃和恢复、20 次进入/退出、60 秒运行中后台、`am kill` 后重新进入及升级后陈旧探针资源替换。真实内存压力 LMK、产品配置迁移和更长后台策略属于后续目标环境验收，不能由本次模拟。
- [ ] A3.6 静态部分于 2026-11-13 复核通过：默认 arm64 Debug APK/AAB 的三个 `.so` 全部 `PT_LOAD` 均为 `p_align=0x4000`、offset/virtual address 余数相符，GNU_RELRO 边界符合 Android 指南；探针与普通 Flutter Debug APK 均通过 `zipalign -c -P 16 4`，Bundletool 1.18.3 AAB `validate` 通过并报告 `PAGE_ALIGNMENT_16K`。三 ABI Debug 试包的 APK/AAB 容器对齐通过，但 armeabi-v7a NDK `libc++_shared.so` 仍为 `0x1000`，故默认范围只含 arm64。`prepare.sh` 固定校验 Node archive、同标签 LICENSE、NDK LLVM NOTICE 和 NDK 根 NOTICE，并随 APK/AAB 打包三份声明。2026-11-14 对照官方 Node 24.22.3/26.13.1 再核候选：官方 nodejs-mobile、fogtape 和 digidem 当前都没有同步到这些安全补丁的 Android 成品；fogtape recipe 提供源代码重基/构建路线，但不是已发布二进制。其 README 的 16 KB Pixel 9 实机说法与 NOTICE、实际 release workflow/run 不符，Aggregate 也没有 16 KB 实体设备。之后在 Linux Docker + NDK r27d 从重放 20 个移动补丁的 Node 24.22.3 源码构建了临时 arm64 `libnode.so`；树 hash 仍不匹配 recipe 预期，但隔离 Debug APK 的 3 个 native libraries 均通过 16 KB ELF/ZIP 检查，并在 LGE AN10 4 KB 真机通过 Node 生命周期、文件和 loopback 验证。Node `LICENSE` 与 NDK r27d LLVM `NOTICE` 的文件 SHA-256 与临时 APK 使用的对应资产匹配；NDK 根 NOTICE 已确认覆盖静态链接的 cpufeatures 源码许可，现已纳入重打包的隔离 NodeProbe APK/AAB，候选 LICENSE 已确认是官方 v24.22.3 的 44 项上游 LICENSE 加 polywasm MIT 条目；recipe 39 项与候选 45 项差异及主要 Android 依赖已在最新记录中分类，但完整二进制 SBOM 与发行许可复核尚未完成。隔离 NodeProbe Release APK/AAB 单 arm64 的 ELF/ZIP 对齐与 Bundletool `PAGE_ALIGNMENT_16K` 检查通过，但未签名，不代表 Aggregate 产品 Release gate。产物仅留在 `/tmp`；配置的 Android `parallel sequential` 移动测试集在 4 KB 真机 3,790 项全过（详见 A3.6 研究记录），Node mobile patches 已于 2026-11-14 完成 20/20 静态审阅，但不能替代跨平台回归；测试证据仍限于既有配置子集，除 `message` 外的 Node 测试类别及 `--flaky-tests=skip` 排除项未覆盖；`message` 的 5 项输出不匹配原因仍待定位，该候选仍不是产品候选。仍需完成发行级二进制 SBOM/许可复核、正式产品 Release 成品检查并在 16 KB 真机加载；x86_64/32-bit 真机加载也未验证。证据与哈希见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。A3.6 保持未关闭。
  - 2026-11-14 补验：用候选 `libnode.so`、Node 24.22.3 headers 与 NDK r27d 编译 arm64 `crc-native` N-API addon，ELF `PT_LOAD` 为 16 KB 对齐；隔离测试 APK 在 LGE AN10 4 KB 真机成功 `dlopen`、调用 N-API、与 `zlib.crc32` 对照并通过错误参数抛错。额外运行 message 类 9 项：4 通过、5 输出不匹配；其中 4 个错误退出样例记录到 Android FORTIFY mutex 行，另一个环境变量样例未从宿主代理传递注释环境变量。两条 child-process `node_run_*` 用例未运行。该结果证明 4 KB 上一次 N-API addon 加载链路，不关闭版本标识漂移、发行候选、未覆盖 Node 类别/异常输出、许可闭包、正式签名 Release 或 16 KB 真机门槛。详情与日志摘要见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。

  - 2026-11-14 追加验收：Node `v24.22.1` 固定 recipe 重建 hash `59a1f9b50b39080936dc0e78838b3945da83d8e0` 精确复现；将上游切换至 `v24.22.3` 后 20 个移动补丁全部干净应用，得到候选 hash `5b1a23adddf4b698abcfa45cc8d22de930c01b32`，未更改旧基线的 `expected-tree.txt`。在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机运行 fork curated Node 集，240 项执行全部通过、0 失败，含 6 项 fork 移动测试；临时测试 APK 已卸载、Aggregate 主 App 未改动。此前隔离 NodeProbe APK 的 Node LICENSE 资产与物化源声明 SHA-256 相同，recipe 根 LICENSE 与物化源清单差异已精确记录。此结果只扩展 4 KB 单 ABI 候选验证，不关闭 A3.6：其它 Node 测试类别、全部补丁/许可闭包审查、Aggregate 产品 Release 签名和 16 KB 真机验收仍开放。详情见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。
  - 2026-11-14 静态补核：候选 `process.versions.node` 为 `24.22.3`，`process.versions.mobile` 却仍为 `24.22.1-0`；发布前须修正移动元数据并重建、重测。Android parallel/sequential status 含 590 条 `SKIP` 模式规则（不等于 590 项测试），且运行排除了 flaky 项；3,790 项只能描述该配置子集。另核实 Android 嵌入模式会读取 embedder 提供的 `NODE_OPTIONS`/`NODE_PATH`/CA 等环境变量、V8 trap handler 被补丁全局关闭、polywasm 仅作为 iOS 后备且有 MIT 声明。环境来源、跨平台影响、许可闭包、Node 其余测试类别和被跳过项仍未完成验收；A3.6 保持开放，Node/npm/CLI 不开放。具体证据见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。
  - 2026-11-14 更正 16 KB 链接配置：fogtape release workflow 使用 NDK r27d，并将 `ANDROID_LDFLAGS=-Wl,-z,max-page-size=16384` 映射到构建步骤的 `LDFLAGS`；因此 CI 已传入 max-page 参数。workflow 和移动 smoke/addon helper 均未配置 `-Wl,-z,common-page-size=16384`，而 Android 官方指南对 r27 及更早版本列出 max/common 两项。候选 ELF 静态对齐通过，但要先补齐 common-page 参数或固定 NDK r28+ 并重新检查真实 release 库；16 KB 实体机加载和运行验收仍未完成。
  - 2026-11-14 移动补丁语义复核：按 Node v24.22.3/recipe 固定 hash 逐段审阅 11/20 个 src、deps、GYP 与 test-harness patch；发现 Clone() 失败时继续的修改没有 Android 条件、message suite 无平台警告过滤范围、Android credentials setter 错误契约未固定，以及 Apple GYP 两处 or True 会绕过 CrossCompileRequested() 架构条件。recipe 另删除 Node upstream CodeQL/Scorecard/license-builder/OpenSSL-V8 update workflows，但保留自己的 verify/build/device/release-control 工作流；不能视为控制等价。上述为静态兼容/验收风险，不是已复现 Android 缺陷；其余 patch 及发行、16 KB 真机门槛仍开放。详情见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。
  - 2026-11-14 移动补丁静态审查完成：按 recipe `patches/series` 审阅 20/20 补丁，范围覆盖 configure/GYP、运行时代码、依赖、测试、CI/文档、ICU lite 与 polywasm。没有确认 Android runtime 缺陷；记录了 lite ICU 会缩小 locale 集、Headers/concurrency/watch-mode 部分测试无条件注释造成跨平台覆盖损失，以及 Android builtin JS 体积和上游扫描/依赖更新工作流差异。未运行 Node 测试或构建；这些是静态审阅结论，不关闭 Node metadata、发行级 SBOM/许可、message/环境转发、签名 Aggregate Release 与 16 KB 真机门槛。详见 [A3.6 运行时研究与静态记录](android-a3-runtime-research.md)。

**交付物：**最小探针、版本/体积/性能表、原生兼容报告。**通过门槛：**目标设备上稳定启动、通信、失败恢复；能取得可维护的原生库且满足分发要求。**停止条件：**维护版本、16 KB、崩溃隔离或生命周期任一关键项无可行方案时，不进入本地 Node 产品化。

### A4：npm 包与 CLI 兼容性实验及选型决定

**依赖：**A3 固定探针已在现有 4 KB 真机运行，可先做隔离的 Debug 包兼容性实验；A3.6 的 16 KB 真机、稳定维护库与许可门槛必须在本地 Node 产品化或 A4 发布判断前通过。把“Node 能运行”与“npm/CLI 能运行”分开验收。当前进度见 [A4 实验记录](android-a4-progress.md)。

- [x] A4.1 在开发机锁定安装一个纯 JS 包，随 App 打包，验证 `require`/`import`、动态加载、资源文件、配置路径与升级；比较原文件树与 esbuild bundle。JSON5 2.2.3 的源码、动态加载、包分发文件、ESM、私有配置和 esbuild bundle 对照在 4 KB 真机通过；force-stop 后重启成功，并确认旧包目录标记被清理。另完成 JSON5 2.2.2/versionCode 1 到 2.2.3/versionCode 2 的 APK 原位升级，确认新包加载、旧包文件清理及用户配置保留。仅代表此 Debug 真机样本。
- [x] A4.2 验证其 `package.json` 的 `bin` 脚本能否**以 Node 入口函数方式**执行；记录参数、退出码、stdout/stderr、取消和并发语义，不依赖 shebang 自动执行。JSON5 2.2.3 `lib/cli.js` 的 `--version`/`--help`、非法输入的 stderr 与退出码 1 在 4 KB 真机通过；运行期间第二个请求收到 busy，处理 4 MiB 校验输入时取消会终止隔离 Node Service 且不回终态结果，重启新 generation 成功。仅覆盖此 Debug 样本，取消是进程级终止。
- [x] A4.3 为“内置包 + 已知入口”定义不同于绝对可执行文件路径的标识；profile/配置/缓存保存在应用私有目录，`profileId` 只作 Runtime 引用。隔离 Debug 探针通过草稿丢弃、保存重启、2.2.2→2.2.3 APK 升级、损坏索引备份、伪造入口拒绝、孤儿清理、双连接删除隔离和卸载清空验收。记录见 [A4.3 内置包入口契约](android-a4-bundled-package-contract.md)。仅 LGE AN10 Android 15/API 35、arm64、4 KB 页；中断保存通过合成 staging/orphan 残留验证，未在精确提交点强杀进程；未实现或开放产品 Android 适配器，16 KB 与 A4.7 决策仍待完成。
- [x] A4.4 单独实验“手机上 npm 安装”：固定 npm 12.2.2 在 LGE AN10 Android 15/API 35、arm64、4 KB 页真机通过 CLI 启动、纯 JS 包下载/依赖解析/SHA-512 lockfile、错误完整性拒绝、缓存离线重装、json5 升级/卸载和 cache verify。npm 12 默认阻止未授权生命周期脚本；精确授权本地 tarball 后 `sh -c node install.js` 以 127 失败，marker 未生成。首轮 `0/11` Messenger 终态统计是验证器时序竞争，修正后已确认普通 registry/离线安装和 npm CLI 资源重拷贝收到 `kind=3`；本地 tarball 脚本样本附近观察到 Service tagged-pointer fatal，根因未确认。仅表示受限 Debug 可行性实验完成，不表示稳定性或产品资格通过；Play 政策未预审，16 KB 真机未覆盖。完整记录见 [A4 npm 安装研究与真机结果](android-a4-npm-install-research.md)。
- [x] A4.5 在 LGE AN10 Android 15/API 35、arm64、4 KB 页的 Node v24.22.1-0 Debug 探针完成 8 个固定边界样本：Node `child_process` 可导入、系统 shell `spawn` 成功；启动 app-private JS 子进程与 `fork()` 的 `app_process64` 因 dalvik-cache 所有权权限错误 `SIGABRT`；ffmpeg/ffprobe/mpv 不存在；桥接未向 stdin 提供 MCP 输入且无 TTY/raw mode；自编译最小 N-API addon 依赖 `libnode.so` 后加载成功、报告 N-API 10。与 nodejs-mobile 文档对 `child_process` 的“不支持”声明保留为版本/构建差异，不推广单机结论。仅表示边界样本完成，不代表通用 CLI、本地 TUI、任意 addon 或产品能力通过；未覆盖 16 KB 真机。完整记录见 [A4 实验记录](android-a4-progress.md)。
- [x] A4.6 **兼容性评估已完成，能力结论为不支持**。2026-11-13 在 LGE AN10 / Android 15/API 35 / arm64 / 4 KB 页测试固定 `@music163/ncm-cli@0.1.7`、Node 24.22.1、npm 12.2.2 和 lockfile，禁用安装脚本；首次 `npm ci` 安装完成。`--version` 返回 0.1.7；帮助动作同时报 API key 未设置、`Unsupported platform` 并退出 1；`configure` 因非 TTY 无法交互；`login --help` 只验证帮助；README 搜索示例在实际包中报 `unknown command 'search'`；TUI 报缺少 mpv。结合 `ffprobe-static@3.1.0` 不支持 Android/arm64 的平台清单及 A4.5 对子进程的边界，音频链路当前不能在该 Node Service 上成立。未提交用户凭证，也未运行真实登录、播放控制或出声。**此复选仅表示样本评估和能力选型已收敛，不表示本地登录/搜索/播放验收通过；Android 本地 `ncm-cli` 明确不支持，后续只可按 A5/A6 的 Host 路线继续验收。**复现和原始结果见 [A4 实验记录](android-a4-progress.md)。
- [x] A4.7 已形成 [ADR 0003：Android 本地 Node、npm 与 CLI 能力边界](decisions/0003-android-local-execution.md)：T1 继续用 Flutter/Dart 在手机运行已验收的远程 HTTP MCP；T2 只保留固定、白名单化的 APK 内置 JS 作为 A3.6 通过后的候选，当前生产白名单为空；T3 任意 npm/CLI/TUI/stdio MCP 转 macOS Host，A5/A6 完成前不开放；`ncm-cli` 本地播放标为不支持。设备端 npm 仅作为 Debug 实验，生命周期脚本和用户任意安装不进入 Android 首版；Node 来源、16 KB 真机、许可/漏洞响应人及发行渠道动态脚本审查仍是产品化门槛。

**交付物：**包兼容矩阵和明确的“本地 / Host / 不支持”决策。**通过门槛：**至少一个真实纯 JS 包完成调用、取消和重启；每个向用户开放的 npm/CLI 行为都有真机结果。**停止条件：**不能安全、可维护地支持设备端安装时，首版仅提供构建时打包的受控包；任意 CLI 走 Host。

### A5：macOS Host 服务、配对与连接向导协议

**依赖：**A1 的执行目标契约，可与 A3/A4 并行。

**状态：**进行中。2026-11-13 已完成 [A5 Host 模块与配对协议设计基线 v0.1](android-a5-host-design.md)、A5.1 生命周期模块和 A5.2 协议核心；A5.3 的适配器 allowlist/向导草稿安全核心及 setup dispatcher 已实现，生产 Mac WSS/Bonjour 组合、Mac 配对管理 UX、Android 配对客户端/UI、Host 本地记录管理及 NSD 发现已实现。`LocalRuntimePort` 将同一个 `MacRuntime` 注入 `MacHostModule`；start/stop 串行化，启动失败回滚，停止 Host 不释放本机运行时。当前 36 方法 JSON-RPC v1 catalog 含只读 `operation.read`；幂等账本记录设备范围状态，setup dispatcher 注入 grant authorizer 后在副作用前记账，重复请求只返回记录状态。A5.3 coordinator 通过 opaque 引用绑定设备与适配器、分离秘密、清理草稿并对不确定保存禁止重试。A5.4 的 Android Keystore、Mac Keychain Host 身份、本机 loopback WSS pin、CryptoKit P-256 签名校验均有独立真机/集成验证；配对客户端验证短期邀请和证书 pin，逐请求签名并校验 Host 身份，Host 元数据在应用私有目录持久化，私钥留在 Android Keystore。自动化、macOS/Android Debug 构建和现有 4 KB 真机启动检查通过。2026-11-13 已通过 USB ADB 隧道在 4 KB 真机完成 Android Keystore→Mac CryptoKit 签名、人工批准、challenge/`host.hello` 认证、重连与撤销；2026-11-14 先以已授权手机在直连 LAN 完成 NSD/WSS/`host.hello`/只读 `connection.list`，再以独立 `.integration` 包生成的新 Android Keystore 身份在直连 LAN 完成申请与 Mac 人工只读审批。NSD 找到 1 个与原始邀请匹配的端点，WSS challenge/`host.hello` 成功，`connection.list` 返回 1 项“网易云音乐”；Mac 撤销临时授权后，复连得到带正确 JSON-RPC request ID 的 unauthorized 响应，Android 转为 `approvalRequired`，并新增了回归测试及 WSS 错误关联修复。隔离包真实 Android Keystore 别名轮换通过，随后撤销临时 grant、卸载隔离包；日常 App 身份及已有“这台手机 · 读取连接”授权保留。2026-11-14 在隔离 `.integration` 包中关闭并恢复 Wi-Fi 后，NSD 重发现 1 个 endpoint，WSS 重连及只读 connection.list 成功；随后撤销临时 grant、关闭 Host。Flutter integration runner 清理时也移除了普通包，故重新构建并安装普通 Debug APK；当前 app-private 目录没有 hosts.json，先前本地数据是否存在未知，Mac 原有只读 grant 保留。2026-11-14 Mac 设置页补上显式 TLS 身份轮换：确认后先撤销全部配对授权，再停止 Host，最后调用 Keychain 轮换；Mac 原生实现先生成并验证候选身份，再更新单条活动身份记录，失败时保留旧身份。Widget 测试覆盖确认/取消、授权撤销失败保护和调用顺序；本轮未对当前用户 Keychain 执行真实身份切换。A5.5 已开始：生产 WSS 已接入 Host runtime dispatcher，连接/能力/运行/资源/提示/账号/终端 RPC 的 Mac 侧 handler 和授权复核已有本地测试；Host CLI 动作编辑仍由 Mac 本机连接页提供，现有 Widget 回归测试保证该入口不会出现在 Host CLI；Android v1 不提供远程动作编辑 UI 或通用 Host 文件传输；Android RemoteRuntime 跨端验收仍待完成；已配对设备权限修改 UI 已实现并覆盖权限更新后的会话清理；新设备的 manifest.get/save 已有 Host handler；Mac 新设备审批已能配置连接向导、连接管理、账号、终端、活动清理及逐连接 read/localControl/externalWrite。Release/signed app 权限也待验收。Keychain grant 注册表已通过 macOS 集成用例覆盖保留已有记录、保存、加载与删除。状态机用例采用确定性 fake verifier；CryptoKit 算法兼容仍由 OpenSSL test fixture 单独覆盖。Keychain TLS 私钥为满足 `dart:io` TLS API 会导出到 Host 进程内存，不证明 Secure Enclave 硬件保护；不能把本机 TLS 或状态机测试当成 LAN Host 已可用。实施和验收记录见 [A5.4 Android 客户端记录](android-a5-android-client.md)。

- [x] A5.1 在现有 `MacRuntime` 外增加 Host 服务入口；沿用同一进程、PTY、MCP 和连接存储，只允许后续 dispatcher 访问已登记操作，不接收任意 shell 字符串。Mac 继续拥有 CLI 程序、工作目录、独立 profile 和密钥配置。控制状态和生产 listener 已接入；测试覆盖并发 start、状态变更、启动失败回滚、配对未就绪时拒绝启动、停止 Host 后本机 CLI 仍可用，以及生产传输组合的惰性装载。
- [x] A5.2 已实现封闭的 JSON-RPC v1 方法/参数目录（初始 33 个方法）、稳定错误码、Host 路径不出线的 setup/manifest DTO、运行/终端事件序号游标、1 MiB 双向帧限制、64 层请求 JSON 深度限制、重复 JSON key 拒绝、JCS 操作 payload 哈希和文件型幂等账本。相同 `(deviceId, operationId, payloadHash)` 不重复执行；同 ID 不同参数拒绝；进程重启时遗留 `started` 标为 `outcomeUnknown`。A5.3 后续增加只读 `operation.read`，A5.4 增加配对/认证入口，当前目录共 36 项；setup dispatcher 已接入向导操作和幂等账本，WSS loopback 测试已验证 authenticated dispatcher path。生产 Host factory 已在 Host 显式启动时将 pairing authorizer、dispatcher 和 operation ledger 接入传输；runtime dispatcher 已覆盖连接、能力、运行、资源/提示、账号、终端及 `manifest.get/save`；`manifest.get/save` 通过受 1 MiB RPC 帧限制的结构化 JSON 传输动作清单。现有连接页不会为 Host CLI 暴露动作编辑器；v1 不提供通用 Host 文件传输。
- [ ] A5.3 在 Host 侧执行 `detectExecutable` 和网易云配置测试；手机显示 Mac 程序位置及检查状态。私钥/Token 只经配对加密通道传送，限制大小并脱敏日志；草稿 ID 绑定设备身份，过期、断线或撤销配对时清理。**已实现的 A5.3 核心：**固定 adapter allowlist、secret/public 字段校验、HTTP URL 与 Bearer token 分离、按设备/adapter 绑定的 executableRef、按设备绑定的 10 分钟 draftHandle、检查/保存摘要脱敏、Host stop/设备撤销清理、保存结果未知时禁止重试，以及注入 authorizer 的 setup dispatcher 与 `operation.read` 状态查询。`HostSetupCoordinator` 已注入 `MacHostModule`；生产 WSS factory 现在会装载 pairing authorizer、setup dispatcher 和文件型 operation ledger，并保持到用户启动 Host 时才加载身份、绑定监听；Mac 配对界面可生成邀请并审批/撤销设备。通用 CLI 按 Mac PATH 名称查找、setup RPC handler 与 Android Host setup port 均已实现；2026-11-14 在当前 checkout 对 Host setup coordinator/RPC、Android RuntimePort 和 Flutter 向导运行 4 个定向测试文件，35 项全部通过，覆盖按名称查找、opaque 引用、授权/幂等、秘密字段分离、检查与草稿保存/清理，以及向导对 Host 返回程序位置和检查状态的消费。仍不关闭：未在真实配对 Host 上执行写配置型 setup.test/setup.save，也未验收 Android→Host 的真实 CLI/TUI/MCP/网易云业务闭环；本轮真实 Host RPC 验收范围仅为 host.hello 与 connection.list，因此未触发生产 setup 写入。
- [ ] A5.4 实现首次配对、Mac 上确认、设备身份、密钥轮换/撤销与重连；限制输出、并发、超时和资源占用。连接删除同步清理 Mac 自有的独立配置，不能把 profile 目录复制到手机。**进度：**Android `AndroidKeyStore` P-256 私钥及 MethodChannel 签名适配器已在 LGE AN10 真机通过；Mac Keychain P-256 身份、证书 SHA-256 pin 和本机 loopback WSS 回环在本机集成测试通过。Dart 配对 authority、一次性邀请/签名申请/本机批准/最小 grant、challenge 认证、逐请求签名/时钟窗口/nonce 防重放、会话资源上限和撤销清理已实现；Keychain grant 注册表覆盖保留已有 grant、增删读写。Mac 生产 factory 已将固定端口 WSS 与 MacHostModule 生命周期接通，listener 仅绑定指定私有 IPv4 接口，原生 DNS-SD publisher 广告稳定 Host ID，Info.plist 与 Release 网络服务 entitlement 已配置；Mac 设置页提供显式启停、邀请二维码、审批、拒绝、修改已配对设备权限及撤销。Android 侧现有严格邀请解析、证书 SHA-256 pin、Keystore 签名申请/认证/RPC、Host 元数据持久化、Bonjour/NSD 地址刷新、手动粘贴回退和按需 QR 扫描界面；新增单测覆盖协议/持久化/发现/UI。134 项 Flutter 测试、analyze、macOS/Android Debug 构建与 LGE AN10 4 KB 真机应用启动通过，APK 七个 native library 均为 arm64 且 `PT_LOAD p_align >= 0x4000`，`zipalign -c -P 16 4` 通过。**2026-11-13 真机补验：**因手机 VPN/LAN 隔离，邀请端点临时改为 `127.0.0.1` 并经 USB ADB 反向转发到 Mac production WSS；Host ID、证书 pin、nonce、有效期未修改。Android Keystore 配对签名由 Mac CryptoKit 接受，Mac 验证码与手机一致；Mac “批准只读”后，Android challenge、签名及 `host.hello` 成功，UI 显示已连接。断开后通过保存记录重连成功；Mac 撤销授权和 Android 移除记录均通过。测试 grant/本地记录、ADB reverse 与临时代理随后清理，CAMERA 权限保持 denied。此闭环验证了真实 Keystore→CryptoKit 和配对状态，不代表直接 LAN/Bonjour 或 NSD 地址发现通过。无 16 KB 实体设备，静态对齐不能代替该设备实测。Android 全局设备身份轮换确认 UI、原生 Keystore 别名切换和清理流程已实现，Flutter fake/Widget 覆盖通过；本轮未对真机 Keystore 执行轮换。2026-11-14 Mac 设置页增加 TLS 身份轮换操作，要求用户确认后按“撤销所有授权→停止 Host→更换 Host ID/证书”执行；native Keychain 将候选密钥和证书验证后再切换单条活动身份记录，切换前失败会保留旧身份。新增 Widget 用例验证取消无副作用、授权撤销失败不会停止 Host 或轮换身份、成功时调用顺序正确；全量 Flutter 测试 217 项、`flutter analyze --no-pub` 和 macOS Debug 构建通过。由于会更改当前 Mac Host 身份并使已保存 pin 失效，本轮未对生产 Keychain 执行轮换。**2026-11-14 直接 LAN 新设备验收：**在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机上，以隔离 `.integration` Android 包创建新 Keystore 身份并使用 Mac 原样短时邀请；NSD 发现 1 个邀请匹配端点，首次配对申请在 Mac 获“读取连接”人工批准，随后 challenge/`host.hello` 成功，且仅调用 `connection.list`（1 项“网易云音乐”）。Mac 撤销该临时 grant 后再次请求收到带原请求 ID 的 unauthorized，Android 映射为 `approvalRequired`；为此修复 WSS pairing error 的 request ID 关联并添加撤销回归测试。真实 Android Keystore 别名轮换在该可卸载隔离包通过，日常 App 身份和既有“这台手机 · 读取连接”授权未动。隔离包卸载、临时授权撤销、Host 停止（`47321` 无监听）、临时邀请/剪贴板文件删除，普通 App 仍安装且相机权限未授予。日常 Android 身份轮换仍未验证；Mac TLS 身份轮换已在独立临时 macOS Keychain 中完成真实集成测试，断言 Host ID 与证书指纹变化且回读稳定，退出后恢复登录 Keychain 默认项/搜索列表并删除临时 Keychain，未轮换当前用户身份。测试要求显式设置 `aggregateMacKeychainIsolated=true`，避免默认写入用户 Keychain。Release/signed 权限和 16 KB 实体运行仍未验证；Mac TLS 私钥为适配 `dart:io` 暂时导出到 Host 进程内存，未验证 Secure Enclave。A5.5 跨端验收仍开放；通用 Host 文件传输不是 v1 范围。
- [ ] A5.5 使用普通 CLI、TUI、stdio MCP、HTTP MCP 与网易云向导检查“检测 → 测试 → 保存 → 调用/登录 → 断线/丢弃”；验证未配对、越权和重复保存。**进度：**Host runtime dispatcher 已接入 production WSS，Mac 侧连接、能力、运行、资源/提示、账号、终端与活动 RPC handler 已实现；精确 permissionLevel 会由 Mac 二次核验，输出会脱敏，运行/终端资源按设备与会话隔离，撤销时清理。此前 2026-11-14 复跑 8 个 A5.5 相关测试文件共 72 项通过；2026-11-14 后续按当前 checkout 再次运行 Host runtime/setup dispatcher、Android RuntimePort、配对授权/协议/WSS、setup coordinator 与连接配置向导共 8 个测试文件，78 项全部通过；`flutter analyze --no-pub` 通过。该组本地自动化测试不替代 Android→production WSS 的完整端到端验收。Mac 新设备审批和已配对设备权限修改可选择连接向导、连接管理、账号、终端、清理活动和逐连接 read/localControl/externalWrite；保存动作清单需连接管理和目标连接 externalWrite，权限变更会断开旧 WSS 会话并清理授权变化前的运行资源。manifest.get/save 已实现并以短期 executableRef 隐藏 Mac 可执行文件路径；Host connection.list 现按逐连接 read 权限过滤。现有连接 UI 明确不向 Host CLI 暴露本机动作编辑器，因此 Android v1 不增加远程动作编辑界面；manifest 模型无附件，v1 文件传输方法已从 RPC catalog 移除，不提供通用 Host 文件读写。Android RemoteRuntime 已具备本地 RPC/运行事件适配测试；2026-11-14 已通过 direct LAN 真机的最小 `host.hello`/`connection.list` 只读链路，但尚未覆盖 Android RemoteRuntime 的普通 RPC、CLI/TUI/MCP/向导完整跨端业务闭环；当日权限编辑 UI、Host grant 更新、会话失效和 WSS 断连测试定向 12 项通过；全量 Flutter suite 212 项通过、flutter analyze 通过，macOS Debug build 成功。本项仍未达到端到端门槛。

**交付物：**可由测试客户端连接的 Mac Host、协议文档及配对/草稿失败样本。**通过门槛：**已授权手机能对 Mac 已登记适配器完成向导与调用；Mac 路径只由 Mac 使用；未授权设备和越权命令被拒绝；断线后的草稿/进程可清理，外部写入显示“结果待确认”。

### A6：Android 多运行端路由、Host 连接与账号/终端

**依赖：**A2 + A5；若 A4 通过，可附加白名单本地 JS 执行器。

- [x] A6.1 实现 Android RemoteRuntime 首段与配对状态 UI：列出指定 Host 的远端连接并赋予稳定 `ExecutionTarget.host(hostId)` / 来源 ID；支持 capability.search、远端 invoke/事件订阅/取消、resource.read、prompt.get；通过签名会话通知流接收 Host run.event。配对区分在线、离线、认证失效、版本不兼容、权限拒绝、超时和结果未知，并将 Host 状态变化通知 Flutter shell 刷新目录。Mac Host connection.list 按逐连接 read 授权过滤。自动化覆盖 Android RPC 路由、Host event 映射、错误状态、授权过滤和配对面板状态；本项只证明客户端适配与 Host dispatcher 单测，不代表 production WSS 跨端真机已验收。活动历史恢复、账号/终端和 A6.3–A6.5 留待后续。
- [x] A6.2 合并 Android HTTP 与 Host 的适配器目录；先选执行设备，再显示该设备的字段。Android 先展示本机 HTTP MCP 与已配对 Mac Host；Host CLI 由 Mac 按程序名查找并签发短期 opaque `executableRef`，手机文件选择器和连接草稿均不接收 Mac 路径。适配器元数据、保存结果和 Host 检查项均经 schema 校验。Host `connectionSetup` 与 `readConnections` 权限分离；单项权限拒绝不再禁用仍有其他授权的 Host 功能。当前没有开放本地 JS 产品适配器：固定 `json5.bin` 仍只是 A4.3 Debug 契约，待 A3.6 运行时/16 KB/分发门槛通过后另行启用。自动化覆盖 target-first 流程、Host 引用与字段路由、结果未知禁止重试、权限隔离和小屏/横屏放大字体布局；4 KB 真机发现的首个表单标签裁切已修正并复验。完整验收记录见 [A6.2 Android 连接向导](android-a5-host-design.md#a62-android-连接向导进度2026-11-13) 小节。
- [x] A6.3 搜索、调用、取消、活动、终端和账号 API 按连接执行目标路由；连接 ID 包含 Host 来源，终端会话固定到创建时的 Host。Host 活动历史按当前设备获准连接合并显示；Android“清空活动”只删除手机记录，不调用会清除 Mac 全局历史的 `activity.clear`。账号 read/login/wait/logout 使用原始 Mac connection ID，并保留账号/终端分级授权。`terminal.open` 现在传递经过长度、数量和 NUL 限制的参数向量；终端输出采用 PTY event sequence 契约，订阅前先监听并缓冲有界的重放事件，Host 断线结束当前会话，副作用超时不自动重试。未缓存的 Host opaque 能力 ID 不直接显示。自动化覆盖活动合并、来源映射、账号句柄和终端打开/订阅/输入/尺寸/中断/关闭/断线；全量 159 项 Flutter 测试、analyze 和 Android arm64/macOS Debug 构建通过；LGE AN10 / Android 15 / API 35 / 4 KB 真机安装并启动，MainActivity resumed，最近 250 条 logcat 无崩溃。尚未通过 production WSS 实际调用 Mac CLI、登录与远程 PTY 输出验收，也没有 16 KB 真机。
- [x] A6.4 Host 网易云沿用 Mac 独立 `profileId` 配置、账号状态与扫码登录；Android 音乐页标明“声音由配对 Mac 输出”，Host 播放/控制仍经 Mac Runtime 执行。`actionRequired` 账号/搜索检查以信息状态展示，不冒充通过；搜索先经手机会话确认，再由 Mac 按能力声明权限复核；account API 同时检查账号 scope 与连接 read 权限，登录还需 terminal scope。音乐流程只传文本关键词和歌曲 ID，不传 Mac 文件路径/`file://`；Android 文件预览与定位明确不支持，Host 内容传输未开放。回归覆盖 actionRequired、Mac 输出提示、同机 QR 限制提示和登出权限。全量 Flutter 161 项通过、analyze 无问题、Android arm64 与 macOS Debug 构建通过；LGE AN10 Android 15/API 35/4 KB 真机安装启动正常，MainActivity resumed，最近 300 条日志无崩溃。未在本轮用真实账号完成 production WSS 登录、搜索或实际听音，也无 16 KB 真机；当前二维码要求另一台设备扫码，同机替代流程留给 A7 重新设计。详情见 [A6.4 Android 网易云 Host 账号](android-a5-host-design.md#a64-android-网易云-host-账号进度2026-11-14)。
- [x] A6.5 终端复用现有 PTY 事件契约，并以 `TerminalPage` 为初始界面；增加 Ctrl、Esc、Tab、四向键、独立中断和横向工具栏；提供有选择复制与显式粘贴，剪贴板传输限制 256 KiB。输出、尺寸同步或输入失败及 PTY 流结束时转为只读并尽力关闭会话；断线后保留已有输出。4 个 widget 用例覆盖控制字符、按键序列、中断、方向变化时的 PTY 尺寸、375×812 深色/1.8 倍文字、844×390 横屏、复制/粘贴/超限拒绝、流结束、写入失败及销毁清理。全量 Flutter 165 项通过，analyze 无问题，Android arm64 与 macOS Debug 构建通过；LGE AN10 / Android 15 / API 35 / 4 KB 真机更新安装、启动，MainActivity resumed，最近 300 条 AndroidRuntime/Flutter 错误日志为空；Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。未在 production WSS 远程 PTY 上进行真实 Host CLI 交互，未手工验收 Android 系统 IME 的具体键盘布局，也没有 16 KB 真机；静态对齐不替代 16 KB 设备运行验收。A7 可重组手机终端界面；本地 JS 可用不意味着本地 TUI 可用。

**交付物：**Android 上统一展示手机与 Host 连接的功能包。**通过门槛：**真机可调用本地 HTTP MCP、Host 普通 CLI/TUI/stdio MCP；向导、账号、取消、断线、重连和执行位置正确；若 A4 未通过，本地 CLI 不可选。

### A7：按使用场景设计 Flutter 手机界面

**依赖：**A7.1 的手机场景研究与流程设计可在 A1 后启动；完整界面实施和验收依赖 A2、A6，本地音乐分支还依赖 A4 的单独验证。

- [x] A7.1 从手机任务绘制功能查找/调用、添加/测试连接、活动摘要与重新打开、Host 终端和网易云播放流程；明确四项手机主导航、页面层级、执行端、网络依赖、失败恢复、活动结果不持久化边界及窄屏/大屏/IME/TalkBack 方向。建议手机默认进入跨来源“功能”，连接详情承载特定 CLI/MCP/网易云体验；Mac 桌面 shell 保持现状。完整流程图、导航图、执行端表、线框和 A7.2–A7.6 交接见 [Android 移动场景与流程（A7.1）](android-mobile-experience.md)。
- [x] A7.2 在 Flutter 内实现手机专用的导航和页面组合：功能、连接、活动、设置四项主导航；手机默认进入跨来源功能工作台；连接详情走独立返回栈，网易云连接进入专属播放器。`<600 dp` 使用底部导航，`600–839 dp` 使用 NavigationRail，`≥840 dp` 扩展 Rail；IME 弹出时隐藏底部导航和迷你播放器。共享领域模型、RuntimePort 与能力页面，macOS 原桌面导航、连接首页和侧栏保持原状。验收：Flutter 全量 168 项通过、analyze 无问题、Android arm64 与 macOS Debug 构建通过；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机安装启动，MainActivity 可见且 APK `zipalign -P 16` 检查通过。没有 16 KB 实体设备；本轮未连接 production WSS Host，端到端远程连接流程留待后续阶段。
- [x] A7.3 重组手机连接向导：第一步选择执行设备，第二步在表单内确认适配器、目标和对应字段，再预检/保存；目标不可用时解释恢复方式。必填项、URL、Host opaque 程序引用和 JSON 参数在字段附近给出校验；检查结果明确标注“已通过 / 待完成 / 未通过”，`actionRequired` 不呈现为完成。IME 下测试/保存固定可达，关闭入口保留；测试时可返回并清理草稿，保存中拦截系统返回，保存结果未知不自动重试。Android 不展示本机程序路径选择器，Host 文件与命令查找仍由 Mac 运行端处理。验收：Flutter 全量 172 项通过、analyze 无问题、Android arm64 与 macOS Debug 构建通过；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机实际走通目标选择、配置页、空表单校验与系统 IME，测试/保存操作在键盘上方可见，返回后回到连接页。没有 16 KB 实体设备；本轮未连接 production WSS Host。
- [x] A7.4 实现手机调用与结果流程：常驻显示来源、执行端和权限；运行期间锁定参数并提供进度、取消与活动恢复；复杂 JSON 可格式化/展开，长输出有界预览并可查看/复制全文；密码字段与常见 CLI 密钥参数脱敏；未知结果明确要求先查活动，不自动重跑；错误提供按类型的恢复建议；Host 终端显示执行端/权限并隐藏常见密钥参数。定向调用、表单、活动、终端 Widget 测试和 analyze 通过；Android arm64 Debug APK、macOS Debug app、`zipalign -c -P 16 4` 通过；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机安装启动，确认手机活动页与运行状态筛选可见。未连接 production WSS，未在实体设备完成实际调用/终端/IME 交互；没有 16 KB 真机，静态对齐不等于 16 KB 系统运行验收。
- [x] A7.5 按手机播放场景适配播放器与迷你播放器：`<600 dp` 时迷你栏分为曲目/来源与主控制两行，将停止/刷新收进菜单，提供返回完整播放器入口；Host 输出位置在完整播放器显示“声音由配对 Mac 输出”，迷你栏用“Mac 输出”短标签并保留完整读屏语义；IME 出现时隐藏迷你栏，音乐页搜索滚动到键盘上方。桌面宽度保留直接控制布局。定向音乐与手机导航测试、全量 Flutter 185 项、analyze、Android arm64/macOS Debug 构建和 Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过；LGE AN10 Android 15/API 35/arm64/4 KB 真机更新安装启动成功。设备无 Host/真实账号，因此未验收远程实际播放和音频输出；手机本地音频仍不开放，16 KB 设备运行未验收。
- [x] A7.6 完成 UI/可访问性验收矩阵：长连接名、复杂对象/数组/枚举 schema、中英文、错误 Token、Host 离线、Host CLI/Node 缺失及大输出均有运行时或界面错误态覆盖；两种主题 × 320/393/700/900 dp 与横屏 844×390 dp × 200% 字体的调用页 Widget 矩阵通过，浅深色正文对比度检查通过，来源→执行端→权限语义阅读顺序通过，主要调用与迷你播放器控件的语义点击区域均 ≥48 dp。全量 Flutter 189 项、analyze、Android arm64/macOS Debug 构建与 APK `zipalign -c -P 16 4` 通过；LGE AN10 Android 15/API 35/arm64/4 KB 真机更新启动、连接设备选择、HTTP MCP 配置、长英文名输入和键盘上方操作区走查通过；系统字体从 100% 暂调至 150% 后页面可读并恢复原值，系统浅色/深色模式截图均已保存，未保存连接草稿已丢弃。截图见[手机体验验收记录](android-mobile-experience.md)与 `docs/screenshots/android-a7.6/`。设备未安装 TalkBack，故未声称实体读屏服务手工验收；本轮没有 production WSS Host，所以错误 Token/Host 离线/Node 缺失为测试桩或既有运行时集成测试覆盖，未在实体设备连接真实服务；未实际进入系统分屏，多窗口断点通过 Widget 尺寸矩阵模拟。

**交付物：**手机场景流程图、Flutter 手机界面与必要的共享组件、截图和真机操作记录。**通过门槛：**快速调用、连接设置、结果查看及已开放的 Host/播放流程在真机可完成；常用操作单手触控可达，关键按钮不被输入法遮挡，读屏能区分执行设备和检查状态；Mac 回归截图与操作无明显退化。

### A8：稳定性、发布与文档

**依赖：**A7；发布声明只能包含已过门槛的能力。

- [x] A8.1 跑公共契约测试、Widget 测试、Android 构建、macOS 回归；在 LGE AN10 真机完成 versionCode 8→9 覆盖升级、进程强停/冷启动、清除数据/首次启动；用无凭证旧版连接记录验证 Android Runtime 读取缺少 `executionTarget` 的数据，现有契约测试确认默认迁移到设备端。15 项契约/领域/连接器/Runtime 测试、189 项 Widget 测试、analyze、边界检查、Android arm64/macOS Debug 构建和 APK `zipalign -P 16` 均通过。限制：真机原有配置为空，迁移使用合成记录；未重启整台设备。全量 `tool/check.sh` 的格式步骤会触及当前未提交主题切换文件，故拆开运行剩余门禁，跟踪中的 Dart 源格式检查通过。
- [x] A8.2 覆盖 arm64 目标 ABI、4 KB 真机与 16 KB 静态兼容性、Node 长后台/崩溃恢复、Wi‑Fi 断开/恢复、Host 离线/撤销测试、凭证与运行资源清理、大结果处理。普通 arm64 APK 的 7 个 `.so` 与固定 Node Debug 探针 APK 的 10 个 `.so` 均通过 NDK `llvm-readelf` 的 16 KB `LOAD`/GNU_RELRO 检查及 Build Tools `zipalign -P 16`；LGE AN10 上真实 4 KB 页，真实 16 KB 系统运行仍待设备。70 秒 Node 请求在 HOME 后运行并于 60 秒后回前台成功；Wi‑Fi 下本机 MCP 服务断线后恢复并再次调用成功。Host 退出/撤销由 Android 运行时与 WSS/配对测试覆盖，未连接 production Host。
- [x] A8.3 覆盖连接向导草稿过期/重复保存/进程被杀、Host 撤权、文档 URI 授权及 profile 清理。LGE AN10 上选择系统文档后只把 ≤32 KiB 内容读入内存；无持久 URI grant、Android app cache 无测试内容副本。强停仍持有未保存 HTTP MCP 草稿的进程后，应用私有目录没有 `connections.json` 或 profile 文件。自动化验证 Host 撤权不回落到手机执行、Android 拒绝 Mac `profileId`/Host 目标落为本机配置；Mac NCM 连接删除后 profile 目录与测试密钥文件清理。200 项 Flutter 测试、15 项共享包测试、analyze、公共层边界、Android arm64/macOS Debug 构建通过。限制：本阶段未连接 production Mac Host；Host 撤权由协议/WSS 测试和 Android Runtime fake 覆盖。受控杀进程测试按设计被 ADB 强停，测试进程报告未完成；强停前后私有存储检查通过。
- [x] A8.4 已审查原生库与 npm 版本/许可证/漏洞、密钥与日志、动态代码分发政策、APK/AAB 体积、构建和签名边界。修复非回环 HTTP、MCP 响应资源上限及 Host 不存在草稿 discard 账本放大；Host 全局账本仍有 10,000 条/4 MiB 上限，并在验收文档定义人工恢复步骤（未做生产演练）。Release 注册表用 release-only no-op integration_test 插件修复，APK/AAB 构建成功并保持未签名；Bundletool 1.18.3 validate、APK zipalign 与 APK/AAB 7 个 arm64 原生库 ELF 16 KB 静态对齐通过。后续增加 Android 全局 16 项 MCP POST 上限，MCP 请求 deadline 超时会中止 HTTP 请求并关闭会话；Stream/并发/取消回归测试覆盖这些边界。LGE AN10 真机 Android HTTP MCP 集成文件 4 项通过，外部 HTTPS 测试跳过；Flutter 全量 211 项、analyze、格式/边界/共享包门禁通过。Codex Security 原差异审查为 0 项可报告漏洞但 coverage partial；外部 HTTPS 当前版本复验仍缺真实 endpoint，Host 账本维护流程尚未演练。无正式签名、16 KB 真机或 production Host/音乐闭环；Node 24.22.1-0 仍为预发布 fork，`a4-ncm` 样本 npm audit 有 8 条 advisory 且不进入主 App Release。详见 [A8 验收记录](android-a8-acceptance.md)。
- [x] A8.5 新增 [Android 内部测试指南](android-user-guide.md)，并更新[故障排查](troubleshooting.md#android-内部测试)；记录 Android 手机能力、Mac Host 配对、Debug 安装、各能力执行位置、网易云 Mac 音频输出和 A8 实测/未测边界。当前无正式 Android 发布包，文档不能视为发布声明。

**交付物：**A8 验收记录、能力/限制说明和用户/故障指南已完成；Release APK/AAB 可构建但未签名，不是分发候选包。**阶段状态：**A8.4 安全缓解与构建检查完成，A8.5 文档完成。Android 分发验收仍等正式签名、16 KB 实机和 production Host/音乐端到端验证；未通过的 npm/CLI/本地播放能力不进入发布说明或可操作入口。

## 5. UI 验收矩阵

| 场景 | 重点 | 首次检查阶段 | 最终验收 |
| --- | --- | --- | --- |
| 快速调用功能 | 从手机入口找到功能、确认执行设备、填写参数、查看结果 | A2/A6 | A7 |
| 运行与恢复 | 进度、长结果、失败后的重试、活动恢复 | A2/A6 | A7/A8 |
| 窄屏竖屏 / 横屏 | 连接切换、导航、全局搜索、返回 | A1 | A7 |
| 连接向导 | 执行设备先选、字段与文件来源正确、测试/保存/丢弃、`actionRequired` | A1/A2 | A7/A8 |
| 大屏 / 分屏 | 侧栏、表单与结果并列、窗口变化 | A1 | A7 |
| 输入法和手势导航 | 表单提交、终端输入、迷你播放器不遮挡 | A1/A6 | A7 |
| 长文本与复杂数据 | 路径、MCP schema、JSON、大输出不溢出 | A2 | A7 |
| 可访问性 | TalkBack、字体放大、状态与执行位置朗读 | A1 | A7/A8 |
| 离线与故障 | Host 离线、Node 失败、权限拒绝、结果未知 | A2/A6 | A8 |

当前 `AppShell` 有 760 逻辑像素抽屉断点，`TerminalPage` 已复用 `terminal_view`；这只是 A1 技术起点。Android 的页面结构、导航方式、断点和终端输入控件须由手机任务与真机交互决定，不能仅用桌面窄窗口截图验收。

## 6. Skillpilot 结果如何取舍

本次修订重新调用 Skillpilot `plan`（review、security、docs、design、testing、strategy）。它推荐 CodeRabbit、Semgrep、Context7 作为可选工具；均未安装，项目现有测试与源码核对优先。它的 UI/测试清单里“真实设备、表单状态、秘密不入库、失败路径、能力回归”可用于 A1/A2/A7/A8。返回的 React/CSS 组件、Playwright 浏览器测试、Stripe、Vercel 和商业分析是通用模板，不适用于此 Flutter/Android 工程；无需其 `TWENTY_FIRST_API_KEY`。完整可执行的阶段任务、依赖和门槛以本文件 A0–A8 为准。

## 依据与待验证事实

- 当前源码：`app/lib/main.dart`、`app/lib/platform/macos/mac_runtime.dart`、`app/lib/features/connections/connection_setup_dialog.dart`、`app/lib/features/connections/connections_page.dart`、`app/lib/app/app_shell.dart`、`app/lib/features/invocation/terminal_page.dart`、`packages/aggregate_contracts/lib/src/connection_setup.dart`、`packages/aggregate_contracts/lib/src/runtime_port.dart`；历史阶段见[公共层准备](phase4-common-layer.md)。
- [nodejs-mobile 官方仓库与发布包](https://github.com/nodejs-mobile/nodejs-mobile)、[官方 FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)、[Android JNI 示例](https://github.com/JaneaSystems/nodejs-mobile-samples/blob/master/android/native-gradle/README.md)。
- [Android 10 可执行文件限制](https://developer.android.com/about/versions/10/behavior-changes-10)、[16 KB 页要求](https://developer.android.com/guide/practices/page-sizes)、[动态代码加载建议](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)、[Google Play 开发者政策](https://support.google.com/googleplay/android-developer/answer/18265346)。
- [Node.js 版本维护状态](https://nodejs.org/en/about/previous-releases)、[Flutter 自适应布局](https://docs.flutter.dev/ui/adaptive-responsive/general)、[Media3 后台播放](https://developer.android.com/media/media3/session/background-playback)、[flutter_pty2 支持情况](https://pub.dev/packages/flutter_pty2)。
- [网易云 CLI npm 包](https://www.npmjs.com/package/%40music163/ncm-cli)的发布版本/依赖来自 npm registry 元数据，Android 行为按 2026-11-13 的 LGE AN10 真机固定样本记录于 [A4 实验记录](android-a4-progress.md)；不外推到其他设备、ABI、Node 构建或 16 KB 页。
