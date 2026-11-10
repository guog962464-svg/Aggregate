# Aggregate

macOS 优先的 CLI/MCP 功能聚合 App。公共层保留跨端接口，当前只构建和验收 macOS。连接后直接进入对应的音乐、CLI 或 MCP 首页；跨连接搜索、通用运行页和动作编辑器仍可使用。当前目标是受信任环境中的预览验收，正式分发暂缓。

## 当前不足与限制

- **端与连接范围：**目前只有 macOS 运行端；Windows、Linux、移动端和 Web 尚未构建或验收，独立远程 Host 也未实现。本地 CLI 可以通过终端使用，但 CLI 没有统一的能力发现协议；要把具体命令变成可搜索、可填写参数的图形化动作，仍需动作清单或可靠的机器可读元数据。MCP 当前接入 stdio 与 Streamable HTTP；HTTP 认证只支持静态 Bearer Token，浏览器 OAuth 尚未实现。
- **网易云账号与搜索：**音乐功能依赖本机 `@music163/ncm-cli` 和 `mpv`。新版添加流程可在 App 内输入 App ID 与 Private Key，先测试本机配置，再保存独立账号目录；保存后在播放器内扫码登录。旧连接仍使用原来的 CLI 配置。每条连接的 CLI 仍只保留一个当前登录账号，Aggregate 无法查询昵称或保存多个账号供一键切回。2026-11-10 本机旧连接的新账号已扫码登录，但 CLI 接口清单返回“用户未授权当前接口”，`ncm-cli commands` 未列出 `search`。扫码登录、开放平台应用凭证和搜索接口可用性是不同条件；见[故障排查](docs/troubleshooting.md)。新版添加流程的真实私钥、扫码和搜索接口链路尚待在当前 Mac 人工验收。
- **验收与分发：**当前 Mac 上的播放、播控和实际出声已由用户在 App 内人工验收；早先 CLI 自动探针曾出现播放状态与空队列不一致，尚未形成稳定的自动回归证据。VoiceOver 搜索结果已能在原生辅助功能树中到达和激活，完整朗读与焦点顺序巡检仍待完成。Intel Mac、macOS 12 和独立系统用户未做实机验收。预览包仅使用 ad hoc 签名，尚无 Developer ID 签名和 Apple 公证，不作为正式分发包；详见[发布检查](docs/release-checklist.md)。

- [阶段 0 实施与验证报告](docs/phase0-report.md)
- [阶段 1 实施与验证报告](docs/phase1-report.md)
- [阶段 2 进度与使用说明](docs/phase2-progress.md)
- [阶段 3 进度与网易云使用说明](docs/phase3-progress.md)
- [阶段 4 跨端公共层准备与验证](docs/phase4-common-layer.md)
- [阶段 5 连接即空间的 UI 改版](docs/phase5-contextual-ui.md)
- [macOS 使用手册](docs/user-guide.md)
- [故障排查](docs/troubleshooting.md)
- [连接器作者指南](docs/connector-author-guide.md)
- [发布检查](docs/release-checklist.md)
- [macOS 首版架构与阶段计划](docs/architecture.md)
- [五页 UI 设计](docs/ui-design.md)
- [契约 v1](docs/contracts-v1.md)
- [ADR 0001](docs/decisions/0001-phase0.md)

唯一 App 在 `app/`，公共包在 `packages/`，可重复的 MCP/CLI/PTY 探针在 `spikes/phase0/`。仓库根目录执行 `sh tool/check.sh` 完成格式、分析、边界、测试与 macOS Debug 构建。依赖由根目录的 `pubspec.lock` 锁定。

当前 macOS App 默认连接真实本机 Runtime。测试和预览入口使用 `createPreviewRuntime()`；该样本位于 `app/lib/preview/`。
