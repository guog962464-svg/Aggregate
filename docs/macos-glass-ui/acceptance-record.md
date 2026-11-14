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

## UI-4：页面布局与按钮位置适配

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-4.1～UI-4.7 |
| 结果 | 通过；UI-5 可开始。七个页面域已接入共享点阵玻璃按钮；页面状态源、回调、忙碌/禁用条件和原主题逻辑保持。 |
| 设计版本 | revision 5；基线 HTML SHA-256 `3e3b7cae0abb58ed6519c2f687cd619a4e2201c613ee5153bc18ba4be0305fd7`。 |
| 代码范围 | App 外壳/搜索、连接与能力运行、MCP/CLI 结果和终端、音乐主页与迷你播放器、功能目录、活动、设置、Mac Host 面板、共享按钮封装和点阵字形。保留平台无关封装；视觉玻璃仅在 macOS + `GlassMotionScope` 下启用，其他平台继续走 Material 回退。 |
| 真实界面操作 | Profile 预览入口原生检查：全功能目录行左对齐；连接页呈现左侧列表和右侧详情；CLI 能力执行返回预览结果；设置页背景连续，主题控件、快捷键和危险操作位置可辨；展开“清空记录”确认后取消，未删除记录。音乐页搜索/结果及迷你播放控件在先前 UI-4 子组检查中核对。 |
| 弹窗与权限边界 | 预览添加连接只显示“不能添加真实连接”说明。正式 Mac Host Profile 中确认 Host 处于停止状态及权限/身份面板布局；未启动监听、生成邀请、批准/撤销真实设备或打开正式授权弹窗。权限选择和授权/撤销路径由 `mac_host_settings_panel_test.dart` 的模拟平台服务覆盖（4 tests passed）；连接向导/动作编辑/删除及危险确认由既有 Flutter 测试覆盖。 |
| 原主题 | `glass_theme_switch.dart`、模拟与校准文件均未改；`appearance_selector.dart` 只把“跟随系统”入口接入统一按钮外观。主题映射和回调由原主题回归验证。 |
| 自动检查 | `dart format`：无格式差异；`flutter analyze --no-pub`：无问题；`flutter test --no-pub`：268 tests passed（更新 paste glyph 后重录两张字形 golden，4 项 DPR/明暗 golden 通过）；UI-4D 最后权限按钮修正后重新执行 Host 面板测试：4 tests passed，分析无问题。 |
| macOS 构建 | `flutter build macos --profile --no-pub -t lib/preview_main.dart` 与 `flutter build macos --profile --no-pub -t lib/main.dart` 均成功；正式入口 Profile 76.4 MB。预览设计操作不触达真实 Runtime。 |
| 工作树 | 保留用户原有 `pubspec.lock` 修改，未纳入本阶段；点阵字形 golden 更新仅对应新增粘贴图案及画廊布局。 |
| 限制 | 窗口缩放矩阵、完整 VoiceOver、实际 Host 授权弹窗与真实外部连接流程留给 UI-5/用户已有安全操作边界；CUA 截图只在任务界面查看，未导出到仓库证据目录。 |
| 提交 | UI-4 独立提交与双远端核对；SHA 见 Git 历史。 |

## 后续阶段

