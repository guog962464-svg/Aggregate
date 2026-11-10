# Aggregate

macOS 优先的 CLI/MCP 功能聚合 App。公共层保留跨端接口，当前只构建和验收 macOS。连接后直接进入对应的音乐、CLI 或 MCP 首页；跨连接搜索、通用运行页和动作编辑器仍可使用。当前目标是受信任环境中的预览验收，正式分发暂缓。

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
