# UI-5：功能、布局与无障碍回归

> 状态：阶段实施完成，验收部分通过。未完成项按实记录在文末；UI-6 可继续测性能，但不会替代这些验收。前置：[UI-4](stage-4-page-adaptation.md)通过。

## 具体流程

1. 先运行受影响测试组，再执行完整项目闸门。新增测试聚焦公共点阵、键盘遍历、放大文字和真实状态边界，不以大量重复快照替代行为断言。
2. 对新按钮建立可控时钟的组件测试；按 UI-2/UI-3 核对图案、中间态、连击、反向、可见性、减少动态效果和独立业务回调次数。
3. 更新截图工具，使装饰时钟可控、截图相位固定；明确执行 `app/tool/ui_review_test.dart`，因为它不在 `flutter test test` 的自动范围内。截图检查使用独立的 `ManualGlassMotionClock`，不关闭产品动画时钟。
4. 用 Profile 预览与自动化 fixture 覆盖中文、长内容、错误、取消、超时和未知终态；不触发真实连接、Host 授权或有副作用的 Runtime 操作。
5. 通过 widget 键盘测试和原生 macOS AX 树检查焦点顺序、按钮名称和状态表达；未直接启用系统 VoiceOver 朗读。图案装饰不能成为重复的可访问节点或每帧朗读内容。
6. 将自动测试、原生目视、AX 树、VoiceOver 和真实 Runtime 的结果分别记录；已补充设置页浅深主题的正文、主题标签、点阵核心和焦点环合成像素抽样；其他页面与完整状态矩阵仍未覆盖。

## 现有检查命令

以下命令在 `app/` 执行，本次文档编写未运行它们：

```sh
flutter test --no-pub test/glass_theme_switch_test.dart test/theme_switch_simulation_test.dart test/theme_switch_realtime_test.dart test/theme_switch_calibration_test.dart test/theme_switch_optics_test.dart
flutter test --no-pub test/widget_test.dart test/connection_experience_test.dart test/capability_run_page_test.dart test/schema_form_test.dart test/connection_setup_dialog_test.dart test/workspace_search_semantics_test.dart test/accessibility_test.dart
flutter test --no-pub test/music_queue_controls_test.dart test/music_mini_player_test.dart test/music_account_control_test.dart test/mac_host_settings_panel_test.dart
flutter test --no-pub tool/ui_review_test.dart
```

在仓库根目录执行完整闸门：

```sh
sh tool/check.sh
```

当前闸门包括锁文件依赖恢复、格式、静态分析、公共层边界、公共包测试、App 测试和 macOS Debug 构建。它不包含 Profile 性能、截图工具执行或原生交互巡检。依赖准备失败应单独记录，不借此升级无关依赖。

首次建立新视觉基线时，在完成固定相位改造后使用 `flutter test --no-pub --update-goldens tool/ui_review_test.dart` 生成候选图，逐张审阅后才接受；之后使用上面的普通比较命令。不能为了消除失败批量重录模型/光学 oracle，截图路径和必要基线的归档方式也要随工具改造明确。

## 布局与状态矩阵

| 维度 | 最低覆盖 |
| --- | --- |
| macOS 窗口（逻辑像素） | 800×600、1024×768、1440×900；640×600 保留现有紧凑回归，不由此承诺新的最小窗口规格 |
| 主题/缩放 | 深/浅色；1×/2×；系统模式与手动模式切换 |
| 视图 | 音乐、CLI、MCP、所有功能、管理、活动、设置；主要弹窗 |
| 按钮状态 | 正常、hover、focus、pressed、disabled、busy、selected、危险确认 |
| 内容 | 中文/英文混排、长名称/路径、多行帮助、复杂表单、空结果与错误 |
| 动态偏好 | 正常/减少动态效果；前台/后台；可见/离屏 |

320 px 浏览器设计预览是参考能力，不替代本轮 macOS 原生尺寸验收。测试字体无法准确覆盖中文时，原生窗口补验中文排版，不把缺字截图当最终基线。

## 验收标准

