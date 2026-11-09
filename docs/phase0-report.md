# 阶段 0 实施与验证报告

> 2026-11-09 · Aggregate macOS 首版。记录本机观察，阶段 1/2 的实现和跨端兼容性不包含在本报告的通过结论中。

## 结论

阶段 0 的四个通过门槛已在 Apple Silicon Mac 上满足：最小 Flutter macOS App 构建并启动；Dart 客户端对独立 MCP 服务的 stdio 和 Streamable HTTP 传输各完成真实调用；macOS PTY 探针完成交互与进程组清理；公共 UI/契约接口的静态依赖边界通过。当前 App 是导航和布局骨架，尚未在界面中接入 CLI/MCP。

## 0.1 开发环境

| 项 | 本机观察 |
| --- | --- |
| macOS | 27.2 (26B123)，arm64 |
| Flutter | 3.47.8 stable，framework `0efc2569fa` |
| Dart | 3.13.7，macos_arm64 |
| Xcode | 27.2 (27B52) |
| 首发架构 | Apple Silicon；Intel 未测 |
| 最低系统候选 | macOS 12.0（Flutter 生成的 Xcode 工程部署目标）；尚未在 macOS 12 机器上运行 |

`flutter doctor -v` 可完成，macOS 设备可用；诊断提示无法取得 Simulator runtime 列表，当前 macOS 构建和运行未受影响。本版不使用模拟器。

## 0.2 Flutter App 与 0.9 布局

`app/` 是唯一 Flutter App，含系统浅深色主题、工作台/连接/活动/设置四个一级入口、添加连接入口，以及宽度低于 760 px 时的抽屉导航。功能运行是后续阶段加入的任务页，详见 [UI 设计](ui-design.md)。阶段 0 页面只显示骨架与空状态，没有伪造的连接或运行结果。

本机 `flutter analyze` 无问题，`flutter test` 的 6 项通过：系统深色主题、宽屏导航、640×600 窄屏抽屉导航、800/1024/1440 px 长内容样本。布局样本包含长 MCP 工具名、含空格的长 CLI 路径和中文错误文案；截断文本保留完整 Tooltip。`flutter build macos --debug` 构建成功，`.app` 经 `open -a` 启动，进程可见。尚未做真实窗口截图与辅助功能评审；这属于阶段 1/3 的 UI 验收。

## 0.3 平台边界

阶段 0 当时的 `app/lib/core/contracts.dart` 和 `runtime_port.dart` 只依赖 Dart 核心类型；阶段 1 已将其迁入 `packages/aggregate_contracts/lib/`，并更新边界检查路径。Flutter 壳不导入 `dart:io`、`dart:ffi`、MCP SDK 或 PTY 包。实际进程、MCP/PTY 探针仍在 `spikes/phase0`，真实 macOS Runtime 接线属于阶段 2。

## 0.4 MCP 互操作

独立服务端使用官方 Python MCP SDK `mcp 2.3.0`（`MCPServer`），客户端使用 Dart `mcp_dart 2.4.3`。同一个 fixture 分别在 stdio 和 `http://127.0.0.1:8765/mcp` 提供能力。两个传输均观察到服务发现协议 `2026-07-28`，并通过：

| 操作 | stdio | 本机 Streamable HTTP |
| --- | --- | --- |
| 初始化/连接 | 通过 | 通过 |
| 列工具、调用 `add(7,5)` | 通过，结果 `12` | 通过，结果 `12` |
| 列资源、读 `memo://phase0/readme` | 通过 | 通过 |
| 列提示、取 `welcome(name)` | 通过 | 通过 |
| `structuredContent` | 观察到 `{sum: 12}` | 观察到 `{sum: 12}` |

HTTP 服务位于本机 loopback，验证的是远程连接使用的 **Streamable HTTP 协议路径**，尚未验证真实外部网络、代理、TLS 或身份认证。fixture 是自编能力、独立 SDK 实现；结果不能外推到所有 MCP Server。

## 0.5 SDK 能力矩阵

