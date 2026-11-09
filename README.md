# Aggregate

macOS 优先的 CLI/MCP 功能聚合 App。阶段 1 已建立单锁文件 Dart workspace、公共契约/领域/连接器/运行包和五页 Flutter 骨架。当前界面使用明确标记的预览数据；真实 CLI/MCP 接入属于阶段 2。

- [阶段 0 实施与验证报告](docs/phase0-report.md)
- [阶段 1 实施与验证报告](docs/phase1-report.md)
- [macOS 首版架构与阶段计划](docs/architecture.md)
- [五页 UI 设计](docs/ui-design.md)
- [契约 v1](docs/contracts-v1.md)
- [ADR 0001](docs/decisions/0001-phase0.md)

唯一 App 在 `app/`，公共包在 `packages/`，可重复的 MCP/CLI/PTY 探针在 `spikes/phase0/`。仓库根目录执行 `sh tool/check.sh` 完成格式、分析、边界、测试与 macOS Debug 构建。依赖由根目录的 `pubspec.lock` 锁定。