## UI-2：统一按钮与细腻点阵

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-2.1～UI-2.6 |
| 结果 | 通过；UI-3 可开始。UI-2 样本通过不代表产品页面接入、连续动效或最终视觉签收完成。 |
| 基线 | UI-1 已提交 `40e44f29f1aae0710d09c44f49e44bdcd4b9631b`；UI-2 开始前当前分支 HEAD 为 `3767d44`。本阶段以独立中文提交交付，具体 SHA 可在 Git 历史中定位。 |
| 设计版本 | revision 5；设计 HTML SHA-256 `3e3b7cae0abb58ed6519c2f687cd619a4e2201c613ee5153bc18ba4be0305fd7`。静态对照来自 `macos-glass-design/refined-cells-dark.png` 与 `refined-cells-light.png`，每个参考按钮为 96 dp。 |
| 环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2；Liquid Retina XDR，1512×982 逻辑点、60 Hz、DPR 2。 |
| 原生运行 | `cd app && flutter run -d macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart`。Profile/Impeller Metal，窗口 1120×860 logical px；浅深主题在同一窗口切换检查。fixture 不注册到产品导航，所有按钮操作均为空回调，顶部主题控件复用原 `GlassThemeSwitch`。 |
| 样本 | 12 个 96 dp 参考图案、12 类实际按钮/状态（主操作、次级、图标、播控、导航、分段、危险、忙碌、禁用等），以及 57 项完整点阵字典；当前 `app/lib` 中 81 个 `Icons.*` 名称均映射到 `GlassGlyphCatalog`。生产页面替换安排在 UI-4。 |
| 原生截图 | [96 dp 深色对照](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-reference-buttons-dark-final.png>)、[浅色对照](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-reference-buttons-light-final.png>)；[深色按钮状态](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-actions-dark-full.png>)、[浅色按钮状态](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-actions-light-full.png>)、[浅色完整图案字典](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-glyph-gallery-light-final.png>)、[深色焦点态](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-button-focused-dark-final.png>)、[深色悬停态](</Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage2-button-hover-dark-final.png>)。所有原生 PNG 为 Retina DPR 2。 |
| 视觉对照 | 同主题、静止相位、96 dp 控件并列检查。网格为 9×9、设计画布32×32、origin4、pitch2.7、core1.9、圆角0.64；小图案核心和间隔清楚。Flutter 样本有渐变玻璃底、内倒角、接触边、共享圆角点阵及状态光弧。相对 revision 5，Flutter 外部环境光晕更克制，且没有背景折射、RGB 色散和设计稿的强外扩暖/蓝辉；这些是逐项记录的跨实现差异，最终质感由 UI-6 结合正式页面复核。 |
| 1×/2× | `glass_glyph_golden_test.dart` 在 DPR 1 和 DPR 2、浅/深外观下绘制全部 57 个图案并对照逻辑尺寸 golden；4 项通过，基线见 `app/test/goldens/glass_glyph_light.png`、`glass_glyph_dark.png`。真实 macOS Profile 显示器为 DPR 2；未连接原生 DPR 1 显示器，因此没有把 Widget golden 描述为物理 1× 屏验收。 |
| 语义与行为 | 新按钮基于 Flutter `TextButton`，保持名称、焦点、选中/启用语义和目标尺寸；Enter 与鼠标各触发一次回调，忙碌/禁用不提供 tap action。无障碍树确认焦点状态；原生深色焦点/悬停截图检查专用内外环。 |
| 缓存与平台 | 点阵几何仅按有限 `GlassGlyph` 枚举惰性缓存为 `Path`，无 shader、纹理或 image handle。组件只依赖 Flutter/Dart；新视觉只在 macOS fixture 预览，生产页面留给 UI-4。原太阳/月亮切换、偏好与系统映射未改。 |
| 逻辑冻结 | `theme_switch_simulation.dart` SHA-256 `2bfa354d3b5511247d213284e36de18b418a7f332545c57f5d3e2625a8906a03`；`theme_switch_calibration.dart` `c0f9cc70fa69462434e62c4ca577576ae03b6dd242d4a2a8a3eb1909cf0cadbd`；`theme_switch_fitted_calibration.dart` `11ffe7ea41b5ebd26d4a59f91dc2c7e98b18dcc794e054d89b6956b4c1febaa7`；`appearance_selector.dart` `83ff338b760c6635eae4ff693acebb92d077baa2f2a939c03fbc4452a5b1ab9f`，均与 UI-0 一致。 |
| 依赖与用户改动 | 未运行 `pub get`；`pubspec.lock` 仍保留用户原有修改，SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 验证 | `flutter analyze --no-pub`：无问题。`flutter test --no-pub test/glass_action_button_test.dart test/glass_glyph_golden_test.dart test/glass_design_tokens_test.dart test/glass_theme_switch_test.dart test/theme_switch_realtime_test.dart test/theme_switch_optics_test.dart test/theme_switch_calibration_test.dart test/theme_switch_simulation_test.dart test/glass_theme_switch_android_test.dart test/android_theme_transition_test.dart`：47 项通过。覆盖 glyph catalog、1×/2×浅深 golden、名称/键盘/鼠标/忙碌禁用/尺寸语义及主题光学与实时回归。 |

