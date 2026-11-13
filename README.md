# Aggregate

[![macOS checks](https://github.com/guog962464-svg/Aggregate/actions/workflows/macos.yml/badge.svg)](https://github.com/guog962464-svg/Aggregate/actions/workflows/macos.yml)
[GitHub](https://github.com/guog962464-svg/Aggregate) · [Gitee](https://gitee.com/shi-shan/aggregate)

**Aggregate 是一个以 macOS 为当前发布目标的 CLI / MCP 能力工作台。**它把本机命令行工具、MCP 服务和它们公开的功能汇集到统一目录中，帮助用户搜索能力、填写参数、确认权限、执行操作并查看结果。

项目使用 Flutter 与 Dart 开发。CLI 和 MCP 仍由各自的程序或服务执行，Aggregate 负责连接管理、能力发现、交互和运行状态呈现。网易云音乐是内置的示例连接器。

## 项目能做什么

- **接入 CLI：**登记本机命令行程序，直接在终端视图中运行命令或交互式 TUI；也可通过动作清单声明常用命令的参数、输入校验、输出类型和权限，再生成图形化表单。
- **接入 MCP：**连接本地 stdio Server 或远程 Streamable HTTP Server，发现 MCP tools、resources、resource templates 和 prompts，并按能力 schema 展示表单、内容与结果。
- **统一查找与调用：**跨连接搜索能力，按连接用途显示音乐、CLI 或 MCP 首页；支持最近使用、收藏、调用进度、取消和结果查看。
- **连接预检与诊断：**添加连接时先测试、再保存。CLI 会检查程序和动作清单；MCP 会握手并发现能力；连接页提供健康状态、能力列表和诊断信息。
- **权限与活动记录：**运行前展示连接来源和权限要求；写入或控制类操作需要确认。活动记录提供状态、时间和来源，不保存调用参数或结果正文。
- **网易云音乐示例：**通过官方 `@music163/ncm-cli` 与 `mpv` 提供账号扫码登录、歌曲搜索、播放和队列控制界面。功能可用性取决于本机依赖、账号配置及服务端授权。

通用 CLI 没有统一的参数描述协议，因此 Aggregate 可以提供原生命令和终端入口；要生成可搜索、可填写参数的图形化动作，需要连接器动作清单或可靠的机器可读元数据。动作清单格式见 [`connectors/manifest.schema.json`](connectors/manifest.schema.json)，示例见 [`connectors/examples/`](connectors/examples/)。

## 使用流程

```text
添加 CLI / MCP 连接
        ↓
测试连接并保存
        ↓
搜索连接公开的功能
        ↓
填写参数并确认权限
        ↓
运行、查看结果与活动状态
```

音乐连接会打开播放器首页；普通 CLI 连接显示命令和动作；MCP 连接按工具、资源和提示组织内容。需要终端交互的命令可在 PTY 终端视图中运行。

## 架构概览

```text
Flutter App（连接、搜索、表单、终端、结果与活动界面）
                          │
                    RuntimePort 契约
                          │
         ┌────────────────┴────────────────┐
         │                                 │
 macOS 本地运行端（当前发布目标）    Android 适配与 Mac Host（实验阶段）
 CLI / PTY / stdio MCP / HTTP MCP     本机 HTTP MCP / 配对与远程调用
```

共享 Dart 契约、领域模型和 Flutter 组件描述连接、能力、权限与运行状态；平台运行端负责进程、终端、凭证和网络接线。公共层避免依赖 macOS API，便于后续复用。Android 相关代码已进入仓库，但仍按实验阶段验证，不属于当前发布范围。

### 主要目录

| 路径 | 内容 |
| --- | --- |
| `app/` | Flutter App、功能页面以及 macOS / Android 平台适配 |
| `packages/aggregate_contracts/` | Runtime、连接、能力、权限与事件等公共契约 |
| `packages/aggregate_domain/` | 搜索、状态、权限和结果等领域逻辑 |
| `packages/aggregate_connectors/` | CLI 动作清单和连接器定义 |
| `packages/aggregate_runtime/` | 公共运行时与预览实现 |
| `connectors/` | 清单 JSON Schema 和连接器示例 |
| `spikes/phase0/` | MCP、CLI 与 PTY 的技术验证样本 |
| `docs/` | 架构、使用、连接器开发、平台计划和验收记录 |

## 平台与当前状态

- **macOS：**当前发布目标。支持本机 CLI、交互式 PTY、stdio MCP 和远程 Streamable HTTP MCP。macOS 上网易云连接的播放与播控已由用户在 App 内验收。
- **Android：**仓库包含 Android 客户端和 Mac Host 远程运行实现，覆盖本机 HTTP MCP、配对流程、连接向导、活动、账号与终端等部分能力。仍在阶段性开发；production WSS 下完整 CLI、网易云账号与音频链路尚未完成真机端到端验收，16 KB 页面设备也未验收。请参阅 [Android 适配计划](docs/android-adaptation-plan.md) 和 [Mac Host 设计与进展](docs/android-a5-host-design.md)。
- **Windows、Linux、iOS 与 Web：**没有当前版本的构建或验收承诺。

已知边界：

- 远程 HTTP MCP 当前使用静态 Bearer Token；浏览器 OAuth 登录尚未实现。
- 网易云功能依赖 Node.js、`@music163/ncm-cli`、`mpv` 及可用的账号和服务端接口权限。
- Android 目前不是正式发布版本；设备端通用 npm/CLI 运行能力、直接 LAN/Bonjour Host 闭环和 16 KB 真机兼容仍有未完成门槛。
- 当前 macOS 预览构建使用 ad hoc 签名，尚未完成 Developer ID 签名和 Apple 公证，不作为正式分发包。

## 开发与运行

### 环境要求

- macOS 开发环境与 Xcode
- Flutter 3.47.8（Dart 3.13.7）
- 网易云连接需要额外安装 Node.js、`mpv` 和官方 `@music163/ncm-cli`

### 获取源码

```sh
git clone https://github.com/guog962464-svg/Aggregate.git
# 或使用 Gitee 镜像：
# git clone https://gitee.com/shi-shan/aggregate.git
cd Aggregate
flutter pub get --enforce-lockfile
cd app
flutter run -d macos
```

也可以从仓库根目录运行 `sh tool/check.sh`。该脚本会按锁文件解析依赖、检查格式与静态分析、验证公共层依赖边界、运行公共包和 Flutter 测试，并构建 macOS Debug App。CI 使用同一套检查流程，配置见 [`.github/workflows/macos.yml`](.github/workflows/macos.yml)。

## 文档

- [macOS 使用手册](docs/user-guide.md)：安装预览包、添加连接、查找功能和使用网易云播放器。
- [架构说明](docs/architecture.md)：产品边界、运行时接口、分层和实现决策。
- [故障排查](docs/troubleshooting.md)：CLI 路径、MCP 连接、权限和网易云问题。
- [连接器作者指南](docs/connector-author-guide.md)：动作清单与 MCP Server 接入约定。
- [发布检查](docs/release-checklist.md)：当前构建、签名和发布验收状态。
- [Android 适配计划](docs/android-adaptation-plan.md)：Android 实验阶段与验收门槛。

## 项目镜像

- GitHub：<https://github.com/guog962464-svg/Aggregate>
- Gitee：<https://gitee.com/shi-shan/aggregate>
