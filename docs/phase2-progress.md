# 阶段 2 进度：macOS 通用平台 MVP

> 历史快照。阶段 2 的本机可验项目已在 2026-11-10 收尾；最新证据与设备限制见[阶段 2/3 本机验收](phase23-acceptance.md)和[阶段 3 进度](phase3-progress.md)。下文“仍待完成”保留阶段 2 结束时的原始记录。

更新：2026-11-09。阶段 2 已开始，核心通路可运行；以下是当前代码与本机验收的记录，不等同于阶段 2 全部验收完成。

## 已实现

| 模块 | 当前行为 | 主要位置 |
| --- | --- | --- |
| 连接 | 添加、刷新、删除 CLI、stdio MCP、HTTP MCP；显示就绪状态、版本和诊断 | `app/lib/features/connections/`、`app/lib/platform/macos/mac_runtime.dart` |
| CLI | 以参数数组启动登记的绝对路径程序；工作目录、环境白名单、30 秒默认超时、1 MiB 输出上限、最多 3 个并行调用、取消、退出码与耗时 | `MacRuntime` |
| 交互终端 | PTY 输入/输出、ANSI/TUI 呈现、尺寸变化、中断、关闭会话 | `app/lib/features/invocation/terminal_page.dart` |
| MCP | stdio 与 Streamable HTTP 握手；分页发现工具/资源/提示；调用、读取、获取提示；刷新或断开后移除失效能力 | `MacRuntime` |
| 目录与表单 | 按名称、描述、来源搜索；目录显示连接来源；基础类型及枚举表单，数组/对象 JSON 输入，UI 和 Runtime 两层校验 | `app/lib/features/catalog/`、`app/lib/features/invocation/schema_form.dart` |
| 结果与权限 | 文本、JSON、MCP 图片、文件路径、isError、退出码/耗时、失败及取消终态；CLI 与未知权限 MCP 工具执行前确认 | `app/lib/widgets/result_panel.dart`、`MacRuntime` |
| 本机数据 | 连接 JSON、最近 100 条脱敏活动；HTTP Bearer Token 经 macOS 钥匙串适配器存取，配置只记录是否有凭证 | `MacRuntime`、`keychain_credential_store.dart` |
| UI | 五页主流程、浅深色主题、响应式侧栏与分栏、全局 ⌘K 返回搜索、连接表单、活动筛选与诊断复制 | `app/lib/app/`、`app/lib/features/`、`app/lib/widgets/` |

真实执行集中在 macOS 适配层。公共契约和 Widget 仍通过 `RuntimePort` 通信，后续可替换为其他平台 Runtime。CLI 动作清单即使声明 `read`，运行时仍按未知权限要求确认；HTTP 明文地址仅允许向本机回环地址发送 Bearer Token。

## 操作方式

1. 在仓库根目录运行 `sh tool/check.sh`，或进入 `app/` 运行 `flutter run -d macos`。
2. 打开“连接”并添加 CLI：填写名称和程序绝对路径。普通调用可在工作台打开“运行 …”，给 `argv` 输入 JSON 字符串数组，例如 `["--version"]`。需要交互时点击“在终端运行”。
3. 添加 stdio MCP：填写 MCP Server 程序绝对路径、启动参数 JSON 数组，以及可选工作目录。添加 HTTP MCP：填写 Streamable HTTP URL，可选填 Bearer Token。添加后状态为“就绪”才会进入工作台目录。
4. 在工作台搜索能力；打开工具后填写参数并确认执行；资源和提示也从各自的能力页读取。活动页只显示运行状态，不保存输入参数和结果正文。
5. CLI 动作可以通过连接时指定已有 JSON 清单导入。清单格式与示例见 `packages/aggregate_connectors/`。图形化动作编辑器排在阶段 3。

## 本机验证