## UI-3：静置、点击与连续操作协调

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-3.1～UI-3.8 |
| 结果 | 通过；UI-4 可开始。新动作时钟、点阵绘制和打断行为已经实现，生产页面的逐页接入留在 UI-4；这阶段的 fixture 点击仍不连接真实业务。 |
| 运行入口 | `cd app && flutter run -d macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart`。Profile 窗口经 CUA 原生查看，Impeller/Metal；画面为暗色、1120×860 logical px、Retina DPR 2。Flutter CLI 曾报告 `Failed to foreground app; open returned 1`，随后 CUA 成功取得窗口并实际点击刷新按钮。 |
| 原生观察 | 暗色 idle 样本及刷新点击中样本均可见；点阵在刷新动作中保持分离，按钮外壳光弧与内部字形同帧变化。CUA 截图在任务界面即时查看，但未导出到仓库；UI-6 仍需保存正式页面的深浅原生截图和最终质感对照。 |
| 共享时钟 | 每个页面/路由一个 `GlassMotionScope` + 单个 monotonic `Stopwatch`/`Ticker`；每个按钮使用唯一稳定 phase seed，不建立独立 ticker。idle 对 painter 的广播合并至约 30 Hz；操作、morph、hover/focus 到显示节奏。`frameTime` 冻结在共享帧边界，使 surface energy 与 glyph sample 读取同一时刻。 |
| 动作与中断 | 12 个动作族使用 UI-3 表列时长、`sin²(πt)` 脉冲和 smootherstep；字形、颗粒亮度和边缘光弧从同一脉冲采样。连续点击保留首个姿态旅程并叠加能量；播放/暂停 morph 用当前点位/alpha 重配最近邻颗粒，新增/离开颗粒淡入/淡出。hover/focus 320 ms、能量不超过 0.15；按下拖出仍取消业务调用。 |
| 可见性与减少动态效果 | Flutter `TickerMode`、`AppLifecycleListener`、scroll/metrics/size notifications + viewport 相交检测。路由或窗口暂离时不继续采样；完全离屏按钮从共享 client set 移除；恢复时按单调时钟求当前帧。`MediaQuery.disableAnimations` 会注销装饰时钟，点击/语义仍可用。 |
| 组件性能 | 每按钮 `RepaintBoundary` 隔离；文字标签另有 repaint boundary。动态 glyph 将同 alpha 档颗粒合并为有限数量的核心与 halo `Path`，没有为每颗粒各自绘制模糊层，也无 shader、image handle 或纹理。实际 Profile frame timing 将在 UI-6 单独采集，当前未据此声称满足帧预算。 |
| 测试 | `flutter analyze --no-pub`：无问题。定向命令覆盖 `glass_motion_test.dart`、原 UI-2 button/glyph/tokens 测试、主题实时/光学/校准/模拟，以及既有 Android theme tests：57 项全部通过。用例包括 12 动作 0/0.25/0.5/0.75/1、点击前后同时间戳连续、100 ms×10 连点和 10 次真实回调、100/200/350 ms 反向 morph、hover/drag cancel、TickerMode/后台恢复、离屏注销、reduced-motion 开关及 30/60/120 Hz/不规则时钟序列。 |
| 主题逻辑冻结 | 本阶段没有改 `theme_switch_simulation.dart`、`theme_switch_calibration.dart`、`theme_switch_fitted_calibration.dart`、`appearance_selector.dart` 或太阳/月亮控件。现有主题实时、光学、模拟、Android 主题回归均纳入定向验证。 |
| 范围与限制 | 点阵按钮生产页面仍未接入；UI-4 开始后对每种真实业务操作逐页替换和验收。本阶段 profile preview 只检视暗色，且没有导出 PNG、物理 DPR 1 或真实 VoiceOver 观察。UI-6 仍需在完整页面、浅深主题及目标机器上采集图像与帧计时。 |

