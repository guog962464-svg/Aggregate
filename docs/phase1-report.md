# 阶段 1 实施与验证报告

> 2026-11-09 · Aggregate macOS。阶段 1 交付公共层与 App 骨架，界面使用预览数据。真实 CLI/MCP 和终端属于阶段 2。

## 已完成

| 任务 | 实施结果 |
| --- | --- |
| 1.1 workspace | 根 `pubspec.yaml` 管理 App、四个公共包和探针；根 `pubspec.lock` 为唯一锁文件。根 `AGENTS.md`、`analysis_options.yaml` 和 `tool/check.sh` 已建立。 |
| 1.2 contracts | `aggregate_contracts` 实现连接、能力、ID、权限、协议版本、结果块、运行事件与错误的模型及 JSON 往返；定义 `RuntimePort`/`McpClientPort`。 |
| 1.3 domain | `aggregate_domain` 实现连接和运行状态转换、能力搜索/过滤、收藏/最近使用、MCP 结果块归一化。 |
| 1.4 connectors | `aggregate_connectors` 解析 [清单 schema](../connectors/manifest.schema.json)，验证平台、动作、占位符、参数类型和超时；[Git 示例](../connectors/examples/git-status.json) 与音乐无关。 |
| 1.5 runtime | `aggregate_runtime` 提供纯 Dart 预览运行器，生成顺序事件、成功/失败/取消结果；macOS `LocalRuntimePort.preview()` 转发到它。 |
| 1.6/1.9 UI | 一个 `AggregateApp`、系统浅深色主题、宽/窄布局、四个一级入口、功能运行页，以及搜索、表单、结果、连接、活动、设置、空/加载/错误组件。 |
| 1.7 主流程 | 预览 MCP 工具可搜索、填写两个整数、校验非法值、运行并显示结构化结果；返回后活动页可见记录。搜索输入支持 Enter 打开首个结果。 |
| 1.8 检查 | `.github/workflows/macos.yml` 和 `tool/check.sh` 覆盖锁文件、格式、分析、公共层测试、Widget 测试、边界及 macOS Debug 构建。 |

## 架构边界

`app/lib/app/`、`features/`、`widgets/` 只接收 `RuntimePort`，不导入系统进程或 MCP SDK。`app/lib/platform/macos/local_runtime_port.dart` 是注入点；当前后端是预览运行器。`spikes/phase0/check_boundary.sh` 对所有公共包和通用 Flutter 页面执行静态依赖检查。

`PreviewRuntime` 的数据和结果均在 UI 标注“预览”。添加连接按钮会说明阶段 2 才能接入真实连接；终端端口明确抛出 `UnsupportedError`。此设计让阶段 1 主流程可验收，同时不会向用户显示虚假的执行成功。

## 本机验证

环境为 macOS 27.2 arm64、Flutter 3.47.8、Dart 3.13.7、Xcode 27.2。根目录运行 `sh tool/check.sh`，结果：

- 单一 lockfile 的 `flutter pub get --enforce-lockfile` 通过；格式与 `flutter analyze` 通过。
- 公共包 10 项测试通过：模型和资源/提示/终端契约 JSON 往返、未知枚举拒绝、运行终态约束、重名来源/搜索/收藏、结果归一化、清单合法/非法输入、预览运行事件与取消。
- Flutter 8 项 Widget 测试通过：深色主题、宽窄导航、五页入口、预览调用、表单错误、活动记录、键盘搜索和三种窗口宽度。
- 公共层依赖边界脚本通过；`flutter build macos --debug` 成功，生成 `app/build/macos/Build/Products/Debug/aggregate.app`；随后重新启动该 `.app`，观察到新的 macOS 进程。

GitHub Actions 工作流已创建，但仓库尚无可查询的远端 CI 运行结果。阶段 1 没有测试真实 CLI/MCP 执行，也没有完成完整视觉截图和辅助功能评审。

## 下阶段接口

阶段 2 在同一 `RuntimePort` 后增加真实连接配置、本机进程/PTY 与 MCP 传输，补充权限、凭证和日志持久化。复杂 JSON Schema、远端鉴权、取消与断线处理按 [架构计划](architecture.md) 和 [ADR 0001](decisions/0001-phase0.md) 验收。当前预览数据不构成“任意 CLI/MCP 已可接入”的结论。
