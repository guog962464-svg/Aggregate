# ADR 0003：Android 本地 Node、npm 与 CLI 能力边界

状态：已接受，2026-11-13；适用于 Android 首版规划，不代表发布资格已通过。

## 决定

Android 首版通过 Flutter/Dart 提供已在真机验收的远程 HTTP MCP 能力。任意 npm 包安装、Node CLI、TUI、stdio MCP 与外部程序不作为手机本地能力；后续由配对的 macOS Host 执行，且在 A5/A6 完成前不对 Android 用户开放。只有在 A3.6 发布门槛通过后，才可评估随 APK 固定版本打包、经摘要验证并由明确入口调用的 JavaScript 模块；这不等于允许用户输入包名、运行 npm、安装生命周期脚本或执行任意 CLI。

## 依据

- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页上的 `@music163/ncm-cli@0.1.7` 样本能返回版本结果，但配置依赖 TTY，实际 README 搜索命令在发布包中不存在，音频链出现 `Unsupported platform`，TUI 缺少 mpv；真实登录、播放和出声未通过。`ffprobe-static` 不包含 Android/arm64 目标；A4.5 还观察到应用私有 Node 子进程无法正常启动。详见 [A4 真机记录](../android-a4-progress.md)。
- 固定 JSON5 纯 JS 包与受限 npm 安装已在同一台 4 KB 设备完成部分 Debug 样本；这证明具体包/入口样本可运行，不证明任意 npm 依赖、CLI、TUI、脚本或 addon 可用。
- 当前 Node 24 Android 构建仍未满足 A3.6 的稳定维护来源、许可/漏洞响应和真实 16 KB 页设备门槛；目标发行渠道对动态脚本分发/运行时安装的审查也未完成。

## 能力矩阵

| 层次 | Android 首版决定 | 当前状态 |
| --- | --- | --- |
| T1：远程 HTTP MCP | 通过手机 Dart Runtime 连接本机回环或 HTTPS 服务 | A2 真机验证已完成；保留已验收范围 |
| T2：受控本地 JavaScript | 仅考虑随 APK 固定、摘要可复现、入口白名单化的包；A3.6 未过前不接入产品 | JSON5/npm 为 Debug 证据；生产白名单暂为空 |
| T3：用户安装的 npm 包、任意 CLI/TUI/stdio MCP | 不在手机本地运行；转交 macOS Host | Host 的 A5/A6 配对、路由和用户流程尚未交付 |
| `@music163/ncm-cli@0.1.7` 本地播放 | 不支持 | 配置/平台/搜索/mpv 阻断；声音链路未验收 |

## 后续门槛

A3.6 必须选定有维护责任的 Node Android 构建，核对来源和许可证，完成目标 ABI 与真实 16 KB 页验收。Aggregate 发布维护者负责固定运行时/ABI 来源、跟踪上游与依赖安全公告、评估更新并维护回归证据；未修复的高危问题阻断发布。发行前需按目标商店审查运行时脚本来源与安装策略。若未来要把具体 JS 包加入本地白名单，应逐包锁定依赖与摘要、禁用未批准生命周期脚本、限制入口与文件/网络能力，并补齐升级、取消、恢复、资源回收和安全审查；任何一次变更都不能自动扩大白名单。