## UI-5：功能与无障碍回归

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-5.1～UI-5.8 |
| 结果 | 自动化、键盘、语义、参数保护、reduced motion、放大文字与两种 DPR 的页面布局回归通过。UI-5.5 的实际合成像素采样及 UI-5.7 的系统 VoiceOver 语音走查未完成；不以自动化结果代替这些证据。 |
| 环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2；内置 Liquid Retina XDR，逻辑 1512×982 点、60 Hz、DPR 2。App 自动化运行于 Flutter test；原生 AX 树抽查使用 Profile `Aggregate.app`。 |
| 页面矩阵 | `app/tool/ui_review_test.dart` 固定 `ManualGlassMotionClock`，以 `FakeAccessibilityFeatures(disableAnimations: true)` 固定装饰相位但保留路由动画。800×600、1024×768、1440×900 × 浅/深 × DPR 1/2 × 9 个音乐/连接/设置/目录/运行预览状态；DPR 1 用 `work/ui-review/` 的 54 张金样比对，DPR 2 同样走完整路由和布局错误检查。12 项通过。图像使用测试字体，中文字符可能呈方框，仅用于结构与路由回归；不能作为中文字体验收。原生 Profile 窗口已目视确认中文可读，但 CUA 截图未导出归档。 |
| 组件覆盖 | `glass_action_button_test.dart` 检查所有点阵在浅/深主题和 DPR 1/2 的绘制、200% 文字操作、Enter 激活、Tab/Shift-Tab 顺序和回调次数。完整 UI-2 glyph golden 仍在原阶段验证；UI-5 的整页面金样没有 DPR 2。`accessibility_test.dart` 以 token 组合覆盖浅深材质端点的文字/图形目标；不含 shader 像素读回。 |
| 键盘与安全 | `widget_test.dart`、`capability_run_page_test.dart`、`glass_action_button_test.dart` 验证 ⌘K 搜索焦点、⌘↵打开确认但不执行背景任务、显式确认一次、Esc 取消并恢复输入焦点、Enter 激活一次及 Tab 顺序；相关断言通过。 |
| 原生语义 | Profile 原生 AX 树确认设置主题按钮值、搜索入口、导航项、音乐控制、清空操作和 Mac Host 控件的可读名称/状态。未启用系统 VoiceOver，也未听取或记录 VoiceOver 实际朗读顺序。 |
| 对比度边界 | 修正深色 muted token 后，`accessibility_test.dart` 的静态色值对比断言通过。没有从 Profile 或 golden 叠层抽取最亮光弧、暗角、主题过渡帧的像素；UI-5.5 仍未通过。 |
| 测试 | `flutter analyze --no-pub`：无问题；`flutter test --no-pub test`：272 项通过；`flutter test --no-pub tool/ui_review_test.dart`：6 项通过；`dart format --output=none --set-exit-if-changed app/lib app/test packages spikes/phase0/bin`：230 文件无变化；`sh spikes/phase0/check_boundary.sh`：通过；公共包 `dart test ...`：15 项通过；`flutter build macos --debug --no-pub`：成功。 |
| 完整脚本 | `sh tool/check.sh` 在工作树现有锁文件下退出码 65，因为 `flutter pub get --enforce-lockfile` 会改动 106 个依赖。为不改写该文件，另将已提交的 `HEAD:pubspec.lock` 临时放入验证工作树，原样运行完整脚本：退出码 0，格式、分析、公共边界、15 项公共包测试、272 项 App 测试与 macOS Debug 构建全通过；结束后逐字节恢复原锁文件。当前保留锁文件 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未纳入阶段提交。 |
| 真实服务 | 未连接真实连接、Host、账号或外部服务；所有状态/错误回归均由 Preview Runtime 或 mock Runtime 覆盖。 |
| 提交 | `f453980dc5a8dcf6d7b589ff4e7ecdc432013553`，`完成 macOS 玻璃 UI 功能验收`。 |

