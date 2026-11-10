# 阶段 4：跨端公共层准备

> 日期：2026-11-10
> 范围：只修改共用契约、Flutter 页面和预览测试；运行与验收设备仍是当前 macOS。此阶段不创建其他平台工程，不实现远程 Host，也不发布其他端。

## 本轮目标

阶段 3 的 macOS 运行端已能在 Aggregate App 内完成网易云播放和播控。阶段 4 先处理共用页面对本机能力的隐含假设，让相同页面能接受不同运行端的能力描述。界面上的快捷键则由显示界面的设备决定。阶段 3 尚未关闭的设备和预览验收项保持原状态，见[阶段 2/3 本机验收](phase23-acceptance.md)。

## 实现

| 层 | 本轮改动 | 后续接端时的责任 |
| --- | --- | --- |
| `aggregate_contracts` | `RuntimePort.features` 返回 `RuntimeFeatures`；JSON 使用 `schemaVersion: 1`，包含 `connectionKinds`、`terminal`、`localFilePreview`、`localFileReveal`。未知连接类型和版本直接拒绝解析。 | 新运行端准确报告能力；若扩展字段，先更新契约与版本处理。 |
| `aggregate_runtime` | `PreviewRuntime` 可注入能力描述，供限制能力的页面测试使用。 | 预览数据只作 UI 样本；真实平台实现不能以样本结果替代系统验收。 |
| macOS 适配 | `MacRuntime` 报告当前本地桌面能力；`LocalRuntimePort` 转发该描述。 | 维持当前 macOS 的进程、PTY、钥匙串与文件接线。 |
| 共用 Flutter UI | 添加连接只显示运行端允许的类型；无添加能力时隐藏入口；终端、文件预览、文件定位按能力显示。系统名称和文件管理器文案按 UI 平台显示。 | 连接新运行端时继续检查功能页、连接页和结果页，不绕开能力门控。 |
| 快捷键 | `ShortcutScheme` 集中定义搜索和运行：macOS/iOS 用 Command，其余 UI 平台用 Ctrl；标签和按键使用同一规则。 | 真机检验各平台键盘、焦点及系统快捷键冲突。 |
| 预览与边界 | 样本工厂移到 `app/lib/preview/`；公共层静态检查覆盖该目录并阻止导入 `platform/macos`。 | 新增共享目录时同步纳入边界检查。 |

`RuntimeFeatures` 描述的是**运行端**，不能只看当前设备。例如未来在 Mac 窗口中连接受限远程运行端时，仍应隐藏本地终端和文件操作。快捷键恰好相反，取决于**显示 UI 的设备**。

现有 `RuntimePort` 仍包含终端和本地文件方法，以保持 macOS 接口兼容；页面先检查 `features` 再提供操作。未来若新增远程运行端，未支持的方法应返回明确的 `unsupported` 错误，同时验证已有连接的只读查看和调用路径。

## 验证记录

- 契约测试：能力 JSON 往返、未知连接类型拒绝解析。
- Widget 测试：HTTP-only 添加连接仅呈现 HTTP MCP；无添加权限的运行端不显示添加入口；不支持本地文件操作时隐藏按钮；Windows 规则下 Ctrl+K 聚焦搜索且运行提示为 Ctrl+Enter。
- `sh tool/check.sh`：格式检查、静态分析、公共层边界检查、公共包测试、App Widget 测试和 macOS Debug 构建通过。
- `flutter test tool/ui_review_test.dart`：明确使用 macOS 平台规则，800×600、1024×768、1440×900 的浅深色六组场景，共 36 张基准截图，通过更新后复测。基准图位于 `work/ui-review/`。

这些结果来自当前 Mac 的源代码和测试；Windows 键盘测试是在 Flutter Widget 环境中的模拟，没有运行 Windows 应用，也没有验证 Windows 原生插件、文件权限或打包。实际 macOS 出声验收来自用户在 Aggregate App 内的人工测试，不由本轮截图和模拟测试重复证明。

## 后续接端入口

1. 先确定目标平台和实际运行位置，再实现对应 `RuntimePort`，逐项报告 `RuntimeFeatures`；不要通过 UI 设备猜测运行端能力。
2. 补齐该端的进程、终端、凭证和文件适配，或定义远程 Host 协议；本轮未实现这些组件。
3. 在目标真机验证连接、调用、取消、快捷键、辅助功能、持久化与构建发布。按平台另立兼容矩阵和验收记录。

现有 macOS 预览包仍按阶段 3 的范围使用。没有 Developer ID 证书时，签名、公证和正式分发仍待后续处理。