| 项 | `mcp_dart 2.4.3` 阶段 0 结论 |
| --- | --- |
| 协议版本 | 与 Python SDK 2.3.0 握手日志观察到 `2026-07-28`；其他版本未测。 |
| 分页 | `listTools/listResources/listPrompts` 有 cursor 请求与 nextCursor API；多页服务未实测。 |
| 结构化输出 | 两种传输均实际收到 `structuredContent`。 |
| 通知 | SDK 有通知 handler API；列表变化等服务通知未实测。 |
| 取消 | SDK 有请求取消/transport 支持；服务端收到取消和进程停止的端到端语义未实测。 |
| 超时 | 探针给各调用设置 Dart Future 超时，真实慢请求及服务端取消语义未实测。 |
| 认证 | HTTP transport 提供 OAuth provider 接口；未接真实受保护服务。 |
| 断线恢复 | stdio/HTTP 源码提供恢复配置；断线、重连和写入结果未知状态未实测。 |

阶段 1 选用 `mcp_dart 2.4.3` 作为 `McpClientPort` 后的候选实现，保留替换空间。阶段 2 在开放任意外部 MCP 连接前逐项补足上表的互操作验证。参考 [mcp_dart](https://pub.dev/packages/mcp_dart) 与 [Python MCP SDK](https://github.com/modelcontextprotocol/python-sdk)。

## 0.6 CLI / PTY

普通 CLI 探针用参数数组运行 `/usr/bin/printf`，结果正确。PTY 候选 `flutter_pty2 3.0.0` 在本机 Dart CLI 中通过：

1. 启动 Python 交互式 TUI fixture，读取 ANSI 输出与初始 `80×24` 终端尺寸。
2. 调整为 `100×30`，fixture 通过 `SIGWINCH` 报告新尺寸。
3. 输入 `ping`/`quit`，收到回显并正常退出，异步关闭会话。
4. 启动含 `sleep` 子进程的 shell，向 shell 进程组发送中断；父、子进程退出，未留下本次进程。

这证明当前 Mac 的基本 PTY 路径。Flutter `.app` 内的插件打包运行、多个并发会话、复杂 TUI 与脱离进程组的后代清理未测。`flutter_pty2` 文档也将 Unix 后代清理描述为尽力而为。见 [包说明](https://pub.dev/packages/flutter_pty2)。

## 0.7/0.8 契约与选型

- [契约 v1](contracts-v1.md)：ID、连接器清单、权限、状态、错误码、结果语义，以及 `RuntimePort`/`McpClientPort`。
- [ADR 0001](decisions/0001-phase0.md)：Flutter、MCP SDK、PTY 与状态/路由选型及限制。
- [UI 设计](ui-design.md)：五页职责、审美立场、颜色/字体令牌和三个关键页面线框。

## 复现命令

在仓库根目录执行：

```sh
cd app
flutter analyze
flutter test
flutter build macos --debug
open -a "$(pwd)/build/macos/Build/Products/Debug/aggregate.app"
```

MCP/PTY 探针首次运行需要 Python 环境；依赖版本已在 `spikes/phase0/pubspec.lock` 锁定，Python SDK 用 `mcp==2.3.0` 固定：

```sh
cd spikes/phase0
python3 -m venv .venv
./.venv/bin/python -m pip install 'mcp==2.3.0'
dart pub get
dart analyze
dart run bin/phase0.dart stdio fixture_server.py
dart run bin/pty_probe.dart
```

另开终端运行 `./.venv/bin/python fixture_server.py http --port 8765`，再在第一个终端执行：

```sh
dart run bin/phase0.dart http http://127.0.0.1:8765/mcp
```

边界检查：在仓库根目录执行 `sh spikes/phase0/check_boundary.sh`。

## 阶段 1/2 继续验证

阶段 1 建立可运行的 `LocalRuntimePort`、契约序列化、连接器清单校验和完整五页骨架。阶段 2 在 `.app` 内连接真实第三方 CLI/MCP，验证鉴权、分页、通知、取消、超时、断线、TUI 渲染与复杂进程树；再接网易云 CLI。当前阶段不把本机协议探针表述为通用平台已经可用。