## UI-6：原生性能与最终验收（部分验收）

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-6.1～UI-6.12 |
| 结果 | 已测的浅/深色静置、刷新/复制/添加、播放控制和 800/1024/1440/1512 logical px 固定宽度滚动交互子场景，各自三轮活动窗的 build/raster P95 均低于 16.667 ms，超预算比例低于 1%。宽度场景未见 >100 ms build/raster 帧；一次隐藏恢复样本出现 102.132 ms raster，重复轮为 24.851 ms。主题开关在 1024 宽另完成三轮、每轮 18 次深浅端点往返拖动，AX 值逐次交替且帧时达标；UI-0 同机端点点击基线也完成三轮，帧时数据已对照。另完成 20 轮页面往返与 RSS 时间序列。不能据此判阶段完成：同一负载连续缩放、精确手势时序和取消、完整生命周期资源审计、像素对比度、截图归档和用户视觉签收仍未完成。 |
| 环境 | MacBook Pro Apple M5 Pro、24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7、Xcode 27.2；内置 Liquid Retina XDR，1512×982 logical px、60 Hz、DPR 2。既有窗口样本为 800 与 1512 logical px；本轮另测 1024×632 和 1440×632 logical px 固定窗口。1440 宽实际 NSWindow frame 由临时原生诊断日志确认；诊断代码已恢复，未保留在提交中。 |
| 运行方式 | 临时 `lib/ui6_profile_main.dart` 启动生产 `AggregateApp`，仅替换为 `Ui6ProfileRuntime`：连接/能力由 `PreviewRuntime` 提供，音乐播放状态由本地 fixture 模拟，不启动进程、不访问网络、不触达真实连接/账号/Host。宽度验证时使用临时 Runner frame 注入，并在测试后恢复 `MainFlutterWindow.swift`；临时入口、Runtime 和原生诊断均未提交。 |
| 采样 | `app/tool/sample_theme_switch_frames.cjs` 监听既有 Mac Profile VM `Flutter.Frame` 事件；没有更改 Profile flags。帧时轮次录 40 秒，按首帧后的 5–35 秒选取 30 秒活动窗。1024/1440 结果逐轮列于下方；1440 滚动第三轮在 29.783 秒活动窗内记录 932 帧，其他宽度滚动轮次约 1,795–1,800 帧；主题拖动三轮均为 1,800 帧。隐藏恢复轮次记录约 12.9 秒无帧空档。JSON `protocolErrors=0` 且未断连。指标为 Flutter build/raster 提交帧，不等于显示器实际呈现 FPS。原始 JSON 位于本机 `/tmp/aggregate-ui6-*.json`（权限 0600，不随提交）；临时 VM URI 不归档。 |
| 负载 | 静置样本覆盖完整工作台的 12 类按钮及浅/深色，各三轮。浅色刷新、复制、添加分别三轮。播放/暂停、上一首/下一首、停止与切页循环三轮，每轮约 31.6–31.8 秒、5 组循环/31 次按钮动作，以本地 Preview 数据运行。原有滚动/缩放三轮在 800↔1512 logical px 之间操作；本轮另以 1024、1440 固定窗口各做三轮、约 30 秒目录长列表往返滚动，穿插设置/管理连接/活动/音乐页切换。未覆盖七个视图的长列表/表单。原有 800 宽主题端点切换三轮各 26 次；1024 宽另做三轮每轮 18 次端点往返拖动，AX 深浅状态逐次交替，未能通过 CUA 控制精确 450 ms 手势时长，也未执行拖动取消。 |
| 活动窗统计 | 以下 build/raster 数值单位均为 ms，格式为 P50/P95/P99/max；“超预算帧”按任一线程 >16.667 ms 计数。每轮分别统计，未以长 idle 稀释 30 秒活动窗。 |
| 多按钮静置·深色 | r1 n=1800：build `0.731/0.994/1.093/1.480`，raster `9.939/13.990/14.534/15.020`，超预算 `0/1800`；r2 n=1800：build `0.710/0.973/1.079/1.418`，raster `9.812/13.951/14.603/15.218`，`0/1800`；r3 n=1800：build `0.729/0.968/1.088/1.293`，raster `10.111/14.108/14.638/15.134`，`0/1800`。 |
| 多按钮静置·浅色 | r1 n=1800：build `1.088/1.410/1.586/3.451`，raster `10.230/14.069/14.535/17.449`，超预算 `1/1800`（0.056%）；r2 n=1801：build `0.873/1.426/1.525/1.694`，raster `9.668/14.052/14.424/14.827`，`0/1801`；r3 n=1800：build `0.944/1.419/1.578/2.720`，raster `9.703/14.014/14.688/15.296`，`0/1800`。 |
| 刷新点击·浅色 | r1 n=1801：build `1.195/1.462/1.588/1.932`，raster `9.278/13.994/14.694/15.769`，超预算 `0/1801`；r2 n=1800：build `1.210/1.436/1.552/1.868`，raster `9.806/14.041/14.622/15.459`，`0/1800`；r3 n=1800：build `1.214/1.448/1.551/1.805`，raster `9.112/13.838/14.535/15.129`，`0/1800`。 |
| 复制点击·浅色 | r1 n=1800：build `1.203/1.423/1.539/1.767`，raster `9.559/13.842/14.536/15.329`，超预算 `0/1800`；r2 n=1800：build `1.198/1.413/1.569/1.880`，raster `9.803/13.657/14.238/15.243`，`0/1800`；r3 n=1800：build `1.203/1.430/1.585/2.497`，raster `9.945/13.898/14.530/15.065`，`0/1800`。 |
| 添加点击·浅色 | r1 n=1800：build `1.203/1.432/1.546/1.880`，raster `9.637/13.773/14.484/15.084`，超预算 `0/1800`；r2 n=1800：build `1.204/1.440/1.546/1.802`，raster `9.674/13.748/14.383/15.039`，`0/1800`；r3 n=1800：build `1.205/1.432/1.530/1.867`，raster `9.679/13.926/14.599/14.997`，`0/1800`。 |
| 播放反向与翻页 | r1 n=1800：build `0.433/0.700/1.164/4.248`，raster `7.010/7.752/8.099/8.588`，超预算 `0/1800`；r2 n=1800：build `0.454/0.728/1.202/5.638`，raster `7.007/7.867/8.244/8.592`，`0/1800`；r3 n=1800：build `0.472/0.763/1.212/4.807`，raster `6.994/7.822/8.220/8.939`，`0/1800`。 |
| 滚动与缩放·800↔1512 | r1 n=1798：build `0.740/1.696/5.490/7.423`，raster `8.726/13.033/14.731/22.535`，超预算 `9/1798`（0.501%）；r2 n=1799：build `0.762/3.506/5.214/6.026`，raster `8.958/13.146/14.558/21.956`，`9/1799`（0.500%）；r3 n=1796：build `0.896/3.602/5.276/6.849`，raster `9.103/13.207/14.893/23.573`，`11/1796`（0.612%）。三轮 P95 达标，最大 raster 约 22–24 ms，未发现 >100 ms 长帧。 |
| 滚动与页面交互·1024 | r1 n=1797：build `0.520/0.914/0.981/5.727`，raster `6.116/6.737/7.100/13.868`，超预算 `0/1797`；r2 n=1796：build `0.658/1.168/1.353/6.372`，raster `6.124/8.842/10.658/79.400`，`1/1796`（0.056%）；r3 n=1795：build `0.530/1.235/1.720/6.357`，raster `7.088/10.136/11.131/25.852`，`2/1795`（0.111%）。三轮活动窗均约 29.983 秒，P95 达标，无 >100 ms build/raster 帧。 |
| 滚动与页面交互·1440 | r1 n=1800：build `0.492/1.011/1.279/5.864`，raster `6.871/9.230/10.083/23.099`，超预算 `2/1800`（0.111%）；r2 n=1798：build `0.570/1.231/1.721/8.042`，raster `7.288/10.552/11.389/13.926`，`0/1798`；r3 n=932：build `0.533/1.193/1.808/4.555`，raster `7.359/11.609/14.738/31.782`，`4/932`（0.429%）。三轮活动窗 29.783–30.000 秒，P95 达标，无 >100 ms build/raster 帧。 |
| 主题实时拖动·1024 | r1 n=1800：build `0.923/4.968/5.099/5.361`，raster `5.235/5.944/6.191/6.637`，超预算 `0/1800`；r2 n=1800：build `0.931/4.939/5.096/5.406`，raster `5.283/5.944/6.190/6.784`，`0/1800`；r3 n=1800：build `0.920/4.959/5.098/5.364`，raster `5.268/5.900/6.155/7.281`，`0/1800`。三轮活动窗约 29.983 秒，CUA 每轮 18 次拖动并逐次确认 AX 明暗状态；build/raster 无超预算帧。 |
| UI-0 同机主题端点点击基线·1024 | 临时 worktree commit `297762e82730b8a99f324b190796c80aae426a9`，相同 Mac/Profile/窗口/DPR/刷新率与锁定的包版本；三轮各 30 秒、每轮 18 次点击往返并逐次确认 AX 浅/深交替。r1 n=1800：build `0.594/4.917/5.102/6.610`，raster `0.507/0.812/0.919/7.736`，超预算 `0/1800`；r2 n=1800：build `0.585/4.799/4.951/5.325`，raster `0.494/0.775/0.884/1.019`，`0/1800`；r3 n=1799：build `0.617/4.918/5.118/11.904`，raster `0.484/0.783/0.874/7.693`，`0/1799`。与当前拖动场景输入不同，只作方向性同机对照；build/raster 提交帧不等同实际显示呈现 FPS。 |
| 主题端点切换·800 | r1 n=1801：build `1.074/4.346/4.817/6.521`，raster `7.692/10.743/11.147/11.619`，超预算 `0/1801`；r2 n=1800：build `1.129/4.293/4.494/7.289`，raster `7.647/10.661/11.100/11.558`，`0/1800`；r3 n=1799：build `1.179/4.467/4.900/32.303`，raster `7.670/10.672/11.242/27.445`，`2/1799`（0.111%），无 >100 ms 长帧。此项只代表 AX 端点切换的帧时。 |
| 生命周期与内存 | CUA 明确隐藏并 Raise 恢复两轮，各观察到约 12.9 秒 Flutter.Frame 空档；一轮恢复后的 raster 为 102.132 ms，重复轮为 24.851 ms，故 lifecycle 只记部分验证。另完成 20 轮页面往返（每轮“所有功能→管理连接→活动→设置”，共 80 次导航）。进程 RSS 约 176 MiB 起、页面循环中升至约 203 MiB、循环结束约 199 MiB；随后 30 秒静置在约 195–208 MiB 波动，未见单向增长。RSS 不能代替 controller/纹理对象数量；离屏和 reduced-motion 原生覆盖未执行。 |
| 原生视觉与动效 | CUA 实窗观察到深色月亮态、浅色太阳态与一次中间拖动态；中间态显示了点阵内部变化、背景过渡与局部光弧。12 类 dot glyph、背景连续性及主题 AX 值均可见。1024 宽三轮往返拖动各 18 次，AX 状态 54 次逐次交替。截图只在交互中查看，未导出归档；没有合成像素对比度或 0/.25/.5/.75/1 相位对照。CUA 未提供精确手势时长控制，且没有可靠验证拖动取消。最终材质意见与用户签收待补。 |
| 结果边界 | UI-6.1 的 800/1024/1440/1512 固定宽度目录滚动子场景及 1024 主题拖动均有三轮数据，但尚未覆盖七视图的长列表/表单，也未测同一负载中的连续缩放和拖动取消。UI-6.2 的宽度/主题场景无 >100 ms build/raster 帧，但隐藏恢复有一次 102.132 ms raster，且帧数据不证明实际显示呈现 FPS。UI-6.3 已完成 UI-0 同机端点点击基线与当前拖动场景的方向性对照，输入不完全相同；关键相位、取消手势和真实呈现 FPS 仍未验证。UI-6.4/6.5 只有部分隐藏恢复及 RSS 证据。UI-6.6/6.9 与 UI-6.10 尚未完成。 |
| 变更范围 | 没有修改 Android、原主题算法/参数、Runtime 协议或生产源码；临时 Profile/窗口诊断改动均已还原。`pubspec.lock` 保留任务前 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 提交/远端 | 本阶段采样报告按部分验收单独提交；提交号与双远端 `main` SHA 在本次任务交付结果中记录。该文档提交不代表 UI-6 或整套 UI 适配已完成。 |

## 后续阶段

UI-0～UI-5 已按阶段独立提交；未通过的对比度与 VoiceOver 项仍保留为限制。UI-6 新增 1024/1440 宽度与三轮主题往返数据、UI-0 同机方向性基线、隐藏恢复观察和 RSS 页面循环证据，但同场景连续缩放、完整生命周期资源/动效证据、像素对照与用户主观签收仍为待办；阶段仍未交付。
