# macOS 玻璃点阵 UI 阶段验收记录

## UI-0：设计基线与行为冻结

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-0.1～UI-0.5 |
| 结果 | 通过；UI-1 可开始 |
| 基线提交 | `99cb13f7afbc4c01e4f6c9a2cdd51f39a270f5d1` |
| 设计版本 | revision 5；`aggregate-glass-macos-v3.html` SHA-256 `3e3b7cae0abb58ed6519c2f687cd619a4e2201c613ee5153bc18ba4be0305fd7`。同目录 `design-specification-v3.json` 标注 revision 5、macOS-only draft。 |
| 设计参考 | [深色界面图](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/macos-glass-design/refined-interface-dark.png>) 和 [浅色界面图](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/macos-glass-design/refined-interface-light.png>) 均为 1024×766；[深色按钮材质图](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/macos-glass-design/refined-cells-dark.png>) 和 [浅色按钮材质图](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/macos-glass-design/refined-cells-light.png>) 均为 1024×1633，包含 12 类图案、静置说明和各自点击动作。设计稿中的按钮动效为交互模拟，不是逐帧参考视频。 |
| 工作树 | 基线时只有用户已有的 `pubspec.lock` 修改；SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`。本阶段不暂存或恢复此改动。 |
| 运行环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2 (26B123)；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2。内置 Liquid Retina XDR 主屏 3024×1964 像素 / 1512×982 点；当前显示模式 60 Hz。 |
| 原生运行 | `flutter run -d macos --profile --no-pub -t lib/preview_main.dart`；Profile 窗口 800×632 logical px，DPR 2，暗色设置页。该入口使用 `PreviewRuntime` mock，不触达用户连接或真实 Runtime。 |
| 原生截图 | [实施前首页](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage0-profile-current.png>)、[实施前设置页](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage0-profile-settings-current.png>)。当前主题控件所在区域以局部不透明矩形渲染，和窗口其余背景明显断开；记录为 UI-1 的待修项。 |
| 减少动态效果 | 全局 `AppleReduceMotion` 值无法从当前设置读取；本基线未确认系统辅助功能开关。后续由 widget 测试覆盖显式 reduced-motion 状态。 |

### 真实操作与业务归属清单

以下映射用于后续页面样式替换。新按钮反馈只能提示相应操作，不能代替这些业务状态。

| 操作范围 | 现有入口与业务结果 | 约束/验收来源 |
| --- | --- | --- |
| 全局搜索、添加连接、导航、迷你播放器 | [app_shell.dart](../../app/lib/app/app_shell.dart)：搜索回到目录并聚焦；添加打开连接向导；导航切换页面；迷你播放器只切入同一音乐会话。 | `shortcut_scheme.dart`、`widget_test.dart`、`connection_setup_dialog_test.dart`、音乐会话测试 |
| 能力目录 | [workspace_page.dart](../../app/lib/features/catalog/workspace_page.dart)：搜索/筛选、来源与状态、打开能力、收藏/最近使用；结果来自当前 Runtime。 | `workspace_search_semantics_test.dart`、`widget_test.dart` |
| CLI 与 MCP 调用 | [connection_home_page.dart](../../app/lib/features/connections/connection_home_page.dart)、[capability_run_page.dart](../../app/lib/features/invocation/capability_run_page.dart)、[schema_form.dart](../../app/lib/features/invocation/schema_form.dart)、[terminal_page.dart](../../app/lib/features/invocation/terminal_page.dart)：选择工具/资源/提示或命令，填写/校验参数，权限确认，运行/取消，显示真实结果并复制或导出。 | `capability_run_page_test.dart`、`schema_form_test.dart`、连接与权限测试；业务完成/失败只由 Runtime 结果决定 |
| 音乐播放器 | [music_player_page.dart](../../app/lib/features/music/music_player_page.dart)、[music_session.dart](../../app/lib/features/music/music_session.dart)、[music_search_results.dart](../../app/lib/features/music/music_search_results.dart)、[music_mini_player.dart](../../app/lib/features/music/music_mini_player.dart)：搜索、播放/暂停、前后曲、停止/刷新、队列、展开迷你播放器；账号登录/退出由独立账号控制流确认。 | `music_queue_controls_test.dart`、`music_mini_player_test.dart`、`music_account_control_test.dart`；复用单个会话 |
| 连接与动作清单 | [connections_page.dart](../../app/lib/features/connections/connections_page.dart)、连接向导与 [action_editor_dialog.dart](../../app/lib/features/connections/action_editor_dialog.dart)：新增、编辑、诊断、测试、配置动作、授权/修复与移除。危险操作需保留确认。 | `connection_setup_dialog_test.dart`、连接体验测试；禁用/忙碌状态按真实回调保留 |
| 活动记录 | [activity_page.dart](../../app/lib/features/activity/activity_page.dart)：筛选、查看详情、复制诊断、重新打开能力。 | 活动页/连接体验测试；显示脱敏记录 |
| 外观、快捷键、本机数据 | [settings_page.dart](../../app/lib/features/settings/settings_page.dart)、[appearance_selector.dart](../../app/lib/features/settings/appearance_selector.dart)：跟随系统/浅色/深色、任意拖动或键盘切换、保留时长、清空活动、应用快捷键。 | 五个主题开关模型/实时/光学测试、设置与可访问性测试；本轮不改主题逻辑 |
| Mac Host 与配对 | [mac_host_settings_panel.dart](../../app/lib/platform/macos/mac_host_settings_panel.dart)：启动/停止 Host、生成/复制邀请、管理配对设备及访问权限。 | `mac_host_settings_panel_test.dart`；保留平台服务现有操作与授权 |
| 弹窗与危险动作 | 向导、参数表单、动作编辑和连接移除弹窗：明确焦点进入、取消/返回、确认、错误；焦点不能穿透模态层。 | `connection_setup_dialog_test.dart`、动作编辑器和 UI 可访问性测试 |

### 主题逻辑冻结核验

UI-0 开始时这六个文件的 SHA-256 均与 [stage-0-baseline.md](stage-0-baseline.md) 表格一致。三个模拟/校准文件保持逐字节冻结。主题 shader 和组件的默认背景渲染路径也作为参照；UI-1 若扩展 shader，只能为 scene 背景坐标新增可选 uniform，并验证旧默认路径不变。 `AppearanceSelector` 的映射、单次回调和语义仍需由后续阶段继续验收。

### 测试基线

在 `app/` 执行主题光学/实时组与主要业务组：

```sh
flutter test --no-pub test/glass_theme_switch_test.dart test/theme_switch_simulation_test.dart test/theme_switch_realtime_test.dart test/theme_switch_calibration_test.dart test/theme_switch_optics_test.dart test/widget_test.dart test/connection_experience_test.dart test/capability_run_page_test.dart test/schema_form_test.dart test/connection_setup_dialog_test.dart test/workspace_search_semantics_test.dart test/accessibility_test.dart test/music_queue_controls_test.dart test/music_mini_player_test.dart test/music_account_control_test.dart test/mac_host_settings_panel_test.dart
```

结果：74 tests passed，退出码 0。依赖未更新；该命令使用 `--no-pub`。

### 原生 Profile 帧时基线

| 操作 | 预期/实际 |
| --- | --- |
| 预热 15 秒后，在原生 dark Settings 外观选择器上运行待机动画并采集 30 秒；阈值按 60 Hz 的 16.667 ms 计算。 | 使用临时 `SchedulerBinding.addTimingsCallback` 观察 `FrameTiming`，记录 1516 个帧样本。该过程只观测 Flutter build/raster 时间，不能声称是显示扫描/真实展示 FPS。入口文件已恢复，探针没有进入仓库。 |
| Build | P50 0.799 ms，P95 1.689 ms，P99 1.785 ms，最大 2.986 ms；超过 16.667 ms：0/1516。 |
| Raster | P50 0.669 ms，P95 1.192 ms，P99 1.315 ms，最大 6.894 ms；超过 16.667 ms：0/1516。 |
| Vsync 至光栅完成 `totalSpan` | P50 1.742 ms，P95 3.043 ms，P99 3.282 ms，最大 10.053 ms。 |
| 静态首页第一次采样 | 因页面没有持续帧而得到 0 个 `FrameTiming`，不纳入基线，也不标记通过。之后在运行中动画的设置页重新完成完整 30 秒采样。 |

**结论：**这是实施前设置控件待机态的 Profile 基准。在该特定场景中所有收集的 Flutter build/raster 时长低于 60 Hz 帧预算。后续需要对交互点击、拖动、导航、音乐页、低端尺寸和发布构建实际复测；本次样本不代表其他页面或发布包。

## UI-1：统一背景与材质令牌

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-1.1～UI-1.5 |
| 结果 | 通过；UI-2 可开始 |
| 基线提交 | UI-0：`297762e82730b8a99f324b190796c80aae426a9b`；本阶段以唯一中文提交标题单独提交，SHA 见 Git 历史。 |
| 设计版本 | revision 5；设计 HTML SHA-256 `3e3b7cae0abb58ed6519c2f687cd619a4e2201c613ee5153bc18ba4be0305fd7`。 |
| 运行环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2；内置 Liquid Retina XDR，逻辑 1512×982 点，60 Hz，DPR 2。 |
| 运行入口 | 产品设置页：`flutter run -d macos --profile --no-pub -t lib/preview_main.dart`。材质 fixture：`flutter run -d macos --profile --no-pub -t lib/glass_material_fixture_main.dart`。两者均为 Profile 实窗；fixture 只显示原主题控件与目标材质高度，不接入产品导航。 |
| 实际窗口尺寸 | 800×600、1024×768、1440×900 均指 Flutter 内容区逻辑像素；为适配原生标题栏，分别调整外窗高度到 632、800、932 点。六个主题/尺寸组合均已截图。 |
| 原生截图 | [800 深](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-dark-800x600.png>)、[800 浅](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-light-800x600.png>)；[1024 深](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-dark-1024x768.png>)、[1024 浅](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-light-1024x768.png>)；[1440 深](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-dark-1440x900.png>)、[1440 浅](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-glass-fixture-light-1440x900.png>)。另有完整设置页对照： [浅色 1024](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-profile-settings-light-1024-768.png>)、[深色 1024](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage1-profile-settings-dark-1024-768.png>)。 |
| 视觉检查 | 六张 fixture 截图均为 Retina DPR 2 实窗。对照不同窗口尺寸和窗口位置后，背景覆盖全窗；主题控件外围未见局部天空重置边或矩形底板。此处是静态截图对照，不代表录制逐帧审看窗口拖动过程。 |
| 1×/2× | `glass_design_tokens_test.dart` 在 DPR 1 和 DPR 2 下分别构造 800×600 逻辑视口，检查 scene 尺寸与异常；真实 macOS Profile 样本为 DPR 2。未测试原生 1× 显示器。 |
| 主题行为冻结 | `theme_switch_simulation.dart` SHA-256 `2bfa354d3b5511247d213284e36de18b418a7f332545c57f5d3e2625a8906a03`；`theme_switch_calibration.dart` `c0f9cc70fa69462434e62c4ca577576ae03b6dd242d4a2a8a3eb1909cf0cadbd`；`theme_switch_fitted_calibration.dart` `11ffe7ea41b5ebd26d4a59f91dc2c7e98b18dcc794e054d89b6956b4c1febaa7`；`appearance_selector.dart` `83ff338b760c6635eae4ff693acebb92d077baa2f2a939c03fbc4452a5b1ab9f`，均与 UI-0 一致。主题组件只发布渲染时间/明暗值并传入全窗背景坐标；交互模型、指针映射、点击/拖动与回调未改。shader 的零尺寸默认值仍使用原 viewport 背景公式。 |
| 依赖 | 未运行 pub get；`pubspec.lock` 保留 UI-0 前用户已有改动，SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 验证 | `flutter analyze --no-pub`：无问题。`flutter test --no-pub test/glass_design_tokens_test.dart test/glass_theme_switch_test.dart test/theme_switch_simulation_test.dart test/theme_switch_realtime_test.dart test/theme_switch_calibration_test.dart test/theme_switch_optics_test.dart test/android_theme_transition_test.dart test/android_shell_test.dart`：30 项通过。覆盖 DPR 1×/2× viewport、场景坐标、原主题光学/模拟/实时/校准、macOS 主题过渡，以及 Android 外观过渡与 shell。macOS 颜色预期按新增 macOS palette 更新。 |
| 平台边界 | `AggregateApp` 仅 macOS 包装 `GlassScene`；macOS `Scaffold`/侧栏透明以显示 root shader。Android/Windows 保留原主题分支；Android 相关测试通过。公共玻璃组件只依赖 Flutter/Dart。 |

## 后续阶段

UI-2～UI-6 在各阶段实施完成后追加各自的验收项，保留失败、未测项和对应提交号。用户对最终材质的主观确认仍与自动化、Profile 数据分开记录。