- [x] **UI-5.1** 原主题组、相关业务组、新组件组和完整项目闸门均通过；三模拟/校准文件不变，其余主题文件只有 UI-0/UI-1 规定的呈现差异，逻辑与默认参考路径原期望值保持。完整 `sh tool/check.sh` 使用已提交的基线锁文件在隔离验证后通过；还原后工作树中的原有锁文件改动仍会使依赖恢复步骤退出，见验收记录。
- [x] **UI-5.2** 覆盖三种逻辑尺寸、浅深主题、DPR 1/2 与 9 个预览路由状态；DPR 1 对照 54 张金样，DPR 2 对所有状态运行布局/渲染错误检查。640 px 紧凑窗口沿用既有回归；这不代表原生 1× 显示器验收。
- [x] **UI-5.3** Tab/Shift-Tab 顺序符合视觉顺序；按钮可按其原生键盘语义激活且只调用一次；⌘K 聚焦搜索，⌘↵只运行当前可用任务，弹窗不触发背景任务，Esc 后焦点恢复。由 widget 测试验证。
- [ ] **UI-5.4** 部分通过：Flutter semantics 回归覆盖图标名称、播放/暂停状态名称、禁用/忙碌与装饰节点隔离；原生 AX 抽查覆盖主要控件名称。Flutter 3.47.8 的禁用控件仍报告 `AXEnabled=true`；2026-11-17 Flutter 3.50.0 Profile 复测中，标准 Material 按钮、显式 `Semantics` 按钮、禁用状态文本和玻璃按钮均变成不可读 AX 节点，启用按钮可读；AX 增强树在应用启动前开启也未改变结果。框架层 15 项定向测试确认禁用节点仍有名称、button flag、`isEnabled=false` 且无 tap action。问题因此指向 Flutter/macOS 原生 AX 导出路径，精确 engine 源码根因尚未定位；不能将“禁用/忙碌可被识别”整体标为通过。实际 VoiceOver 朗读顺序仍未完成，详见验收记录中的 3.50.0 精确定位复测。
- [ ] **UI-5.5** 实际合成背景上，项目目标为普通文字对比度至少 4.5:1、关键图形/焦点提示至少 3:1。新增 macOS Profile 设置页浅/深截图像素抽样：正文 14.27:1 / 10.16:1，主题按钮文字 4.74:1 / 7.47:1，太阳/月亮点阵核心 4.93:1 / 7.65:1，均达到目标。选中态光弧的局部探索值为深色 2.32:1、浅色 1.15:1；目前把它视为次要装饰（状态另由图案、滑块位置和 AX 值表达），不能单独作为焦点/关键图形通过。主题开关的 2px 焦点环已绘于 artwork 前景；2026-11-15 以真实键盘焦点采集 Profile 实窗，按 sRGB 线性亮度对上下左右环段的内外相邻像素抽样，浅/深主题最低分别为 3.30:1 / 3.93:1，达到 3:1 目标。为保证浅色环对比，新增主题专用 `focusRing` 令牌并同步玻璃按钮焦点描边；几何仍由 Widget 回归验证。2026-11-17 Flutter 3.47.8 `ThemeData.lerp` 探针测得进度 0.25/0.50/0.75 时，当前 `GlassDesignTokens.text` 对 `surface` 为 3.747:1 / 1.015:1 / 3.917:1；UI-0 等效基础主题为 4.250:1 / 1.094:1 / 3.603:1。UI-0 源码中的 macOS 全局 560 ms `easeInOutCubic` 主题过渡在当前版仍保留；这不是新增转场时序，当前玻璃配色的模型对比度相较基线在早段较低、中点相近、后段较高，但三处都低于 4.5:1。探针不是 shader 实窗像素。实际过渡帧、禁用态和其他页面材质仍缺完整抽样，UI-5.5 保持部分验收；后续若调整需保留太阳/月亮控件切换逻辑和原 560 ms 转场并做原生复验。
- [x] **UI-5.6** 参数错误不调用 Runtime；权限拒绝不执行；取消/失败/超时/未知终态正确；复制使用真实结果，音乐与 Host 由真实状态驱动。以完整 App 回归和现有 Preview Runtime fixture 测试验证；未连接用户真实服务。
- [ ] **UI-5.7** 增大系统文字或辅助显示设置后，主要操作仍可访问；减少动态效果停止装饰但保留功能；VoiceOver 主要流程走查记录齐全。200% widget 文字测试通过；2026-11-17 的 macOS Profile 实窗验证 AppKit Reduce Motion 已传播到 Flutter、装饰停止且主题切换/按钮点击仍有效。禁用态 AX 有已记录的 Flutter/macOS 导出缺陷，实际系统 VoiceOver 主要流程走查仍未执行，因此本项保持部分验收。
- [x] **UI-5.8** 新 idle 没有造成截图超时或测试永不归稳；固定相位测试与产品动效的边界明确，未用全局永久禁用动画掩盖问题。固定相位预览快照 6 项通过。2026-11-17 的 UI review 将 `ThemeSwitchArtwork` shader 预加载移到 `setUpAll`，避免各 `testWidgets` 异步区等待同一个 Future；12 个完整页面用例重复通过，54 个 DPR 1 金样断言稳定。

对比度是本方案采用的项目验收目标；新 Flutter 叠层已有设置页静态 Profile 像素样本，但未覆盖完整材质/状态矩阵，也未完成软件无障碍认证。UI-6 通过前不能将本阶段截图/Debug 构建称为流畅度验收。详细执行结果见 [验收记录](acceptance-record.md#ui-5功能与无障碍回归)。