| 检查 | 结果与边界 |
| --- | --- |
| `sh tool/check.sh` | 最终代码改动后重跑通过：格式、分析、公共层依赖边界、公共包/Widget/Runtime 测试、macOS Debug 构建 |
| `dart run app/bin/stage2_smoke.dart` | 通过：`printf` CLI、`cat` PTY 输入/尺寸/中断/关闭、Python MCP fixture 的 stdio 与 HTTP 工具/资源/提示、HTTP 断线后刷新目录、活动脱敏 |
| Runtime 测试 | 通过：未经确认的调用被拒绝、非法 JSON Schema 参数被拒绝、CLI 执行/恢复、动作清单不能自降权限、100 ms 超时、Bearer Token 不进入配置及删除时清理（模拟凭证库） |
| 实际 Debug App | 通过：UI 添加并运行 `printf`、打开 `cat` 终端输入并收到回显、停止后子进程退出；曾发现并修复页面 `setState` 回调和沙盒 PTY 启动问题 |
| UI 复核 | 当前 Debug 构建的独立预览副本中，目视检查深色工作台、连接、活动、设置、连接弹窗，以及浅色工作台和设置；修复连接弹窗字段与浮动标签拥挤。Widget 测试覆盖 640、800、1024、1440 宽度的相关布局、表单校验、运行流程和从运行页用 ⌘K 返回搜索。预览副本已退出并清理 |
| Release App | 本机可启动，识别已有连接；打开 `/bin/cat` 终端后退出 App，确认 App 与 `cat` 子进程均结束。测试创建的 `Cat` 连接已清理。Apple Silicon 设备、macOS 27.2，构建为 arm64 + x86_64，最低系统版本配置为 macOS 12。仅本机 arm64 实跑，x86_64 未实跑 |
| 开发包 | Release `.app` 已压缩为 ZIP；最终 v0.2.0 包解压后 `codesign --verify --deep --strict` 通过，Info.plist 版本为 0.2.0。前一包曾从临时目录实际启动，在当前用户已清空连接的配置下看到“还没有可用功能”，随后正常退出；最终包的代码仅变更版本元数据，未再次做 UI 启动。最终 ZIP SHA-256：`870267913581d20a27f29aea02197da2c17b604ae29cbd7da9495e94c60fa135` |
| UI 更新开发包 | 当前 UI 改动后重新构建 Release 并生成 `Aggregate-macOS-UI-preview-v0.2.0.zip`；解压后 `codesign --verify --deep --strict` 通过，bundle id 与版本为 `io.github.guog962464.aggregate` / `0.2.0`，二进制含 arm64 与 x86_64。ZIP SHA-256：`e5abe09c1329fb6b164311e69d4a784b851e237118820f92219be20bdd355df0`。该包尚未单独启动目视复核；同源 Debug 构建已做原生 UI 复核。签名为 ad hoc，未公证 |

验证基于仓库当前未提交改动和根目录 `pubspec.lock`。MCP fixture 是 `spikes/phase0/fixture_server.py`，使用本机 Python 虚拟环境；它是自建验收样本，尚无第三方 MCP Server 兼容性矩阵。
本阶段代码尚未提交或推送，阶段 2 改动尚未触发远端 CI。

## 仍待完成

> 2026-11-09 补记：阶段 3 已加入显式文件预览/访达定位、资源与提示耗时、原生 Keychain 跨进程读写测试、MCP 有限自动重连及损坏配置备份。以下为阶段 2 结束时的历史状态。HTTP MCP OAuth 和普通 CLI 子进程树清理仍未实现，最新验收边界见[阶段 3 进度](phase3-progress.md)。

- **2.7** 文件结果目前显示路径，尚无文件预览/安全打开；MCP 图片与文本可显示。资源、提示的耗时尚未显示。
- **2.8** 真实 App 内的 macOS 钥匙串写入/重启恢复/删除尚需端到端验收；当前通过的是模拟凭证库测试和构建。OAuth 登录流程尚未实现，现支持静态 Bearer Token。
- **2.10** 开发包已生成，解压后的 App 在当前用户清空连接配置后正常启动；Release App 直接退出时的 `/bin/cat` 清理已实测。仍需另一独立用户配置、不同 macOS 版本及更复杂子进程树的验收。
- **2.11** 五页空状态及基础浅深色已在真实 Debug App 目视复核；仍需用真实 MCP 内容走查长名称、复杂 schema、连接故障和窄窗口。当前有预览数据 Widget 尺寸测试以及真实 CLI 连接/调用/终端走查。
- UI 规划中收藏、编辑/启停连接、独立搜索浮层、设置持久化、音乐视图和迷你播放器尚未实现；见 `docs/ui-design.md` 当前实施状态。
- 异常配置恢复、MCP 自动重连、OAuth、进程树清理、签名/公证与升级迁移留待后续阶段。当前开发构建为临时签名，未公证，不是正式发行包。

为允许用户选择的任意本机 CLI 与 PTY 在 App 内运行，macOS App 已取消 App Sandbox。此决定适用于当前直接分发开发包；正式发行前需确定签名、公证、权限和分发方式，并重新审查执行边界。
