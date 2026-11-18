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

### 2026-11-18：运行、刷新、搜索点阵二次校正

- 用户指出这三个高频图案看起来不协调。复看 96 dp 暗色 Profile 样本后确认，旧的曲线采样会产生半格点位，刷新箭头还会重复落点；三者在同一图案内的点距因此不如其余图案规整。
- `GlassGlyph.play`、`refresh`、`search` 现在都使用 9×9 显式点阵掩码和同一圆角颗粒/窄羽化。运行三角缩至平衡的 7 行并按视觉重心对中；刷新明确保留圆环开口和箭头端；搜索改为闭合圆环并与斜柄连续衔接。没有改按钮业务回调、动作时长/曲线、主题开关或 Material fallback。
- [macOS Profile 暗色 96 dp 图案实窗](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/three-icons-after-grid-search.png>)（Retina DPR 2，SHA-256 `e4e334aa10e43d86bcca6689c5fff7299b13fcc6e67f6a4b75c91e31dbb3d565`）中可见三种新轮廓；另有 32 dp 浅/深 golden `app/test/goldens/glass_primary_glyphs_light.png`、`glass_primary_glyphs_dark.png`。三个形状均通过网格对齐、无重复点断言。`flutter test --no-pub test/glass_action_button_test.dart test/glass_motion_test.dart test/glass_glyph_golden_test.dart` 28 项通过；`flutter analyze --no-pub` 无问题；Profile 实窗由本轮源码重新构建。
- 这次截图用于静态轮廓对照，不单独证明原生点击动画每个时刻，也不关闭 UI-6.7 的逐实例动静态签收。既有动作 profile 和按钮交互代码未改；太阳/月亮切换逻辑没有变化。

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
| 结果 | 自动化、键盘、语义、参数保护、reduced motion、放大文字与两种 DPR 的页面布局回归通过。主题开关焦点边框现由 Widget 回归确认绘制在 artwork 前景。UI-5.7 的系统 VoiceOver 语音走查未完成；不以自动化结果代替这些证据。 |
| 环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2；内置 Liquid Retina XDR，逻辑 1512×982 点、60 Hz、DPR 2。App 自动化运行于 Flutter test；原生 AX 树抽查使用 Profile `Aggregate.app`。 |
| 页面矩阵 | `app/tool/ui_review_test.dart` 固定 `ManualGlassMotionClock`，以 `FakeAccessibilityFeatures(disableAnimations: true)` 固定装饰相位但保留路由动画；在 `setUpAll` 预加载主题开关 shader，使六个测试用例共享已完成的加载 Future，不在各自的异步测试区内等待。800×600、1024×768、1440×900 × 浅/深 × DPR 1/2 × 9 个音乐/连接/设置/目录/运行预览状态；DPR 1 用 `work/ui-review/` 的 54 张金样比对，DPR 2 同样走完整路由和布局错误检查。12 项通过。2026-11-17 按实际 shader 渲染更新了 5 张设置页金样；第六张 800×600 浅色设置金样本次已与稳定截图一致，无需改动。逐张检查六种设置页尺寸/主题后，主题控件均正常显示。图像使用测试字体，中文字符可能呈方框，仅用于结构与路由回归；不能作为中文字体验收。原生 Profile 窗口已目视确认中文可读，但 CUA 截图未导出归档。 |
| 组件覆盖 | `glass_action_button_test.dart` 检查所有点阵在浅/深主题和 DPR 1/2 的绘制、200% 文字操作、Enter 激活、Tab/Shift-Tab 顺序和回调次数。完整 UI-2 glyph golden 仍在原阶段验证；UI-5 的整页面金样没有 DPR 2。`accessibility_test.dart` 以 token 组合覆盖浅深材质端点的文字/图形目标；不含 shader 像素读回。 |
| 键盘与安全 | `widget_test.dart`、`capability_run_page_test.dart`、`glass_action_button_test.dart` 验证 ⌘K 搜索焦点、⌘↵打开确认但不执行背景任务、显式确认一次、Esc 取消并恢复输入焦点、Enter 激活一次及 Tab 顺序；相关断言通过。 |
| 原生语义 | Profile 原生 AX 树确认设置主题按钮值、搜索入口、导航项、音乐控制、清空操作和 Mac Host 控件的可读名称/状态。2026-11-19 在 macOS Profile 测试中通过系统设置启用 VoiceOver，开关读回 checked=1；完整 AX 树保留设置页名称与值，但尝试 VO+Right 后字幕面板没有显示应用控件播报，实际朗读顺序仍未确认。测试结束将开关读回 0，VoiceOver 服务不再运行。 |
| 对比度边界 | 修正深色 muted token 后，`accessibility_test.dart` 的静态色值对比断言通过。2026-11-15 新增真实 macOS Profile 设置页合成像素样本，浅/深主题的正文对比度为 10.16:1 / 14.27:1，主题按钮标签为 7.47:1 / 4.74:1，当前太阳/月亮点阵核心为 7.65:1 / 4.93:1。按 sRGB 线性亮度与局部材质采样计算；深色截图 [settings-dark-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-dark-profile.png) SHA-256 `ab5379655f333d9e9b26232349711c9b8cf5171bd24a8139a994bb6e76644554`，浅色截图 [settings-light-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-light-profile.png) SHA-256 `56aaf4a3e1b000112ef0f56f8f7f6a5c4813f011b5c988bc7de85cd85aafaa96`。选中态光弧探索性局部亮度比为深色 2.32:1、浅色 1.15:1；该弧目前仅作次要装饰，非键盘焦点环或唯一状态提示。主题开关原焦点边框绘制在会覆盖它的 artwork 下方；现已用前景绘制层修正，并由 Widget 回归验证 2px 主题色边框存在且在前景。焦点环现已完成浅深主题的原生合成像素抽样并达到 3:1 目标。2026-11-17 Flutter 3.47.8 `ThemeData.lerp` 比较当前玻璃主题与 UI-0 等效基础主题：进度 0.25/0.50/0.75，当前 `GlassDesignTokens.text/surface` 分别为 3.747:1 / 1.015:1 / 3.917:1；UI-0 `onSurface/surface` 为 4.250:1 / 1.094:1 / 3.603:1。2026-11-18 在 `AggregateApp.builder` 增加 macOS 插值文字对比修正：已有对比达标的文字色保持原值，未达标时选择与当前 `ThemeData.surface` 对比更高的黑/白；覆盖 `ColorScheme.onSurface/onSurfaceVariant`、有显式颜色的文字主题、列表/标题颜色和玻璃 `text/muted` 令牌。浅深端点配色不变。单元测试检查 101 个等距插值位置，macOS 转场 Widget 测试检查实际中段 ThemeData，均确认对应语义表面对比至少 4.5:1；Android 分支未改。UI-0 的 macOS 560 ms `easeInOutCubic` 转场与主题开关逻辑保持不变。此处仅为 ThemeData.surface 模型对比，不能替代动画 shader 和各半透明材质上的原生合成帧采样；过渡中的实际像素、禁用态和其他页面材质仍未完整验证，因此 UI-5.5 保持部分验收。 |
| 测试 | `flutter analyze --no-pub`：无问题；`flutter test --no-pub test`：272 项通过；`flutter test --no-pub tool/ui_review_test.dart`：6 项通过；`dart format --output=none --set-exit-if-changed app/lib app/test packages spikes/phase0/bin`：230 文件无变化；`sh spikes/phase0/check_boundary.sh`：通过；公共包 `dart test ...`：15 项通过；`flutter build macos --debug --no-pub`：成功。 |
| 2026-11-18 对比修正验证 | `dart format` 涉及的 4 个 Dart 文件；`flutter analyze --no-pub` 无问题；`flutter test --no-pub test/glass_design_tokens_test.dart test/android_theme_transition_test.dart` 全通过；完整 `flutter test --no-pub` 302 项通过；`git diff --check` 通过。完整测试日志中有预期的无效 MCP 端点错误输出，对应负向测试通过。 |
| 完整脚本 | `sh tool/check.sh` 在工作树现有锁文件下退出码 65，因为 `flutter pub get --enforce-lockfile` 会改动 106 个依赖。为不改写该文件，另将已提交的 `HEAD:pubspec.lock` 临时放入验证工作树，原样运行完整脚本：退出码 0，格式、分析、公共边界、15 项公共包测试、272 项 App 测试与 macOS Debug 构建全通过；结束后逐字节恢复原锁文件。当前保留锁文件 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未纳入阶段提交。 |
| 真实服务 | 未连接真实连接、Host、账号或外部服务；所有状态/错误回归均由 Preview Runtime 或 mock Runtime 覆盖。 |
| 提交 | `f453980dc5a8dcf6d7b589ff4e7ecdc432013553`，`完成 macOS 玻璃 UI 功能验收`。 |

### 2026-11-19 系统 VoiceOver 开启态 Profile 复核

使用 `flutter run -d macos --profile --no-pub -t lib/preview_main.dart` 启动 `preview_main.dart` 的内存 PreviewRuntime；没有连接真实服务。通过系统设置将 VoiceOver switch 从 0 打开并读回 `checked=1`。在 macOS 27.2.1 / Flutter 3.47.8 stable 的 Aggregate 800×632 logical px 窗口中，完整 AX 树仍包含四个设置标签、导航按钮、“外观主题”值“深色”和“跟随 macOS 系统”。键盘发送 VO+Right 后，字幕面板仅显示 VoiceOver Utility 的启动提示，没有得到可验证的应用控件朗读或焦点目标；因此只确认系统开启态下 AX 树可读，未完成 VoiceOver 主流程，也没有新增禁用控件 AXEnabled 结果。测试结束将 System Settings 的 VoiceOver switch 读回 `0`；`launchctl` 中 VoiceOver 服务无运行进程，已退出本轮启动的 Profile、System Settings 和 VoiceOver Utility。屏幕捕获只作临时局部检查并已删除，未归档完整桌面图像。

## UI-6：原生性能与最终验收（部分验收）

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-6.1～UI-6.12 |
| 结果 | 已测的浅/深色静置、刷新/复制/添加、播放控制和 800/1024/1440/1512 logical px 固定宽度滚动交互子场景，各自三轮活动窗的 build/raster P95 均低于 16.667 ms，超预算比例低于 1%。本轮修复页面栈在窗口尺寸变化时被重复创建的问题；24 个 CLI 样本连接下，800↔1440 logical px 原生连续缩放完成三轮，build/raster P95 均低于 13.9/9.9 ms，超预算比例均低于 0.3%。宽度场景未见 >100 ms build/raster 帧；一次隐藏恢复样本出现 102.132 ms raster，重复轮为 24.851 ms。主题开关在 1024 宽另完成三轮、每轮 18 次深浅端点往返拖动，AX 值逐次交替且帧时达标；UI-0 同机端点点击基线也完成三轮，帧时数据已对照。另完成 20 轮页面往返与 RSS 时间序列。本轮新增活动页惰性列表，并完成工作台、连接、活动、设置四页与连续窗口缩放联合负载三轮；build/raster 帧时均达门槛。随后对七个长列表/表单场景各做三轮 Profile 滚动，六类场景无 >100 ms 帧；90 字段表单首组三轮中一轮出现 112.742 ms build 峰值，三轮补充滚动未复现，仍作为未定位的间歇性异常保留，未标通过。原生拖动取消对照、生命周期对象审计及动态关键帧对照仍待完成；生产页面双主题静态截图已由代理按本轮范围自验，但未逐项检查全部产品按钮实例和动态状态，因此 UI-6 保持部分验收。 |
| 环境 | MacBook Pro Apple M5 Pro、24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7、Xcode 27.2；内置 Liquid Retina XDR，1512×982 logical px、60 Hz、DPR 2。既有窗口样本为 800 与 1512 logical px；本轮另测 1024×632 和 1440×632 logical px 固定窗口。1440 宽实际 NSWindow frame 由临时原生诊断日志确认；诊断代码已恢复，未保留在提交中。 |
| 运行方式 | 临时 `lib/ui6_profile_main.dart` 启动生产 `AggregateApp`，运行时由 `Ui6ProfileRuntime` 返回合成数据：24 个 CLI 连接、1 个 MCP 连接、1 个本地音乐样本连接、90 个 CLI 能力、60 个 MCP 工具、2 个音乐能力和 60 条活动记录；不启动外部进程、不访问网络、不触达真实连接、账号或 Host。窗口扫宽使用临时 Runner frame 注入，测试后恢复 `MainFlutterWindow.swift`；临时入口、Runtime 和原生诊断均未提交。 |
| 回归检查 | 首轮活动页/工作台子阶段全量 `flutter test --no-pub` 274 项通过；2026-11-15 后续连接首页与管理连接惰性列表变更后全量 279 项通过，音乐搜索长列表加入后 281 项通过，运行参数表单加入后 282 项通过；主题 450 ms 实时指针及取消恢复用例后全量 284 项通过；焦点环前景层回归后全量 285 项通过。2026-11-17 修复管理连接短列表布局及 UI review shader 预载后，全量 `flutter test --no-pub test` 289 项通过，`flutter test --no-pub tool/ui_review_test.dart` 12 项通过，`flutter test --no-pub test/connections_page_lazy_test.dart` 4 项通过，`flutter analyze --no-pub` 无问题。活动页惰性构建回归曾在旧实现上失败（屏外第 60 条已构建），改后通过；连接首页 90 项桌面/紧凑目录、管理连接页 90 个连接/能力的桌面/紧凑滚动回归均通过；2026-11-17 新增 1 个连接/1 个能力的自然高度回归，原有 90 项懒构建仍通过；音乐搜索 90 首桌面/紧凑宽度滚动和对应播放回调、原有短结果无障碍语义回归均通过；参数表单 90 字段回归覆盖屏外必填校验、滚动后行内提示和最终参数值。主题焦点测试将 `FocusManager` 固定为传统键盘焦点模式，确认焦点边框存在并置于绘制前景；未采集更新后的原生焦点图像。Widget 回归仅证明构建边界、行为和可达性；新增长列表场景的帧时见下方原生 Profile 记录。 |
| 采样 | `app/tool/sample_theme_switch_frames.cjs` 监听既有 Mac Profile VM `Flutter.Frame` 事件；没有更改 Profile flags。帧时轮次录 40 秒，按首帧后的 5–35 秒选取 30 秒活动窗。1024/1440 结果逐轮列于下方；1440 滚动第三轮在 29.783 秒活动窗内记录 932 帧，其他宽度滚动轮次约 1,795–1,800 帧；主题拖动三轮均为 1,800 帧。隐藏恢复轮次记录约 12.9 秒无帧空档。七类长列表/表单在临时 worktree（被测源码基线 `7d28c476ec4094784c39053c303c0abe7d29bb8b`）的 Profile `PreviewRuntime` 夹具中另采三轮：每轮录 40 秒、首帧后 5–35 秒活动窗，主动滚动约 30 秒；其中参数表单一轮只有 1,502 个活动窗帧，另两轮各 1,800。夹具用本地合成数据，不接服务；原始 JSON 保存在本机 `/tmp/aggregate-ui6-schema-profile/`（权限 0600，不随提交）。JSON `protocolErrors=0` 且未断连。指标是 Flutter build/raster 提交帧，不等于显示器实际呈现 FPS；临时 VM URI 不归档。 |
| 负载 | 静置样本覆盖完整工作台的 12 类按钮及浅/深色，各三轮。浅色刷新、复制、添加分别三轮。播放/暂停、上一首/下一首、停止与切页循环三轮，每轮约 31.6–31.8 秒、5 组循环/31 次按钮动作，以本地 Preview 数据运行。原有滚动/缩放三轮在 800↔1512 logical px 之间操作；本轮另以 1024、1440 固定窗口各做三轮、约 30 秒目录长列表往返滚动，穿插设置/管理连接/活动/音乐页切换。另以独立 Profile 夹具分别滚动工作台 92 项、连接首页单连接 91 项能力、管理连接 90 个连接、管理连接明细 91 项能力、活动 60 条、音乐结果 90 首和运行参数表单 90 字段。原有 800 宽主题端点切换三轮各 26 次；1024 宽另做三轮每轮 18 次端点往返拖动，AX 深浅状态逐次交替，当时未能通过 CUA 控制精确手势时长，也未执行拖动取消。2026-11-15 以只读 CGEvent tap 实测：`agent-desktop --duration 450` 两向移动跨度为 524.0/517.9 ms；`--duration 397` 六次交替拖动（每向三次）跨度 455.4–466.1 ms、均值 460.8 ms，且六次 AX 端点逐次符合预期。原生取消仍未执行。修复后联合负载每轮在 800↔1440 logical px 扫宽时往返滚动工作台、管理连接、活动、设置四页 40–44 个 down/up scroll pair；每页每轮至少两次 AX 路由校验。 |
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
| 连续缩放·800↔1440 | 在完整 Preview fixture 中用原生 `NSWindow.setFrame(display: true)` 按 17 ms 间隔由 800 缩至 1440 再回缩，单轮原生扫宽约 41 秒，VM `Flutter.Frame` 连续采样 40 秒；每轮均触达 800 与 1440 logical px。r1 n=2400：build `0.204/13.811/14.487/46.341`，raster `7.758/9.889/10.835/13.479`，超预算 `7/2400`（0.292%），提交帧率估值 59.85；r2 n=2400：build `0.136/11.070/11.532/35.991`，raster `8.047/9.442/9.800/10.256`，`1/2400`（0.042%），59.98；r3 n=2403：build `0.135/10.699/10.991/37.872`，raster `8.066/9.563/9.876/10.337`，`1/2403`（0.042%），59.98。三轮 P95 均低于 16.667 ms，没有 >100 ms build/raster 帧。该场景只测连续窗口缩放，未同时进行目录滚动；提交帧率不等于显示器实际呈现 FPS。 |
| 活动页长列表惰性构建 | 60 条活动记录的单页 40 秒采样。改前 n=2211：build `1.531/17.725/19.031/22.958`，raster `12.941/16.081/17.109/20.738`，超预算 `299/2211`（13.523%）；改后 n=2351：build `1.151/10.394/12.567/13.615`，raster `12.675/14.778/15.757/17.085`，超预算 `2/2351`（0.085%）。改后滚动 109 对、改前 86 对，输入不完全相同，仅作方向性定位。CUA AX 初始仅列出 11 条可见记录；测试验证离屏第 60 条滚入后可见。 |
| 连接目录长列表惰性构建 | 连接首页桌面目录以 `SliverList.builder` 构建；紧凑目录在 40 项以上改用 PageFrame 的惰性 sliver。90 项 CLI 样本分别在 1024×768 桌面宽度与 700×768 紧凑宽度运行 widget 回归：首屏 `CapabilityRow` 均少于 20 个，第 90 项初始未构建，滚动后可见，且无 Flutter 异常。另在独立原生 Profile 夹具以 91 项能力完成三轮滚动，帧时见原生 Profile 行。 |
| 管理连接长列表惰性构建 | 连接管理页目录与选中连接能力明细均改为有界 `ListView.separated`。90 项 Preview 连接分别在 1024×768 和 700×768 回归，首屏 `ListTile` 少于 20 个，末项初始未构建；滚到第 90 项后可见。紧凑宽度还能打开末项详情；单连接 90 项能力明细首屏 `CapabilityRow` 少于 20 个并可滚至末项。另在独立原生 Profile 夹具分别以 90 个连接和 91 项能力完成三轮滚动，帧时见原生 Profile 行。 |
| 音乐搜索长结果惰性构建 | 40 首以下维持原本随页面自然展开的结果布局；40 首及以上启用有界 `ListView.separated`。90 首样本分别在 1024×768、700×768 测试，第 90 首初始未构建、滚动后可见，点击“播放 歌曲 89”仍准确调用对应歌曲回调。短列表原生语义回归确认“播放 示例歌曲”仍可访问。另以 90 首合成结果完成三轮原生 Profile 滚动，帧时见原生 Profile 行。 |
| 运行参数长表单惰性构建 | 40 个字段以上启用有界 `ListView.builder`。90 字段样本确认末尾必填项初始未构建时仍会被全表校验发现，滚动到末项后显示行内错误；填写后校验通过且提交参数一致。小于 40 个字段继续内联构建。另以 90 字段完成三轮原生 Profile 滚动；其中一轮出现 112.742 ms build 长帧，见原生 Profile 行并保留为未通过项。 |
| 原生 Profile·工作台 92 项 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 7.978–8.300 ms，raster P95 14.401–14.688 ms。build 或 raster 任一超过 16.667 ms 的帧为 2/1800、0/1800、1/1800（最高 0.111%）；没有 >100 ms 帧。 |
| 原生 Profile·连接首页 91 项能力 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 4.114–4.321 ms，raster P95 11.289–11.360 ms；无超 16.667 ms 或 >100 ms 帧。 |
| 原生 Profile·管理连接 90 项 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 4.962–5.219 ms，raster P95 10.928–11.038 ms；无超 16.667 ms 或 >100 ms 帧。 |
| 原生 Profile·管理连接明细 91 项能力 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 3.690–4.329 ms，raster P95 10.066–10.577 ms；无超 16.667 ms 或 >100 ms 帧。 |
| 原生 Profile·活动 60 条 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 4.998–5.285 ms，raster P95 13.472–13.668 ms；无超 16.667 ms 或 >100 ms 帧。 |
| 原生 Profile·音乐结果 90 首 | 隔离 PreviewRuntime 夹具，三轮各 1,800 帧；build P95 0.764–0.944 ms，raster P95 4.194–4.514 ms；无超 16.667 ms 或 >100 ms 帧。 |
| 原生 Profile·参数表单 90 字段 | 初始三轮活动窗分别记录 1,502、1,800、1,800 帧；build P95 1.759–1.802 ms，raster P95 0.650–0.667 ms。一轮 max build 112.742 ms，超预算 10/1,502 帧（0.666%），其中 1 帧 >100 ms；另两轮 max build 2.873/3.612 ms，均无超预算帧。随后三轮补充复测（每轮活动窗 1,800 帧；其中两轮按 20 组 down/up 滚动、组间隔 1.2 秒）：build/raster P95 分别为 0.288/0.763、0.341/0.673、0.328/0.677 ms，max build 为 2.322–2.553 ms、max raster 为 1.102–1.211 ms，均无超预算帧。原始长帧未能复现但仍保留；原因尚未定位，该场景不通过长帧门槛，不能由补充轮抵消。 |
| 联合滚动与缩放·修复后 | 800↔1440 logical px 原生窗口每 17 ms 扫宽；24 CLI 样本连接、152 项能力、60 条活动记录；每轮 40 秒采样，CUA 路由与滚动操作持续 30.824/31.610/31.593 秒。以下格式为 build/raster P50/P95/P99/max，超预算按任一线程超过 16.667 ms 计。r1 n=2338：`1.203/11.088/13.342/17.479` / `11.700/14.600/17.157/21.760`，`32/2338`（1.369%）；r2 n=2341：`1.322/11.101/13.433/18.968` / `11.821/14.884/17.434/26.753`，`35/2341`（1.495%）；r3 n=2342：`1.219/11.021/13.680/16.799` / `11.771/14.728/16.950/22.360`，`30/2342`（1.281%）。起始后 32 秒近似活动窗的 build/raster P95 为 11.022/14.350、10.937/14.585、10.997/14.544 ms，超预算比例为 1.010%/1.011%/1.008%。三轮均无 >100 ms build/raster 帧；提交帧率估值 58.47–58.65，不代表实际显示呈现 FPS。 |
| 主题实时拖动·1024 | r1 n=1800：build `0.923/4.968/5.099/5.361`，raster `5.235/5.944/6.191/6.637`，超预算 `0/1800`；r2 n=1800：build `0.931/4.939/5.096/5.406`，raster `5.283/5.944/6.190/6.784`，`0/1800`；r3 n=1800：build `0.920/4.959/5.098/5.364`，raster `5.268/5.900/6.155/7.281`，`0/1800`。三轮活动窗约 29.983 秒，CUA 每轮 18 次拖动并逐次确认 AX 明暗状态；build/raster 无超预算帧。 |
| UI-0 同机主题端点点击基线·1024 | 临时 worktree commit `297762e82730b8a99f324b190796c80aae426a9`，相同 Mac/Profile/窗口/DPR/刷新率与锁定的包版本；三轮各 30 秒、每轮 18 次点击往返并逐次确认 AX 浅/深交替。r1 n=1800：build `0.594/4.917/5.102/6.610`，raster `0.507/0.812/0.919/7.736`，超预算 `0/1800`；r2 n=1800：build `0.585/4.799/4.951/5.325`，raster `0.494/0.775/0.884/1.019`，`0/1800`；r3 n=1799：build `0.617/4.918/5.118/11.904`，raster `0.484/0.783/0.874/7.693`，`0/1799`。与当前拖动场景输入不同，只作方向性同机对照；build/raster 提交帧不等同实际显示呈现 FPS。 |
| 主题端点切换·800 | r1 n=1801：build `1.074/4.346/4.817/6.521`，raster `7.692/10.743/11.147/11.619`，超预算 `0/1801`；r2 n=1800：build `1.129/4.293/4.494/7.289`，raster `7.647/10.661/11.100/11.558`，`0/1800`；r3 n=1799：build `1.179/4.467/4.900/32.303`，raster `7.670/10.672/11.242/27.445`，`2/1799`（0.111%），无 >100 ms 长帧。此项只代表 AX 端点切换的帧时。 |
| 生命周期与内存 | CUA 明确隐藏并 Raise 恢复两轮，各观察到约 12.9 秒 Flutter.Frame 空档；一轮恢复后的 raster 为 102.132 ms，重复轮为 24.851 ms，故原生 lifecycle 只记部分验证。2026-11-17 定向复测：短隐藏 10 轮（各 1.5 s）max raster `13.071–13.990 ms`，无 >100 ms 帧；长隐藏 3 轮（各约 12.9 s）复现 `13.02–13.05 s` 的 Flutter.Frame 空档，但恢复后 max raster 为 `14.460–14.824 ms`、build < `1.05 ms`，均无 >100 ms 帧。原单次 102.132 ms raster 未再现，根因仍未定位，不据复测覆盖原失败。`flutter test --no-pub test/glass_motion_test.dart test/glass_theme_switch_test.dart` 定向 18 项通过，覆盖 `TickerMode`、应用 lifecycle 暂停/恢复、完全离屏注销、reduced-motion 注销并保留点击，以及主题开关 reduced-motion snap；原生离屏/reduced-motion 设置未覆盖。另完成 20 轮页面往返（每轮“所有功能→管理连接→活动→设置”，共 80 次导航）。进程 RSS 约 176 MiB 起、页面循环中升至约 203 MiB、循环结束约 199 MiB；随后 30 秒静置在约 195–208 MiB 波动，未见单向增长。源码所有权审阅核对了 `GlassMotionScope` 单共享 Ticker/timers/lifecycle listener、按钮 motion/state controllers、主题开关 Ticker/FocusNode、主题 artwork 的 shader 与两张 `ui.Image`、窗口背景 shader/frame 的 dispose 路径；SDK 对 `FragmentProgram.fromAsset` 持有进程级缓存。RSS 与源码审阅都不能代替原生 controller/图像对象数量，恢复帧 >100 ms 原因仍未定位。 |
| 2026-11-19 同进程 Hide/Activate 复测 | macOS Profile / Flutter 3.47.8 / Impeller MetalSDF / 800×632 logical px。通过 `⌘H` 确认同一进程窗口隐藏 12.9 秒，再用原 Profile bundle 激活；30 秒 VM `Flutter.Frame` 采样记录 13.083 秒帧空档，恢复首帧 build/raster 为 0.898/13.479 ms，整轮无 >16.667 ms build/raster 帧，frameCount=1026（包含隐藏时段）。原始 102.132 ms 长帧未复现，故不覆盖历史异常，也不据此宣告根因已定位。另做的 minimize/restore 造成窗口尺寸变化，路径不同，不计入本项。 |
| 2026-11-19 主题开关 450 ms 连续拖动三轮 | macOS 27.2.1 arm64 / Flutter 3.47.8 Profile / Impeller / 60 Hz / 800×632 logical px，隔离 `Ui6InspectionRuntime` 内存夹具。每轮 30 秒 `Flutter.Frame` 采样，深色起止，交替拖动 26 次、每次 27 个移动事件，请求 450 ms，逐次检查 AX 状态；三轮共 5,416 帧。r1/r2/r3 build P95 为 4.997/5.011/4.997 ms，raster P95 为 6.381/6.330/6.404 ms；build/raster 最大值依次为 6.543/6.880、6.359/7.067、6.493/7.021 ms。三轮都没有超过 16.667 ms 的 build 或 raster 帧，手势实际跨度范围 450.12–454.15 ms，最终 AX 状态均为深色。未在采样中截图。原始 Flutter.Frame 与逐事件输入 JSON 及 SHA-256 保存在 `/Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-3-theme-drag-frame-timings/`。该指标是 Flutter 提交帧 build/raster 时长，不是屏幕 present 时间或物理 FPS；本场景未复现用户报告的卡顿，但不能据此宣告问题已修复。 |
| 原生视觉与动效 | CUA 实窗观察到深色月亮态、浅色太阳态与一次中间拖动态；中间态显示了点阵内部变化、背景过渡与局部光弧。12 类 dot glyph、背景连续性及主题 AX 值均可见。1024 宽三轮往返拖动各 18 次，AX 状态 54 次逐次交替；另用方向键确认 AX 值可在深/浅端点间切换。2026-11-15 另导出同一 Profile 设置页的深浅窗口 PNG，实际 sRGB 像素抽样中正文、主题按钮文字和活动点阵核心均达到对比度目标；图像和哈希见上一行。Widget 指针回归覆盖 450 ms 拖动期间的中间态、抬手才提交以及中途取消恢复原端点。焦点环现按主题开关轨道尺寸/圆角绘制于 artwork 前景，Widget 检查其 2px 线宽、中心和几何尺寸；真实键盘焦点 Profile 实窗的浅/深主题合成像素最低对比度为 3.30:1 / 3.93:1，截图及 SHA-256 见后续焦点环记录。按钮 fixture 截图 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-buttons-fixture-disabled.png` 可见复制按钮灰化。2026-11-15 在隔离 Profile 最小夹具中对照玻璃按钮、裸 `Semantics`、语义包裹 `TextButton` 和普通禁用 `TextButton` 四种控件：Flutter Widget Semantics 均报告 `isEnabled=false` 且没有 tap action，但 `agent-desktop` 与直接 `AXUIElementCopyAttributeValue(kAXEnabledAttribute)` 均读到 `AXEnabled=true`。当前 Flutter 3.47.8 / Engine revision `cf636b1dfb` 的桌面 `AccessibilityBridge::SetStateFromFlutterUpdate` 未将 `is_enabled=false` 映射为 `Restriction::kDisabled`，macOS `AXEnabled` 则根据该 restriction 计算；故确认是 engine 桥接缺口，当前应用层 Semantics 结构不是原因。Flutter 官方主干已有相应转换（[bridge](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/common/accessibility_bridge.cc#L2297-L2304)、[macOS AX 映射](https://github.com/flutter/flutter/blob/master/engine/src/flutter/third_party/accessibility/ax/platform/ax_platform_node_mac.mm#L3239-L3244)），本机稳定版仍缺此转换。原生禁用语义未通过，需待使用包含修复的稳定 engine 后重验。视频帧对照页 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/theme-switch/stage6-keyframes.html` 展示原视频帧和 fitted Flutter 渲染的 9 组位置样本，包括静置、近似 0.25/0.5/0.75/1 和视频实际的部分反向轨迹；反向段约从 0.77 到 0.08 后再次前进，图像是离线逐帧对照，不是生产 macOS 实窗录屏。按钮尺寸/状态 fixture 现已在浅深两主题归档；生产页面 Profile 静态样本见下节。焦点环合成像素对比已通过。2026-11-15 用只读 CoreGraphics session event tap 记录系统实际收到的鼠标事件：`--duration 450` 的两向移动跨度为 524.0/517.9 ms；校准参数 `--duration 397` 的六次交替移动跨度为 455.4–466.1 ms（均值 460.8 ms、中位数 460.2 ms），六次 AX 浅深端点均正确。按下到首个移动事件为 189–201 ms，属于输入工具的拾取等待，不计入移动跨度。隐藏/暂停生命周期取消回退已于 2026-11-17 原生复核通过；OS 未发出 `PointerCancelEvent`，故系统 pointercancel 对照与最终用户签收仍未完成。原始事件和 SHA-256 见末尾时间戳记录。 |
| 按钮样式/尺寸双主题 Profile fixture | 隔离 bundle `io.github.guog962464.aggregate.ui6focusafter`，macOS Profile，800×600 logical px 内容区、截图 scale factor 2。深色：`/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-all-buttons-profile.png`、`stage6-all-buttons-profile-scroll-1.png` 至 `scroll-5.png`；浅色：`stage6-all-buttons-profile-light-top.png`、`stage6-all-buttons-profile-light-glyphs.png`、`stage6-all-buttons-profile-light-states.png`、`stage6-all-buttons-profile-light-states-2.png`、`stage6-all-buttons-profile-light-states-3.png`。覆盖 12 类 96dp glyph reference、primary/secondary/icon/playback/reference 五种尺寸，以及 navigation/segmented/danger/busy/disabled 状态；临时 fixture 以浅色初始值构建以便导出，未改生产入口/偏好。截图记录静置材质样貌，不代表原生 click 动画逐帧或生产页面覆盖。选择截图 SHA-256：深色首屏 `9de4825c0fbb60593006ce8c399022bc5f8330ef59a4ec57bd1fd2094130aa66`，深色状态 `a7a9fcbbbb87b083c18d0cb921f30606d597bdf4dbed5b299d1748b19f6f6c33`，浅色 glyph `b7bcee23123f056e97576508187d75697828269ba5a17cedc0242347af30f7a4`，浅色状态 `eae16cdb21decc8b33682fe1f8f935e8644722fcfcb77abf68290a746118fb60`。 |
| 结果边界 | UI-6.1 的固定宽度目录滚动、1024 主题拖动、800↔1440 连续缩放、工作台/连接/活动/设置四页联合滚动缩放及七类长列表/表单均有三轮 Profile 数据；该四页联合场景在缩放时往返滚动；另已完成三轮跨类别混合压力，包含按钮点击、播放控制、主题拖动、滚动、原生窗口 Fill/Restore 和隐藏/恢复，详见 2026-11-17 专项记录。90 字段表单原始三轮有一轮超 100 ms build 长帧，另补三轮未复现，原因未定位。450 ms 实时指针序列和取消已由 Widget 回归覆盖；原生六次双向拖动以逐事件时间戳核验，移动跨度 455.4–466.1 ms；2026-11-19 三轮 800×632 主题拖动的逐事件跨度为 450.12–454.15 ms，5,416 个提交帧中没有超 16.667 ms 的 Flutter build/raster 帧。2026-11-17 实窗确认应用隐藏时会取消活动拖动，迟到释放不会切换主题；OS 未发出 `PointerCancelEvent`，故原生 pointercancel 对照仍未完成。UI-6.2 的宽度/主题/连续缩放与六类长列表场景无 >100 ms build/raster 帧；表单原始样本和隐藏恢复各有一次超过 100 ms 的帧，表单另三轮未复现，隐藏恢复的原始单次 102.132 ms 在三次约 12.9 s 定向复测中未复现，根因仍未定位；帧数据不证明实际显示呈现 FPS。主题拖动 Profile 三轮未复现本次主观卡顿反馈，但也不能证明问题已修复。UI-6.3 已完成 UI-0 同机端点点击基线与当前拖动场景的方向性对照，输入不完全相同；视频关键相位已有离线对照，真实呈现 FPS 未验证。UI-6.4 的系统 Reduce Motion 运行中开关更新及 hidden/paused 主题拖动取消回退已原生验证，但隐藏恢复长帧仍未定位；UI-6.5 的路由循环、RSS、所有权审阅和 Dart VM 托管对象计数已按条款通过；GPU/native 分配及 controller 活跃状态未测，不作推断。UI-6.6/6.7/6.8 仍部分通过；UI-6.9 的代理静态截图自验已完成，但全部产品按钮实例和动态状态未逐项覆盖；UI-6.10 尚未完成。 |
| 变更范围 | 修改共享 Flutter 页面栈布局、主题开关焦点环的绘制层级、玻璃按钮的可见性复核调度、工作台长目录、连接首页/管理连接长目录与能力明细、音乐长搜索结果、活动长列表和大型运行参数表单的惰性构建；表单校验覆盖全部 schema 字段，没有改 Android 专用代码、主题模拟/校准算法、Runtime 协议、主题映射或切换逻辑。临时 Profile fixture、Runner 窗口注入和诊断分支均已清理。`pubspec.lock` 保留任务前 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 提交/远端 | 首次 UI-6 报告提交 `98749bb2536420c3e43acd6a4f3409ccac608bcf` 只包含验收文档；既有工作台/活动子阶段提交 `fd11345ff311a52eaf1bce9d180498b001729be1`。本轮 90 字段参数表单实现、回归与验收记录提交 `490d13d390e3b6521e07e63e8e2ddddff75899ec`；主题开关焦点环绘制层级修正另提交 `fa4e90ec55a612af39729840f499c1b39b535e5e`，GitHub 与 Gitee 分支均核对为该 SHA。后续生命周期和资源所有权审阅继续只按其实际证据记为部分验证，该性能子任务交付不代表 UI-6 或整套 UI 适配已完成。

## 后续阶段

UI-0～UI-5 已按阶段独立提交；未通过的对比度与 VoiceOver 项仍保留为限制。UI-6 新增联合滚动缩放三轮、活动页长列表性能回归、UI-0 同机方向性基线、隐藏恢复观察、RSS 页面循环与 Dart VM 对象计数；UI-6.5 按既定范围通过。禁用态原生语义、长帧根因、PointerCancelEvent、逐帧动态视觉对照和最终交付记录仍待完成；阶段尚未交付；生产页面静态截图自验已完成。

### 2026-11-15 生产页面双主题实窗抽查

- 构建：macOS Profile，入口 `lib/preview_main.dart`，隔离 bundle `io.github.guog962464.aggregate.ui6focusafter`。使用 PreviewRuntime 本地合成数据，不加载真实账户、连接或 Host。产品代码来自 `931008b340bc9c42abf3d1741e00876ac548c28b`；临时 bundle 配置只用于隔离应用身份。主题开关文件与当前工作区一致。
- 视口：窗口 AX bounds 为 800×632 logical px；导出 PNG 为 1824×1488 像素。每页采集浅/深主题首屏，共 10 张；工作台与设置页各补底部滚动样本，共 4 张；另采设置页深色侧栏焦点和主题开关焦点样本，共 3 张。合计 17 张。
- 生产页面样本对应连接首页（示例网易云音乐）、工作台（侧栏“所有功能”）、管理连接、活动和设置五页，可核对主要材质、页面层级和控件位置。初版标为 home 的两张图经 OCR 复核实际为设置页，已重新捕获连接首页并替换；随后逐张核对 17 张图片的页名与画面内容。代理在本轮范围内完成静态视觉自验，未发现明显的整体背景断层、材质层级或主要控件位置问题。截图均为静置状态，不能证明页面内全部按钮实例已逐项复核，也不构成点击动画逐帧、帧呈现率或 VoiceOver 语音验收。
- 证据目录：`/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-production-pages/`。文件与 SHA-256（`shasum -a 256`）：

| 截图 | SHA-256 |
| --- | --- |
| `activity-dark-top.png` | `e7ed2dafdf3620e55b4ba196585ba1bccb30eeea23151d7a69fcb8bb2d480c8b` |
| `activity-light-top.png` | `dfa1a3befe41a32bffe4e77a5b5f311098842b65caf3236f5f6868a892d7ac5f` |
| `all-functions-dark-bottom.png` | `2bb661cdc1ded614832dfc38cb04f4392d012bf60c0e2af0f05e739b82e605c7` |
| `all-functions-dark-top.png` | `4f0f6e10f499282813d2b1c59e86d6f74dd9d490f0fb3f5d951c034545a998f6` |
| `all-functions-light-bottom.png` | `68d93e6792d580c6021d686d7ed67c7210abf386960591d5c3f5b6c521c68d64` |
| `all-functions-light-top.png` | `821476fac8c4699675f956e2cae58078c050cf5c04b14eada4c4e8e4d3a2d41f` |
| `home-dark-top.png` | `29e4ebb0c3be1ad51924cbba64d350c660867a93177a1e54988113beadbb7e48` |
| `home-light-top.png` | `2bef0a64935815ced4f90d6e5207bda3d2845e666ec4f750dbf96b6b06cc8230` |
| `manage-connections-dark-top.png` | `479a77cb0a3a888d4cb646d91e3ded753a83cc8d98b7d1ef2dca055259657b26` |
| `manage-connections-light-top.png` | `5ed87ca0f5651d0826b3c5de5bf62d40d8d153af11ecddab401a7f52ef054fda` |
| `settings-dark-bottom.png` | `1464569d2f575448a2bc95b911d0fcf91efc53f04ebbe14fa3c394efdb7bea7f` |
| `settings-dark-sidebar-focus.png` | `7995184013ef2496b3449b381dd21517332bfd746b36afc9f3a7cf67e5320509` |
| `settings-dark-theme-focus-controlled.png` | `e4b36f8b2a7116c075d740107732db5deb0348e9c93ae3ec3af15b7ddfb2ccb7` |
| `settings-dark-theme-focus.png` | `5246307a28c6895a24a40102e5ba5a591ff3fbd0f23f863b9705996e60166265` |
| `settings-dark-top.png` | `8dbf1500739fc0171c47176bb7109d69aa008f3d4c206d080719bea064c5dcba` |
| `settings-light-bottom.png` | `b137ed51f28a6dedafa6bce68303b81120abc7b734f4abe25819c6cf55c7f4b2` |
| `settings-light-top.png` | `d4a71fa4707a282d1c18287383b3d0c29286db28025071f09da4530acd910d9f` |

- 自检：PNG 尺寸由 `sips` 检查；主题值和受控焦点状态由隔离 Profile 窗口的 AX 查询确认；所有图像均重新计算 SHA-256。该子阶段只更新验收文档，未重跑产品测试；`git diff --check` 作为提交前检查。
- 状态：生产页面静态截图抽查和代理自验完成；UI-6 仍部分验收。禁用态原生 AX 语义、原生拖动取消、间歇性长帧原因、原生资源对象数量及全部按钮动态状态复核仍待补齐。焦点环浅深主题合成像素对比已通过下方新记录。

### 2026-11-15 VoiceOver 增强树复测

- 环境：macOS 隔离 Profile 探针；VoiceOver 在系统设置中从关闭切到开启，并确认应用原生属性 `AXEnhancedUserInterface=1` 后再查询。3.47.8 / Dart 3.13.7 / Engine revision `cf636b1dfb`；测试入口和依赖修改均在 `/private/tmp/aggregate-ui6-focus-after`，未改本仓库文件。
- 探针含一个禁用 `GlassActionButton`、一个 `Semantics(enabled: false, button: true)` 包裹的禁用 `TextButton` 和一个可用 `TextButton`。屏幕上三者均可见；增强 AX 树提供四个按钮节点（语义包装节点与其子节点重复暴露同一标签）。直接读取 `kAXEnabledAttribute` 时四个节点全部为 `true`，`agent-desktop` 快照也没有禁用状态；这确认了 3.47.8 当前构建下的禁用态原生 AX 失败，而不是只在 VoiceOver 关闭时出现的空树假象。
- 同一夹具用 Flutter 3.50.0 / Dart 3.14.0 / Engine revision `371f77202a` 补做对照。VoiceOver 开启、`AXEnhancedUserInterface=1` 时，两个禁用语义节点在 AXChildren 中存在，但 `AXRole` 及名称属性不可读；`agent-desktop` 仅识别可用按钮。3.50.0 因而也未通过此项，不能仅凭 bridge 源码变更认定语义已修复。
- 已在系统设置关闭 VoiceOver，退出并重新启动隔离探针；复核开关为关闭且新进程的 `AXEnhancedUserInterface=0`。本次没有录制/验证实际朗读音频，因此不把它记为 VoiceOver 语音走查通过。没有修改 Flutter 页面、切换按钮逻辑或生产配置；`pubspec.lock` 继续保留原工作区用户修改并未纳入任务。
- 结论：UI-6 禁用态原生语义仍失败；应用层 Widget Semantics 测试不能代替 macOS engine AX 导出结果。需要项目采用经实机 VoiceOver 验收通过的 Flutter engine 后再关闭该缺陷。


### 2026-11-18 设置页真实 shader 相位跟随

- `GlassSceneFrame` 暴露一个只在 `switchDaylight` 跨越 0.5 时变化的前景明暗监听器；`AggregateApp` 用它重建语义文字主题，`PageFrame` 为无显式样式的正文继承当前 `bodyMedium`。shader 仍每帧绘制，保留任意拖动、主题开关交互及 560 ms 全局主题转场。
- macOS `AggregateApp` 设置页回归在深→浅和浅→深方向各逐 16 ms 检查 40 帧，断言正文前景与生产 `ThemeSwitchArtwork.frame.theme` 的亮暗侧一致；阈值单测覆盖同侧连续帧不重复通知。`glass_design_tokens_test.dart`、`glass_theme_switch_test.dart`、`accessibility_test.dart`、`macos_reduce_motion_test.dart`、`page_frame_test.dart`、`widget_test.dart` 六个测试文件通过，`flutter analyze --no-pub` 无问题。
- 另用 1024×768、DPR 2 的生产 shader 离屏合成作诊断采样：约 112 ms 有一处保守边缘像素比为 4.478:1；约 119 ms 切为黑色前景后同一采样方法为 5.317:1。112 ms 的前景仍与 shader 相位一致；该栅格边缘比值未记录指定前景/背景色对，不能作为规范通过或失败判定，详见下方方法复核。离屏读回不能代表原生 display-present；本次探针截图已清理，UI-5.5 继续部分验收，尚缺实际色对、原生窗口逐帧和其他材质/状态矩阵。

### 2026-11-18 UI-5.5 对比度边缘采样方法复核

- 复核对象：上方设置页真实 shader 相位跟随记录中的 4.478:1 / 5.317:1，是 1024×768、DPR 2 离屏图像上的保守边缘像素读数。原始探针图已清理，现有记录没有保存像素坐标、抗锯齿覆盖率、对应的字形内点或指定背景色样本。
- 判定：WCAG 2.2 SC 1.4.3 要以用户代理/样式中的前景色与正常使用时指定背景色评估；抗锯齿屏幕边缘值不等于规范所测色对。W3C G18 也说明，图文亮度变化时可以对字形后方背景做遮罩，或按其所在位置调整文字亮度。故 4.478:1 不能独立作为失败数值，5.317:1 也不能代表全动画通过。参见 [WCAG 2.2 对比度说明](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum) 与 [W3C G18](https://www.w3.org/TR/WCAG20-HTML-TECHS/G18.html)。
- 结论与后续：撤销“该边缘采样略低于 4.5:1 即动态对比失败”的结论，不据此改产品颜色或背景。UI-5.5 仍部分验收；待获取实际指定文字色、对应文字后方背景色和动画样本，再覆盖禁用态及其他页面材质。该方法修正不构成实窗或 display-present 证据，也未重跑产品测试。

### 2026-11-18 设置页动态 shader 文字描边验收

- 色对测量：以真实 `AggregateApp` 设置页正文 `主题选择保存在本机。` 的文字矩形为采样区域，在 1024×768 logical px、DPR 1 下，以生产 `glass_scene.frag` 单独绘制同尺寸背景。201 个等距 `switchDaylight` 进度点各取正文区域 9×3 个背景样本，并使用当前指定纯黑/白文字色计算 sRGB 相对亮度对比。白字在 0.475/0.480/0.485/0.490/0.495 时最低为 `4.478/4.415/4.353/4.292/4.233:1`；黑字在 0.500 时为 `4.493:1`。这证明颜色交接附近确有正文色对低于 4.5:1，而单独把文字颜色交接阈值移到附近也不能覆盖这段背景。
- 修正：不改 `ThemeSwitchSimulation`、0.5 文字颜色交接、shader daylight、560 ms 曲线、任意拖动、端点业务回调或按钮标签。在 `GlassSceneFrame` 另外发布只在阈值变化时通知的描边状态：daylight `0.46–0.51` 时，对正文/标题/列表文字应用 8 个方向、1 logical px 的相反色轮廓；ThemeData 文字颜色和背景仍按原来的 0.5 分界。按钮标签不加轮廓。该做法采用 [W3C G18](https://www.w3.org/WAI/WCAG21/Techniques/general/G18) 对变化背景文字使用轮廓或光晕的方案。
- 回归：`macos_dynamic_backdrop_text_contrast_test.dart` 用生产 shader 在设置页真实正文矩形取样，覆盖 800×600、1024×768、1440×900 三种窗口尺寸各自 1×/2× 六组组合；检查轮廓对背景至少 3:1、正文色与轮廓至少 7:1，轮廓区外所测正文色对至少 4.5:1。`glass_design_tokens_test.dart` 检查轮廓样式、按钮标签排除和阈值去抖；`macos_reduce_motion_test.dart` 在真实双向转场逐帧检查轮廓显示窗口及既有文字色交接。合计 13 项定向 Widget 用例通过，相关六个源码/测试文件的 `flutter analyze --no-pub` 通过。测试只读离屏 shader 样本，不证明 macOS display-present 或 VoiceOver 朗读。
- 结论：设置页中段正文的对比呈现修正通过自动化验收；UI-5.5 仍部分通过。尚需浅色初始态、标题/列表/禁用态、其他页面材质以及原生显示捕获。

### 2026-11-18 UI-5.5 浅深初始主题动态采样

- 补验目标：确认设置页文字描边与前景交接回归在浅色偏好启动时也覆盖正确的生产 shader 背景，而不只在深色偏好启动时成立。
- 方法：`macos_dynamic_backdrop_text_contrast_test.dart` 现在分别以深色、浅色偏好启动真实 `AggregateApp` PreviewRuntime，再对设置页正文实际矩形重复生产 `glass_scene.frag` 的十个转场相位采样；窗口为 800×600、1024×768、1440×900，DPR 各为 1×/2×，合计 12 组启动偏好/窗口/DPR 组合。每相位仍检查中段描边对背景至少 3:1、正文色对描边至少 7:1，轮廓区外文字色对至少 4.5:1，并在基准样本确认描边窗口确有必要。
- 样式范围：每个相位另断言页标题、分节标题、正文/副标题和 `ListTile` 标题/副标题同步采用当前黑/白前景及八向描边；三种标签文字维持无描边。此项验证 ThemeData 样式传播，不把其他文字矩形登记为已完成像素采样。
- 结果：`flutter test --no-pub --reporter compact test/macos_dynamic_backdrop_text_contrast_test.dart` 通过；`dart format` 无改写。该测试从十个相位重放 shader 状态，不是原生窗口的实时输入或 display-present 捕获。
- 结论与边界：关闭了该回归的“仅深色偏好启动”缺口。禁用态、其他页面材质、VoiceOver 与原生显示捕获仍待验收，UI-5.5 继续部分验收。未改主题模拟、按钮交互或生产色彩阈值。

### 2026-11-18 UI-5.5 设置页多区域文字相位补验

- 覆盖：把生产设置页采样区扩为页标题、页副标题、分节标题、正文和两条快捷操作 `ListTile` 标题，共六个实际文字矩形；每个矩形在 3×3 窗口尺寸/DPR 配置及浅/深初始偏好下，按 12 个临界 daylight 相位采样生产 shader 背景。`headlineMedium`、`titleMedium`、`bodyMedium`、`bodySmall`、ListTile 标题/副标题在每相位断言文字前景与 8 向轮廓；`labelLarge/Medium/Small` 断言无轮廓。
- 新缺口：扩展后的矩阵首次发现 `1440×900@1x`、深色偏好启动时，`ListTile: 运行当前功能` 在 daylight `0.515` 的黑字/背景为 `4.428822:1`，此时旧描边窗口已经关闭，低于项目 4.5:1 门槛。
- 修正：把 `GlassSceneFrame` 描边结束阈值从 `0.51` 扩至 `0.52`，仅影响正文、标题、列表文字的描边状态；文字颜色仍在 `0.5` 交接，主题模拟、560 ms 时序、任意拖动和按钮回调均未改。加入 `0.52` 描边边界与 `0.525` 无描边边界采样。
- 验证：浅/深启动各六组窗口/DPR、每组 12 个相位（合计 144 个组合）均通过；轮廓/背景至少 3:1、文字/轮廓至少 7:1，轮廓区外指定文字/背景至少 4.5:1。`flutter test --no-pub --reporter compact test/glass_design_tokens_test.dart test/macos_reduce_motion_test.dart test/macos_dynamic_backdrop_text_contrast_test.dart` 13 项通过；相关四个 Dart 文件的定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。
- 边界：背景数值来自 `GlassScene` 离屏渲染，而不是整页半透明表面合成或 macOS display-present；本轮只扩展设置页六个文字位置，不关闭其他页面材质、禁用态、VoiceOver 或原生显示验收，UI-5.5 保持部分验收。

### 2026-11-18 UI-5.5 多路由标题临界相位补验

- 覆盖：在生产 `AggregateApp` 中采集音乐首页、工作台、连接管理、活动和设置页标题的真实屏幕矩形，并保留设置页副标题、分节标题、正文及两条快捷操作 ListTile 标题；共十个位置。每个位置继续使用同尺寸、同 ThemeData 的生产 `GlassScene` shader 背景样本。
- 新缺口：新增音乐首页标题位置后，发现 `1024×768@1x`、深色偏好启动、daylight `0.525` 的黑字/背景最低为 `4.428822:1`；此前描边结束值 `0.52` 仍太早。
- 修正与结果：将描边结束值扩至 `0.53`，前景文字色仍于 `0.5` 交接。增加 `0.53` 描边内相位和 `0.535` 无描边相位；两种初始偏好、六组窗口/DPR 和 14 个相位共 168 组组合全部通过。描边区检查背景对比至少 3:1、文字/描边至少 7:1，窗口外检查文字/背景至少 4.5:1；所有位置每相位同时核对标题/正文/ListTile 样式和按钮标签例外。
- 验证：`flutter test --no-pub --reporter compact test/glass_design_tokens_test.dart test/macos_reduce_motion_test.dart test/macos_dynamic_backdrop_text_contrast_test.dart` 13 项通过；`flutter analyze --no-pub` 针对 `glass_scene.dart` 与三个相关测试文件通过，`git diff --check` 通过。
- 边界：这些数值是逐路由文字位置上的离屏 `GlassScene` 背景色对，不是各页面卡片、按钮或半透明表面合成，也不是原生 display-present。其他页面材质、禁用态、VoiceOver 与原生呈现仍未完整验收，UI-5.5 保持部分验收。


### 2026-11-18 UI-5.5 玻璃操作按钮文字相邻材质采样

- 新缺口：实际合成场景里，禁用/忙碌文字及说明、来源小字沿用 `muted` 后，在浅深过渡期间无法保证与各自玻璃按钮面的 4.5:1；同时不能把正文亮暗交接直接套给按钮，因为按钮材质仍属于当前选择的主题。
- 修正：`withMacOSBackdropTextContrast` 保留玻璃令牌的当前主题色。非危险按钮标题（包括禁用/忙碌）继续使用主题正文色；说明/来源小字以 `muted` 向正文色调整 18%，保持次要层级。危险文字仍使用危险色。禁用面 `.52` 透明度、语义状态、图标、点击和动效规则不变；按钮文字不加转场描边。
- 验证：`macos_dynamic_backdrop_text_contrast_test.dart` 在 1024×768、DPR 1 的 `AggregateApp` PreviewRuntime 设置页，对普通、禁用、忙碌、危险按钮标题及禁用说明/来源共六类文字，覆盖浅/深两种初始偏好和 14 个临界相位（168 组文字/相位组合）。每个文字基线右侧的同一按钮面取三个未被文字覆盖的相邻像素，全部达到 4.5:1；按钮文本无阴影。该取样较此前错误映射到工具栏按钮的采样已修正。本轮四个回归文件共 25 项通过，六个 Dart 文件定向 `flutter analyze --no-pub` 无问题，格式检查和 `git diff --check` 通过。
- 边界：此处是离屏合成中同一玻璃按钮面相邻像素样本，不是 glyph 下方精确背景反演，也不是 macOS display-present。只覆盖设置页合成样本，不覆盖全部 109 个按钮调用点、其他页面材质/状态、VoiceOver；UI-5.5 仍部分验收。

### 2026-11-18 UI-5.5 内容表面与按钮文字插值补验

- 新缺口：把可读性检查扩展到整个深浅主题混合过程后，正文在 `surfaceContainerLow` 上曾落到 4.499:1 附近；按钮的透明禁用面与危险标签也不能只用端点色或玻璃渐变的单一中点推断。
- 修正：`withMacOSSurfaceTextContrast` 同时检查 `surface`、`surfaceContainerLow`、`surfaceContainer`；找不到同时满足 4.5:1 的纯黑/纯白前景时，页面文字使用 8 向零模糊轮廓，并保持文字/轮廓至少 7:1、轮廓/三种表面至少 3:1。玻璃按钮文字按按钮渐变位置和禁用态 `.52` 面透明度估算材质；跨越灰阶临界区时以同一轮廓规则提供过渡对比。`GlassDesignTokens` 继续承载主题端点材料，按钮面透明度、状态语义、交互和太阳/月亮切换逻辑不变。
- 验证：`glass_design_tokens_test.dart` 对深到浅的 101 个 ThemeData 插值点、6 种页面文字样式和 3 种内容面逐点验证；`macos_dynamic_backdrop_text_contrast_test.dart` 对普通、禁用、说明、来源、忙碌、危险六类按钮文字共 12 个标签样本，覆盖 secondary、primary、reference 三类尺寸；在 1024×768、DPR 1 的每个插值点采同按钮面 3 个相邻像素，逐点验证文字对比或轮廓规则。玻璃令牌/按钮/reduced-motion/文字对比度四个测试文件共 27 项通过；七个 Dart 文件定向 `flutter analyze --no-pub` 无问题，格式检查与 `git diff --check` 通过。
- 边界：跨表面/主题插值用 ThemeData 和 Widget 离屏合成，按钮像素取样是文字旁同一按钮面的邻近像素，不是 glyph 下方背景反演，也不是原生 display-present。未覆盖所有 109 个调用点、全部页面材质状态矩阵、VoiceOver 和无障碍认证；UI-5.5 继续部分验收。

### 2026-11-15 浅深主题焦点环合成像素验收

- 构建：隔离 bundle `io.github.guog962464.aggregate.ui6focusafter` 的 macOS Profile；项目 Flutter 3.47.8 / Dart 3.13.7，PreviewRuntime 本地合成数据。窗口 AX bounds 800×632 logical px，DPR 2，导出 PNG 为 1824×1488。通过物理 Tab 到达主题开关焦点，使用左右键切到浅/深端点；焦点状态由实窗完整轨道环可见性与 AX 主题值复核。
- 复测发现原浅色 `glow` 焦点色对玻璃轨道的局部对比未达到 3:1，新增 `GlassDesignTokens.focusRing`：浅色 `#6F3C0D`，深色 `#8B9AFF`。主题开关轨道环与所有玻璃按钮焦点描边共用该语义令牌，太阳/月亮模拟、拖动积分、键盘映射及偏好逻辑没有改动。
- 像素方法：将 PNG 颜色解码为 sRGB 线性相对亮度，在焦点环上、下、左、右直线段各取环像素，并分别与环的内、外相邻材质像素比较；报告 8 组局部比值中的最小值。浅色最低 `3.30:1`（下侧内缘）；深色最低 `3.93:1`（下侧内缘），均高于本项目 3:1 目标。此项只验证静态端点下焦点提示，不覆盖主题拖动中间帧、其他 focus style/材质或 VoiceOver 语音。
- 浅色焦点样本：[settings-light-focus-ring.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-focus-contrast/settings-light-focus-ring.png)，SHA-256 `ea0cd5ce04019ad4c08f1236c3b37f73240bf31d0defc17c222d98d58e0b9ea1`。深色焦点样本：[settings-dark-focus-ring.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-focus-contrast/settings-dark-focus-ring.png)，SHA-256 `af193d0d74499c8a4aef964709b03d9b21b8cb77cd1949629de13b667ad1451b`。
- 验证：`flutter test --no-pub` 全量 286 项通过（含新增 focus ring token 对比测试）；`flutter analyze --no-pub` 无问题；macOS Profile 构建成功；`git diff --check` 通过。本次复测只运行隔离包，未接触正式账户、连接或 Host。
- UI-5.5 / UI-6.6 仍为部分验收：普通文字/端点按钮样本和焦点环目标已达成，中间态、禁用态及其他页面材质的完整合成矩阵仍未完成；UI-6 其他原生性能、资源数量、VoiceOver 与最终视觉签收项不因本记录而关闭。

### 2026-11-15 原生主题约 450 ms 事件时序校准

- 构建：隔离 Profile 应用 `io.github.guog962464.aggregate.ui6focusafter`，本地 PreviewRuntime 设置页；macOS 屏幕逻辑坐标、浅/深滑块中心分别为 `(896,588)` / `(816,588)`；没有连接真实账户、服务或 Host。
- 测量：独立 Swift 小程序先调用 `CGPreflightListenEventAccess`，随后用只读 `CGEvent.tapCreate(..., options: .listenOnly)` 仅记录该控件附近的 `leftMouseDown`、`leftMouseDragged`、`leftMouseUp` 时间戳与位置；不拦截、不合成、不修改事件。首轮 `agent-desktop drag --duration 450` 两向各一次，首末 `leftMouseDragged` 间隔为 `524.015 ms`（浅→深）和 `517.868 ms`（深→浅），说明 CLI 参数本身高于目标实际跨度。
- 校准：`--duration 397` 下执行六次交替拖动（浅→深、深→浅各三次）；每次记录 25 个 `leftMouseDragged` 事件。首末拖动事件间隔分别为 `456.914 / 460.267 / 465.968 / 466.076 / 455.386 / 460.112 ms`，均值 `460.787 ms`、中位数 `460.189 ms`、范围 `455.386–466.076 ms`；距 450 ms 目标的均值偏差约 `+2.4%`。六次操作后辅助树的浅深端点值均逐次交替，最终为 `深色`。
- 分界：从 `leftMouseDown` 到首个 `leftMouseDragged` 的拾取等待为 `189–201 ms`；移动跨度从首个至最后一个拖动事件计，抬起另晚 `17.1–24.6 ms`，所以不把拾取等待混作连续移动时间。事件样本证实了原生输入节奏接近 450 ms，不等于验证主题光效每个渲染帧的相位或真实显示器呈现 FPS。
- 证据：[450 ms 请求·浅到深](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-native-drag/duration450-light-to-dark.jsonl>) SHA-256 `c83a7a82b547797c33280144bb9e6c760af0080afc55ea91ffc62a891f8e679b`；[450 ms 请求·深到浅](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-native-drag/duration450-dark-to-light.jsonl>) SHA-256 `cc3d5dec744db835cb6e45ee3281b7450337e907d931b09ab8787e04ba93e88c`；[校准后的六次事件](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-native-drag/six-drags-duration397.jsonl>) SHA-256 `76f3a52688677384c48584bdb63579ca8cc8bd0692547e29b3ea6c6391e75727`。
- 取消尝试：1,600 ms 拖动期间发送 Escape 没有卸载设置页，最后仍走完整释放并切到深色；不能算 pointercancel。native pointercancel 与 Widget 已有取消回归的实窗对照仍未完成。UI-6.1/6.8 保持部分验收；UI-6.3 的原生事件时序子项已有证据，其关键相位和呈现帧率仍待补。
- 本次只有隔离夹具输入和验收记录；没有修改产品源码、太阳/月亮算法、拖动积分、主题映射或偏好逻辑。

### 2026-11-15 原视频指针轨迹 Profile 实时对照

- 构建：macOS Profile 隔离应用 `io.github.guog962464.aggregate.ui6profile`，使用本地 PreviewRuntime 合成设置页；浅色开关起始为深色，完成原视频路径后由原生 AX 确认为浅色。系统 `reduce_motion=false`。没有连接真实账号、服务或 Host，也没有触碰用户的 Debug 实例。
- 输入：以源视频测得的可见滑块中心坐标和帧时刻重建一条连续鼠标路径，使用原生指针实时拖动，未回放固定动画帧。只读 CoreGraphics event tap 收到 mouse down 1 次、drag 55 次、up 1 次；最大坐标差为 `0.0000298 px`（x）与 `0 px`（y），相对源采样的事件时差范围为 `-5.8678–+4.1161 ms`，down 到 up 共 `1818.14 ms`。源坐标由视频中可见滑块中心反推，不能恢复原始物理鼠标硬件轨迹。
- 捕获：ScreenCaptureKit 获得 166 张 `720×540` 实窗帧。捕获帧的中位间隔为 `16.66646 ms`，最大间隔 `33.33296 ms`；callback 与媒体 PTS 差为 `-10.5858–+3.0302 ms`。这组间隔含至少一次丢采样，不是显示器实际 present FPS。
- 对照：无注册、无颜色校正，在控件 ROI `(170,155)-(550,410)` 内计算 MAE；只排除源图没有、实窗里可知位置的 `55×55 px` 鼠标指针。目标源帧 137（PTS `3.058911 s`）与对应实窗帧 87（拖动后 `1143.60 ms`）的 MAE 为 `72.0527/255`。在目标前后 0.5 秒源帧中，最近视觉匹配是源帧 136（PTS `3.003222 s`），MAE `5.4114/255`，对应最近帧偏差约 `-55.6889 ms`。对照图：[source-live-phase-comparison.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-7/source-live-phase-comparison.png)，SHA-256 `c6dff3ea80293a1178748971714e5b343bf135a924a02a18a56f2d5ab7c49c7a`；事件记录 SHA-256 `e0f15a482ab888eac146d9c7ea46a89ced2aa411b877bddc3067757a56b9a9e3`；分析 JSON SHA-256 `f97d7ca55e0985c10f7e134e0664a406e77cdd0203a90233f9ec9cee974e88a2`。
- 结果边界：输入轨迹的逐点坐标与节奏已对齐到测量精度，但实时实窗的太阳/月亮图像和光效没有在目标时刻逐帧匹配，UI-6 动态视觉仍未通过。约 `-55.69 ms` 是由最近源帧推算的估计相位差，不是确定的物理延迟：路径只能重建可见滑块中心，录屏存在 33.33 ms 采样间隔，且没有显示器 present 时间戳。相同进度的光效差异提示仍需检查动效相位/映射；本轮没有据此修改模拟、拖动或切换逻辑。
- 自检：用户的主题开关逻辑保持原样，工作区产品源码未改；起点为深色、终点 AX 为浅色。截图与原帧对照图已目视复核。该子阶段只更新验收文档，本轮未重跑产品测试；`git diff --check` 为提交前检查。UI-6 仍部分验收，原生取消、动态相位、原生资源计数、恢复长帧根因、VoiceOver 语音和最终视觉签收均未因此关闭。

### 2026-11-15 原视频轨迹输入采样率复核

- 目的：确认前次约 `-55.69 ms` 的最近源帧偏差是否只由源轨迹反向段 `55.69 ms` 的稀疏采样空档造成。重新构建同一可见滑块中心轨迹，按 60 Hz 线性插值发送实时鼠标输入，不回放画面帧。
- 构建与状态：隔离 macOS Profile `io.github.guog962464.aggregate.ui6profile`，模拟与校准配置与当前源码一致，仅无关的焦点环绘制不同；起始深色 AX 值及稳定深色截图均确认，系统 `reduce_motion=false`，结束浅色 AX 值确认。仅操作此隔离进程，没有触碰用户 Debug 实例、真实账户、服务或 Host。
- 输入：56 个源视频可见滑块中心样本插值为 110 个计划位置；只读 CoreGraphics event tap 收到按下 1 次、拖动 109 次、释放 1 次。最大坐标误差 `0.000029 px`；相对源视频采样的事件时差 `-0.339–+4.383 ms`；按下到释放 `1818.625 ms`。事件日志：[计划输入](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz/events.jsonl>) SHA-256 `7f42fd85ed45c61c420244373f34e2339a8c56629b33633754bdd05310c84626`；[系统实际输入](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz/observed-events.jsonl>) SHA-256 `21809f3827ef63989af4957e03901b7ead97b067ad59656e789dd4d96f003876`。
- 捕获：ScreenCaptureKit 获得 165 张 `720×540` 实窗帧，中位样本间隔 `16.666 ms`、最大 `33.333 ms`；callback 与 PTS 差为 `-12.363–+4.983 ms`。样本间隔不等于显示器实际呈现 FPS。
- 对照：不做图像注册或颜色校正，在原 ROI `(170,155)-(550,410)` 全程 52 个隔帧样本上，对全量、左侧背景、开关主体、点阵核心扫描 `-160..+160 ms` 的全局源序列偏移，步长 `2 ms`。最低误差分别出现在 `-46 / -46 / -46 / -42 ms`；同时间 MAE 分别为 `20.380 / 18.488 / 24.792 / 29.394`，移至最优偏移后分别为 `8.452 / 7.523 / 12.577 / 17.258`。目标帧 137（PTS `3.058911 s`）最近的实窗帧 87（拖动后 `1147.252 ms`）MAE 为 `68.603/255`；源前帧 136 的 MAE 为 `6.300/255`。对照图：[60 Hz 同步对照](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz/source-live-phase-comparison-60hz.png>) SHA-256 `0bf4a6eac6223bfaf82526d6a7da27716361945749572c7c6367c7ae525a7df9`；[分析 JSON](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz/native-live-analysis-60hz.json>) SHA-256 `c6494d6a8e8cec3de09103f01640cc882ed612e7a55092a5988ae83cf14106f8`。
- 复核结论：改为 60 Hz 后偏差仍约 `42–46 ms`；另一次 120 Hz 实时插值采集的全局最优偏移为 `-52 ms`（开关/点阵区域 `-60 ms`）。因此“仅由反向处源点稀疏”及“120 Hz 事件过密”两种解释均不足以说明现象。视觉相位差仍未通过；源可见中心不等于原始物理指针，视频 PTS 与实窗捕获均没有显示器 present 时间戳，故这些数值表示图像序列对齐量，不是确定的产品输入至光子延迟，也不足以单独支持修改模拟参数。
- 自检：只读系统事件数、输入点位/节奏、起终 AX 值及静态端点截图均已复核；未改产品代码、太阳/月亮模型、拖动积分、主题映射或偏好逻辑。`git diff --check` 为本子阶段提交前检查。UI-6 仍部分验收。

### 2026-11-15 原视频轨迹末端停留响应复核

- 目的：在完整实时轨迹终点额外按住 500 ms，检查滑块和内部光效是否在释放前追到静止目标，以区分持续跟随误差与释放后的回弹。
- 环境：继续使用隔离 macOS Profile `io.github.guog962464.aggregate.ui6profile`、PreviewRuntime 设置页和 `reduce_motion=false`；初始 AX 状态为深色。未触碰用户 Debug 实例、真实账户、服务或 Host。输入路径是由源视频可见滑块中心插值出的实时 CGEvent，不是固定帧回放；只读 CGEvent tap 同步记录实际鼠标事件，ScreenCaptureKit 捕获 720×540、60 Hz 目标间隔的窗口区域。
- 输入：插值路径末端 `source_pts=3.058911111 s`、`relative_ms=1151.5 ms`、坐标 `(853.58,590)`；系统 tap 记录 down 1、dragged 70、up 1。最后一个拖动事件时间为 host `417394.336783 s`，实际 mouse-up 为 `417394.849927 s`，端点保持 `513.144 ms`。事件坐标误差约 `0.00003 px`；末端事件相对计划时刻约 `+0.9 ms`。结束后 AX 仍为深色，因为轨迹停在中间位置。
- 画面响应：末端后 `4.37 ms` 的最近捕获帧（`frame_0087.png`，PTS `417394.341151 s`）仍接近反向前的滑块位置；约 `20–54 ms` 间画面开始追到终点，至 `54.37 ms`（`frame_0090.png`，PTS `417394.391150 s`）已进入稳定位置。后续按住约 459 ms，滑块未等到 mouse-up 才归位；释放后的画面另有应用外层主题提交变化。由此可将“按住期间的可见跟随间隔”和“释放后的回弹/主题提交”分开观察。
- 证据：[输入计划](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz-reversal-hold/events.jsonl>) SHA-256 `f35fd65b1d155095d91a16dfaf7662e4309a46c5aecaab146b243ca32ed82d91`；[只读系统事件](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz-reversal-hold/observed-events.jsonl>) SHA-256 `04847d168f042fd21021984c76b36cee7c05b90d62afb9b6d4625a4cbde2e808`；[采样帧时间表](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz-reversal-hold/frames.jsonl>) SHA-256 `7f1c44a0bcc4cffb419f0ec9792818f26b002f4434aaa0cddcce16f895d6e99a`；末端即时帧 [87](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz-reversal-hold/frame_0087.png>) SHA-256 `3ccab0e041f395e9159a43acf7acfe8385b025ec6b3e79cb9a8af3a6e46d7b3d`；稳定帧 [90](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-live-frames/synchronized-capture-60hz-reversal-hold/frame_0090.png>) SHA-256 `02234dd5d5713ff66e74cb796830c77b375e8df025846d906979bdff05b622b2`。
- 结论边界：捕获帧不是 display-present 时间戳，约 54 ms 只表示这次系统事件到采样画面中稳定位置的时间差；不能据此把延迟归因于 Flutter build/raster、macOS 合成器或真实输入至光子时间。该路径为合成 CGEvent，也不代替手动拖动主观流畅性测试。因此未改主题拖动/切换逻辑或校准参数，连续视觉相位仍未通过，UI-6 保持部分验收。
- 自检：检查 tap 的事件类型/数量、末端事件与 mouse-up 的时间差、帧 PTS 序列、终点前后 PNG 及 AX 最终状态；未运行产品测试。`git diff --check` 作为文档阶段提交前检查。

### 2026-11-15 app 失焦期间原生拖动取消尝试

- 目的：检查切换到其他前台应用是否会使主题开关收到原生 pointercancel，并确认已开始的拖动不会在中断时错误提交。
- 方法：隔离 Profile 初始为深色；经 macOS CoreGraphics 事件路由按住左滑块 `(816,588)` 并拖至浅色端 `(880,588)`。拖动期间调用 Finder 激活，脚本确认 `activate()` 返回成功且 `NSWorkspace.shared.frontmostApplication` 为 `com.apple.finder`，随后在 Finder 仍为前台时对全局坐标 `(880,588)` 释放。另一个只读 session event tap 记录鼠标事件，没有拦截或更改它们。
- 结果：tap 收到 mouseDown 1、mouseDragged 1、mouseUp 1，拖动跨度约 `609.68 ms`；系统前台切换确已成功，但释放后隔离 Profile 的 AX 主题值变成浅色。这说明本次应用切换没有产生可验收的取消路径；拖动仍正常结束并提交，不得记为 pointercancel 通过。之后在隔离窗口内通过 AX 将主题恢复为深色并重新确认。
- 证据：[只读系统事件](</Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-native-drag/cancel-verified-attempt-events.jsonl>) SHA-256 `5e4a18f6bc842154608472d2630972dd02cdd95d5be26ed6ccb3b30f46b765ed`。脚本也在 mouse-up 前打印并确认 Finder 前台，释放后读取 AX 深色/浅色状态。
- 结论边界：这是一条合成 CGEvent 的原生 AppKit/Flutter 输入路径，不是物理鼠标测试，也没有直接观察到 Flutter `PointerCancelEvent`。因此 native cancel 仍未验证；此前 Escape 尝试和本次 app 激活都不能替代 pointercancel。没有修改控件逻辑，UI-6 保持部分验收。
- 自检：前台应用标识、系统事件序列、mouse-up 后 AX 终态，以及恢复后的深色终态均已核对；未运行产品测试。`git diff --check` 作为文档阶段提交前检查。

### 2026-11-15 云端阶段状态复核

- 复核基线：GitHub `guog962464-svg/Aggregate` 与 Gitee `shi-shan/aggregate` 的 `main`，两端 `git ls-remote` 均返回 `e630855dc039992ab7ebbfbfa5dc235c4b170564`。UI-3 实施提交为 `dc6967c`，UI-4 为 `8afa95b`，UI-5 实施/部分验收为 `f453980`；不重复声明这些历史检查在云端重跑通过。
- 本次仅校正阶段状态：UI-5.4 不能在后续原生禁用节点 `AXEnabled=true` 的失败证据存在时仍勾选通过；总览应区分已完成的设置页合成像素抽样与尚缺的完整状态矩阵。未改动产品源码、主题交互或依赖。
- 实际执行通过：`git diff --check`；`sh spikes/phase0/check_boundary.sh`（输出 `PASS public Flutter/core boundary`）；三个模拟/校准文件 SHA-256 与 UI-0 表逐字一致。
- 环境限制：当前仅可访问 Linux 云电脑，没有连接的 Mac，也没有可执行的 Flutter SDK。本次没有重跑 Flutter 测试、macOS 构建、VoiceOver、原生取消/生命周期、图像对象计数或帧时采样。历史 Mac 原始证据位于 Mac 本地，当前未重新读取。
- 结论：UI-0～UI-4 保持历史完成状态；UI-5/UI-6 保持部分验收。禁用态原生 AX、完整对比度与 VoiceOver、原生 pointer cancel、动态相位、间歇长帧、生命周期/对象计数和最终动态质感签收仍须补齐；不能因本次文档一致性校正而关闭目标。

### 2026-11-15 macOS CI 闸门修复与实测

- 起点 `e61e7fedf36508a4e46fa96ceeff926e2dde2062` 的 [run 43699234553](https://github.com/guog962464-svg/Aggregate/actions/runs/43699234553)：格式、分析、公共边界和 15 项共享包测试通过；Flutter 测试 273 通过、13 失败，macOS 构建跳过。此前仅查询 commit statuses 得到空数组，不能代表 Actions 通过。
- 独立提交 [`2020125`](https://github.com/guog962464-svg/Aggregate/commit/2020125ba93a07ae6c1176086512d0df538b3b31) 将 CI 的 UI 测试工作目录设为 `app`，执行 `flutter test test`，与 `tool/check.sh` 一致。4 个 fixture 文件路径静态核验可达。[run 43726553133](https://github.com/guog962464-svg/Aggregate/actions/runs/43726553133) 实测 283 通过、3 失败：8 项缺 fixture 与 PTY native asset 错误不再出现；Android arena-release 此轮也通过，但未据单轮结果定位其历史失败原因。剩余 3 项均为 NCM 环境相关测试，构建仍跳过。
- 独立提交 [`2ccb960`](https://github.com/guog962464-svg/Aggregate/commit/2ccb960da002e0fb5ca54296ba858113a15cdc3c) 在 CI 明确检查 Node、在 mpv 缺失时通过 Homebrew 安装真实 mpv，再打印版本。没有跳过或弱化用例，没有用假 mpv 替代生产环境检查；测试原有的本地 ncm-cli shell fixture 保留，不连接真实音乐服务或账号。
- [run 43727152456](https://github.com/guog962464-svg/Aggregate/actions/runs/43727152456) 对精确提交 `2ccb960da002e0fb5ca54296ba858113a15cdc3c` **成功**：锁文件恢复、格式、分析、公共边界、15 项共享包测试、286 项 Flutter 测试与 macOS Debug 构建均通过。日志记录 Node `v24.22.2`、Homebrew `mpv--0.41.0_12.arm64_tahoe.bottle.tar.gz`、`mpv v0.41.0`，并输出 `Built build/macos/Build/Products/Debug/Aggregate.app`。NCM 三项及 Android arena-release 通过；原太阳/月亮实现和断言均未修改。
- 发布：两次 CI 修复均已通过 GitHub 连接器发布到 `main`，随后 `git fetch` 与本地内容逐字核对。对同一实际远端提交的 Gitee 正常推送仍失败：`could not read Username for 'https://gitee.com': No such device or address`。没有强推；双端交付尚未完成。
- 范围限制：本次仅改 CI 环境与闸门入口，不改产品源码、主题逻辑或锁文件。CI 的 Debug 构建、Widget/Runtime fixture 测试不等于 Mac 实窗 Profile 性能、VoiceOver、原生禁用 AX、pointer cancel、动态相位、生命周期及最终质感验收；UI-5/UI-6 仍保持部分验收。

### 2026-11-17 Flutter Profile 帧时与输入分发诊断

- 环境：Flutter 3.47.8 / Dart 3.13.7，隔离 Profile bundle `io.github.guog962464.aggregate.ui6frametrace`，PreviewRuntime 设置页。临时追踪只记录 `FrameTiming`、主题开关 `PointerMoveEvent` 时间戳和模拟状态；采样后已恢复生产入口、组件源码和 bundle 配置，没有把诊断代码提交。
- 时钟：同步采集 649 组成对的 wall、mach absolute/host、mach continuous 样本。`wall - host` 中位数 `1794882611.813514 s`，范围 `1794882611.8135087–1794882611.8135345 s`；`wall - continuous` 中位数 `1794821782.2234912 s`，范围 `1794821782.2234864–1794821782.2235074 s`。两组时钟基准相差约 `60829.590023 s`，因此先换算再比较；直接相减会产生错误延迟。
- 输入片段：Profile trace 内有 1,065 条主题开关指针移动记录，首末事件跨度 `26.766 s`（约 `39.79 events/s`）。按上述时钟桥接，事件时间戳到 Dart 处理记录的中位数 `13.367 ms`、P95 `14.105 ms`、最大 `16.537 ms`；到下一次 Flutter vsync 的中位数 `29.048 ms`、P95 `29.095 ms`；到该帧 raster finish 的中位数 `34.465 ms`、P95 `35.133 ms`、最大 `35.773 ms`。
- 同片段内 1,618 个 Profile 帧的 build 中位数/P95/最大为 `0.742/0.921/1.417 ms`，raster 为 `4.939/5.533/6.062 ms`，`FrameTiming.totalSpan` 为 `5.733/6.246/7.077 ms`；build、raster、totalSpan 均无超过 `16.667 ms` 的帧。vsync 间隔中位数与 P95 均为 `16.667 ms`，最大 `16.672 ms`，没有超过 `20 ms` 的间隔。该样本未显示拖动区间存在 build/raster 超预算。
- 推断与限制：样本中可见约 `13 ms` 的事件时间戳到 Dart 处理间隔，随后等待下一个 vsync；这为继续检查输入分发及帧相位提供方向，但尚未找到根因。此段 PointerEvent 没有与只读原生 event tap 的事件 ID、同次 ScreenCaptureKit 帧配对，也没有 display-present 时间戳；以上不是物理输入至光子延迟，不能据此确认或推翻先前约 `54 ms` 的采样画面差，也不关闭 UI-6 动态相位验收。
- 采集作废项：一轮 ScreenCaptureKit 未核验前台进程，帧不属于 Aggregate Profile，未纳入证据；另一轮虽采到 Profile 窗口，但合成拖动缺少左键按下标志，event tap 记录 down 1、drag 71、up 1，而 Flutter 没有对应的主题拖动回调、滑块也未移动，故整轮作废。两轮都没有作为视觉通过样本。用户要求不再切换其屏幕后，停止了前台激活和鼠标注入；Profile 诊断进程已关闭。
- 证据：[Flutter Profile trace](/Users/guo/.codex/visualizations/2026/11/17/aggregate-ui6-frame-trace/flutter-frame-trace.jsonl)，SHA-256 `d49d2b412b98b4a79b273298282193451ae010bac5fdaddec1569f4cd02c1504`；[时钟配对](/Users/guo/.codex/visualizations/2026/11/17/aggregate-ui6-frame-trace/run3/clock-pairs.jsonl)，SHA-256 `6e714a1d4a80b4f878c10ac975e4751b15ecdb17667d3cc725e39867fae81b29`；[无效拖动的原生事件记录](/Users/guo/.codex/visualizations/2026/11/17/aggregate-ui6-frame-trace/run5/event-tap-raw.jsonl)，SHA-256 `fbb7deb1e9dd0452a78bdb2027b0bfac184e190f51a3e41e2e1c36fea152f434`。不保留错误前台应用的屏幕帧。
- 自检：临时 Profile build 成功；定向 `flutter analyze --no-pub lib/preview/frame_trace.dart lib/preview_main.dart lib/features/settings/glass_theme_switch.dart` 通过，未运行完整产品测试。诊断文件已恢复，`pubspec.lock` 用户改动保留未暂存。主题拖动、端点提交、太阳/月亮模拟、偏好映射和动画参数均未修改；UI-6 仍部分验收。

### 2026-11-17 Flutter 玻璃动效与主题拖动组件回归

- 命令：在 `app/` 执行 `flutter test --no-pub test/glass_motion_test.dart test/glass_action_button_test.dart test/glass_theme_switch_test.dart test/theme_switch_realtime_test.dart`，进程退出码 `0`，30 项测试通过。
- 覆盖：按钮 reduced-motion 点击可用性、完全离屏后共享时钟注销、`TickerMode` 与应用生命周期暂停/恢复、按钮 200% 文字/键盘操作，以及切换 450 ms 实时拖动释放提交、反向拖动和 pointer cancel 恢复端点；实时模型另覆盖 20/30/60/120 Hz 与长隐藏间隔。
- 证据范围：这是 Flutter test 下的组件/模型回归，不是原生 macOS 窗口验收。它不证明 AppKit 离屏/减少动态效果集成、原生 `PointerCancelEvent`、屏幕捕获相位、显示器实际呈现帧率或 VoiceOver 语音；UI-6.4、UI-6.8 与最终签收仍为部分验收。
- 自检：四个测试文件完整运行并显示 `All tests passed!`；本轮没有启动、聚焦或注入输入到应用窗口，没有修改主题切换生产逻辑。当前工作树其他未提交项（`docs/android-a3-runtime-research.md`、`docs/android-a4-npm-install-research.md`、`docs/android-adaptation-plan.md`、`pubspec.lock`）不属于本次改动，保留原样。

### 2026-11-17 UI review 稳定性与短列表布局回归

- 根因：连接页 UI 金样最初在单个预览能力时出现大面积差异。`connections_page.dart` 为 1 项内容预留了有界列表高度，空白向下挤压设置/详情内容；将单连接/单能力降到自然高度后，单项显示恢复，40 项以上仍用有界惰性列表。
- 金样稳定性：设置截图有时在 `ThemeSwitchArtwork` 的 fragment shader 加载完成前捕获，太阳/月亮缺失，随后测试又呈现完整光效。测试套件改为 `setUpAll` 预加载 shader，避免在每个 `testWidgets` 的异步测试区等待同一个 Future；第二个尺寸/主题用例不再卡住。按稳定渲染重录 5 张设置页金样，另外 1 张浅色 800×600 金样与稳定截图一致。六张 PNG 均已逐张目视检查。
- 改动：连接数或能力数小于 40 时保留自然展开的 `Column`；达到 40 项继续使用 `ListView.builder`/`ListView.separated`。抽出共用连接行 builder，选择回调、状态和业务逻辑未改。新回归覆盖 1 连接、1 能力，既有 90 项懒构建用例保留。
- 验证：完整 UI review `12` 项通过，包含 DPR 1 的 `54` 个金样断言和 DPR 2 的完整导航/布局检查；连接懒构建专项 `4` 项通过；App 全量 `289` 项通过；`flutter analyze --no-pub` 无问题。金样文字使用 Flutter 测试字体，中文方框仍不作为文字可读性验收。
- 边界：没有启动或聚焦应用窗口，没有鼠标注入；没有修改主题模拟/校准、太阳/月亮切换、偏好映射或回调。图像是 Flutter test 截图，不替代 Profile 原生窗口、动态逐帧、VoiceOver 或 UI-6 最终验收；UI-6 仍部分通过。
- 切换逻辑冻结复核：`theme_switch_simulation.dart`、`theme_switch_calibration.dart`、`theme_switch_fitted_calibration.dart` 当前 SHA-256 分别为 `2bfa354d3b5511247d213284e36de18b418a7f332545c57f5d3e2625a8906a03`、`c0f9cc70fa69462434e62c4ca577576ae03b6dd242d4a2a8a3eb1909cf0cadbd`、`11ffe7ea41b5ebd26d4a59f91dc2c7e98b18dcc794e054d89b6956b4c1febaa7`，与 UI-0 基线一致。对照 `297762e82730b8a99f324b190796c80aae426a9` 审阅差异：`glass_theme_switch.dart` 增加 scene 发布/清理、背景坐标传递和前景焦点绘制；shader 增加可选全窗背景坐标，零尺寸默认值仍退回原 viewport 公式；`appearance_selector.dart` 仅把 macOS glass-scope 下的“跟随系统”入口替换为统一按钮。`_down`/`_move`/`_finish`、tap/drag recognizer、键盘动作、`_select` 与偏好映射没有差异。

### 2026-11-17 UI-2 生产按钮图标覆盖补齐

- 复查范围：扫描 `app/lib` 实际使用的 Material 图标，并逐项对照 `GlassGlyphCatalog` 的 codepoint 表。发现 92 个唯一 `Icons.*` 常量中有 8 个缺少映射，包含可进入 macOS 玻璃按钮作用域的生产操作图标。
- 实现：为 8 个图标补全语义别名和 codepoint 映射；退出与更多新增专属 9×9 圆角点阵，其余图标复用匹配的既有点阵语义。当前图案字典为 60 项。
- 回归：测试验证 8 个 codepoint 与名称别名一致、退出/更多图案各自独立，并在 macOS `GlassMotionScope` 下构建 8 个操作按钮和 1 个图标按钮且无映射异常。深浅主题的 1×/2× glyph golden 已更新并通过。
- 范围边界：本项只证明 Flutter Widget 与 golden 渲染；没有原生 Profile 单项截图，新图案仍需独立 macOS 桌面逐项视觉签收。没有改主题模拟、太阳/月亮图形公式、拖动积分、端点选择、偏好映射、回调或主题动画。

### 2026-11-17 UI-3 退出与更多按钮动效

- 实现：为退出和更多增加专属动作族：退出 560 ms，图案沿出口方向轻推并进行点阵扫描；更多 520 ms，三列点阵向外舒展回弹。动作枚举共 15 项（含 neutral）；本次手动时钟回归覆盖 14 个带点击动作的族。
- 验证：`app/` 下 57 个已跟踪 `*_test.dart` 文件合计 293 项通过；完整 golden 测试包含深浅色 1×/2× 四个 glyph 断言并通过。对 4 个改动 Dart 文件执行 `flutter analyze --no-pub` 无问题、`dart format --set-exit-if-changed` 零改动；静态扫描 92 个唯一 Material 图标，缺失映射为 0。测试未包含未跟踪集成文件。
- 范围边界：本次没有启动或聚焦原生应用窗口，也没有原生 Profile 动效截图；Widget/Golden/模型测试不能替代新动作的原生静置与点击质感签收。UI-5/UI-6 其他未完成项保持开放。

### 2026-11-17 UI-3 全部点阵动效 profile 补齐

- 复查：对 `app/lib` 的生产按钮图标入口重新扫描，发现 90 个可直接识别的按钮调用中有 20 个（涉及 13 种 glyph）使用通用 `neutral` 反馈，缺少各自明确的静置与点击差异。另有 26 个动态 IconData 入口，包含播放、导航、状态及连接图标，不能只按源码中的直接常量判断覆盖完整。
- 实现：60 个 `GlassGlyph` 现在分别映射到唯一 `GlassMotionAction` 和独立 `_GlassMotionProfile`；profile 为静置图案、点阵光效、时长、位移、缩放、旋转、漂移与亮度幅度提供显式参数。production glyph 的动作映射不再回退到 `neutral`。播放/暂停形态变化时，内部静置 profile 也在 360 ms morph 内平滑插值，避免切换瞬间光效跳变。
- 逻辑边界：保留共享时钟、点击能量包络、重复触发连续性、`TickerMode`/生命周期/离屏注销及 reduced-motion 路径。没有改太阳/月亮主题控件、拖动积分、主题映射、偏好或业务回调。
- 验证：`dart format --output=none --set-exit-if-changed lib/widgets/glass/glass_motion.dart test/glass_motion_test.dart` 退出码 0；`flutter analyze --no-pub lib/widgets/glass/glass_motion.dart test/glass_motion_test.dart` 无问题；`flutter test --no-pub` 在 `app/` 下 293 项通过；映射表检查为 61 个 profile（60 个 glyph + `neutral`），action 与完整 profile 配置均无重复；`git diff --check` 通过。
- 边界：此次没有启动、聚焦或操作原生应用窗口。Widget 测试覆盖 60 个 glyph 的 idle/click/idle 采样与连续性，但不代表 60 个图案均已在 macOS Profile 原生窗口逐项目视通过；这些视觉签收与 UI-5/UI-6 的其余原生缺项仍保持开放。未跟踪的 Android 集成测试和用户自己的原型、锁文件、Android 文档改动均未纳入本项。

### 2026-11-17 当前主线 UI 动效回归复跑

- 基线：当前主线 HEAD `003d0c7d9a411ec3be784712e310a1ec87e510f6`；该提交只改 Android Host 测试与文档，没有改本次测试涉及的玻璃动效或主题控件源码。
- 命令：在 `app/` 执行 `flutter test --no-pub test/glass_motion_test.dart test/glass_action_button_test.dart test/glass_theme_switch_test.dart test/theme_switch_realtime_test.dart`，退出码 `0`，34 项通过。
- 覆盖：60 个按钮图案映射/动作连续性、点击业务回调、TickerMode/生命周期/离屏/reduced-motion，以及主题开关 450 ms 拖动提交、反向和 pointer cancel 回归。
- 边界：该轮没有启动或聚焦原生窗口，也没有修改主题模拟、校准、指针识别或提交逻辑。它不替代原生 VoiceOver、pointercancel、离屏/reduced-motion、动态帧相位和呈现帧率验收；UI-6.4 与 UI-6.8 仍部分验收。工作区用户修改的 `pubspec.lock` 未触碰。

### 2026-11-17 原生按钮图案检查页与 3.50.0 对照补记

- 夹具：把 `app/lib/widgets/glass/glass_buttons_fixture.dart` 的 60 个 glyph 展示从静态图案改为可点击 `GlassActionButton`，使用独立 PreviewRuntime；所有点击回调为空操作，不触发业务行为。macOS Flutter 3.47.8 Profile AX 树列出 60 个 glyph 按钮及其名称。该证据确认可访问节点覆盖，不等于实际逐一朗读或逐项检查动效。
- 视觉证据：深色 800×632 按钮样本、浅色 800×632 按钮样本和深色 1512×949 logical px 完整 glyph 网格均归档在 [stage6-native-review](/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-native-review/)。PNG SHA-256 分别为 `72ee7dc973616cb2d2a05262d3c0abcf1e705ab645baac305207271d5f476baf`、`6aa7a202f3dc0c994e0d58620a9b7b1f700dae2ab6cdffbce56eac0911af3207`、`94b94482010c2a40b6028205e2d8c6533dbcb90a7e73bda7f5e52e6c77d05280`。浅/深按钮样本和完整网格均已目视检查；另外用左右半屏视图逐项查看了 60 个静态 glyph，点阵颗粒、按钮材质与排列整体一致，未发现明显错位或渲染异常。此检查不覆盖各图案的静置/点击动效、运动相位或真实生产实例，故不据此关闭 UI-3 动效逐项验收或 UI-6.7。
- 3.50.0：官方下载 Flutter 3.50.0 stable arm64 archive 并校验其官方 manifest SHA-256 `ed2d08a3e3c023e84cbe9316d21bd88fda6ee9552f90c1eb4da41a07c170fb35`；隔离 Profile fixture 构建成功。官方[Flutter 3.50.0 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.50.0)列出将 disabled/read-only semantics 映射为 AX node restriction 的 engine 变更。本轮原生检查误读了普通参考样本的 enabled 属性，且 disabled 样本未出现在当时查看的树范围，因此这次探测对修复是否生效没有结论；不覆盖此前增强 AX 树记录的“禁用节点 role/名称不可读”，UI-5.4 仍部分通过，需在可精准定位禁用节点的真实 VoiceOver 树中重验。
- 回归：当前工作树下 `app/` 的 `flutter test --no-pub` 完整测试通过 294 项。此次只改 fixture 与 UI 阶段验收文档；未改主题开关、业务回调或生产运行逻辑。隔离 app 进程、临时 worktree 与临时 Flutter SDK 均已关闭/清理；工作区其他 Android、Runtime 与 lockfile 修改未纳入本项。

### 2026-11-17 Flutter 3.50.0 精确定位禁用节点复测

- 环境：隔离 macOS Profile fixture，Flutter 3.50.0 / Dart 3.14.0 / Engine revision `371f77202a`。以当时主线 `ea23879034fa8c7bd2a81ff45a98c966f818f152` 创建临时 worktree；该基线到当前主线的差异没有改动 `app/lib`、本次测试或本阶段文档。临时 bundle ID 为 `io.github.guog962464.aggregate.axprobe350`。
- 定位：fixture 将禁用玻璃按钮 `AX_DISABLED_GLASS_PROBE`、可用玻璃按钮 `AX_ENABLED_GLASS_PROBE` 和禁用 `TextButton` `AX_DISABLED_TEXT_PROBE` 放在窗口顶层可见区域，避免把普通参考节点误认为禁用节点。Profile 构建成功，窗口大小 800×632 logical px。
- 原生结果：VoiceOver 未开启；将原先未设置的 `AXEnhancedUserInterface` 临时设为 `true` 后直接遍历 macOS AX 树。树可读到 `AX_ENABLED_GLASS_PROBE` 且 `AXEnabled=true`；禁用节点没有可读的 AXRole、标题、描述、值、帮助、标识符或 enabled 属性，读到一个属性均返回 `kAXErrorNoValue` 的未知叶节点。`agent-desktop` 同样只识别可用玻璃按钮。此轮是对禁用节点的明确失败结果；它不等于 VoiceOver 语音走查。
- 原生结果：VoiceOver 未开启；首轮将原先未设置的 `AXEnhancedUserInterface` 设为 `true` 后查询，树可读到 `AX_ENABLED_GLASS_PROBE` 且 `AXEnabled=true`，禁用节点则没有可读 AXRole、标题、描述、值、帮助、标识符或 enabled 属性。`agent-desktop` 同样只识别可用玻璃按钮；该结果不等于 VoiceOver 语音走查。
- 假设区分：在第二个隔离 Profile fixture 中，先设置 `AXEnhancedUserInterface=true`、再启动 3.50.0 应用。直接 AX 遍历按窗口位置识别出禁用标准 Material 按钮、显式 button Semantics、仅带禁用说明的文本 Semantics 和 Aggregate 玻璃按钮；四个节点的 AXRole/标题/描述/值/帮助/标识符/enabled 都不可读，均为无子节点的未知元素，但其屏幕位置与尺寸可读。唯一有业务语义的 AXButton 是启用玻璃按钮，名称可读且 `AXEnabled=true`。这排除了应用启动时序和玻璃按钮专属包装作为该现象的解释；证据指向 Flutter/macOS 原生 AX 导出路径，尚未通过进程内 engine 节点数据定位具体函数缺陷。
- Widget 对照：Flutter 3.50.0 下，`test/glass_action_button_test.dart` 与 `test/accessibility_test.dart` 共 14 项通过；额外临时回归再断言标准 Material、显式 Semantics、玻璃按钮三者均保留名称、button flag、`isEnabled=false` 和无 tap action，1 项通过。故 Flutter framework 层输出正确，缺陷出现在 Profile 应用的 macOS AX 暴露结果。
- 清理：两轮完成后分别退出唯一隔离应用，PID 查询为空；删除临时 `AXEnhancedUserInterface` 键并确认恢复为启动前的未设置状态；删除临时 Aggregate/Flutter worktree 和 Swift 查询脚本，不接触用户其他应用。
- 结论：Flutter 3.50.0 Widget 语义测试通过，原生 AX 禁用态仍不通过，UI-5.4 继续部分验收。启动前打开 AX 增强树、换用标准按钮或静态文本都没有修复，因此目前没有证据支持应用层无损补丁；不因 engine 源码包含 restriction 映射而推断 macOS app 已修复。生产源码、太阳/月亮切换逻辑及业务行为均未改动。

### 2026-11-19 Flutter 3.47.8 禁用语义 AX 最小原生复现

- 环境：macOS 27.2.1（Mac17,9 arm64），Flutter 3.47.8 / Dart 3.13.7、engine revision `cf636b1dfb`；Profile 800×632 logical px、Impeller MetalSDF。临时入口只包含一个禁用生产 `GlassActionButton`、一个显式禁用 `Semantics`、一个禁用标准 `TextButton` 和一个启用玻璃控制；无 Runtime、网络或业务回调。入口完成复现后已移除源码，源文件和查询脚本保存在[本地诊断证据](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui5-4-disabled-ax-probe/results.md>)。
- 原生结果：`agent-desktop` 的精确标签 AX 查询连续 3 次报告禁用玻璃按钮 `enabled=true`。独立 Swift `AXUIElementCopyAttributeValue(kAXEnabledAttribute)` 直接读取结果：玻璃按钮、显式 `Semantics`、标准 Material 按钮均为 `AXEnabled=1`；启用玻璃按钮也是 `1`（`AXError=0`）。因此排除 agent-desktop 单独误读及 GlassActionButton 单独包裹方式。
- Framework 对照：`flutter test --no-pub test/glass_action_button_test.dart test/accessibility_test.dart` 共 16 项通过。新增 `null callback keeps disabled framework semantics` 用例覆盖最小组件调用，Flutter Semantics `isEnabled=false`、无 tap action；已有 busy/disabled 回归继续验证业务回调不触发。框架语义测试不是原生 AX 修复，原生树的 enabled 状态仍不正确。
- 版本及来源：本次 3.47.8 结果与此前 3.50.0 Profile 结果呈现方式不同，但两者都不能提供可读且准确的禁用原生节点；后者的精确记录见上方 2026-11-17 小节。Flutter 3.50.0 官方发布说明列出 [PR #190353](https://github.com/flutter/flutter/pull/190353)，其目标是将禁用/只读状态映射到 AX node restriction；这一 upstream 变更没有推翻本项目对实际 Profile 窗口的观测。当前证据把差异定位在 Flutter framework semantics 到 macOS AX 的导出边界，具体 engine/AppKit 函数仍未单独定位。没有通过加入可操作 tap、隐藏禁用项或重复原生控件做视觉/语义妥协，因此 UI-5.4 仍部分验收；VoiceOver 朗读也未完成。
- 测试夹具没有改系统 VoiceOver 或 AXEnhancedUserInterface 设置。临时 Profile app 与 runner 已关闭，入口源码已移除；主题切换和生产业务逻辑未改。

### 2026-11-17 macOS 系统减少动态效果接线

- 原因：在隔离 Profile 探针中，将 macOS 系统 Reduce Motion 开启且确认 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true` 后，原应用窗口仍读到 `MediaQuery.disableAnimations == false`。当前 Flutter macOS Runner 没有把 AppKit 该偏好映射到 Flutter accessibility features。
- 实现：macOS Runner 新增 `aggregate/macos_reduce_motion` EventChannel，初次订阅读取 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`，并监听 `accessibilityDisplayOptionsDidChangeNotification`；共享 `AggregateApp` 只接收平台无关的 `ValueListenable<bool>`，在根 `MediaQuery` 合并 `disableAnimations`，不让公共组件直接依赖 AppKit。既有 GlassThemeSwitch/GlassActionButton reduced-motion 路径与太阳/月亮模拟、拖动、端点提交、偏好映射保持不变。
- 自动化：新增 app-level macOS Widget 回归，通过注入 `ValueListenable` 检查禁用动画状态可正反更新、主题开关在关闭装饰动画时仍可操作。全量 `flutter test --no-pub` 298 项通过；`flutter analyze --no-pub` 无问题；`flutter build macos --profile --no-pub` 成功，Flutter 3.47.8 stable / Dart 3.13.7。
- 原生验证：隔离 bundle `io.github.guog962464.aggregate.reducemotionprobe`，macOS 27.2.1 / Mac17,9 arm64，窗口 800×632 logical px。系统 Reduce Motion 开启时，Swift 读值为 `true`，Flutter AX 静态文字为 `SYSTEM_REDUCE_MOTION true`；点阵按钮实际点击后 `BUTTON_CLICKS 1`，主题开关点击后 `THEME_LIGHT true` 且 AX 值为“浅色”。这验证了启用态初次读取与功能可用，不证明系统设置打开期间的反向实时切换通知或显示器逐帧呈现。
- 清理：关闭唯一 Profile 探针进程并删除临时 app 与临时 Dart 入口；系统 `reduceMotion` 恢复到原始关闭值 `0`，新 Swift 进程读取 `NSWorkspace...` 为 `false`；工作区仅保留本次源代码/测试/阶段文档改动及用户已有的 `pubspec.lock` 改动。无临时 worktree 遗留。
- 结论：UI-5.7 的减少动态效果功能子项与 UI-6.4 的原生启用态覆盖通过。UI-5.7 仍因实际 VoiceOver 主流程未走查而部分验收；UI-6.4 仍因隐藏/恢复长帧及生命周期、离屏混合场景未完成而部分验收。未修改太阳/月亮主题模拟、校准、任意拖动、端点提交、偏好或业务回调。
- 依据：Apple 文档说明 `NSWorkspace.accessibilityDisplayShouldReduceMotion` 提供该状态，并通过 workspace `accessibilityDisplayOptionsDidChangeNotification` 通知显示选项变化：[属性](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)、[通知](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification)。

### 2026-11-17 VoiceOver 主流程实窗尝试

- 环境：隔离 macOS Profile 应用，Flutter 3.47.8 / Dart 3.13.7，bundle `io.github.guog962464.aggregate.voiceoverprobe`，使用 PreviewRuntime。AX 树可列出主导航、播放器和设置页文字；经“所有功能”进入“设置”后也能读到当前主题值与页面说明。
- VoiceOver：从系统设置开启 VoiceOver，并使用已开启的字幕面板观察实际播报。焦点只报告位于系统 `group` 内，提示需用 Control-Option-Shift-下箭头与上箭头进入/退出；通过 agent-desktop 和 CUA 尝试 VoiceOver 键盘导航后，字幕转为“系统，有新的，窗口”，焦点没有进入应用控件，继续停在根 group。没有读到应用按钮或设置项名称/状态，故主流程朗读顺序未验证，UI-5.7 保持部分验收。
- 收尾：关闭 VoiceOver；退出唯一隔离 Profile 应用和 VoiceOver Utility；关闭本次打开的系统设置；删除临时 worktree `/private/tmp/aggregate-voiceover` 及 OCR 临时文件。进程查询无 `AggregateVoiceOver`、VoiceOver Utility 或系统设置残留，`git worktree list` 仅有主工作区。减少动态效果保持关闭。未触碰用户应用窗口，主工作区原有 `pubspec.lock` 修改未改动、未暂存。
- 边界：AX 树中可读的名称不等于 VoiceOver 语音顺序通过。此次结果反映本次系统级导航未成功，不能区分应用语义问题与自动化键盘焦点未送达；需用可操作的真实 VoiceOver 输入完成主要流程朗读后再验收。

### 2026-11-17 VoiceOver 导航复核与清理

- 复核：再次在隔离 Profile 探针中开启 VoiceOver。字幕仍先落在应用根 `group`；将 VoiceOver 分组改为“忽略群组”、初始光标临时设为窗口首项后，尝试 Control-Option-右箭头只得到不完整的字母字幕片段，无法确认焦点进入任何应用控件，也没有读到稳定的按钮名称或状态。此轮仍不能关闭 UI-5.7 的 VoiceOver 主流程项。
- 控制路径：VoiceOver Utility 的“允许 AppleScript 控制 VoiceOver”原本关闭，复核中保持关闭；Utility 的无障碍操作在该窗口上超时，因此未通过脚本控制绕过真实导航。已将全局分组偏好恢复为“标准”，并在系统设置确认关闭 VoiceOver。
- 收尾：退出隔离 Profile 探针、VoiceOver Utility 和系统设置；删除 `/private/tmp/aggregate-voiceover2`、临时 XCTest 目录及字幕 OCR 文件。复核后 `git worktree list` 仅有主工作区，进程查询无这三个任务应用残留；主工作区仅有用户原先修改的 `pubspec.lock`，未改动、未暂存。
- 结论：本轮没有完成可复核的 VoiceOver 控件朗读，不改变 UI-5.4 / UI-5.7 的部分验收结论；仍需用可靠的 VoiceOver 输入完成设置页主流程，并核对控件名称、状态和顺序。

### 2026-11-17 Xcode VoiceOver UI 测试探针

- 方法：在临时 worktree 将 macOS `RunnerTests` 改为 UI testing bundle，编译调用 `XCUIDevice.shared.voiceOverService` 的探针；Flutter Profile 预览应用构建成功。此改动只在临时 worktree，未带回项目。
- 结果：初次运行因测试运行器未签名而被 macOS 安全策略阻止；改为有效签名后运行器进程可启动，但 Xcode 仍未创建测试 worker，`.xcresult` 显示 `totalTestCount=0` / `result=unknown`，Flutter AUT 与 VoiceOver 均未启动。故这不是实际朗读结果，也不能据此判断 `XCUIVoiceOverService` API 可用性或应用语义。
- 收尾：停止 Xcode 后台测试运行器，退出相关进程，删除临时 worktree 和结果包；系统 VoiceOver 保持关闭、全局分组恢复“标准”、AppleScript 控制保持关闭。主工作区原有 `pubspec.lock` 未动、未暂存。
- 结论：Xcode UI 测试 harness 配置/启动问题仍待定位；UI-5.7 VoiceOver 主流程保持部分验收。下一次应先用最小原生 macOS UI testing target 单独验证 runner/worker 生命周期，再接入 Flutter 预览应用。

### 2026-11-18 macOS VoiceOver 空内容组上游对照

- 对照：Flutter 官方 issue [#189683](https://github.com/flutter/flutter/issues/189683) 报告 macOS VoiceOver 启用后，`FlutterView` 内容 `AXGroup` 仍为空，即使 framework semantics tree 已有名称和按钮；报告记录 VoiceOver 只进入空 group，并于 2026-08-01 关闭为 `not planned`。该症状与本项目 2026-11-17 的 Profile 尝试相符，但报告使用 Flutter 3.44.6 / macOS 26.5.1，不能据此认定本项目当前 engine 的精确根因，也不代表有可用修复。
- 当前源码核对：Flutter 3.47.8 的 [GlassActionButton](../../app/lib/widgets/glass/glass_action_button.dart) 显式输出 `button: true`、`enabled: _enabled`，并仅在启用时提供 `onTap`；本机 SDK engine 的 `ax_platform_node_mac.mm` 将语义 role/name 映射到 AX 属性，并以 node restriction 计算 `AXEnabled`。现有 Widget 语义回归可检查这些 framework 输出，但无法修复或证明 macOS 原生导出树已可读。没有找到符合现有约束的 app 层无损补丁，本轮未修改业务或主题代码。
- 结论：UI-5.4 与 UI-5.7 仍未通过；真实 VoiceOver 主流程也未获有效控件朗读证据。不得把 upstream issue 的相似症状当作 Aggregate 根因诊断；后续需在获得可工作的原生语义树/VoiceOver 输入路径后重测。

### 2026-11-17 独立 Xcode UI testing runner 复核与清理

- 方法：根据前一轮记录，另建不依赖 Flutter 的最小原生 SwiftUI 宿主与 `MinimalVoiceOverUITests` UI testing target。测试目标尝试通过 `XCUIDevice.shared.voiceOverService` 启用 VoiceOver 并遍历控件；Xcode 项目与 DerivedData 均放在 `/private/tmp/aggregate-vo-minimal`。
- 结果：宿主与 UI test target 能被 Xcode 识别，但 `xcodebuild test` 在 runner 初始化阶段失败，退出码为 65；错误为 `MinimalVoiceOverUITests-Runner` 初始化 UI testing 时 “Timed out while enabling automation mode”。测试用例计数没有建立，宿主应用和 VoiceOver 均未启动，因此这次没有朗读、应用语义或控件顺序证据。
- 清理：VoiceOver 偏好仍为关闭（`voiceOverOnOffKey=0`）；未发现 VoiceOver、最小宿主或 Xcode runner 进程，桌面仅有当前 ChatGPT 会话窗口。已删除 `/private/tmp/aggregate-vo-minimal`（含工程、DerivedData 与 `Run1.xcresult`）；主工作区仅保留用户原有 `pubspec.lock` 改动，未触碰、暂存或提交。
- 结论：在独立最小原生 target 中仍无法完成 UI automation runner 初始化；失败发生在任何测试执行之前，不能据此推断 `XCUIVoiceOverService` 可用性、Aggregate 的 AX 行为或 VoiceOver 朗读。UI-5.7 仍部分验收。后续若继续此路径，应先解决 Xcode automation mode 初始化环境问题；也可使用经用户确认的真实 VoiceOver 输入完成朗读验收，不能再把构建成功视作 runner 可用。

### 2026-11-17 macOS 隐藏期间取消主题拖动

- 复现：在隔离 Profile 窗口中开始主题拖动，调用 `NSRunningApplication.hide()` 后再 unhide/activate，并在恢复后释放鼠标。系统生命周期序列为 `resumed, inactive, hidden, inactive, resumed`。隐藏期间 native `PointerCancelEvent` 计数为 0；旧实现恢复后收到迟到 mouseUp，会把深色端点提交为浅色。
- 修复：`GlassThemeSwitch` 监听应用生命周期，在 `hidden` 或 `paused` 时调用现有 `_finish(cancel: true)` 收尾，并在 dispose 时移除监听。`inactive` 单独出现时不取消，确保普通失焦不会中断仍可见的拖动。主题模拟、拖动积分、端点映射、偏好和业务回调保持原样。
- 原生复核：同一隐藏/恢复序列中 OS 仍未发出 `PointerCancelEvent`；隐藏回调取消进行中的拖动，恢复后释放鼠标主题值保持深色，随后正常点击成功切换浅色。该结果验证生命周期取消回退，不宣称 Flutter 收到了系统 pointercancel。
- 自动化与构建：主题开关定向测试 10 项、全量 `flutter test --no-pub` 300 项通过；`flutter analyze --no-pub` 无问题，格式检查无改动；macOS Profile `Aggregate.app` 构建成功。另有回归验证 `inactive` alone 不取消可见拖动，拖动到端点后仍正常提交。
- 清理与边界：临时 Profile fixture、CGEvent 脚本和截图均已删除，未触碰用户窗口。`pubspec.lock` 用户修改保留且未纳入。UI-6.4 的隐藏生命周期取消子项通过；UI-6.8 仍部分验收，原生 `PointerCancelEvent`、动态画面相位与真实显示呈现帧率仍无证据。


### 2026-11-17 UI-6.1 跨类别混合压力采样

- 环境：MacBook Pro（Apple M5 Pro，24 GB），macOS 27.2.1，Flutter 3.47.8 stable / Dart 3.13.7；内置屏幕当前模式为 1512×982 logical px、60 Hz、DPR 2。每帧预算按 16.667 ms 计算。隔离 `Aggregate.app` Profile fixture，起始窗口 800×632 logical px；原生窗口菜单 Fill/Return to Previous Size 在 800×632 与约 1512×949 logical px 间切换。测试未改 `pubspec.lock`。
- 工作负载：三轮各采样 60 秒，fixture 动作均为无业务回调的 PreviewRuntime 控件。每轮点击 Run 9 次、Pause/Add/Refresh 各 6 次、Copy/Save 各 5 次、Prev/Play/Next 各 3 次、Refresh Status 3 次；另有 6 次主题浅深往返拖动、3 组播放区滚动往返、3 次窗口 Fill/Restore 往返，以及一次 Cmd+H 隐藏后 Raise 恢复。每轮 AX 主题端点、窗口恢复与生命周期恢复均正确，无缺失控件。首个至最后一个输入分别为 39.129、39.393、39.459 秒；采样剩余部分为静置段。Fill/Restore 是原生菜单尺寸切换，不代表连续拖边缩放；连续缩放另有既有三轮记录。测量期间不录屏。
- 指标：VM `Flutter.Frame` 提交帧，未测物理显示器 present 时间。每个指标格式为 P50/P95/P99/max，单位 ms；`超预算` 指 build 或 raster 超过 16.667 ms。

| 轮次 | 帧数 | build | raster | totalSpan | build/raster 超预算帧 | 活动窗帧数；build P95/max；raster P95/max；totalSpan P95/max |
| --- | ---: | --- | --- | --- | --- | --- |
| r1 | 3537 | 0.747/1.330/2.249/3.854 | 6.132/10.504/12.906/16.070 | 6.910/12.060/15.286/34.103 | 0/3537 | 2283；1.97/3.85；11.34/16.07；12.83/34.10 |
| r2 | 3546 | 0.753/1.308/2.230/3.081 | 6.075/10.575/13.388/16.371 | 6.869/12.127/15.370/36.787 | 0/3546 | 2301；1.98/3.08；11.46/16.37；13.00/36.79 |
| r3 | 3546 | 0.751/1.268/2.177/3.275 | 6.150/10.502/13.744/16.701 | 6.942/12.272/16.272/33.496 | 1/3546（0.0282%） | 2306；1.92/3.27；11.59/16.70；13.33/33.50 |

- 分窗：活动窗 build/raster 超预算比例为 0%、0%、0.0434%；各轮 totalSpan 超 16.667 ms 的帧分别为 21、18、27。静置段各有 1240–1254 帧，raster P95 为 7.62–7.82 ms、max 为 8.43–8.52 ms；totalSpan P95 为 8.28–8.47 ms、max 为 9.00–9.13 ms，均无 >16.667 ms 帧。r3 有一帧 raster 16.701 ms，按 5% build/raster 超预算门槛仍达标；totalSpan 峰值单独列示，不等同于 build/raster 超预算率。
- 结论与边界：该跨类别混合压力子场景通过三轮帧时门槛，UI-6.1 整体仍部分通过。原始 VM-service 输出和临时 URI 文件在记录结果后已删除；Profile fixture 已退出，没有遗留 Aggregate 验收进程。此结果仅证明 Flutter 提交帧，不证明物理呈现 FPS、逐帧主题相位、`PointerCancelEvent`、reduced-motion 原生行为或运行时资源对象数量。

### 2026-11-17 UI-6.3 绝对渲染时钟隔离复核

- 环境：macOS 主机离线 Flutter widget export，Flutter 3.47.8 stable / Dart 3.13.7；当前基线 HEAD `2ce638286ab4bc799db1a4030202d6c270e65119` 加本次仅供验收的导出工具改动。输入为存档 200 帧裁切、实测时间表、拟合背景/几何、运行时校准、连续指针输入和动态 source-time mapping。
- 方法：基线 `THEME_SWITCH_RENDER_CLOCK_OFFSET=0`；候选 `0.046` 秒。两次均保持每帧 source-time mapping 与 motion input sampling 不变；候选只在状态积分后使用 `simulation.advance(0, renderTime)` 更新绝对点阵亮度时间，并将同一 renderTime 传入 shader。比较固定裁切、相同时间、未配准、未校色、无遮罩。没有运行原生窗口或改动产品的主题切换逻辑。
- 结果：两次各导出 200 帧且工具测试通过。全帧平均 MAE 为 `7.3371849794` → `7.3376826475/255`；171 帧 eligible mean MAE 为 `6.2835453467` → `6.2841405655/255`；稳定视野 79 帧 mean MAE 为 `4.4272927953` → `4.4283509359/255`；稳定控件区域 mean MAE 为 `7.8285863393` → `7.8281241077/255`。绝对渲染时钟前移 46 ms 对完整图像与稳定视野没有可测的实质改善，不能解释原生采样中 `42–60 ms` 的全局时间偏移；未据此更改产品 `timeOriginSeconds` 或动画物理。
- 证据：逐帧数值摘要保存在本机 `/Users/guo/.codex/visualizations/2026/11/17/aggregate-ui6-clock-phase/`。`render-clock-0ms.json` SHA-256 `00215f99f199ad3e29418effbe70b92a10c4f22d9b62552d9d2f2d6db777ad68`；`render-clock-plus46ms.json` SHA-256 `8034036bcd02a2a51a884b278ae4e957967d6af0b210627cec2afc3c1927e997`。渲染 PNG 与临时报告已删除；源帧可由本机原始参考目录重建。`dart format --output=none --set-exit-if-changed tool/theme_switch_reference_frames_test.dart` 无格式变更，`flutter analyze --no-pub` 通过。
- 结论边界：这是离线绝对亮度/shader 时钟的单点隔离试验，不代表 macOS 窗口显示呈现或实时拖动 1:1 通过。`UI-6.3` 仍部分通过；下一步需要能将原生输入采样时间与 display-present 时刻配对的实窗证据，或更可靠的原视频指针输入源。

### 2026-11-18 UI-6.3 太阳射线频率/相位交叉验证

- 环境与输入：Flutter 3.47.8 stable / Dart 3.13.7 的离线参考帧 exporter；复用已存档 200 帧参考图、79 组太阳射线光度观测、20 个射线格点、指针输入、逐帧 source-time mapping 与现行校准。原始下载视频当前路径不存在。
- 拟合：对 63 个训练帧联合搜索 `sunRayRate` 和共享 `sunRayPhase`，每格点的 photometric gain/bias 仅作训练拟合的干扰项；16 个 `sourceIndex % 5 == 0` 帧留出。候选 `2.218 / 0.333937 rad`；相较现行 `2.2 / 0.5050001 rad`，光度 RMSE 训练集 `0.05046621 → 0.05005923`、留出集 `0.04949150 → 0.04876729`。
- 完整图像复核：保持输入、几何、主题和截图时间不变，导出全部 200 帧并对固定画幅做无配准/无校色/无遮罩差分。由于存档 `live-fit/reference` 已是 `720×540` 裁片，导出器还会按原始参考画幅从 y=444 裁切；临时将裁片放回 `720×1080` 画布后重跑，避免双重裁切。现行/候选 all-frame MAE 为 `7.33718507/7.33718438`，稳定视野为 `4.42729291/4.42728696`，稳定控件 ROI 为 `7.82858628/7.82855220`。整体差异可以忽略。
- 决定与边界：拒绝候选值，产品继续使用 `sunRayRate=2.2`、`sunRayPhase=0.5050001`；没有修改模拟、光效或任意拖动逻辑。200 帧 exporter 通过；离线全图 MAE 约 `7.34/255`，UI-6.3 逐帧实时一致仍未通过。首轮错误裁切的临时参考、渲染和差分文件均已删除，本轮没有产品代码变更。


### 2026-11-18 UI-6.5 Dart VM 资源对象采样

- 环境：隔离 macOS Profile bundle `io.github.guog962464.aggregate.ui6resources`，产品代码基于 commit `4aa7f457bc42cc0e99652d36e905b2e1a2065080`；Flutter 3.47.8 stable / Dart 3.13.7。临时 worktree 只用于设置隔离 bundle id 和启动预览，产品代码未在主工作区修改。
- 方法：在“所有功能、管理连接、活动、设置”间循环导航 20 轮、共 80 次；通过 VM Service `getAllocationProfile(gc=true)` 在第 0、1、5、10、20 轮后读取存活对象数和 heap/external usage。样本是预热后的 Dart VM 存活对象快照。
- 结果：第 1、5、10、20 轮的 `Ticker` 均为 200、`_WidgetTicker` 29、`AnimationController` 222、`ui.Image` 2、Flutter `widgets.Image` 0、`FragmentProgram` 2、`FragmentShader` 2、`_NativePicture` 181；第 0 轮 `_NativePicture` 为 144，其余列出的主要对象计数相同。GC 后 heap 为 16,498,064–16,499,872 bytes（约 16.50 MB），external usage 稳定为 26,816 bytes；未见预热后随路由循环单向增加。
- 证据：紧凑 JSON `/Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-resource-audit/allocation-counts.json`，SHA-256 `540df947169126c15075dce30798499b2f6039c75804ed28933596b2156d4dc4`。
- 结论与限制：补足 Dart VM 管理对象数量证据；`_NativePicture` 等是 Dart VM 类型快照，不是 GPU/Skia/native texture 的分配计数，也不揭示 controller 是否正在 tick。结合源码所有权审阅和 RSS 记录，可按 UI-6.5 明文范围判定此导航负载预热后没有观察到 Dart 管理对象持续增长；该范围通过，原生 GPU 分配与活跃 controller 状态仍未测。
- 清理：关闭隔离 Aggregate Profile 应用并中断 Flutter runner；进程查询无应用/runner 残留；删除 `/private/tmp/aggregate-ui6-resource-probe` 临时 worktree。主工作区只剩用户原有 `pubspec.lock` 修改，未修改、未暂存。未运行产品测试，本次仅更新验收文档。


### 2026-11-18 UI-6.5 条款复核与状态更新

- 对照：UI-6.5 明列的 20 轮路由、进程 RSS、源码所有权释放路径和运行时 controller/图像/资源对象数量现均有证据。Dart VM `getAllocationProfile(gc=true)` 在原生 macOS Profile 进程中提供存活对象计数；20 轮预热后主要计数持平。
- 状态：将 UI-6.5 从部分通过更新为通过。理由是该新增计数填补了此前唯一明列的运行时对象数缺项；不把 GPU/native allocation、Skia 纹理和 controller 活跃状态加入隐含验收条件。
- 范围：这不改变 UI-6.1～6.4、UI-6.6～6.10 的部分或未完成状态，也不证明没有 GPU 内存泄漏。完整数据与边界见上方“UI-6.5 Dart VM 资源对象采样”。


### 2026-11-18 UI-6.4 系统 Reduce Motion 运行时切换

- 环境：Mac17,9 arm64 / macOS 27.2.1，Flutter 3.47.8 stable / Dart 3.13.7，隔离 macOS Profile bundle `io.github.guog962464.aggregate.ui6motionruntime`，产品基线 commit `0f9a6eeb0a5b05a62b9f7a4df890bb9ab1da944f`。
- 方法：使用 PreviewRuntime 隔离应用数据；临时入口实例化与正式 `main.dart` 相同的 `MacReduceMotionPreference` 通道订阅。临时 AX 标签同时显示 notifier 值和 `AggregateApp` 的 `MediaQuery.disableAnimations`，没有修改主工作区源码。系统设置 Accessibility > Motion 的“减弱动态效果”开关起始为关闭。
- 结果：通过系统设置 UI 开启后，其 AX 开关为 `1`，应用标签在两秒内从 `PREFERENCE false MEDIA false` 更新为 `PREFERENCE true MEDIA true`；关闭后开关回 `0`，应用回到 `PREFERENCE false MEDIA false`。`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 在测试前后均为 `false`；系统偏好键最初未设置，结束后仍未设置。
- 依据：AppKit 要求使用 `NSWorkspace.notificationCenter` 监听 `accessibilityDisplayOptionsDidChangeNotification`，并通过 `accessibilityDisplayShouldReduceMotion` 读取当前值；本轮确认该通知能把真实设置变化传入 Flutter 根 `MediaQuery`。[通知文档](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification)，[状态属性文档](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)。
- 清理与结论：退出隔离 Aggregate Profile 应用和本轮启动的 System Settings，停止 Flutter runner，删除 `/private/tmp/aggregate-ui6-reduce-motion-runtime` worktree。查询未发现对应应用/runner 残留；`git worktree list` 仅主工作区；系统偏好恢复为关闭且未设置状态。UI-6.4 的系统开关动态更新子项通过；阶段仍部分验收，隐藏恢复长帧根因和生命周期混合负载未解决。仅更新验收记录，未运行产品测试。

### 2026-11-18 UI-6.7 生产动作按钮共享组件覆盖审计

- 代码覆盖：扫描 `app/lib/**/*.dart`，生产页面共 109 个 `GlassActionButton`、`AggregateActionButton`、`AggregateIconButton` 调用点，分布于 20 个文件。macOS 正式入口的 `AggregateApp.builder` 提供 `GlassMotionScope`；两个平台包装器在该作用域下统一委托 `GlassActionButton`。其他显式 Material 按钮均处于非 macOS 或缺少玻璃作用域的回退路径，Android 专用设置面板不属于 macOS 页面。
- 变体覆盖：Profile fixture 对应全部七种 `GlassButtonKind`、五种 `GlassButtonSize`，并覆盖 selected、busy、disabled、description/source、iconOnly、expand 等渲染入口。既有 Profile 截图包含浅/深主题的 12 类参考 glyph、按钮尺寸/状态样本和五个生产页面；60 glyph 的完整深色网格与双主题 DPR 1/2 golden 已分别目视/自动检查。
- 当前验证：在 `app/` 执行 `flutter test --no-pub test/glass_motion_test.dart test/glass_action_button_test.dart`，21 项通过。手动时钟测试逐个检查全部 60 个 glyph 的唯一动作 profile、点击归一化采样及静置回归；按钮测试覆盖 Material 图标映射、深浅主题 1×/2× 绘制、尺寸、状态语义和鼠标/键盘激活。三张已归档 Profile 图的 SHA-256 与既有记录一致。
- 结论与边界：本轮完成了共享组件调用点与参数变体审计，但提交时将它扩大解释为 UI-6.7 通过；随后对照阶段原标准发现这一结论过宽，已由下方范围纠正恢复为部分验收。测试仍证明组件/模型覆盖，不证明每个真实页面位置均已目视签收。

### 2026-11-18 UI-6.7 实例签收范围纠正

- 更正原因：阶段条目要求检查所有产品按钮实例。共享渲染器、完整 glyph 模型测试和少量 Profile 样本不能证明不同页面/弹窗里的真实尺寸、邻接关系、文案长度及状态呈现都正确；把它们当作逐实例视觉验收的替代品会缩小原验收范围。
- 当前有效结论：UI-6.7 保持部分验收。保留 109 个调用点/20 个文件的源码映射、21 项动作与组件测试结果、五种尺寸和七种类型的 fixture 样本，以及五个生产页面截图作为已完成证据；这些证据不关闭其他布局位置的实例签收。
- 后续工作：已依据当前源码建立 [109 个生产按钮调用点清单](ui-6.7-button-instance-matrix.md)，明确其对应页面和现有证据范围；调用点不等于动态列表的全部运行时实例，清单也不代表视觉签收。下一步在隔离 Profile 预览中补齐终端、音乐播放器/账户/搜索结果、运行表单、连接和动作对话框等状态，再用安全 stub 覆盖 Mac Host 设置区。每个实际实例需核对尺寸/位置、相邻控件、浅深主题及适用的 disabled/busy/selected 状态，逐行附上截图证据；无法到达的状态继续标未验证。

### 2026-11-18 UI-6.7 隔离 Profile 逐页补证

- 环境：Mac17,9 arm64 / macOS 27.2.1；Flutter 3.47.8 stable / Dart 3.13.7；产品源码基准 `d6968a8bc388ec6e45f7acfb46ccedefd31cc680`（后续文档提交不改 `app/lib`）；隔离 `lib/preview_main.dart` Profile PreviewRuntime；暗色主题。窗口 AX 内容区按 1156×796 logical px 调整，导出的原生窗口截图为 2536×1816 px。截图尺寸不用于推算 DPR 或显示器呈现帧率。
- 操作：查看首页、工作台、数字参数表单和成功结果；用键盘实际输入 `2`、`3` 后触发预览运行，结果为 `sum: 5`。非空音乐搜索返回两首预览数据，检查可播放与不可播放行；点播放后进入“正在启动/确认播放状态”并保持 busy。PreviewRuntime 对 music session 不执行真实播放校验，因此这不是稳定播放或真实业务成功的证据。AX `set-value` 只更改辅助功能读数、没有更新 Flutter 表单控制器；故表单使用键盘事件输入，早期 `03a/03b` AX 填写截图不作为证据。`03e` 仍显示先前的必填提示，不作为表单校验通过证据。
- 目视结果：暗色首页、工作台、表单、成功结果、搜索行和播放启动状态中，截图可见的按钮位置与同组控件没有发现明显错位；范围只覆盖这些暗色实窗画面。确认执行对话框、搜索授权/歌曲控制对话框在 PreviewRuntime 中跳过；终端按钮隐藏；该运行路径也没有 JSON 展开字段、活动运行取消态或播放后离开音乐主页的全局迷你播放器截图。上述实例保持未验证，详见逐行矩阵。
- 证据：[暗色首页](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/01-home-dark.png>) SHA-256 `68c160fa601dbf42eb42d22feae74067e18e91503d7abd3de90a200a7609ece2`；[暗色工作台](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/02-workspace-dark.png>) `19263e0683bb042eedca0aad65226d194c0cd355eb5515b7b9a7b0d4167f96fc`；[数字表单输入](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/03c-run-form-after-keypress.png>) `3c74e5f1d82d67384d9753667ff1c0eeaca3533c5fea2e464050ca5f5af823e4`；[成功结果](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/04-run-result-dark.png>) `12c9f8165eda83cea6581e451487399d93e5dc2a50a42a8c7e8bd6d8faeb8009`；[非空搜索结果](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/05-music-search-results-dark.png>) `d7a201afd6f117c383d446e785c3e2d4ada7779e3ee3b82e702cf957a21ca6ae`；[播放启动 busy](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-button-instance-review/06-music-starting-dark.png>) `897dc9a2529582ea34eadd4ee07e7ea8d4091f228bf7cdaa9c29b6815b10a53f`。
- 结论与清理：本批只给矩阵中截图确实呈现的调用点补了页面级/局部实例证据，没有将屏幕截图扩大为整个文件或所有状态签收。UI-6.7 仍部分验收；浅色、动态收尾、确认对话框、MiniPlayer、Mac Host 及其他缺少截图的行继续开放。退出隔离 Aggregate Profile runner 后确认无 Aggregate 应用或 Flutter runner 进程；未触碰 Chrome、微信、钉钉、Charles、用户连接数据或 `pubspec.lock`。只更新验收文档，未运行产品测试。

### 2026-11-18 UI-6.7 Mac Host 隔离状态补证

- 夹具：新增 `app/lib/preview/ui6_inspection_main.dart`、`ui6_inspection_runtime.dart` 与 `ui6_inspection_host.dart`，为生产设置页提供进程内 Runtime/Host stub。假 Host 只在内存中维护 Host 状态、配对申请和设备授权；不打开网络监听、不读 Keychain、不连接 Android。Runtime 使用 PreviewRuntime 作基础，连接设置、音乐账户、终端和结果均留在隔离进程内。
- 操作与结果：Profile 实窗先显示 Host 停止态，随后启动 stub Host 查看运行态、待审批设备和已配对设备；打开自定义权限对话框后取消，未更改权限；对假申请执行“批准只读”后，申请行消失、假配对设备数从 1 变为 2。此操作只验证生产 UI 控件与内存状态变更，不表示真实 Mac Host 网络/Android 配对已验收。
- 目视与范围：暗色 Host 停止/运行按钮、轮换入口、邀请入口、刷新、待批动作、已配对设备动作和自定义权限弹窗的可见布局/邻接关系没有发现明显错位。只完成静态外观查看及批准只读这一内存操作；未操作拒绝、允许连接向导、保存自定义权限、修改/撤销设备权限、身份轮换、停止 Host 或邀请复制；未检查浅色、各按钮动画或完整确认弹窗。因此矩阵 B084–B101 仅更新本轮实际看到的行，未捕获的确认/邀请状态继续开放，UI-6.7 仍部分验收。
- 实窗证据（PNG 保存在仓库外的验收目录）：[Host 停止态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/17-settings-host-stopped-dark.png>) SHA-256 `749e162dc6e0bfefee0116445e046872735fbffcb95d55750134b5fe906b46a9`；[Host 运行态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/18-settings-host-running-dark.png>) `610af2edfe5c1db463db923b6957eb57e2c8dd78ebdcb6f7bad8a19213877ac7`；[待处理与已配对设备](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/20-settings-host-pairing-dark.png>) `5b443448c089d197b61f31e2d73c1f2d75609446e8355b2077eb0a56e650b04d`；[自定义权限弹窗](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/21-host-custom-permissions-dark.png>) `0d05965d5985bb2fc952adaa5fb75c8ab5cda44bd4ca0858bc249b1d59e8c5e0`；[批准只读后状态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/22-host-approved-dark.png>) `6c062e6fe01e10981f861f4f88fb70cc7f528fea9be7565c83aec08c9ac851ca`。
- 验证与桌面清理：夹具加入后、实窗检查前已执行 `flutter test --no-pub`（300 项通过）、`flutter analyze --no-pub`（无问题）和三文件格式检查（零改动）；截图与文档更新不改 Dart 源码。关闭本轮临时 Aggregate Profile app/runner 后，`pgrep` 未发现对应 app、Flutter runner 或 inspection entrypoint 进程；未关闭用户自己的其他应用，也未触碰 `pubspec.lock`。

### 2026-11-18 UI-6.7 音乐、Host 与结果状态补证

- 环境：Mac17,9 arm64 / macOS 27.2.1；Flutter 3.47.8 stable / Dart 3.13.7；隔离 Profile 入口 `lib/preview/ui6_inspection_main.dart`；暗色主题。该批只补文档与仓库外 PNG 证据，没有修改产品 Dart 源码。
- 音乐与迷你播放器：真实生产音乐页中打开搜索授权对话框，并在进程内预览中授权后查看两条样例结果；歌曲播放确认对话框打开后取消。离开音乐页后全局 MiniPlayer 显示预置样例播放状态；点暂停只打开确认框并取消。未执行真实播放、暂停或外部音乐请求；样例播放状态不代表音乐后端成功。
- Mac Host：打开假邀请详情，检查短时二维码、有效期、loopback 地址与复制按钮；未复制邀请。查看已配对设备的权限编辑对话框后取消；撤销配对与身份轮换确认框均只打开后取消。Host/配对数据仅在隔离进程内存中，不启动监听、不连接手机、不读写 Keychain，也没有改变真实设备权限或身份。
- MCP 与错误结果：检查 JSON 字段折叠/展开；辅助功能名称从“展开 JSON 编辑器”变化为“收起 JSON 编辑器”，没有改 JSON 内容，截图中的字段视觉差异不明显。运行隔离夹具的“演示恢复状态”后，内存 Runtime 返回 `StateError('预览错误态：未联系任何执行端')`；查看红色处理提示和按钮，并展开错误详情。错误正文通过 AX 树核对；详情截图受固定 MiniPlayer 遮挡，没有把被遮住的文本算作视觉验收。“检查活动状态”未点击，也没有重试或真实执行端调用。
- 本批目视检查到的暗色按钮实例没有发现明显错位。它只证明所列页面与截图状态；不证明静置/点击动画节奏、浅色主题、真实音乐/Host 行为或其余生产按钮实例。UI-6.7 继续部分验收。
- 实窗截图位于仓库外的 `/Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/`：
  - [音乐搜索授权](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/23-music-search-confirm-dark.png>) SHA-256 `10caa16eef6b3a50e82eb1745ff4a90bc383a3eae5f29ee9cf309eb01fc42bbc`；[搜索结果与音乐播放器](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/24-music-search-results-authorized-dark.png>) `73074b2ad2c0d449252ee2df7ffbdf38adddf289f141f4b086e1038ebb0128e5`；[歌曲播放确认](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/25-music-play-confirm-dark.png>) `a3e09a57291e1ecb2732005f9eee2dd34f5fca932092234b31a673952b4b7b4d`。
  - [MiniPlayer 样例状态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/26-mini-player-dark.png>) `a465f90d51eb6d5a711fe99ba3367426949045b7b0efcafa9e2ccea51a12221b`；[MiniPlayer 暂停确认](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/27-mini-player-pause-confirm-dark.png>) `35c5fa916797be93b89c6574b2fb542749656d36802ec30f85a08227eeae6c1a`。
  - [Host 身份轮换确认](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/28-host-rotate-confirm-dark.png>) `a382a93c26ef47347722a3673af861cf0f11efcf45f427762e43b4956967bbb2`；[假邀请详情](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/30-host-invitation-dark.png>) `052a587d382b3e73c051b298e84e82affd24b619791b02c86b97c3c384fceb20`；[设备权限编辑](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/31-host-edit-permissions-dark.png>) `cacb8e801b43696a17f480e5d92a64eb5a3fcf07ed33ee6aea69a37f717b1fdc`；[设备撤销确认](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/32-host-revoke-confirm-dark.png>) `4ea93873e176c1027daf6c0769753e6aa717dc2ba0930401b207fbc5a1531c5a`。
  - [JSON 折叠态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/33-json-form-dark.png>) `84a4ad03fddb09b7aaa8ace7d71421b21d2254d63ac471a30d248d7b75189618`；[JSON 展开态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/34-json-form-expanded-dark.png>) `e859ffdc94082cb335d4b0813f9733221c99b578f81d65166ac1b8f9f241c786`。
  - [模拟错误结果首屏](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/35-simulated-error-result-dark.png>) `efd80f627d83063595879a16c7ec8396ffbe9bde8c2d2912780e192d4d54fc0e`；[错误提示滚动位置](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/36-simulated-error-result-scrolled-dark.png>) `bd3eb46dd0f7a40b7d23ab3b9f1cf48d4bde1558032b78fcd179acb1148aa9d1`；[错误详情展开态](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/37-simulated-error-detail-dark.png>) `97cc88c893cbfe731f8a050353bc7839613500a2c2da7da91bbedfc40cec60cc`。
- 逐调用点状态更新见 [UI-6.7 按钮实例核对表](ui-6.7-button-instance-matrix.md)。GUI 检查后发送 `q` 让 Profile runner 正常退出；核对未发现 Aggregate 应用或 Flutter runner 残留，未关闭用户的其他应用。

### 2026-11-18 UI-6.7 浅色实窗补证与临时进程清理

- 环境：沿用隔离 macOS Profile `lib/preview/ui6_inspection_main.dart` 与进程内 PreviewRuntime；将生产设置控件切到浅色后检查少量页面。所有搜索/运行数据均为本地验收样例。
- 实际覆盖：浅色设置页可见全局搜索、侧栏、主题控件及底部样例播放器；CLI 运行表单显示运行按钮；填入无敏感文本 `UI-6.7 light fixture` 后打开真实“确认执行”弹窗，核对写入权限说明与取消/执行按钮，并点击取消，未执行写入；音乐页可见播放器样例、搜索框和全局 MiniPlayer；本地模拟错误结果的“检查活动状态”恢复按钮在滚动后靠近当前视口下沿。截图当时没有把滚动位置推进到末尾，不能据此判断按钮与 MiniPlayer 是否重叠。证据和哈希如下：
  - [浅色设置页](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/38-settings-light.png>) SHA-256 `ccd7f0575af222614b3e9215dfd54f1cf2d45061f8e5e30c4dda21cf6325bfde`。
  - [浅色运行表单](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/40-cli-result-form-light.png>) SHA-256 `f0d8aab6712e4290310ede4be42b6d67907164181ed77530ea5ff337ae020fbf`；[浅色确认执行弹窗](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/45-write-confirm-dialog-light.png>) SHA-256 `1d1aba019762c91c746b6baca325ef6730ae16198288115e6e0e3650baee01ae`。
  - [浅色音乐页](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/49-music-light.png>) SHA-256 `24c3455cb2837dbebe11cdad6820d1663fd7c31d31af0569b9d92f3e49266fb3`；[浅色错误恢复位置](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/48-error-result-light-scrolled.png>) SHA-256 `5dde4670e803152ee3c7ac7c0a4cf9c8cc0fd66f64036afada2b33b52e8e62cd`。
- 未完成项：音乐搜索触发的授权弹窗未能可靠验证点击结果，截图中没有授权弹窗或搜索结果；未访问外部服务。其余浅色调用点、所有静置/点击收尾、稳定音乐状态及恢复按钮在原生实窗最终滚动位置的画面仍待核验，UI-6.7 继续部分验收。
- 清理：给搜索授权按钮的辅助功能点击返回“已投递、未验证”，后续快照仍显示弹窗；未重试，直接对临时 Flutter Profile runner 发送 `q` 并收到 `Application finished.`。随后进程核对没有 Aggregate 预览或对应 Flutter runner；协作任务列表只含当前主任务。未关闭用户的其他软件，工作区中原有 `pubspec.lock` 改动仍保留。此批只更新验收文档，未运行产品测试。

### 2026-11-18 UI-6.7 连接页面与弹窗浅深补证

- 环境：macOS Profile `lib/preview/ui6_inspection_main.dart`，隔离 PreviewRuntime；使用连接列表内存样例、预览 CLI 适配器和本机 Mac（预览）目标。未触发测试连接、删除、外部命令、文件选择、导入/导出或任何保存。
- 操作与结果：浅深主题下各查看连接列表、执行设备选择器、连接配置表单及动作编辑器；选择“本机 Mac（预览）”只打开第二步内存表单，随后取消。动作编辑器滚动到“检查并预览参数”按钮后取消，未改 JSON、未预览、未保存。截图中可见的按钮和邻接关系未发现明显错位；动作编辑器滚动后预览按钮完整露出。自动检测、紧凑全屏配置、删除确认和连接工作区入口未出现，继续标记未核。
- 浅深截图（均在仓库外验收目录）：
  - 连接列表：[浅色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/50-connections-list-light.png>) `dd6d9f9b478e6393f53a86a8aae9a3ac4d18a734c759cdc3f9ec11d067019628`；[深色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/50-connections-list-dark.png>) `42a725924f25cd60e9d0fdcac06d33c9dff6aaa84b5c96c20b452e1a336190b0`。
  - 目标选择器：[浅色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/51-connection-target-light.png>) `577691cdad92e4e871fbf92418ffeb8a48aad7488c833c25a30702e48195e7b2`；[深色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/51-connection-target-dark.png>) `28e9295b3c9fcb97ca7ba9b9ec911b648d98920e4867494604766504871ad266`。
  - 连接配置：[浅色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/52-connection-setup-light.png>) `37031c3354cedea9af21fc59faf4211e0f455a7560f5d39f02fac1d4b041cff7`；[深色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/52-connection-setup-dark.png>) `ab5ab12fd8cd53a8b8fab9c10a242e51db049c1863e9249a9f5c0ba2f54ccc7f`。
  - 动作编辑器：[浅色初始](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/53-action-editor-light.png>) `1c306a51c92a27ee8edfbc157d4fc0f350b3de47832390562a21a240173bd798`；[浅色滚动](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/53a-action-editor-light-scrolled.png>) `1daa963ccacbc5943eb37c03b9b2f537800ff098c446c45f05a1b8a797504692`；[深色初始](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/54-action-editor-dark.png>) `3f9f0f8c6f7d6c02a0762f63d1abed38e4527fbe843e59a927e9b5b6d2bc26a5`；[深色滚动](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/54a-action-editor-dark-scrolled.png>) `6a89308a4693a35e4bdb95954caffc569c1295f673ae024b6d197cc9e46ebe79`。
- 清理：配置表单取消后正常回到连接列表。`flutter run` 这次未保持可写标准输入，发送 `q` 失败；随后用临时窗口自带关闭按钮关闭应用，进程查询没有匹配的 Aggregate Profile app 或对应 Flutter runner。没有关闭用户其它软件。截图/文档更新未运行产品测试。

### 2026-11-18 UI-6.7 删除确认和连接详情补证

- 环境：隔离的 macOS Profile fixture，连接数据仅为 `Ui6InspectionRuntime` 进程内样例。浅色设置后通过连接导航进入 Git CLI 样例详情；深色状态打开删除确认弹窗。浅色详情图 [`56-connection-detail-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/56-connection-detail-light.png>) SHA-256 `153f548425bfc7e53b48ae7c7ade6a21012d1fc984c62bafea77b8f2a86d0f8a`；深色确认图 [`55-delete-confirm-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/55-delete-confirm-dark.png>) SHA-256 `f8615543b6f142a96cb9d45425bb5941fb99e1fe4e273aa8683211d62064f5dc`。
- 目视范围：浅色连接详情页可见返回、添加和样例能力入口；深色删除弹窗可见标题、说明、取消和危险删除按钮。删除按钮未点击；取消按钮的 AXPress 返回“已投递、未验证”，下一次快照仍见弹窗，未重复点击；按 Escape 后弹窗关闭，fixture 仍显示三条连接。浅色删除确认、其余操作按钮动态状态仍待核。
- 清理与验证：临时 `flutter run` 收到 `q` 并返回 `Application finished.`；精确进程查询未找到本次 Profile app 或 `ui6_inspection_main` Flutter runner。没有关闭用户其他应用。只生成两张验收截图并更新文档，未运行产品测试。

### 2026-11-18 UI-6.7 活动页浅深实窗补证

- 环境：`lib/preview/ui6_inspection_main.dart` 的隔离 Profile，启动时显式设置 `--dart-define=UI6_SEED_ACTIVITY=true`。默认预览入口不生成这些记录。fixture 在内存 `PreviewRuntime` 合成成功、校验失败、取消三种记录，不运行命令、不访问网络和用户数据。
- 截图：深色全状态列表 [`57-activity-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/57-activity-dark.png>) SHA-256 `711aa13cd1d002fbc15bca089c7ae1ad5be934d31bebf094597abdd906386002`；深色滚动详情 [`58a-activity-failed-detail-dark-scrolled.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/58a-activity-failed-detail-dark-scrolled.png>) `ef023d5ba4afb01a1420426afc2665d47cc64c8a280d407c93d7298f2b70b1b2`；浅色滚动详情 [`59b-activity-failed-detail-light-scrolled.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/59b-activity-failed-detail-light-scrolled.png>) `2ac417d4df5448308c938049bf247a0323678bdba5637b77cb4df333339da700`；浅色失败筛选列表 [`59c-activity-failed-list-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/59c-activity-failed-list-light.png>) `fb2b3bd3db9195fb162d370dfe65fcaf60b01de1ed8763f6826c00d3164ace98`；浅色全量列表 [`60b-activity-all-light-current.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/60b-activity-all-light-current.png>) `cb60cc272533a7c4361a7149c1426ce890dbfbba55967d9fd9131e0dfa1a3b35`。
- 操作与发现：刷新活动后失败样例仍在；失败筛选只显示失败行，选择后打开紧凑详情，再点“返回记录”恢复列表；七个筛选和复制/重新打开按钮已目视。未触发重新打开、复制诊断或运行中取消。浅色全量截图在本轮后段还显示额外 `music.state` 成功条目；这些事件位于同一隔离 `Ui6InspectionRuntime`，其 `invoke` 委托给内存 `PreviewRuntime`，触发次数与来源动作未在本轮区分，不把该数量作为稳定 fixture 计数。滚动到详情操作行后按钮可见，底部与固定 MiniPlayer 间距很小，但截图中未见按钮内容被遮挡。
- 验证：`flutter test --no-pub test/activity_page_test.dart` 3 项通过，包含 seed 幂等检查和既有列表/运行中取消 Widget 测试；`flutter analyze --no-pub` 无问题。 Profile runner 收到 `q` 并返回 `Application finished.`；进程查询无本轮 Aggregate app/runner。此批只用于活动按钮局部补证，不代表 109 个调用点逐项签收。

### 2026-11-18 UI-6.8 按原版刷新间隔积分

- 来源核对：重新取得作者官方 `main.js`，SHA-256 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`，与本机 `inputs/sources.json` 所记摘要一致。原版每次 `requestAnimationFrame` 使用实际间隔并截断到 `1/30 s`；滑块弹簧每帧四个子步，光带相位与点阵弹簧使用本帧步长，太阳射线和月亮星点亮度由同一绝对时间逐帧求值。
- 修改：删除产品实时路径的固定 `1/60 s` 积分累加器，`advanceRealtime` 现在直接调用原有逐刷新积分。120 Hz 下不再隔帧停止滑块、粒子和光带位置更新。仅改变时间积分采样；拖动、反向、释放、端点提交、主题偏好和减少动态效果逻辑未改，也没有引入参考帧序列。
- 验证：新增 120 Hz 单刷新步测试，并核对可变刷新间隔的 `1/30 s` 上限；`flutter test --no-pub` 全量 301 项通过，`flutter analyze --no-pub` 无问题，`git diff --check` 通过。离屏光学探针与 60 Hz 独立模型样本均在全量测试中通过。另增强 macOS 实际设置路由回归，断言页面中的 `GlassThemeSwitch` 使用 `videoFittedThemeSwitch`，且配置含完整 113 个粒子参数；`flutter test --no-pub test/android_theme_transition_test.dart` 两平台变体 2 项通过，分析通过。该检查锁住生产接线，不代替逐帧图像对照。
- 范围边界：这是由官方源码与模型回归证明的更新时间修正，没有新录制原生窗口逐帧差分，也没有测量物理 display-present 时刻或实际 120 Hz 显示面板。原录屏 PTS 映射、初始绝对时钟、粒子随机对应和整帧 MAE 差距仍存在；UI-6.8 继续部分验收，不能据此声称 1:1 完成。

### 2026-11-18 UI-6.8 源时钟映射偏移候选复核

- 问题与候选：独立 66 帧图像映射为 `a=0.9963953591`、`b=6.5278820067`，拟合残差 RMSE 为 `18.528 ms`；其相对现行 +6.5 s 来源时钟的中位差为 `+19.786690 ms`。离线重导出 200 帧，固定现有校准、输入路径、主题/几何和粒子参数，只把绝对渲染时钟前移该中位差，不改产品代码。
- 复现校验：基线重导出与既有归档基线一致，eligible 171 帧 mean MAE 为 `6.2835453467/255`（既有 `6.2835454119`）；稳定视野 79 帧为 `4.4272927953/255`（既有 `4.4272929147`）。
- 结果：候选在 eligible 171 帧将 mean MAE 从 `6.2835453467` 增至 `6.2842520947/255`（差 `+0.0007067480`）；稳定视野 79 帧从 `4.4272927953` 增至 `4.4289982701/255`（差 `+0.0017054748`）；稳定控件 ROI 从 `7.8285863393` 增至 `7.8290721107/255`。稳定视野中的 76 个已参与时钟映射帧亦略有变差；未参与映射的稳定留出帧仅 3 个，不足以支持独立泛化结论。候选未显示稳定改善，故拒绝，不修改产品时间原点、动画物理或交互逻辑。
- 证据与限制：逐帧指标与每帧数据保存在本机 [`summary.json`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-clock-map-reevaluation/summary.json>)，SHA-256 `52169c4fc1c2e50a8256fe18822eec829d6f3ba65c1627a87e43c097a522453d`。这只是用重建裁片/拟合几何进行的离线候选比较；映射约有 `18.5 ms` 拟合残差，留出帧太少，也没有原生 display-present 时间戳，不能据此认定实际显示相位或逐帧 1:1。临时 200 帧渲染目录已删除，未启动或切换用户桌面应用；UI-6.8 继续部分验收。

### 2026-11-18 UI-6.7 失败恢复按钮与 MiniPlayer 可达性复核

- 问题来源：浅色 Profile 截图 `48-error-result-light-scrolled.png` 中，“检查活动状态”按钮靠近结果区当前视口下沿。截图的滚动位置没有到达末尾，单凭该画面无法确认是否与固定 MiniPlayer 重叠。
- 复现路径：新增 `capability_run_page_test.dart` 的 macOS Widget 回归，使用生产 `ConnectionHomePage`、嵌入式 `CapabilityRunPage`、`ResultPanel` 和 `MusicMiniPlayer`，向隔离 Runtime 注入 MCP 连接失败结果；将页面滚动到最大范围后比较按钮与 MiniPlayer 的实际矩形。
- 原生补证：隔离 Profile 的浅色错误恢复页面滚到末尾后截图 [`61-error-result-light-scroll-end.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/61-error-result-light-scroll-end.png>)，SHA-256 `f02561f9a5c307038afd3bf50f5cd0ea25bce6018a6412e3398b9cf841ee50d1`。恢复按钮 AX 矩形为 `{x:422,y:578,width:139,height:40}`，错误详情行是 `{x:422,y:627,width:668,height:48}`，MiniPlayer 歌曲标签从 `{x:408,y:764}` 开始；再次向下滚动 12 个滚轮单位后前两项位置不变，确认已到滚动末尾。截图中错误卡片、恢复按钮和详情行完整显示，MiniPlayer 位于其下方。
- 结果与验证：Widget 和浅色原生实窗都确认滚到最大范围后恢复操作完整可见；未发现生产布局缺陷，因此没有改产品布局代码。`flutter test --no-pub test/capability_run_page_test.dart` 10 项通过；`flutter analyze --no-pub` 无问题；Dart 格式与 `git diff --check` 通过。B106 及 UI-6.7 范围说明已加入原生证据；UI-6.7 仍因其他按钮实例和动态状态未全量签收而保持部分验收。

### 2026-11-18 UI-6.7 活动页运行中取消 Profile 补证

- 环境：使用隔离 Profile 入口 `lib/preview/ui6_inspection_main.dart`，同时设置 `UI6_SEED_ACTIVITY=true` 与 `UI6_SEED_ACTIVITY_RUNNING=true`。新增记录仅存在于 `Ui6InspectionRuntime` 内存中，不调用真实服务，不运行命令，不访问网络、Keychain 或用户连接数据。
- 视觉证据：暗色运行中列表 [`62-activity-running-dark-list.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/62-activity-running-dark-list.png>) SHA-256 `c62c5caf081a02d030f79e06122dc3a2916ec5b37da599383527aeccfded497f`；暗色详情 [`63-activity-running-detail-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/63-activity-running-detail-dark.png>) SHA-256 `4a13ef57830f82d5090fba570532c4aa4f19ff0d117ff2abf55fe5a01ae72061`。详情首屏的操作区在 MiniPlayer 上方滚动内容之外；语义滚动将“取消运行”带入可见区后点击成功。
- 操作与结果：原生 AX 树先确认状态“运行中”和按钮“取消运行”；点击后按钮消失，状态变为“已取消”，详情提示“已请求取消；请刷新确认最终状态。”该结果证明隔离 fixture 的取消状态转换与页面反馈，不证明生产服务的取消请求及异步终态。未执行任何外部动作。
- 验证与清理：新增 `activity_page_test.dart` fixture 测试；定向运行 `flutter test --no-pub test/activity_page_test.dart`，4 项通过；`flutter analyze --no-pub lib/preview/ui6_inspection_main.dart lib/preview/ui6_inspection_runtime.dart test/activity_page_test.dart` 无问题；定向 Dart 格式与 `git diff --check` 通过。Profile runner 收到 `q` 正常退出，并确认 Aggregate 与 Flutter runner 进程已结束。B010 已更新；UI-6.7 仍部分验收，浅色运行态、完整操作区截图及真实服务响应仍未签收。

### 2026-11-18 UI-6.7 活动页浅色运行中取消补证

- 环境：同一隔离 macOS Profile fixture 初始偏好为浅色；AX 树确认主题值“浅色”。样例数据仍只存在 `Ui6InspectionRuntime` 内存中。
- 浅色截图及 SHA-256：运行中列表 [`64-activity-running-light-list.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/64-activity-running-light-list.png>) `abb5cfd22dd9e3fb9ba1c6f07885c0a6c4c6d312ce1e206e510f4319d4c1f81a`；详情首屏 [`65-activity-running-detail-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/65-activity-running-detail-light.png>) `5043c66d9d784dc4a919ee08a45f866b5015ed78cb7687d2c8c1ca362471b09f`；滚至操作区 [`66-activity-running-detail-light-scrolled.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/66-activity-running-detail-light-scrolled.png>) `58cc4570fb39a9c0986699123e229e5abee75b9c0a30e4a89c0658979d74f485`；取消后详情 [`67-activity-cancelled-detail-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/67-activity-cancelled-detail-light.png>) `6b6c4fb18b938f6a742cc5301f9af59bc9197a8f6d3138c5cc1651cf3340af0f`。
- 原生交互与几何：点击运行中行后详情显示“运行中”及“取消运行”。`scroll-to` 将取消按钮滚到可见区；AX 按钮矩形 `{x:729,y:710,width:113,height:40}`，MiniPlayer 暂停按钮矩形 `{x:910,y:761,width:46,height:47}`，垂直净距 11 logical px，未遮挡。点击取消按钮后 AX 节点消失，状态更新为“已取消”，页面提示“已请求取消；请刷新确认最终状态”。此结果只验证进程内 fixture 的 UI 状态转换，不证明生产服务终态。
- 清理及范围：Flutter runner 的 stdin 已关闭，因此用 Aggregate 窗口关闭按钮退出；AX 返回窗口不存在，进程查询无 Aggregate app、Flutter runner 或 xcodebuild 残留。两主题的运行/取消状态已核；活动筛选器其余状态、真实服务响应及 B010 外其他未核调用点仍开放，UI-6.7 维持部分验收。没有改动生产布局或主题逻辑。

### 2026-11-18 UI-6.7 活动页全部筛选状态浅色实窗验收

- 环境：新增隔离夹具开关 `UI6_SEED_ACTIVITY_FILTER_STATES=true`，仅为 Profile 页面补入合成“超时”和“结果待确认”记录；连同成功、失败、取消与运行中样例共覆盖六类状态。记录只存在于本进程内，不调用真实服务。
- 原生操作：逐一点击“成功”“失败”“取消”“超时”“运行中”“结果待确认”，AX 树每次只保留对应状态的记录行；随后点击“全部”，六类样例全部恢复。静态画面中的每种状态图标、标签与筛选上下文已抽查。截图和 SHA-256：[`68-activity-filter-all-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/68-activity-filter-all-light.png>) `3534b926a18cde353c5a9abb4e9a4ff900328b5b47e35c3df0c1ffd5d37c1450`；[`69-activity-filter-success-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/69-activity-filter-success-light.png>) `45b47db51b5aa361f5b6015eb42a8a75cdf474541944b175e63c76ac01a12836`；[`70-activity-filter-failed-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/70-activity-filter-failed-light.png>) `f95f15c82e0f600f4987a7d7441e9561e6e96b4f8d7df3f3d6558aeed212e20e`；[`71-activity-filter-cancelled-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/71-activity-filter-cancelled-light.png>) `da7c476af36e41a2a27a60745a63f18a4020bd7b2ff22986ab92f6df7cf6b2ff`；[`72-activity-filter-timeout-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/72-activity-filter-timeout-light.png>) `91392fc3ef66700e1919f729d46e5784831b48b2872e5624e36aed0c0808fe52`；[`73-activity-filter-running-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/73-activity-filter-running-light.png>) `de05ac23b3b9ea5b51260c93e31da516b67b1b205cb7776b699bd215b55aa0b6`；[`74-activity-filter-unknown-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/74-activity-filter-unknown-light.png>) `86b439e68cf07580b07cb79b8545562a2c95e683acb6fdcf60584f09d803c90c`；[`75-activity-filter-all-restored-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/75-activity-filter-all-restored-light.png>) `f0bea8b409ca09ca1e489040c694efd1bd4ee51563ff7e664d3185c82ded4306`。
- 代码与验证：只扩充 `Ui6InspectionRuntime` 的 Profile fixture 和 `activity_page_test.dart` 幂等/清理回归，没有改生产页面或过滤逻辑。`flutter test --no-pub test/activity_page_test.dart` 5 项通过；三文件分析无问题，Dart 格式检查及 `git diff --check` 通过。
- 清理与边界：Flutter runner 用 `q` 正常退出，进程检查没有 Aggregate app、Flutter runner 或 xcodebuild 残留。该轮只验证浅色夹具状态筛选和静态外观；点击动效逐帧、真实服务数据以及其他按钮调用点仍待核，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 工作台类型筛选浅色实窗验收

- 环境：使用隔离 macOS Profile 入口和本地合成的 17 项工作台能力数据；截图窗口为 800×632 logical px。数据只来自进程内 PreviewRuntime，不访问真实连接或服务。
- 原生操作：逐项点击“工具”“资源”“提示”“CLI”，AX 树分别显示 3、1、1、12 项；再点“全部”恢复 17 项。各筛选的结果范围与按钮选中态已通过实窗快照及截图抽查。
- 截图与 SHA-256：初始/全部 [`76-workspace-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/76-workspace-light.png>) `b5aecfe6469c0dac8f19e2c4896877c6f113a9176b54707c6469250b4365a1d8`；工具 [`77-workspace-filter-tools-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/77-workspace-filter-tools-light.png>) `87e1ab8ed556b51d7a6a208e229651ac4a919bb651e78285b28ccadae275c441`；资源 [`78-workspace-filter-resources-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/78-workspace-filter-resources-light.png>) `1344d076835a923837adaea5f281f72cfe76966d8ec8371d1bd4d034a10bedb4`；提示 [`79-workspace-filter-prompts-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/79-workspace-filter-prompts-light.png>) `21173788d4c466d9ac4edc0c6c4bc7c6d5b5f990f56793468ee08c4e4688761b`；CLI [`80-workspace-filter-cli-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/80-workspace-filter-cli-light.png>) `c628f402456cb79ab8e82a2250f5dfc133e0f616d9cf98a285aa4cc2916127f8`；全部恢复 [`81-workspace-filter-all-restored-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/81-workspace-filter-all-restored-light.png>) `62b31838177fbb2e0f9d2405bb775788fff7d1679c25dbba27bf57b775967d48`。
- 范围与清理：本轮只核对浅色类型筛选结果和静态布局；点击/静置动效、搜索清除 B012、无匹配状态清除 B016、空连接态的添加 CLI/MCP 按钮 B013–B015 均未签收。搜索框的 AX `set-value` 没有形成可确认的 Flutter 输入事件，因此不作为产品行为结果。临时 Aggregate Profile 和 Flutter runner 已关闭，确认当前仅 Codex 窗口可见；用户工作应用和带未保存会话的应用未关闭。UI-6.7 仍为部分验收。

### 2026-11-18 UI-6.7 工作台搜索与空连接动作隔离 Widget 回归

- 夹具：`Ui6InspectionRuntime` 增加空工作台连接数据及可配置 `RuntimeFeatures`；Profile 编译期开关 `UI6_EMPTY_WORKSPACE=true` 可显示空连接态，配合 `UI6_HTTP_ONLY_WORKSPACE=true` 可展示仅支持 HTTP MCP 的文案和操作。夹具仍为进程内 stub。
- 回归：B012 输入 `Git` 后清除搜索并恢复 17 项；B016 选择资源筛选、输入无匹配文本后点击清除，搜索和类型筛选均复位并恢复全部 17 项；B013/B014 的空连接按钮回调分别传递 `cli`/`mcpStdio`，HTTP-only 状态下 B015 回调传递 `mcpHttp`。只验证 Widget 状态及回调，不打开配置流程或执行添加。
- 验证：`flutter test --no-pub test/workspace_search_semantics_test.dart` 3 项通过；夹具和测试文件 `flutter analyze --no-pub` 无问题；`dart format --set-exit-if-changed` 与 `git diff --check` 通过。没有改生产页面逻辑或主题按钮逻辑。
- 范围：本轮未启动 Profile app，因此 B012–B016 的浅色/深色实窗位置、尺寸、真实点击动效和空连接态视觉仍未签收；B013–B015 的回调测试也不代表真实连接创建流程。UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 工作台搜索与空连接按钮浅色实窗验收

- 环境：使用 `Ui6InspectionRuntime` 的进程内数据，普通状态包含 17 项能力；空连接状态使用 `UI6_EMPTY_WORKSPACE=true`，HTTP-only 状态另加 `UI6_HTTP_ONLY_WORKSPACE=true`。窗口 800×632 logical px，未访问真实连接、服务、命令或凭据。
- 搜索与筛选：键盘输入 Git 后 AX 只列出 3 项；点击“清除搜索”后输入框清空并恢复 17 项。再选资源筛选并输入 `ui6-no-match`，截图显示空结果和“清除筛选”；点击后搜索与筛选复位、标题恢复“全部功能 · 17”。
- 空态按钮：普通空态截图显示“添加 CLI”和“添加 MCP”；分别点击后选“本机 Mac（预览）”，配置表单分别显示“预览 CLI”与“预览 stdio MCP”；HTTP-only 空态只显示“添加 HTTP MCP”，点击后表单显示“预览 MCP HTTP”。三条路径均只查看表单并取消，未点“测试连接”或“保存连接”。未输入 HTTP 凭据；截图中的安全存储说明属于复用生产表单文案，不代表 fixture 写入了 Keychain。
- 截图及 SHA-256：Git 结果 [`82-workspace-search-git-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/82-workspace-search-git-light.png>) `cdf13145f60ccab345e13ebea22480fdac9be7c6e5a9feb879d68bd72fca74f3`；无匹配 [`83-workspace-empty-filter-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/83-workspace-empty-filter-light.png>) `0ab36599211cfb29c4434cdc244e25d82ff0f4775cdb5df5201efe267e47ef84`；清除后恢复 [`84-workspace-search-cleared-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/84-workspace-search-cleared-light.png>) `4043dcded7e6c9a87ae568f7b3a07d2a8fd9fd1603dec06fe83e87d1e4ed97ea`；普通空态 [`85-workspace-empty-connections-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/85-workspace-empty-connections-light.png>) `400b5779f285bb435f979e1a25759bf42381a72dd93339f36bb887a1b1c58c96`；CLI 表单 [`86-workspace-add-cli-preview-form-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/86-workspace-add-cli-preview-form-light.png>) `2ba3a455893fa17c23619881cd5087b970b928afb3eddf8d05713a63596adaeb`；stdio MCP 表单 [`87-workspace-add-mcp-preview-form-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/87-workspace-add-mcp-preview-form-light.png>) `7f210e9c297e87d96cc457e35047401f9b8b39d0ccb91e60a7e7b6acb0b5e300`；HTTP-only 空态 [`88-workspace-empty-http-only-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/88-workspace-empty-http-only-light.png>) `ae9e1975d49d8bc1a75d703f52029cab223989f7bbcdd28ec51bb59e4cd7491d`；HTTP MCP 表单 [`89-workspace-add-http-mcp-preview-form-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/89-workspace-add-http-mcp-preview-form-light.png>) `6d36804b1a794c2ba31c8ee4bc204f745866dbd4fddc501d217cf378a4cfb602`。
- 夹具修正与验证：原 Profile stub 缺少 `mcpStdio` adapter，导致添加 MCP 按钮打开 CLI 表单；现增加纯内存 stdio stub，并按 `RuntimeFeatures` 过滤可用 adapter。`workspace_search_semantics_test.dart` 3 项通过，覆盖 B012–B016 搜索/清除及 CLI、stdio MCP、HTTP MCP 类型回调；三文件定向分析、格式检查和 `git diff --check` 通过。正式页面行为和主题切换逻辑未改。
- 清理与边界：Profile runner 用 `q` 退出，确认无 Aggregate app 窗口或相关 app 进程；当前仅 Codex 窗口可见。以上只覆盖浅色实窗及隔离表单；深色状态、各按钮静置/点击动画逐帧和真实连接创建仍待核，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 动作编辑器浅色交互实窗验收

- 环境与边界：使用隔离 macOS Profile `lib/preview/ui6_inspection_main.dart` 和 `Ui6InspectionRuntime`，仅操作“UI 检查 · Git CLI”内存样例。没有运行 CLI、测试连接、读取文件、选择导出路径、写磁盘、访问网络/Keychain 或使用真实连接。
- 原生交互：新增动作后 AX 清单出现 `action1`；点击取消后重开，清单恢复为仅含原动作 `version`，确认草稿丢弃。点击“检查并预览参数”后，AX 读取结果 `["仅内存预览", "--help"]` 及“此操作不会运行程序”的提示。保存后重新打开，预览动作菜单含 `version` 和 `action1`；保存只写入当前进程内 fixture，退出后销毁。
- 文件面板：导入打开 macOS 原生 open 面板，未选择文件时“打开”禁用，点击“取消”返回编辑器；导出打开原生 save 面板后点击“取消”，未选路径、未导出文件。
- 截图与 SHA-256：新增动作状态 [`90-action-editor-added.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/90-action-editor-added.png>) `5bd06d16241c8afa4e287373075521c58a18e4a9ba92189956ab2cdcd3735151`；取消后回到连接详情 [`94-action-editor-cancel-check.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/94-action-editor-cancel-check.png>) `a4425b62b5b8e29c4cd05e675c95036a9007a03ea9e0b00bffa822ba12f850dc`。参数预览与下拉项结果由同一 Profile AX 树直接读取。
- 回归与清理：`action_editor_test.dart` 增加取消草稿并重开检查；`flutter test --no-pub test/action_editor_test.dart` 3 项通过，定向 `flutter analyze --no-pub lib/features/connections/action_editor_dialog.dart test/action_editor_test.dart` 无问题，格式与 `git diff --check` 通过。关闭 Profile 后确认无 Aggregate、Flutter runner 或 Flutter 工具进程残留；未改生产动作逻辑或太阳/月亮主题逻辑。
- 范围：B018–B023 的浅色动作路径已有局部交互证据；深色实窗动态、各按钮静置/点击动画逐帧与其余生产按钮调用点仍未逐项签收，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 连接配置路径补证

- 环境与边界：使用隔离 Profile `lib/preview/ui6_inspection_main.dart` 和 `Ui6InspectionRuntime`。目标仅为本机 Mac（预览）及虚构的配对 Mac（样例）；表单输入、测试和查找均由内存 stub 处理，没有连接设备、执行命令、访问网络或读取凭据。
- B024：选择配对 Mac 样例，输入虚构程序名 `git` 并点击“在 Mac Host 查找程序”；stub 返回空结果，界面显示“Mac Host 未找到该程序，请检查名称或授权”。见浅色截图 [`100-connection-setup-host-detect-miss-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/100-connection-setup-host-detect-miss-light.png>)，SHA-256 `7e8adee432aeb2792fdcb32645e2a051503219545d1d0c34d7aeeb2323ba854c`。
- B025–B027、B029：本机 Mac 预览表单打开原生文件面板后取消，未选文件或读取文件。随后仅在内存表单输入虚构路径 `/tmp/ui6-preview-cli` 并测试；AX 结果为“已通过：预览安全检查。未访问本机命令、网络或凭据存储。”保存按钮随之启用，但未点击；再取消表单，没有保存连接。测试通过截图 [`98-connection-setup-test-passed-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/98-connection-setup-test-passed-light.png>)，SHA-256 `0e0d26d2bbb83f64607f49ea60134f7546d21284b0e01142fa9fb44633bbf487`。
- B028（后续更正）：另一轮 Profile 实测窗口实际为 540×700pt，已进入 600pt 以下紧凑全屏分支；原生点击“关闭添加连接”后表单消失，草稿未保存。截图见下方 `102-connection-setup-compact-light.png`。此前依据另一进程的 768pt 实际宽度得出“紧凑分支无法进入”的结论不准确；小屏 Widget 用例仍覆盖相同关闭行为。
- B030–B032：目标选择器显示本机 Mac 与虚构配对 Mac；两项分别进入对应内存预览表单，取消项关闭选择器，没有连接设备。目标选择器 [`96-connection-target-light-current.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/96-connection-target-light-current.png>) SHA-256 `0d713b3307a86894e69a086709b5ef9ea2480536e6f3df145fa21deff888a91e`；本机表单 [`97-connection-setup-local-light-current.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/97-connection-setup-local-light-current.png>) `b1b3f00139d43a8834c3d29c7f08587b22cd30ca9cf2d38379160634e97499c1`；配对 Mac 样例 [`99-connection-setup-paired-mac-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/99-connection-setup-paired-mac-light.png>) `903e981c0955b4e665d41279be170cf503fd397d3c7ee862576842d289afc801`。
- 验证与清理：`dart format --set-exit-if-changed test/connection_setup_dialog_test.dart` 与 `git diff --check` 通过。Profile runner 收到 `q` 正常退出；应用窗口、Aggregate 进程及 Flutter runner 均已确认不存在。此次只覆盖浅色连接配置路径；深色交互、原生紧凑布局和对应按钮的静置/点击动效仍待核，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 连接列表紧凑布局和详情动作实窗补证

- 环境：隔离 macOS Profile 窗口 540×700pt，连接数据来自 `Ui6InspectionRuntime` 进程内样例。未连接设备、运行 CLI、调用外部服务、访问网络或读取凭据。
- B028 复核：窗口进入紧凑连接配置分支；实窗点击右上角“关闭添加连接”后表单消失，草稿未提交。该直接证据更正本记录前一节中基于 768pt 窗口得到的判断。
- B030–B036、B043：紧凑目标选择器显示本机 Mac 与配对 Mac 样例；点击关闭后选择器消失。选择本机 Mac（预览）进入配置表单后点关闭，表单消失。连接列表进入 Git CLI 详情，点击“返回连接”恢复列表。添加连接仅进入目标选择器，没有提交连接。
- B033/B034/B042：从 MCP 样例打开浅色删除确认；截图中取消和危险删除按钮均可见。点击取消后弹窗消失，未点击删除，样例仍保留。
- B038/B039：把 Git CLI 样例下移后重新读取连接顺序，确认顺序变化；首页上移呈禁用外观，下移按钮呈可用外观。Flutter macOS AX 将禁用按钮报告为 enabled，故禁用判断依据为界面外观与源码 `onPressed: null`，不作为 AX enabled 语义通过。
- B040/B041：从 Git CLI 详情打开动作编辑器，查看原动作 `version` 后取消，未保存；分别对 MCP、Git 内存样例点击测试连接，隔离 runtime 的刷新只返回样例连接，不访问外部服务。
- B037：macOS 不适用。`app_shell.dart` 仅在 `_mobilePlatform` 下提供 `onOpenConnection`，因此“打开连接工作区”按钮只在移动端呈现。
- B044–B047：macOS 不适用。`LocalRuntimePort` 实现 `ConnectionSetupPort`，正式 macOS 新建流程进入 `ConnectionSetupDialog`；此通用 `AddConnectionDialog` 的程序/动作清单选择、取消和添加按钮不在 macOS 路由中。尝试从 `PreviewRuntime` 打开添加流程时，界面显示“预览模式不能添加真实连接。”提示并由 Escape 关闭；没有绕过预览安全保护或改变连接数据。macOS 对应程序文件选择与取消路径由 B025 覆盖。
- 截图及 SHA-256：紧凑目标选择器 [`101-connection-target-compact-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/101-connection-target-compact-light.png>) `b77b8628f0d46a8fdde92808fac122b1623bca3b1c9a25cab5053cc87d6aa4b7`；紧凑配置表单 [`102-connection-setup-compact-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/102-connection-setup-compact-light.png>) `e050890b6ebbc27573747c2d29ddc7593efbb4cf7314a83a0281b83b91c4923d`；连接详情 [`103-connection-detail-compact-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/103-connection-detail-compact-light.png>) `3721e33c9f30c11a77525867de2ab2c644f13fab006dc315c594b83b49c903f8`；排序按钮状态 [`104-connection-actions-first-item-compact-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/104-connection-actions-first-item-compact-light.png>) `7e1a1178c960e8408f14a80353b8b38f8e8083c35a96ea9111e2e07ad9a485e8`；删除确认 [`105-delete-confirm-light-compact.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/105-delete-confirm-light-compact.png>) `6b4365981e09ed69e5ceae9ea391b2138aea8ebddba28f4df3f244ad6c56aacd`；动作编辑器 [`106-action-editor-from-detail-compact-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/106-action-editor-from-detail-compact-light.png>) `ed3ad457d3e7a4dd99d4fa85025a0f003136439b83b539c872d27faa4062ca34`。
- 清理与范围：第一轮 Profile 用 `q` 退出；第二轮 Flutter 进程未保留可写 stdin，随后通过 `agent-desktop close-app Aggregate` 正常退出，并确认应用列表无 Aggregate、无窗口、无 Flutter runner。没有关闭 Charles、GW 或用户的其他应用。仅补充浅色紧凑实窗交互证据，深色动态、逐按钮静置/点击光效和其余未覆盖调用点仍待核；UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 运行确认、JSON 控件与全内存终端补证

- 环境与隔离：浅色 macOS Profile 使用 `lib/preview/ui6_inspection_main.dart` 和 `Ui6InspectionRuntime`。源码确认 `invoke` 委托给进程内 `PreviewRuntime`；终端会话由 `ui6-inspection-*` 标识，输入只写入内存流，`interruptTerminal` 只输出 `^C`。本轮没有运行外部命令、连接服务、访问网络或使用用户连接数据。
- B048–B050：从“暂停播放”无参表单点击“运行”后出现外部写权限确认；点击“取消”关闭确认框，没有触发写入。“执行”按钮在画面中可见但未点击。表单 [`107-write-capability-form-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/107-write-capability-form-light.png>) SHA-256 `f2755bbe5acfc6f898558e9cbcfe2e500bb4b406087d61f894d926417efdab9b`；确认框 [`108-write-confirm-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/108-write-confirm-light.png>) `f50e24fa907ddac7ac55580eb248bbaa80e541749319726afe6b3cdc956a748e`。
- B051、B055–B059：通过“在终端运行”进入 UI 检查专用全内存终端，画面说明不会运行外部命令。点击“中断程序”后显示 `^C`；点击 Ctrl 后再发送 Tab，Ctrl 提示消失；Tab 与 ↑ 按键仅写入本地内存 stub。无选择时复制按钮呈禁用外观但未点击；粘贴按钮未点击，避免读取系统剪贴板。未逐项检查其余终端按键。表单 [`111-terminal-action-form-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/111-terminal-action-form-light.png>) `fe5f18092c0cffb5d5d4d838430ad9d6d2e6125bfbb28a508b9f6d5031dfe0ad`；stub [`112-terminal-stub-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/112-terminal-stub-light.png>) `69773d2545dce998659dfb732eb59687ae970d087bce1b687063984f2882a857`；Ctrl 提示 [`113-terminal-key-input-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/113-terminal-key-input-light.png>) `e63a2700dc3c6ad9d006e095debfe223b98bf30d6f83d01144acd9e01db0a78a`；按键交互 [`114-terminal-key-interaction-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/114-terminal-key-interaction-light.png>) `e18bf5614d51ded340f3130c48b983bebee0f1f17d0af93381ef9b58c29056af`；中断显示 [`115-terminal-interrupt-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/115-terminal-interrupt-light.png>) `b8420390742292f3a4900a5e1805591d3c8174c0ccb79df577c5d9cd8fed43fd`。
- B052–B054：`UI6_SEED_ACTIVITY_RUNNING=true` 在隔离 fixture 中显示运行中的 Git 状态样例；点击取消后重新读取 AX，确认“运行状态：已取消”，只证明内存样例状态转换。取消前界面 [`116-running-cancel-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/116-running-cancel-light.png>) `1ea5083b849a2f39c322a32017e3cf3214d5f9a9b8951b6a75c1e37d00bda5e5`。JSON 表单使用有效默认值 `{}` 点击格式化后没有报错，但没有可见变化；因此非空 JSON 格式化未获验证，AX 直接设置表单值未能提交到控件状态，不以此推断产品缺陷。展开/收起后 AX 名称分别切换为“收起 JSON 编辑器”和“展开 JSON 编辑器”；展开图 [`109-json-form-format-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/109-json-form-format-light.png>) `fee287299e3da05d66ec780fead661f8631ade0503f0a01189e9c6767817f2c5`；[`110-json-editor-expanded-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-inspection-runtime/110-json-editor-expanded-light.png>) `1d084cb89f9e1b561ce081dda1cd85deea5ffe2b88f833f3054d862b196f570e`。
- 清理与范围：Profile 收到 `q` 并正常退出；随后应用清单与进程查询均未发现 Aggregate、Dart AOT fixture 或 Flutter runner 残留。Charles、GW、Codex、终端和访达在检查前已运行，均保留。以上仅覆盖浅色隔离 UI 的局部交互，不代表真实终端、服务取消、所有按键、非空 JSON 或按钮动效已验收；矩阵 B048–B059 已更新，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 音乐控件 Widget 回归核对

- 回归结果：对六个音乐/连接 Widget 测试文件分批运行后，再合并重跑 `flutter test --no-pub --reporter compact test/music_account_control_test.dart test/music_mini_player_test.dart test/music_search_permission_test.dart test/music_queue_controls_test.dart test/music_search_results_lazy_test.dart test/connection_experience_test.dart`，20 项全部通过。测试均使用内存 PreviewRuntime/stub，没有登录真实音乐账号或调用外部服务。
- 现有覆盖：账号面板打开、退出确认的取消/执行、二维码登录取消/完成和切换账号；MiniPlayer 的控件布局、溢出操作区、桌面停止/刷新入口，以及 macOS Widget 变体里玻璃播放按钮从暂停图案变为继续播放图案并保留同一元素；搜索授权取消/允许、音乐控件执行授权、搜索结果播放和加入队列。这些断言验证 Widget 行为与语义，不代表原生 Profile 画面的光效/动效通过。
- 未覆盖：账号面板关闭与刷新状态按钮没有对应断言；MiniPlayer 控制授权取消、音乐搜索结果里的权限播放确认、MiniPlayer busy 状态也没有由上述用例覆盖。B060–B079 矩阵已只在对应调用点标记 Widget 测试范围；账号面板、非预览歌曲播放授权和原生静置/点击动画仍待验收。
- 原生画面限制：重新启动 Profile 时 `flutter run` 报告 `Failed to foreground app; open returned 1`。改用 Profile `.app` 完整路径打开后，窗口列表显示 800×632，但 AX 将内容控件全部标为 `offscreen`；截图 API 只返回 170×140 logical 的小预览图，不能用于页面或按钮外观验收，该临时截图已删除。按应用名尝试激活时系统另启动 Debug 构建并返回 `APP_UNRESPONSIVE`；该临时实例已结束。没有对这些画面执行交互，也没有关闭 Charles、GW 或其他用户应用。
- 收尾：Profile 与本轮 Debug 临时实例均已退出；应用清单没有 Aggregate，关联进程查询也没有 Profile/Debug runner 残留。未修改产品代码或测试代码，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 设置、Host 与主题切换 Widget 回归

- 回归结果：`flutter test --no-pub --reporter compact test/mac_host_settings_panel_test.dart test/widget_test.dart test/glass_theme_switch_test.dart` 28 项全部通过。设置页和主题测试使用 PreviewRuntime/手动动画时钟，Mac Host 面板测试使用 `_FakeHostControl`、`_FakePairingControl` 与 `_FakeIdentityRotation`；没有启动真实 Host、网络监听或设备配对。
- 主题逻辑：`glass_theme_switch_test.dart` 覆盖 450 ms 实时拖动只在释放后提交、指针取消恢复端点、隐藏应用时取消拖动和减少动态效果；`widget_test.dart` 覆盖设置页主题偏好写入 PreviewRuntime。这些是 Widget/模型回归，保持现有拖动和提交契约，不代表原生 Profile 帧或 display-present 验收。B080 矩阵已补充测试范围。
- Mac Host 行为：fake 端回归覆盖启动 Host、生成邀请二维码、批准向导权限、自定义及逐连接权限、修改/保存权限、撤销设备，以及身份轮换确认取消与执行。B085–B090、B095–B098、B100–B101 只标注用例实际触达的行为。本批测试未覆盖直接停止按钮、复制配对信息、刷新配对列表和拒绝请求；B094 批准只读与 B099 权限弹窗取消仍依据原有暗色实窗记录，本批没有复测。原有暗色截图不因 Widget 测试升级为原生动态验收。
- 设置清理操作：`widget_test.dart` 覆盖设置布局和外观偏好，没有触发或验证“清空记录”确认，因此 B081–B083 状态未提升。
- 范围：只更新验收文档，未修改产品代码或测试；没有启动桌面应用，用户应用未受影响。UI-6.7 仍部分验收，尚有原生浅色画面、逐按钮光效/动效和未覆盖 Host 操作待核。

### 2026-11-18 UI-6.7 主题开关材质基线按钮光效迭代

- 验收标准更新：用户指出普通按钮应达到“切换明暗模式”控件的材质与光效层次。当前目标是在不改太阳/月亮切换行为的前提下，让共享操作按钮也有玻璃体积、缓慢流动的暖光和协调的按下反馈；此前只要求按钮统一点阵风格的标准继续保留。
- 实现：`GlassActionButton` 表面加入与浅色主题开关相同的太阳暖金色、高光缓慢移动、柔化边缘发光和按下内陷/增亮。按钮表面动画复用现有 `GlassMotionScope`，静置表面以约 15 Hz 刷新，交互过渡最多约 30 Hz；关闭动态效果时停用。导航/分段按钮仍保留轻量选中材质。`glass_theme_switch.dart` 的指针映射、动画模拟和 `onChanged` 行为未改。
- 组件画面：[设置页材质对照截图](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/final-settings-capture.png>)，SHA-256 `acb3db14c555e1ee3838648a8a8c807d3264968b0ec64c873ddbc9afdb64f923`。该图来自临时 Flutter Widget 采样，1024×766、DPR 1；测试字体回退，因此只用于比较开关与按钮表面，不用作文字或布局验收。
- 验证：`flutter test --no-pub --reporter compact` 全部 316 项通过；`flutter analyze --no-pub` 无问题；`flutter build macos --profile --no-pub` 成功。Profile 实际运行约 40 秒后 `ps` 的进程 CPU 样本为 14.9%；这是进程占用观察，不是 FrameTiming/显示 FPS 基准。
- 原生限制与范围：本轮 Profile 窗口未暴露可用的 Accessibility 树，`agent-desktop` 无法取得可靠窗口图；Flutter Skia 截图接口因 Impeller 不支持而失败，macOS 原生设备截图接口也不支持。故未将 Widget 图升级为原生实窗签收。UI-6.7 继续部分验收；普通按钮的实窗静置/按下画面对照、所有生产实例布局和其他未完成矩阵行仍开放。

### 2026-11-18 UI-6.7 按主题开关材质基线重做按钮光场

- 验收标准纠正：用户指出上一轮只是给按钮加暖色光，主体质感仍不像明暗切换滑块。当前要求改为共享滑块的玻璃面、双层倒角、右上角暖光发射点、面内反射和按下内陷；保持按钮业务回调及主题开关拖动/点击逻辑不变。
- 实现：所有操作按钮共享同一层叠玻璃面和上右暖光弧，静置光点固定在主题开关光带所在角落并缓慢呼吸，交互时增亮和扩展弧段；独特点阵动画继续由原 glyph 动作描述驱动。浅色暖光取自主题开关太阳色 `0xFFFFA82E`，深色保留月光蓝。导航/分段仍使用较低亮度。面内危险文字提高了计算对比余量以抵消高光区域影响。
- 动画预算：按钮表面静置更新约 10 Hz，交互过渡最多 30 Hz；减弱动态效果时停止表面动画。按钮表面使用固定上右弧路径，不逐帧计算路径采样，也不增加每按钮的独立 ticker。
- 对照画面：[主题开关与三类操作按钮同屏 Widget 对照](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/revised-switch-buttons-final.png>)，SHA-256 `9c2a8b6c778b9038f680bfb5ca2d872c83169ec0cb07db64441f099a6b7111f6`。画面由 `ThemeSwitchArtwork` 的片元着色器与普通按钮在同一个 Flutter Widget 测试窗口采样，1024×480、DPR 1；测试字体回退，只作材质/光场相对位置比较，不作文案、产品布局或原生实窗验收。
- 验证：最终版本 `flutter analyze --no-pub` 无问题；`flutter test --no-pub --reporter json` 全量 377 项通过，`git diff --check` 通过。`flutter run --profile -d macos --no-pub -t lib/glass_buttons_fixture_main.dart` 可构建 Profile 64.5 MB 包，但系统返回 `Failed to foreground app; open returned 1`；5 秒进程采样处于 AppKit 等待状态，后续空闲 CPU 样本为 0%，均未获得有效的前台动画帧率或帧时间证据。
- 原生限制与范围：当前 Widget 对照比上一版更直接，但不替代前台 Profile 实窗目视。未声称与主题开关着色器达到像素级同材质或帧级签收；UI-6.7 继续部分验收，普通按钮原生静置/按压画面、生产调用点布局和其他未完成矩阵行仍开放。

### 2026-11-18 UI-6.7 暗色月光方位 Profile 对照

- 实窗对照：使用明确的 `Profile/Aggregate.app` 路径运行 `glass_buttons_fixture_main.dart`，避开 Launch Services 按 bundle ID 选中 Debug 包的问题。Profile 画面显示主题开关与 12 类按钮样例；逐项对照发现暗色主题开关的月光弧在左下，而操作按钮仍将蓝色发光固定在右上。
- 修正：按钮表面暗色渐变轻微向页面底色/内凹色收敛；月光柔光中心和弧形发射边移动到左下，随主题呼吸；浅色太阳仍用右上发射边。只改 `GlassActionButton` 绘制，不改 `GlassThemeSwitch` 的拖动、点击、提交时机或回调。尝试把常态表面改为 93% 透明时，动态对比回归在日夜过渡 0.36 低到 4.44:1，已撤回该透明度改动。
- Profile 图：[开关与 12 类点阵样例](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-lunar-aligned.png>)，SHA-256 `2c560bcba12a9378208fbb5ba665cbc092b75e2b6a04723254ca95462e121fb5`；[动作与状态样例](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-action-samples.png>)，SHA-256 `27e2dd2c6f94c1d1c29e4e6bae189ebc141a461044af142cbc133b15821f6ccc`。均为原生 Profile fixture 窗口截图，不是生产设置页全调用点签收。
- 验证：`flutter build macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart` 成功，包 62.9 MB；`flutter analyze --no-pub` 无问题；按钮、动画时钟、动态对比及主题开关定向回归 34 项通过；Dart 格式检查与 `git diff --check` 通过。
- 动态边界：截图足以核对静态材质与月光方位；窗口在连续帧抽样期间失去可枚举 surface，未用该组结果计算空闲 FPS 或帧时间，也未验证按住时画面。profile fixture 正常退出。UI-6.7 仍部分验收，生产按钮逐调用点、按下瞬间及前台帧时证据继续开放。

### 2026-11-18 UI-6.7 双主题玻璃按钮高光收敛

- 原生 Profile 同屏对照显示，按钮在月亮态仍有偏亮的整圈银边和宽光带，面色也浅于主题开关。`glass_action_button.dart` 现将暗色面层向 surface/inset 加深，强度按主题进度非线性淡入；降低暗色面内反射与周边高亮，并按按钮高度缩放弧形发射宽度，收细柔光、核心线和白色高光。浅色边缘反射随主题进度保留太阳暖光。仅修改共享按钮绘制；`GlassThemeSwitch` 着色器、拖动映射、点击和释放提交逻辑、按钮回调均未改。
- 同一 Profile fixture 中分别记录深色月亮与浅色太阳样例：深色图 [`native-profile-lens-final.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-lens-final.png>)，SHA-256 `f4984e88fa3bfe6b9c572260a30616becde10c252c606df146271fd20f7e83ce`；浅色图 [`native-profile-lens-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-lens-light.png>)，SHA-256 `e6f5bd15ff7c12cba0b886ee215736769ab3cf2e5708f58d6b90d59d4f4a664a`。浅色使用语义开关切换，操作前后 AX 分别读回“深色”“浅色”；两图均为 800×632pt macOS Profile fixture，不是生产页面逐调用点签收。
- 一次过渡端点压暗尝试在主题进度 0.36 的文字样本降到 4.44:1；改为高次非线性暗色权重后，最终定向对比测试恢复通过。最终 `flutter test --no-pub --reporter compact test/glass_action_button_test.dart test/glass_motion_test.dart test/macos_dynamic_backdrop_text_contrast_test.dart test/glass_theme_switch_test.dart` 34 项通过；`flutter analyze --no-pub` 无问题；Dart 格式检查、`git diff --check` 通过；macOS Profile fixture 构建成功（62.9 MB）。
- 结论仍为部分验收：静态两主题图显示按钮表面和局部光带更接近主题开关，但按钮仍由独立 Dart `CustomPainter` 绘制，没有复用开关片元着色器，故不记为同一渲染材质或像素级对齐。原生按压帧、FrameTiming/FPS、生产调用点全量布局仍未验收。Profile 窗口已关闭，应用清单确认无 Aggregate app 残留。
- retrieval_feedback：采用本记录上一节与当前任务笔记对“主题切换交互冻结、Widget 不替代原生静态证据、未测状态不签收”的边界；以 `glass_theme_switch.dart` 与 `glass_theme_switch.frag` 对照当前按钮 `CustomPainter`，据此只收敛按钮光场，不触碰开关模拟器。仅检索本项目源码和当前任务笔记，未查其他项目或 web。

### 2026-11-18 UI-6.7 按钮与主题开关共用玻璃光学 shader

- 实现：将运行时 shader 程序加载移至平台无关的 `GlassOpticRenderer`。操作按钮现在调用与主题开关相同的 fragment shader 资源，并复用同一套距离场、法线折射、边缘照明、发射弧与颗粒光学函数；按钮独有的圆角尺寸、状态、强调色和面色通过独立 uniform 分支传入。按钮点阵图案仍由原 glyph painter 绘制在玻璃面上，所以它们没有被采样纹理做逐像素折射。
- 主题切换保护：`GlassThemeSwitch` 的手势映射、模拟器、拖拽/点击判定、释放提交与回调未改。主题开关继续走 shader 原路径（显式 `renderMode=0`）；Profile 实窗由 AX 点击从“深色”切到“浅色”，读回“浅色”且两主题画面正常。
- 原生 Profile 截图：[深色共享 shader](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-shared-shader-dark.png>)，SHA-256 `8a6959d15e7dc985acf2bf58009ba38f4370883e62100fbbb9ea552859c8714e`；[浅色共享 shader](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-shared-shader-light.png>)，SHA-256 `167129cb1bea41ad13d6d9950cef633b316432f3eba7d1aa2d259f2e2c53ef23`。窗口截图为 1692×1356 像素、DPR 2；仅覆盖 fixture 静置态，不代表生产调用点逐项复核或按压过程验收。
- 验证：`glass_action_button_test.dart`、`glass_motion_test.dart`、`glass_theme_switch_test.dart`、主题模拟/实时/光学与动态文字对比测试共 45 项通过；`flutter analyze --no-pub` 无问题；`flutter build macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart` 成功；`dart format` 与 `git diff --check` 通过。
- 限制：未采集按住帧、FrameTiming/FPS 或多实例原生性能数据；静态截图中太阳暖光在大尺寸样例上的扩散仍比主题开关集中。当前只证明按钮与开关共用 shader 资源及光学方程，尚未签收 1:1 同外观。UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 运行、刷新、搜索点阵图案精修

- 用户指出运行、刷新、搜索三个大尺寸 glyph 显得碎且生硬。调整运行三角形的视觉重心；重画刷新环的对向箭头；加粗搜索柄与镜片的连接。统一点单元从 1.9 调至 2.15，圆角半径从 0.64 调至 1.075，增大柔边与轻晕，并给点阵核心增加很浅的斜向明暗。点阵栅格及按钮业务回调保持不变。
- 为保持按钮不同尺寸下光带比例与主题开关一致，操作按钮 shader 坐标按 198 单位的参考直径归一化；深色月光留在左下，浅色太阳光留在右上。主题开关仍使用原始 shader 分支与完整状态机。
- macOS Profile 静置截图：[三图标深色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-tall-dark.png>)，SHA-256 `72cc815bca09e9d3a3f6ef449ea3c782c53fe082dbd96c30279157b7232677b2`；[三图标浅色](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-tall-light.png>)，SHA-256 `331d87f5d092feb88af194c88e91be88104436fb98d89a71cabbb1f957dd5d96`。PNG 为 1784×1684、DPR 2 的 fixture 实窗；语义开关从“深色”切到“浅色”，AX 读回浅色。截图覆盖运行、刷新、搜索，其他按钮只作材质旁证。
- 验证：更新后的 `glass_glyph_golden_test.dart` 1×/2×、浅/深四组 golden 通过；按钮、glyph、motion、theme switch、主题模拟/实时/光学与动态文字对比共 49 项通过；`flutter analyze --no-pub` 无问题；macOS Profile fixture 成功构建；Dart 格式检查与 `git diff --check` 通过。
- 未验收：glyph 点阵仍由 Flutter painter 画在 shader 玻璃面上，没有进入同一纹理做逐点折射；没有记录按住动画帧、FrameTiming/FPS 或所有生产页面调用点。本轮改善形状和点单元质感，不代表用户已签收 1:1。UI-6.7 继续部分验收。

### 2026-11-18 UI-6.7 运行、刷新、搜索轮廓二次重绘

- 用户再次指出这三个大图标最突兀。本次更新前一条记录中的轮廓选择：播放三角改用更宽、重心居中的实心点阵；刷新改为单条近圆回转弧加明确箭头头部，替换先前容易读成加载环的双弧方案；搜索镜片闭合为圆环，手柄从右下切点连续接出，替换先前开口过大的镜片。三者仍使用同一圆润点单元、光晕与缓存绘制流程，其他 glyph、按钮业务回调和太阳/月亮交互逻辑未改。
- 新轮廓控制在 glyph 画布既有 `4..25.6` 点中心范围内，点序直接供原有 `GlassMotionController` 使用。新增 32 dp、DPR 2 的浅/深视觉 golden：[`浅色`](../../app/test/goldens/glass_primary_glyphs_light.png)、[`深色`](../../app/test/goldens/glass_primary_glyphs_dark.png)；同时更新 1×/2× 的全字典 golden。聚焦图只展示点阵与主题底色，不模拟按钮玻璃 shader。
- 一次初始重绘将点中心放到既有画布范围之外，`glass_action_button_test.dart` 的点阵坐标约束检出；将三种几何收回原范围后，glyph 映射、坐标、按钮、动画、主题切换、模拟/实时/光学和文字对比定向套件共 51 项通过。`flutter analyze --no-pub` 无问题；macOS Profile fixture 构建成功（62.9 MB）。构建输出包含依赖 `mobile_scanner` 的既有 macOS API 弃用警告。
- 当前证据为静态点阵预览、Widget 动画/业务回归和 Profile 构建；没有重新采集玻璃按钮实窗按压帧、FrameTiming/FPS 或所有生产调用点。此轮只完成三个轮廓修订，UI-6.7 仍部分验收。

### 2026-11-18 UI-6.7 三枚主图标玻璃实窗静态复核

- 重新打开隔离的 macOS Profile `glass_buttons_fixture_main.dart`，在 96 dp 玻璃控件中同屏核对运行、刷新、搜索。深色截图 [`dark`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-redrawn-dark-complete.png>)，SHA-256 `3effdeb02f2d5cc846b3c9f72f97cb4912870ee82e895379fdeaefd7401db430`；浅色截图 [`light`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-redrawn-light.png>)，SHA-256 `c64022c1f2e67cafbe5d75077161b4be50f696ae9097b6263f6321dbcd1005da`。两张均为 1692×1356 截图、DPR 2。
- AX 读取主题状态由“深色”变为“浅色”；仅操作隔离夹具中的主题演示，不调用产品动作。实窗确认播放三角与圆点光晕清晰，搜索柄接点连续，刷新弧的箭头尖端在浅深背景均可见。Profile 进程已正常退出，`agent-desktop list-apps --app Aggregate` 返回空列表。
- 尝试用原生指针拖动留取运行按钮按压帧，但操作返回 `delivered_unverified`，截图不能证明帧处于按下状态，因此不作为按压态验收证据。按压帧、FrameTiming/FPS、生产调用点全覆盖仍待补；本节只签收浅深静态实窗轮廓，UI-6.7 继续部分验收。

### 2026-11-18 UI-6.8 用户指定网页参考源复核

- 原视频已删除后，用户指定 [Glass Light Toggle](https://experiments.thisiswhitespace.com/glass-light-toggle) 作为可访问参考。页面加载的 `main.js?v=3` SHA-256 为 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`，与仓库独立模型 oracle 记录的 source SHA 完全相同；不是仅凭相似外观推定代码来源。
- 按照公开源码复核了轨道/滑块/17×17 点阵常量、太阳与月亮按角度配对、每点错峰/旋绕/弹簧、实时拖动输入、逐刷新时间上限，以及玻璃折射、色散、霜化、边缘灯带与背景散射。当前 Dart 模拟和 `glass_theme_switch.frag` 已有这些对应机制。现有 oracle 用固定种子与中途反向事件验证来源算法；当前拟合参数仍单独配置，没有用截图覆盖或重置。
- 网页 Chromium/SwiftShader 1440×757 的暗态、拖动 25%/50%/75% 和亮态采样：[`制作说明/暗态`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-reference-how-made.png>)（SHA `3a9feb4fe7e4e2f63c7f43676d928a9098e2118ef2f343d48f845b3f815ec85d`）、[`25%`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-reference-drag-25.png>)（SHA `5f1cf93e4d8cdab8775c8021eba92452137d45d8bb47ced5951992dd1f1bc5e4`）、[`50%`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-reference-drag-50.png>)（SHA `9b399cd9850a07ecfc22ab7838a53819114cc9f13e4652eec39342703673435d`）、[`75%`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-reference-drag-75.png>)（SHA `5c5f5fc09ce5685e59bcd9af31cb4ca06a71e1663f9a4ff76e0a15387cd37ed9`）、[`亮态`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-reference-light.png>)（SHA `4e7aadf4b3830c10a9f7f8cec17797e2cd141454520c1f9d6fec2ba2c2e36be4`）。它们用于机制/端点观感对照，不是本机 Flutter 或 macOS 实窗画面。
- 验证：`flutter test --no-pub --reporter compact test/theme_switch_calibration_test.dart test/theme_switch_realtime_test.dart test/theme_switch_simulation_test.dart test/theme_switch_optics_test.dart test/glass_theme_switch_test.dart` 共 26 项通过；`flutter analyze --no-pub` 无问题。既有 macOS Profile 设置页浅/深端点截图也已与网页端点目视对照。没有修改主题逻辑、运行参数或其他工作区中的 Android 改动。
- 限制：网页随机种子未知且每次重载会变；本轮没有采集 Flutter 与网页同步输入的原生连续录屏，也没有物理 display-present 时间戳。原视频轨迹的 `42–60 ms` 历史偏移估计并未被网页静态样本替代或消除；无法据此宣称原视频逐帧 1:1，UI-6.8 仍部分验收。

### 2026-11-18 UI-6.8 网页参考当前部署复核

- 再次读取用户指定的 [Glass Light Toggle 页面](https://experiments.thisiswhitespace.com/glass-light-toggle)。当前页面返回 Next.js 部署 `dpl_HTAd9EyjDwpmH9jaAFGH52jqjsbf`，页面标题与说明仍描述玻璃明暗开关及月亮到太阳的点阵变化。
- 当前 HTML 未加载此前记录的 `main.js?v=3`；直接请求 `/glass-light-toggle/main.js?v=3` 与 `/main.js?v=3` 均返回 404。因此 `7f7b5d15…` 是此前部署快照的源码摘要，不作为当前线上部署源码已核实的证据。此次只核实页面元数据和加载入口，没有从新部署取得可比的开关实现，也没有采集新部署的连续动作画面。
- 处理：保留既有源码快照、独立 oracle 和静态截图作为此前参考版本的证据；不据此推断当前线上实现完全相同，不改产品参数或主题切换逻辑。UI-6.8 仍部分验收，当前部署的实时动作对照和 Flutter/macOS 同步连续捕获仍待完成。

### 2026-11-18 UI-6.8 当前实验 iframe 源码确认

- 继续追踪当前 Next.js 路由包中的实验入口后，确认 `glass-light-toggle` 页面通过 iframe 加载 `/standalone/glass-light-toggle/index.html`。该 iframe HTML 返回 200，含一个 canvas，并加载 `/standalone/glass-light-toggle/main.js?v=3`；本轮取得脚本 26,498 字节，SHA-256 为 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`，与此前记录和独立 source oracle 一致。
- 更正：上一节测试的 `/glass-light-toggle/main.js?v=3` 与 `/main.js?v=3` 是错误猜测的路径，404 不代表 iframe 中的实现不可用。当前在线实验脚本与此前快照相同，既有源码对照可用于当前实验实现。
- 边界：脚本身份相同不等于新 Next.js 外层布局、实际 macOS/Flutter 动画相位或 display-present 已逐帧对齐。本轮没有同步录制当前 iframe 与 Aggregate；UI-6.8 继续部分验收，不调整产品模拟或主题切换逻辑。

### 2026-11-18 UI-6.7 三枚图案点击态原生复验

- 以隔离的 macOS Profile 夹具重建并打开 96 dp 图案样本。AX 树列出“运行”“刷新”“搜索”等按钮；刷新语义 `AXPress` 返回 `delivered_unverified`，无法从延迟静帧确认瞬时状态，因此没有重试。随后基于已验证前台的独立夹具窗口尝试运行按钮的物理坐标点击并录制该窗口 4 秒；事件也返回 `delivered_unverified`，采样帧未出现可归因于运行按钮的清晰点击态，指针位置与预期无障碍框不一致，不能据此签收。
- 刷新按钮的 headed 元素点击另因命中测试判断按钮被滚动区域遮挡而返回 `not_delivered`；未对该次动作重试。没有尝试搜索按钮，也没有证据证明这三枚图案的原生点击态已逐帧通过。
- 夹具由 `agent-desktop close-app` 正常退出并确认进程结束；未触发任何业务回调或外部服务。没有产品代码改动，UI-6.7 保持部分验收；当前提交只更正图案静态形状，动效模型单元测试通过不等于原生按压视觉通过。

### 2026-11-18 UI-6.7 依据目标图重绘运行、刷新和搜索

- 用户提供 96 dp 图案参考图，并指定 [Glass Light Toggle](https://experiments.thisiswhitespace.com/glass-light-toggle) 作为缺失视频的材质/光效参考。以附件的三个图案为轮廓依据，按 9×9 单元重新映射：运行是窄高右指三角，刷新是右侧带箭头缺口的环，搜索是闭合镜片加右下两点斜柄。共享圆点、玻璃绘制、动效 profile、按钮尺寸/命中区和回调均保持原样；没有触碰主题开关状态机。
- macOS Profile 原生夹具浅色和深色静态截图：[`浅色`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-grid-ref-light.png>)，SHA-256 `a5149f47bb5fdb8bad6e1b61eba12c3299aea5a753aa7184f929a42da1b1b34d`；[`深色`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-three-glyphs-grid-ref-dark.png>)，SHA-256 `da2d8dcaf9cfef9e624baf69e7fb3e4c9e2286bc0d93134d3eff4db43058622b`。两张均为 1824×1488、DPR 2；实窗中同屏看到 96 dp 按钮及运行、刷新、搜索图案。主题状态由 AX 从深色读回浅色；夹具进程随后正常退出。
- `glass_action_button_test.dart` 的 9×9 网格、三图案点位和单元数量断言通过；浅/深三图案 golden 与全字典 golden 已更新。`glass_glyph_golden_test.dart`、`glass_action_button_test.dart`、`glass_motion_test.dart`、`glass_theme_switch_test.dart` 共 38 项通过，`flutter analyze --no-pub` 无问题，macOS Profile 夹具构建成功（62.9 MB）。构建只有 `mobile_scanner` 依赖的既有弃用警告。
- 限制：本次签收静置轮廓及玻璃实窗浅深外观，不代表三个原生按下瞬间已逐帧采集；先前点击态复验仍为未验证。UI-6.7 继续部分验收。

### 2026-11-18 UI-6.8 当前网页与原生拟合组件实时拖动复核

- 网页端：在用户指定页面的真实实验 iframe `/standalone/glass-light-toggle/index.html` 中，通过 Chromium CDP 派发鼠标按下、连续移动与释放，分别实际完成深→浅和浅→深拖动；以实时拖动中多个时点截图核对月亮/太阳点阵内部变化、滑块移动和边缘光，不是固定帧序列播放。浏览器环境为 1440×757、DPR 1、Chromium/SwiftShader。暗态、正向 50%、反向 50% 和浅态窗口截图分别为 [`dark`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-live-cdp-dark-start.png>)（SHA `3d33341e36a7ef0f8e062eaae9e326c7a7508e1df94d9dad258eb1a9ca8bd316`）、[`forward 50%`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-live-cdp-drag-50.png>)（SHA `bdb6fe7b45b3676619f8324f33f92daa473adc211785612424af7b129fe7a32d`）、[`reverse 50%`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-live-cdp-reverse-50.png>)（SHA `c5e72dc1469da2e11712ac71b66440c99bd60dca64d92d852609ceaa758a4dda`）和 [`light`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/glass-light-toggle-live-cdp-light-end.png>)（SHA `4d8f8c124ee3b899c0576584b2cf47f2b3a5c1bf35d912bb0de6c1c8bf4619e7`)。
- macOS 端：使用隔离 Profile fixture，将生产 `GlassThemeSwitch` 按生产的 `videoFittedThemeSwitch` 校准参数放入 `GlassScene` 和 `GlassMotionScope`，在 320×240 logical 控件样本上用 headed 鼠标分别真实拖动 3 秒正向与反向；每次手势期间按五个时点捕获应用窗口，AX 在终点读回浅色/深色。暗态及两向中段窗口裁图分别为 [`dark`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-fitted-switch-dark.png>)（SHA `639d8b7c20a0f0fc8c12b32be7a11981b8f8ea83b6c31d8c45377d71a3a7eb09`）、[`forward sample`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-fitted-forward-2-switch-crop.png>)（SHA `88a432cb45408025bcdc01266474a51d3a550c923c1ae877fb0d2cbf6f04f963`）和 [`reverse sample`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/native-profile-fitted-reverse-2-switch-crop.png>)（SHA `b84d2fd4b29ff9e47dc2d10f06efa7da27285fdf5e7884434dcceecbd657c162`）。截图可见两向拖动时内部粒子、太阳/月亮形态与边缘光持续变化。夹具随后正常退出；没有改产品代码、切换参数或状态逻辑。
- 验收边界：网页与 macOS 分别执行实时输入，并未共享输入时钟、帧时间戳或随机粒子种子；两侧分别使用 Chromium/SwiftShader 与 Flutter/macOS renderer，截图也不是物理 display-present 记录。因此本次只证明网页参考和原生拟合组件都响应任意方向的真实拖动，并提供内部粒子及光效变化的动态采样证据；它不证明网页与应用逐帧同步，也不消除原视频轨迹先前测得的约 `42–60 ms` 相位差。UI-6.8 仍部分验收，不能据此宣称 1:1 逐帧还原。

### 2026-11-18 UI-6.8 长间隔恢复遵循网页单帧上限

- 来源：用户指定的[当前实验页面](https://experiments.thisiswhitespace.com/glass-light-toggle)加载官方 [`main.js?v=3`](https://experiments.thisiswhitespace.com/standalone/glass-light-toggle/main.js?v=3)，本地取得脚本 SHA-256 为 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`。网页在每个 `requestAnimationFrame` 以 `min(1/30, delta)` 积分一次，并以 `performance.now()` 驱动绝对时钟；没有因暂停超过两秒而把未完成的滑块/粒子动画吸附至终点。
- 修正：删除 `ThemeSwitchSimulation.advanceRealtime` 超过两秒时对未拖动模型调用 `snapTo` 的额外分支。恢复后首帧只走一次 1/30 秒上限，接下来的帧从此前位置继续；没有固定帧序列，也没有改变指针拖动、释放投影、端点提交、取消或主题偏好逻辑。
- 验证：`dart format` 检查 `theme_switch_simulation.dart` 和 `theme_switch_realtime_test.dart`，无格式改动。于 `app/` 执行 `flutter test --no-pub --reporter compact test/theme_switch_realtime_test.dart test/theme_switch_simulation_test.dart test/theme_switch_calibration_test.dart`，15 项全部通过；新增回归确认 8 秒间隔与一次 1/30 秒更新完全一致，并从保留的中间状态继续运动。
- 范围：这是长间隔积分策略与线上模型的一致性修正，不验证网页和 macOS 的同步逐帧相位、随机粒子对应或 display-present 时间；UI-6.8 的动态相位及整体 1:1 签收仍未完成。

### 2026-11-18 UI-6.8 官方脚本 113 组粒子初始化参数对照

- 来源：以当前参考页实际加载的官方 [`main.js?v=3`](https://experiments.thisiswhitespace.com/standalone/glass-light-toggle/main.js?v=3) 为源，SHA-256 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`。在独立 Node VM 中使用 fixture 记录的 LCG 种子 `1831565813` 替换 `Math.random`，从网页源码执行月亮/太阳配对和 `PIX` 初始化，导出 113 行、每行 7 个参数。
- 验证：扩充 `theme_switch_model.json` 的独立 oracle；`theme_switch_simulation_test.dart` 逐项将 Dart 生成的 delay、curl、lift、stiffness、drag、phase、twinkle 与官方脚本的 791 个值按 `1e-12` 容差比较，随后继续检查 151 个 60 Hz 时间步中的轨迹样本。与 `theme_switch_realtime_test.dart` 联合定向运行共 10 项通过，Dart 格式检查和 `git diff --check` 通过。
- 范围：这验证选定 LCG 种子下 113 组粒子的初始化算法和模型轨迹，不等同于线上随机种子已找回，也不证明使用录屏拟合系数的生产控件与网页当前随机会话同步逐帧；粒子随机对应、时钟同步和 macOS display-present 仍未通过。

### 2026-11-18 UI-6.8 官方脚本 113 组粒子动态状态回归扩展

- 对照：在上一项相同源码 SHA `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`、LCG 种子 `1831565813` 和事件序列下，再次直接执行官方 JavaScript；先核对已存四颗代表粒子与滑块、主题、光带、光强等标量，导出值全部一致后才更新 fixture。
- 覆盖：将官方动态样本扩展到第 0、60、70、90、110、150 帧的全部 113 颗粒子，每个粒子比较 x/y/size/alpha，共 678 个粒子状态与 2712 个数值；模拟仍按事件推进完整 151 个 60 Hz 步，不使用帧序列驱动产品。
- 验证：`flutter test --no-pub --reporter compact test/theme_switch_simulation_test.dart test/theme_switch_realtime_test.dart` 共 10 项通过；`flutter analyze --no-pub` 无问题，`git diff --check` 通过。主题切换产品代码及拟合参数没有修改。
- 边界：这补齐选定随机种子下六个检查点的内部粒子动态模型对照，不覆盖全部 151 帧、未知录屏随机种子或 macOS 实际展示时刻；网页与产品仍没有共享时钟/随机种子，逐帧 1:1 仍未签收。

### 2026-11-18 UI-6.8 官方脚本全 151 帧粒子轨迹对照

- 来源与数据：继续使用当前官方脚本 SHA-256 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`、固定 LCG 种子 `1831565813` 和相同的 hover/主题反向事件。由官方 JS 逐帧采集 0–150 帧的全部 113 颗粒子，每粒子记录相对坐标、尺寸及 alpha（共 17,063 个状态、68,252 个字段），以 gzip JSON 基线保存于 `app/test/fixtures/theme_switch_particle_trajectories.json.gz`，SHA-256 `fe107b7ef7e72e8e1ca49043c4c51e1ea173de00dc098ce6aed810746b2f00f2`。
- 验证：模拟按同一 60 Hz 事件序列完整运行 151 步，每一步将 Dart 端全部 113 颗粒子的 x/y/size/alpha 与源基线逐项比较，容差 `1e-9`；同时校验压缩基线 SHA。`flutter test --no-pub --reporter compact test/theme_switch_simulation_test.dart` 全部 5 项通过。原有六个关键帧标量和可读粒子快照仍保留。
- 范围：这是固定随机种子下、官方脚本与 Dart 模型在 60 Hz 上的完整粒子轨迹算法回归；没有复原录屏所用随机种子，也没有同步线上网页与 macOS 的时钟、输入、渲染器或实际显示呈现时间。因此不能声称录屏逐帧 1:1；UI-6.8 仍部分验收。

### 2026-11-18 UI-6.8 官方 WebGL 与 Flutter shader 同状态图像对照

- 来源：重新从当前官方 [`main.js?v=3`](https://experiments.thisiswhitespace.com/standalone/glass-light-toggle/main.js?v=3) 下载并核对 SHA-256 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`。离线工具 `app/tool/capture_theme_switch_source_frames.cjs` 在独立 Chrome headless + ANGLE SwiftShader 进程中按 oracle 的 LCG seed、事件序列和 720×540 / DPR 1 / scale 0.76 / center (360,267) 捕获第 0–150 帧。六个源码模型检查点的九个标量逐项比对；全部 151 帧 × 113 颗粒子都与 SHA-256 已校验的完整轨迹基线按 x/y/size/alpha 对照，容差 `1e-9`；通过后才落盘。
- 对照：`flutter test --no-pub tool/theme_switch_reference_frames_test.dart` 用相同 151 组状态绘制 Flutter fragment shader；随后通过 `compare_theme_switch_frames.py` 对全部 151 对原始 720×540 图像直接比较，不注册、不校色、不遮罩。覆盖完整 0–2.5 秒、60 Hz 采样序列；平均 RGB MAE 为 `0.0631750/255`，最大单帧 MAE 为 `0.0747111/255`（第 51 帧）；每帧完全相同像素占 `98.73%–99.42%`。差异主要集中于点阵边缘的跨渲染器采样。
- 证据：[六个代表帧并排与差分图](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/contact-sheet.png>) SHA-256 `ffd97ab6f3d8c695779655aabfc06115fcb25680c21a1ab6c4ea8031836cfdbd`；[全 151 帧比较浏览页](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/comparison/index.html>)；[metrics.json](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/comparison/metrics.json>) SHA-256 `bd56a45241e02154fd581297bc15bcdfe63a54f3fbe9ccdcc99836bb67deef38`；[官方源 manifest](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/source/source-manifest.json>) SHA-256 `08e1b4f9e01dc023c892f463f4f718da2d08b519c9004a4d42d97f1789f22527`。
- 边界：这些图像来自 Chrome SwiftShader 与 Flutter widget-test shader renderer 的同状态静态输出，不是 Aggregate macOS Profile 实窗、Metal/Impeller 或物理 display-present 捕获。完整帧序列和很低的图像 MAE 仍不能证明未知录屏随机种子、录屏输入，或网页与产品的实时动画时钟已经同步；UI-6.8 仍部分验收。

### 2026-11-18 UI-6.8 macOS Profile / Impeller 全 151 帧同状态图像对照

- 方法：新增隔离入口 `app/lib/preview/theme_switch_native_capture_main.dart`，直接调用生产 `ThemeSwitchArtwork`，不初始化或修改主题切换业务状态机。Flutter 3.47.8 / Dart 3.13.7、macOS 27.2.1 下构建 Profile 62.4 MB；运行日志确认 Impeller `MetalSDF`。入口从同一已校验源模型读入全部 151 组状态，在 Profile 引擎内以 720×540、DPR 1、scale 0.76、center (360,267) 通过 `RenderRepaintBoundary.toImage` 导出 PNG。
- 结果：将全部 Profile 图像与同状态官方 WebGL 源图未配准、未校色、无遮罩对比。151 帧平均 RGB MAE `0.3868485/255`，最大单帧 `0.4163683/255`（第 136 帧）；完全相同像素占 `38.64%–48.07%`。差异图目视表现为点阵边缘和细光带的跨渲染器采样值变化，没有看到整体位置偏移或太阳/月亮状态不一致。
- 证据：[Profile 比较浏览页](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/comparison-profile-engine/index.html>)；[metrics.json](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/comparison-profile-engine/metrics.json>) SHA-256 `e0fa284249e762227bf589f779ccfe3ede79b6de5f8483000d56a9f6fe61b26a`；[第 136 帧 Profile 输出](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/native-profile/profile-render-136.png>) SHA-256 `137abca36805564665e0575cfe107d7c0340e6eec7ae2dc690954848d74619cc`；[第 136 帧差分图](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/comparison-profile-engine/difference/frame_0136.png>) SHA-256 `22ff413561c665da4fc94cc40a08768e28f62f410d045425b716f15eb7aefef3`。完整源码状态清单见 [manifest.json](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-8-official-webgl-pixel-check/native-profile/manifest.json>)，SHA-256 `5aaf3008be9557a5ebc75c3b0cb3f150d24db35bf600bc6eb0bbfbcc1fe57cb8`。
- 边界：这是生产 artwork 在 macOS Profile / Impeller 引擎中的离线同状态图像采集，不是实窗逐时刻录屏或物理 display-present 时间测量；也没有复原原录屏随机种子、指针输入时间轴或线上网页相位。UI-6.8 的源模型与 Profile shader 栅格验收有证据，实时输入同步和录屏逐帧 1:1 仍部分验收。

### 2026-11-18 UI-6.7 三枚主图标点击反馈增强与 Profile 复核

- 根据 96 dp 参考图保留运行、刷新、搜索的 9×9 点阵轮廓，只调整 `GlassMotionAction.play/search/refresh` 的点击幅度：运行增加右向位移、轻微横向扩张与扫光；搜索扩大镜片缩放和扫光；刷新保留整圈旋转并加深点光亮度。未改 glyph 掩码、按钮 hitbox/业务回调或太阳/月亮主题切换状态机。
- 新增模型回归：点击中点播放图案的平均中心位移必须大于 `0.9 × glyphPitch`，搜索图案的平均半径必须大于静置样本的 `1.08×`。定向执行 `flutter test --no-pub test/glass_motion_test.dart test/glass_action_button_test.dart test/glass_glyph_golden_test.dart`，29 项通过；移除临时入口后 `flutter analyze --no-pub` 无问题。Flutter 3.47.8 / Dart 3.13.7 的 macOS Profile fixture 构建成功（61.8 MB）。
- 原生检查使用隔离 96 dp `GlassActionButton` fixture，回调只更新本地计数器。以 headed 合成指针在每个按钮内按下/释放；浅色时运行、刷新、搜索计数各为 1，切到深色后再各点击一次，AX 读回浅色/深色状态及计数各为 2。`agent-desktop` 动作回执是 `delivered_unverified`；计数器变化和对应应用窗口截图确认了按钮命中及回调结果。浅深静置图与每枚按钮的点击中段图均为 1824×1488 DPR 2，窗口已正常退出。
- 静置图：[`light`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/three-glyph-after-motion-profile.png>) SHA `78a7e47fc813a3b417f61d8417209326225e42449940f808ccddcfc9e3e76a52`；[`dark`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/three-glyph-after-motion-profile-dark.png>) SHA `3b36d4adcd5eae264e2b60abc72a7b1789d0259b9e5222bbaa8c822a9e20f0a7`。
- 浅色点击中段：[`run`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/run-click-new-mid.png>) SHA `a271c642f01f3630f7fd01da531ba2e526f84984337c7583d75e579117f5be8f`；[`refresh`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/refresh-click-new-mid.png>) SHA `11dcc11b632aa7a2582386a275f973af8e699f820b2bc2790f7b8e00a33f1182`；[`search`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/search-click-new-mid.png>) SHA `d683a3f673ccee89e11139e678bcb3faa851faaf860c27917bbcba4415542bd9`。
- 深色点击中段：[`run`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/run-click-new-dark-mid.png>) SHA `8e5e3ec9c6c2179099d83e89a44522b78d3c848605182a82afbc0c6067caac21`；[`refresh`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/refresh-click-new-dark-mid.png>) SHA `454fd990a81daf74543cecf87f35ac638dbdf1e5dccb3ebca603c0bfde2d8212`；[`search`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-design-alignment/search-click-new-dark-mid.png>) SHA `2e2f329fd61ccd9ef0757588b420416f747418431ab340e22080bef80a80e4fa`。
- 验收边界：这些图只核对共享 `GlassActionButton` 在 96 dp 设计尺寸下的静置和点击态，不代表逐个生产调用点都已复核；截图没有共享 display-present 时间戳，不能声称逐帧对齐。UI-6.7 仍部分验收，109 个生产调用点的其余状态继续按[逐实例表](ui-6.7-button-instance-matrix.md)追踪。

### 2026-11-18 UI-6.7 设置活动记录清理按钮 Profile 验收

- 使用 `lib/preview/ui6_inspection_main.dart` 的隔离 macOS Profile 入口（Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1 arm64，800×632 logical px，DPR 2）。启动时通过 `--dart-define=UI6_SEED_ACTIVITY=true` 注入三条仅驻留 `PreviewRuntime` 内存的样例：成功、失败和已取消。`Ui6InspectionRuntime.clearActivity` 只清理这些样例，未连接生产数据库、网络、Mac Host 或外部服务。
- B083“清空记录”在浅/深设置页都可见并打开确认弹窗；浅色页面图为 [`local-data-light-before.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-settings-actions/local-data-light-before.png>)（SHA `d7d733648f6cd15a1b645cd120c512e49918072f15d4e1d97b77e9ceff4f47c2`），深色页面图为 [`local-data-dark-before.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-settings-actions/local-data-dark-before.png>)（SHA `13cb8961558966b395f8e3fb3c2bea449b525becbe42169585cf788b280af726`）。确认弹窗浅色图为 [`clear-dialog-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-settings-actions/clear-dialog-light.png>)（SHA `33f33b831dc480b4897cdd97dbbb80fcbdecba66704a675dd95720bbb8063791`），深色图为 [`clear-dialog-dark-confirm.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-settings-actions/clear-dialog-dark-confirm.png>)（SHA `5fea8f184466cacdb9c75566773ff1d737db61869d04cc8c10ca3a7969b51a7d`）。所有图为 1824×1488 PNG、DPR 2。
- B081“取消”在深色确认弹窗中被实际点击；之后活动页仍显示三条预置记录（成功/失败/已取消），确认取消没有清空。B082“清空记录”在浅色确认弹窗中被实际点击；之后活动页 AX 只显示“还没有运行记录”，截图为 [`activity-empty-after-confirm-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-settings-actions/activity-empty-after-confirm-light.png>)（SHA `75426704396b13210ea5e04b588a430ed9a2734ffca7b11402753ca34befadd2`）。动作只作用于本轮进程内样例。
- Profile 构建成功（72.8 MB）；Flutter runner 正常退出，应用清单与进程查询均无 Aggregate/runner 残留。此轮没有产品代码变化或测试运行。B081–B083 的浅/深静态外观和确认/结果路径已有证据，但未采集按钮按下动画关键帧、FrameTiming/FPS；全量逐调用点和动态状态仍未签收，UI-6.7 继续部分验收。


### 2026-11-18 UI-6.7 Mac Host 启停、轮换确认与邀请 Profile 验收

- 使用隔离的 `lib/preview/ui6_inspection_main.dart` macOS Profile 夹具（Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1 arm64，800×632 logical px，DPR 2）。源码检查确认 `Ui6InspectionRuntime` 的 `start`、`stop`、邀请生成只改进程内预览数据，不打开 Host listener、不读取 Keychain。Profile 中仅观察到 Flutter VM service 的 loopback 端口；针对 Host 预览端口 44321 的 `lsof` 查询无监听结果。
- B088 启停按钮分别在浅/深主题实际点击。AX 从“已关闭”变为“运行中”，点击停止后恢复“已关闭”。浅色运行图 [`host-running-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-running-light.png>)（SHA `dc71c38c6955033df7c582758683a5ca9d24a869b439308d86142298e4092257`），深色运行图 [`host-running-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-running-dark.png>)（SHA `fba364bcb190ca8d2fcf2085eb4299fd49681f1f0ec035cd75f8cc7bd217b67f`）；停止后浅色图 [`host-stopped-after-click-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-stopped-after-click-light.png>)（SHA `130c59f29ab1dbff052358b3b705ae6af53bbf8ce4a0f10eee6b67888efe9415`），深色图 [`host-stopped-after-click-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-stopped-after-click-dark.png>)（SHA `60200325d89c9b4ddf48c1fa3d0a04fc81184042eb9b90d1b2c6e9da4395714e`）。
- B089 浅色 Profile 打开“轮换 Mac Host 身份”确认弹窗并点击取消。截图 [`host-identity-confirm-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-identity-confirm-light.png>)（SHA `8eb6f8f938d6010f128d04cd62be480bae90903717af1daca0e13082b0eaf603`）；取消后 AX 仍显示 Host 运行、一个假配对设备与邀请。实窗没有执行确认轮换；确认路径由现有 fake Host Widget 回归覆盖。
- B090 浅色 Profile 首次点击“生成新邀请”；截图 [`host-invitation-generated-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-start-stop/host-invitation-generated-light.png>)（SHA `b188201d97b74ef3eca2ee741fd9dc5d847a74f28c067e7ed995870f0a6e453c`），AX 读到邀请过期信息和一个本机网络地址。该首屏截图中的二维码被窗口底部区域部分遮挡；后续滚动复核见下方 B090 补证。
- Profile 进程收到正常退出并关闭，应用清单和进程检查没有 Aggregate/Flutter runner 残留。本轮无产品代码变化、未运行测试；B088–B090 均缺原生按钮按下动画关键帧；B090 后续补齐二维码视觉可见性，但原生 AX bounds 仍为 1 px 高，不能据此签收整页或所有调用点。


### 2026-11-18 UI-6.7 Mac Host 配对与设备权限 Profile 验收

- 使用隔离 `lib/preview/ui6_inspection_main.dart` macOS Profile 入口（Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1 arm64，800×632 logical px、DPR 2）。源码确认所有 Host 操作委托 `Ui6InspectionHost`：待配对、已配对、grant 更新、撤销仅存在当前进程内；没有读 Keychain、连接真实手机或调用网络 Host。每次 AXPress 均以新的 AX 状态树复核结果；动作回执本身是 `delivered_unverified`，不作为画面动作独立通过证据。
- B092/B093 暗色静态卡片：待处理 Android 假设备 `UI 检查 Android` 与批准/拒绝入口截图 [`pairing-controls-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/pairing-controls-dark.png>)（SHA `9a5c9f2fb517374c61504f31b670f0062839f1d4aff9e22f1de1c8aac3a6c516`）；已配对假设备截图 [`paired-devices-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/paired-devices-dark.png>)（SHA `7aa74af87c8bfff951ec937f4ca3f5aa71bd31e576ba47bc88004ab66e7a2f28`）。页面均在 Host 假状态中采集。
- B094 点击“批准只读”后，AX 读回待处理为空、已配对设备权限只有“读取连接”；结果截图 [`readonly-approved-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/readonly-approved-dark.png>)（SHA `3f49ef57d6a0e0142990bd5c01dba0527d6ec7839830d7b4a3a80cb0388d401a`）。B095 停止/启动假 Host 重新生成待处理样例，点击“允许连接向导”后，AX 读回权限“读取连接 · 连接向导”。
- B096 点击“自定义权限”打开 [`custom-permission-dialog-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/custom-permission-dialog-dark.png>)（SHA `32586ab64b5df5a32b83bc7ef7970c5d709aed40514b64428767567ccf4704c4`）。在 Git CLI 假连接选择本机控制（AX 同时显示读取已选择）和连接向导后批准；假设备进入已配对列表。B097 再打开“修改权限”，AX 回读本机控制仍被选中；增加连接管理与 Git CLI 外部写入，确认读取、本机控制、外部写入均选中，并保存。弹窗截图 [`edit-permission-dialog-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/edit-permission-dialog-dark.png>)（SHA `465a7e906e927705dfc08486d27951599321b6c54931e8d8e9034c752208332c`）；保存后 AX 的设备范围更新为读取连接、连接向导和连接管理。所有批准及变更均只写入 fixture fake。
- B098 点击“撤销”打开确认弹窗 [`revoke-confirm-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/revoke-confirm-dark.png>)（SHA `92f5d29346eaf8dd8fcf4ac037183d7497b203c6971b733e2510d4b16e94fda5`），再点击取消。取消后 AX 仍读到一台已配对预览设备，截图 [`revoke-cancelled-paired-remains-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/revoke-cancelled-paired-remains-dark.png>)（SHA `bbb7384727b2b6906275fc3b393d24003d166f11eb9021dc1993adc858accc22`）。
- 最后停止假 Host 后，`lsof` 仅显示 Flutter VM service `127.0.0.1:60379`，Host 端口 44321 无 listener；`agent-desktop close-app Aggregate` 成功退出，列表和 PID 检查无残留。本轮无产品代码变化、未运行测试；仅有暗色静态及语义交互状态，无按钮按下关键帧、浅色配对页、FrameTiming/FPS，也未点击“复制配对信息”。B092–B098 不替代全页/全部调用点验收，UI-6.7 保持部分验收。


### 2026-11-18 UI-6.7 权限弹窗按钮 B099–B101 补充映射

B099“取消”在 B097 保存后重新打开的已配对权限弹窗中实际点击；弹窗关闭，新的 AX 树仍显示原假 grant。B100“保存权限”已在同一实窗编辑流程点击，AX 回读范围从读取连接/连接向导更新为再含连接管理。B101 逐连接权限 chip 在 B096/B097 中分别选择 Git CLI 本机控制和外部写入，AX 读回选择态，并确认本机控制/外部写入自动包含读取。截图沿用前一节的 [`custom-permission-dialog-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/custom-permission-dialog-dark.png>) 与 [`edit-permission-dialog-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-permissions/edit-permission-dialog-dark.png>)。这些回调只读写 `Ui6InspectionHost`；AXPress 回执未证明物理按压，未采按下动画帧。

### 2026-11-18 UI-6.7 暂停播放权限确认暗色 Profile 验收

- 环境与边界：`lib/preview/ui6_inspection_main.dart` 的 macOS Profile 与 `Ui6InspectionRuntime`；所选“暂停播放”标注为“仅更新本地预览状态”，但权限分类仍是外部写入，因此运行前显示确认框。源码确认 fixture 的 `invoke` 委托给进程内 `PreviewRuntime`，不控制音乐播放器、不运行外部命令、不访问服务或网络。
- B048：在无参表单点击“运行”打开确认框，再点“取消”；新 AX 树确认弹窗关闭、运行状态仍为“尚未运行”。
- B049/B050：重新打开确认框并点击“执行”；AX 确认“运行成功 / 预览结果：暂停播放”。这只验证隔离 fixture 的按钮与状态呈现，不代表真实音乐暂停或外部写入成功。未点击“复制结果”，未读取或写入系统剪贴板。
- 暗色确认框截图 [`pause-confirm-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-music-pause-confirmation/pause-confirm-dark.png>)，SHA-256 `db7b76ee1718969b3e5f26527e6045c97388de6fdc2506c8bda13469ab8db45`；完成状态截图 [`pause-result-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-music-pause-confirmation/pause-result-dark.png>)，SHA-256 `cb5d9d7700ceb6be79e13f7f72740eaebc47fd3f5ff7dc682d5b6258fdf2d957`。
- Profile app 正常关闭；GUI 清单及 `pgrep` 均未发现 Aggregate 或 Flutter runner 残留。没有产品代码或测试变化；AXPress 的 `delivered_unverified` 回执由随后的 AX 状态读取确认。未采物理按下帧、FrameTiming/FPS；UI-6.7 和 UI-6.8 仍有其他未验收项。


### 2026-11-18 UI-6.7 工作台功能行 B102–B103 Profile 验收

- 使用 `lib/preview/ui6_inspection_main.dart` 隔离 macOS Profile fixture（Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1 arm64，800×632 logical px、DPR 2）。`Ui6InspectionRuntime` 委托 `PreviewRuntime`，不启动外部命令或网络；偏好设置也存于本进程的 PreviewRuntime。
- B102 点击工作台“两个整数相加”功能行，只进入参数页；AX 显示来源 UI 检查 · MCP、只读权限和“运行状态：尚未运行”。没有触发“运行”或快捷键，故没有执行工具。工作台浅深截图 [`workspace-actions-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-workspace-actions/workspace-actions-dark.png>)（SHA `ad1153ef4ef4458db22ed6686d587329c87524a4689b40d28831269590e7ab8c`）；行打开后的参数页 [`feature-open-form-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-workspace-actions/feature-open-form-dark.png>)（SHA `f73c58c6bde5c86322ca57bd734b93ed050ef5e9aef1f3493d538c1937c1a849`）。
- B103 点击同一条目的收藏按钮，AX 显示“收藏的功能”分组和“取消收藏”；截图 [`workspace-favorite-added-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-workspace-actions/workspace-favorite-added-dark.png>)（SHA `071f7885d1ba84b7410ccce267af5d44b6fa95eca4cca5ec21fc565f352c9053`）。随后点击取消收藏，AX 显示恢复“收藏 两个整数相加”，没有收藏分组；退出 fixture 前 PreviewRuntime 偏好恢复空集合。
- AXPress 回执仍为 `delivered_unverified`，以新的 AX 树确认页面/收藏状态；没有物理按下关键帧。应用关闭且无 Aggregate runner 残留。无产品代码变化或测试运行，`git diff --check` 通过。B102–B103 仅暗色交互覆盖，UI-6.7 其余状态和生产调用点仍未全部验收。


### 2026-11-18 UI-6.7 通用页面错误态 B104 临时夹具验收

- 使用临时 `ui6_page_state_fixture_main.dart` macOS Profile 入口直接呈现生产 `PageState.error` 组件（Flutter 3.47.8 / Dart 3.13.7，深色主题）。静置错误态截图 [`page-state-error-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-page-state/page-state-error-dark.png>)（SHA `16fba4f31f8cb82d33789095582b2b40384a6425e158cf88d5e1d52608aa3629`）。
- 点击“重试”后，AX Press 回执为 `delivered_unverified`；新的 AX 树从“重试计数：0”更新为“重试计数：1”。此回调只递增夹具本地计数，证明按钮可操作及回调连接，不代表真实数据加载、网络请求或错误恢复已验证。
- 夹具源文件已移除；`agent-desktop close-app` 确认 Aggregate 窗口进程退出，随后确认 GUI 应用与 Flutter runner 均无残留。无产品代码变化、未运行测试；没有按下关键帧或 FrameTiming/FPS，B104 仅验证暗色组件实例，UI-6.7 仍部分验收。


### 2026-11-18 UI-6.7 错误结果恢复操作 B106 Profile 补证

- 使用 `lib/preview/ui6_inspection_main.dart` 暗色 macOS Profile fixture（Flutter 3.47.8 / Dart 3.13.7，800×632 logical px、DPR 2）。点击本地 MCP 假能力“演示恢复状态”并运行后，AX 读回“运行失败”和错误处理卡片；`Ui6InspectionRuntime.invoke` 在该假能力分支抛出本地 `StateError`，没有启动外部执行或网络请求。
- 向下滚动 8 个滚轮单位后，恢复卡片、“检查活动状态”及“查看错误详情”均完整显示在固定 MiniPlayer 上方。截图 [`failure-recovery-scrolled-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-failure-recovery/failure-recovery-scrolled-dark.png>)（SHA `59e9a7cf04f3423f975519bf163744d19a55fd6f4ad954607a54f4d008ba1490`）。
- 点击“检查活动状态”后，新的 AX 树仍为“运行失败”，没有恢复结果或状态变化；AXPress 回执 `delivered_unverified`。源码显示 `CapabilityRunPage._checkActivityStatus` 在 `handle == null` 时直接返回，而此假错误在产生 RunHandle 前抛出，因此该按钮在此 fixture 路径不能验证真实活动查询。此边界只说明本地模拟错误的交互限制，不外推为所有生产 Runtime 的故障。
- fixture 正常关闭，GUI app 和 Flutter runner 无残留。没有产品代码变化或测试运行；无物理按下关键帧/FrameTiming，B106 仅暗色 Profile 视觉与受限交互验收，UI-6.7 仍部分验收。此结果覆盖先前“检查活动状态未点击”的范围描述；早前截图、布局滚动位置与真实 Runtime 行为限制仍保留。


### 2026-11-18 UI-6.7 本地文件结果 B108–B109 Profile 验收

- 使用临时 `ui6_file_result_fixture_main.dart` 暗色 macOS Profile 入口直接呈现生产 `ResultPanel` 文件结果组件（Flutter 3.47.8 / Dart 3.13.7，800×632 logical px、DPR 2），假路径为 `/tmp/aggregate-preview-report.txt`。点击 B108“预览文件”后 AX 显示“预览文件：/tmp/aggregate-preview-report.txt”；`Ui6InspectionRuntime.previewLocalFile` 仅委托 `PreviewRuntime` 返回该字符串，不读取真实文件。截图 [`local-file-preview-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-file-result/local-file-preview-dark.png>)（SHA `d2160e2705220175101217a876a07af59f22310df6bf52591bf2bbe7d4f12b8d`）。
- B109“在访达中显示”点击回执为 `delivered_unverified`；前后 Finder 窗口列表均为空，AX 页面无错误或状态变化。该 fixture 的 `revealLocalFile` 是空实现，因此只证明控件可触发且没有启动 Finder，不代表生产文件揭示行为。
- 临时 fixture 已删除，Aggregate Profile app 与 Flutter runner 均正常关闭且无残留。没有产品代码变化或测试运行；未点击“复制结果”，无按下动画关键帧/FrameTiming。B108–B109 仅暗色组件级 fake 验收，UI-6.7 仍部分验收。


### 2026-11-18 UI-6.7 结果待确认恢复 B107 Profile 验收

- 在 `ui6_inspection_main.dart` Profile 入口用 `UI6_SEED_ACTIVITY_FILTER_STATES=true` 注入进程内超时/结果待确认样例。活动页打开假 `status` 记录后点击“查看运行”，CapabilityRunPage 从内存活动恢复 `RunState.outcomeUnknown` 与 RunHandle；没有重新运行能力或访问真实执行端。
- 页面显示恢复说明和“检查活动状态”。点击后 AX 读回状态仍为“结果待确认”，并出现“结果仍未知；请先在执行端确认，不要直接重跑。”提示。检查动作仅读取此进程内 PreviewRuntime 历史，不重跑操作。截图 [`unknown-outcome-recovery-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-unknown-outcome/unknown-outcome-recovery-dark.png>)（SHA `aca0c4529cc0ae4fd878d0eed835fa75aad83b6e26e91fe0f5a700520b95af51`）。
- AXPress 回执为 `delivered_unverified`，以操作后的新 AX 树和提示确认结果。关闭 Profile app 后 GUI app 与 Flutter runner 均无残留。没有产品代码修改或测试运行；仅暗色状态，无物理按下关键帧/FrameTiming，B107 仅 fake 组件级验收，UI-6.7 仍部分验收。


### 2026-11-18 UI-6.7 Mac Host 撤销与身份轮换确认 B085/B087 Profile 验收

- 在 `ui6_inspection_main.dart` 暗色 macOS Profile（Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1 arm64，800×632 logical px、DPR 2）启动 `Ui6InspectionHost`。源码确认该 Host 只改进程内配对/状态；启动不开放 listener、不读 Keychain，`rotate()` 返回预置 `PREVIEW ONLY` 身份。
- B085 打开“撤销设备配对？”确认框后点击“撤销设备”；新 AX 树中“已配对设备”及配对卡片消失，待处理假设备仍在。对话框截图 [`revoke-confirm-profile-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-confirm-actions/revoke-confirm-profile-dark.png>)（SHA `4838b2e5569c8f8d246185db71c0fb7377a2c21d4c0deec21228814abc0537d5`）。
- B087 再打开“轮换 Mac Host 身份？”确认框并确认“撤销授权并轮换”；AX 出现“Mac Host 身份已轮换。请启动 Host，并让手机重新配对。”，Host 状态回到已关闭，待处理/配对设备列表被清空。确认框截图 [`identity-rotation-confirm-profile-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-confirm-actions/identity-rotation-confirm-profile-dark.png>)（SHA `36538f3cab681bb4193e83a9198938f2c73a67ae84d215a7cd70a1da35a00298`）；结果截图 [`host-rotated-profile-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-confirm-actions/host-rotated-profile-dark.png>)（SHA `b6be363dfc71e0f88eb92d63c1518fbe63ea74712d16f6d6892bfac38601ff64`）。目标端口 44321 无 listener。
- 两个确认操作均只变更隔离 fake；AXPress 回执 `delivered_unverified`，使用新 AX 树确认结果。Profile app 与 Flutter runner 正常退出，无残留。没有产品代码变化或测试运行；仅暗色静态/语义结果，无按下关键帧/FrameTiming，B085/B087 不代表真实配对设备撤销或 TLS 身份轮换，UI-6.7 仍部分验收。


### 2026-11-18 UI-6.7 运行、刷新、搜索图案居中微调

- 根据用户指出的三枚点阵图案，对照 96 dp 参考图和 Profile 实窗，发现运行三角在 9×9 字形画布中从最左列起画，导致整枚图案明显偏左。将三角整体右移两格，让轮廓重心靠近按钮中心；点数仍为 25，格距、点径、圆角、光晕、刷新/搜索形状和按钮回调均未改。
- 暗色原生 Profile 静置图 [`run-centered-dark.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-run-glyph-centering/run-centered-dark.png>)，SHA-256 `de6e818ef61f49a787fc94fcc94d681c5a2922e024de4e07c524737e3de5e51f`；浅色原生 Profile 静置图 [`run-centered-light.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-run-glyph-centering/run-centered-light.png>)，SHA-256 `db9d67446b6e1508e337f46eb37455e7bf34cc788bf005a38d0b2ca27be499f9`。两图均为 1824×1488 像素、DPR 2；AX 已回读浅色主题。
- 验证：更新 golden 时 `flutter test --no-pub --update-goldens test/glass_glyph_golden_test.dart test/glass_action_button_test.dart` 共 18 项通过；随后正常模式联合运行 `glass_action_button_test.dart`、`glass_glyph_golden_test.dart`、`glass_motion_test.dart` 共 29 项通过。`flutter analyze --no-pub` 无问题，两个 Dart 文件格式检查通过，Profile 构建成功。更新了全 glyph 浅/深 1×/2× golden 与主 glyph 浅/深 golden。夹具 app 与 Flutter runner 已关闭，无残留。
- 本轮只调整静态几何位置；未改变太阳/月亮状态机或三个 glyph 的点击动画/业务逻辑，也未采按下帧和 FrameTiming/FPS。此处签收的是组件级居中修正，不替代逐个生产按钮的动效验收；UI-6.7/6.8 仍部分验收。


### 2026-11-18 UI-6.7 B105 复制结果 Widget 级拦截验收

- 使用生产 `ResultPanel` 与 macOS `GlassMotionScope` Widget 变体；在 `SystemChannels.platform` 注册测试 messenger，截获 `Clipboard.setData` 到进程内字符串变量。点击语义按钮“复制结果”一次后，记录到一次平台通道调用，内容为 `已完成\n\n{\n  "count": 2,\n  "ok": true\n}`，并显示“已复制结果”。测试没有调用 macOS 剪贴板服务，没有读取或改变系统剪贴板。
- 新增 `app/test/result_panel_clipboard_test.dart`，定向运行 `flutter test --no-pub --reporter compact test/result_panel_clipboard_test.dart` 通过（1 项）。首次运行发现测试语义句柄的清理顺序错误，改为测试结束前显式 dispose 后通过；Dart 格式通过。
- 此项证明生产组件的 macOS 分支会把拼接后的结果交给 Clipboard 通道并显示成功提示；不能替代真实原生 Profile 按压或系统剪贴板写入验收，B105 仍为部分证据。未读取用户剪贴板数据。


### 2026-11-18 UI-6.7 B091 Mac Host 配对信息复制 Widget 验收

- 使用生产 `MacHostSettingsPanel` 与测试 fake Host/PairingControl。启动只改变测试进程内状态，生成的短时邀请及 `127.0.0.1:43123` endpoint 都是 fake。点击“复制配对信息”后，测试 messenger 在 `SystemChannels.platform` 捕获一次 `Clipboard.setData`；写入文本与同一 fake 邀请的完整 `qrPayload` 完全一致，页面显示“配对信息已复制”。
- 定向执行 `flutter test --no-pub --reporter compact --plain-name 'copies the generated invitation through an intercepted platform channel' test/mac_host_settings_panel_test.dart`（macOS Widget 变体）通过 1 项；`flutter analyze --no-pub` 无问题，`dart format` 和 `git diff --check` 通过。
- 这是组件回调和 payload 的隔离验收，不是 macOS Profile 系统剪贴板写入、真实 Host、网络配对或原生按下动画验收；测试未读取或改变系统剪贴板，B091 仍部分验收，UI-6.7 继续部分验收。


### 2026-11-18 UI-6.7 B090 Mac Host 邀请二维码完整可见性复核

- 使用 `ui6_inspection_main.dart` macOS Profile（窗口 AX bounds 800×632 logical px，DPR 2）；Host 和配对数据均来自进程内 `Ui6InspectionHost` fake。启动 fake Host、生成一次邀请后，将 Mac Host 页面滚动到邀请详情。未启用真实 listener、网络配对或 Keychain。
- 暗色实窗截图 [`host-invitation-generated-dark-scrolled.png`](</Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-7-host-invitation-scroll/host-invitation-generated-dark-scrolled.png>) 为 1824×1488 PNG，SHA-256 `89e5c2ca7b419b4119a0dbeb9694bc092c9d78820cc88d0c48ed0733f47eedff`。完整二维码、邀请过期时间、一个本机网络地址及“复制配对信息”按钮均在截图中可见；首屏原浅色截图的二维码裁切由滚动后完整截图补足。
- 在这张截图对应的最终滚动状态下，`agent-desktop get --property bounds` 的 live 读取仍给“复制配对信息” `{x:602,y:749,width:139,height:1}`；AX 节点保留 Click action。故只签收实窗视觉可见性，仍不签收该按钮的 AX 几何。没有捕获原生按下关键帧；B090 保持部分验收，UI-6.7 仍部分验收。Profile app 和 Flutter runner 已退出，无残留；无产品代码或测试变化。


### 2026-11-18 UI-6.7 B090 Flutter Semantics 与 macOS AX 边界对照

- 在同一隔离 Debug 夹具中，以 `ext.flutter.debugDumpSemanticsTreeInTraversalOrder` 检查邀请页滚动后的 Flutter 树。`复制配对信息` 对应节点的本地矩形为 `Rect.fromLTRB(24.0, 622.0, 162.6, 662.0)`，高度 40 logical px，带 `tap` action，且未标记 `HIDDEN`。
- 同状态的 live macOS AX 读取仍为 `{x:602,y:749,width:139,height:1}`；实窗 Profile 视觉证据仍见上方 B090 截图。此差异排除了按钮本地语义框只有 1 px 高的解释，但尚不能区分 Flutter macOS 坐标/裁剪转换与原生 AX 查询路径；不据此归因到某一层或做猜测性 UI 补丁。
- Debug 树只作语义几何诊断，不作为视觉验收；未记录 Debug 截图。隔离 Debug app 已关闭，fake Host 无 listener、Keychain 或网络配对；无产品代码/测试变化。B090 的 AX 几何仍未通过，UI-6.7 保持部分验收。


### 2026-11-19 UI-6.8 当前 Glass Light Toggle 网页复核（替代已删除视频）

- 用户确认原 MP4 已删除，并指定[当前 Glass Light Toggle 页面](https://experiments.thisiswhitespace.com/glass-light-toggle)作为参考。当前 Next.js 页面部署 ID 为 `dpl_HTAd9EyjDwpmH9jaAFGH52jqjsbf`，iframe 加载 `/standalone/glass-light-toggle/index.html`；当前 `main.js?v=3` 为 HTTP 200、26,498 字节，SHA-256 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`，与此前已核源码基线相同。
- 使用隔离 Chromium/SwiftShader、1440×913 视口，通过 CDP 从暗态拖至亮态，20 次移动输入；在第 10 步保持按下时采中段，随后释放并采亮态。三张图分别为[暗态](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/glass-toggle-web-dark.png>)（SHA `de124cfb52fee9991ec745aba77a209c011480fb44f47f9e2b79805256793292`）、[拖动中段](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/glass-toggle-web-drag-mid.png>)（SHA `908a6907707504e4ec63be4f8cd23c9bbefb309190b3cc2a5752effc2bd7388b`）和[亮态](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/glass-toggle-web-light.png>)（SHA `a7385c30e950e47fcda40696615f1095075b9aaaa65e76b44a96f73507d47d32`）。可见月亮/星点到太阳点阵的内部变化、滑块位移，以及冷蓝到暖橙边缘光变化。
- 该网页替代被删除视频作为后续视觉/源码对照依据；它不等于原录屏，不能据此宣称已与原视频逐帧相同。当前实验脚本与旧基线 SHA 相同，但没有同步采集网页和 Aggregate 的物理呈现时钟。本轮未改主题状态机、拟合参数或产品代码；UI-6.8 仍部分验收。


### 2026-11-19 UI-6.7 高优先级生产按钮 B001/B005/B050 Profile 核对

- 使用 `lib/preview/ui6_inspection_main.dart` 的暗色 macOS Profile 夹具，窗口 800×632 logical px、DPR 2；`Ui6InspectionRuntime` 将操作委托给进程内 `PreviewRuntime`，没有连接真实音乐、执行命令或发起网络请求。按钮截图均为 1824×1488 PNG。
- B001 全局搜索：实窗 AX bounds 192×40。物理合成点击回执为 `delivered_unverified`，随后的新 AX 树确认已进入“所有功能”页并出现搜索字段。首页/搜索后截图分别为[`home-dark-before.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/home-dark-before.png>)（SHA `04f7f826514f77718d5faed080da39e28c31e01f212c5f0c5238edb11e1153e3`）和[`search-workspace-dark.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/search-workspace-dark.png>)（SHA `094f17568bd2cddaf4a775cf3ce5cac80c4470dfecf84cb2597e577338ee62f5`）。未采搜索按钮按下关键帧。
- B005 活动刷新：标题右侧 AX bounds 46×46。点击前截图[`activity-dark-before.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/activity-dark-before.png>)（SHA `0677cb4b5253237c5eff7b625df6467fbec34fffce8a8ac66052b11004d10458`）显示 3 条；点击后新 AX 树和截图[`activity-dark-after.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/activity-dark-after.png>)（SHA `50f4a93f42dc4e27f9b237d43c6feb6d81dd3f4d5e4c2f4f65dc612aa9ebd76b`）显示 6 条。本轮核对源码确认按钮只调用 `reload()`，重新读取 `listRecentRuns()`；前后新增的状态记录属于进程内 fixture，未把记录变化归因给按钮，也未触发外部服务。
- B050 暂停播放运行表单：短窗口首屏滚动位置下按钮只有部分区域可见；向下滚动后完整按钮 AX bounds 为 87×40，见[`表单滚动前`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/pause-run-form-dark.png>)（SHA `a555177a845ee81638a535be353e45f44c3c1886a7fe8594010ba78aafdd3ef4`）及[`表单滚动后`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/pause-run-form-dark-visible.png>)（SHA `d23a16194ac657ffa7c538fb90dee5c251b8f306f538cfa4c536974a5c54c202`）。点击“运行”后 AX 确认弹窗显示功能、执行端和外部写入权限；弹窗图[`pause-run-confirm-dark.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-run-refresh-search/pause-run-confirm-dark.png>)（SHA `8d20c1f42ad7812463929c888d5bbbc795720a70384c761bdc8f35892a45e6d3`）。本轮未确认执行：AX 点击回执因被 `Dismiss` 静态文本遮挡而为 `not_delivered`，未重试；此前 B049 的 PreviewRuntime 执行结果记录仍是既有证据。源码核对 `Ui6InspectionRuntime.invoke` 委托到 `PreviewRuntime.invoke`，不会调用真实音乐服务。
- 临时 Profile 窗口正常退出，Flutter runner 与 Chromium 均无残留。没有产品代码或测试变化；静置/页面反馈已核，三枚生产按钮的按下动画关键帧、FrameTiming/FPS、浅色对应实例及全量调用点仍未签收。UI-6.7 继续部分验收。

- 同日补采浅色 Profile 实例：使用同一 `lib/preview/ui6_inspection_main.dart` 隔离入口，窗口内容 800×600 logical px、DPR 2。所有本批 PNG 都用 `agent-desktop screenshot --app Aggregate` 只截 Aggregate 窗口（1824×1488），没有保存桌面其他应用画面。MouseDown 由 CGEvent 发往当前窗口 AX bounds 中心；第一张截图请求在按下约 90ms 后开始，截图调用返回后才发 MouseUp；释放样本请求约在 MouseUp 70ms 后开始。截图 API 没有 display-present 时间戳，调用期间耗时也远长于请求偏移，因此这些图只能作为按住/释放附近的实窗样本，不能标记为精确动画相位、时长或逐帧验收。
- B001 浅色全局搜索 AX bounds 仍为 192×40。鼠标按下样本中搜索入口可见暖光，释放后 AX 树从设置页转到“所有功能”并出现搜索字段。图：[按住样本](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b001-search-held-window.png>)（SHA-256 `2fb3907502bfd906f57ce3e3e6926a1f1594f110013fa4080af32fd06302c524`）、[释放后样本](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b001-search-release-window.png>)（`06e46c8699f7f2d1417ea5642d319e194ebaaa83e897eb90657b090011635f2a`）。
- B005 浅色活动刷新 AX bounds 为 46×46。鼠标按下/释放样本保留在活动页；源码确认 `onPressed: reload`，只重设 `listRecentRuns()` future。夹具记录在这次会话中有其他本地状态变化，不将列表条数变化归因于刷新，也没有连接真实数据服务。图：[按住样本](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b005-refresh-held-window.png>)（`799baf170ef2d552f36aa9ffc706b156e9d01ac1876a95a660972bfc37ff6e67`）、[释放后样本](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b005-refresh-release-window.png>)（`cb4313c91530a59f98997ad391317b8f54968abd1074b7d677571b32c7442bfd`）。
- B050 浅色“运行”AX bounds 为 87×40。鼠标释放后打开“确认执行”，AX 显示暂停播放、预览连接、此设备及外部写入权限；随后实际点击“取消”并确认返回表单，AX 运行状态仍是“尚未运行”。没有确认执行、触发音乐服务或调用外部命令。图：[按住样本](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b050-run-held-window.png>)（`01024df95efb9b13be02756fa6cc05b63e16f1f6f3781fd126d524862395031f`）、[释放后/确认弹窗](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-production-buttons-light/b050-run-release-window.png>)（`e57c77cba7d301090be20f4deae18f716d10f94436aba0dab449d277a8dd337c`）。
- 临时 Profile 窗口通过 Close 退出；随后进程查询未找到本轮 Aggregate Profile 二进制或对应 Flutter run 进程。仅更新文档，没有改产品代码，也没有运行测试。B001/B005/B050 的浅色静置与交互路径补充了生产实窗证据；完整按下动画时序、FrameTiming/FPS、所有生产按钮实例和 VoiceOver 仍未验收，UI-6.7 保持部分验收。


### 2026-11-19 UI-6.8 网页与 macOS Profile 同屏双向对照

- 参考：原 MP4 已删除；按用户指示，以当前 [Glass Light Toggle 页面](https://experiments.thisiswhitespace.com/glass-light-toggle)为对照。网页实际脚本副本 `main.js?v=3` SHA-256 为 `7f7b5d15bd974a2023bd7c044333f90b9962764c9b18aef0d3bdad6c3bf2e3ee`，与前述官方源 oracle 基线一致。源页面自身每次加载仍随机初始化；本地临时夹具在该脚本前固定 LCG seed `1831565813`，状态消费 113×7 个值后为 `700164006`，对应 `ThemeSwitchCalibration.reference` 的种子。
- 产品调整：macOS `SettingsPage` 将 `ThemeSwitchCalibration.reference` 显式传给 `AppearanceSelector`；`AppearanceSelector` 默认值继续为 `videoFittedThemeSwitch`，故 Android 标准设置页没有切换参数。改变范围只限 macOS 视觉模型的 calibration 选择；`GlassThemeSwitch` 的拖动/点击状态机、偏好提交回调、取消/反向处理及运行端协议没有改。`flutter test --no-pub test/android_theme_transition_test.dart` 两平台变体 2 项通过，覆盖 Android 保留 fitted、macOS 使用 source reference；`flutter analyze --no-pub` 无问题；macOS Profile 构建成功并实窗确认设置 AX 端点可双向切换。
- 对照环境：Apple M5 Pro 内屏，显示器 3024×1964 Retina、缩放 2×（1512×982 logical）；Flutter 3.47.8 stable、Dart 3.13.7、macOS Profile / Impeller `MetalSDF`。应用是 `Ui6InspectionRuntime` 与 `PreviewRuntime` 的隔离数据，无真实服务/Host。应用窗口 800×632 logical，控件布局宽 440、高约 203；轨道几何按 `432×(440×0.76/720)` 得约 200.64 logical px。Chromium 主视口 700×545 CSS、DPR 2；iframe 内源码使用 `zoom=0.464444`，轨道同为约 200.64 px，中心纵向偏差约 1.8 logical px。
- 输入与采样：每个方向从端点开始，将 30 个线性移动点在 500 ms 内依次发送给 CDP 与 macOS CGEvent；全屏 PNG 在进度 0%、25%、50%、75%、100% 按下态采集，随后释放并延时 650 ms 捕获稳定态。每张 3024×1964 PNG 同时包含网页和 Aggregate。脚本在网页与原生调用返回后记录 monotonic 时间：中途 move 对的调用返回差为 0.025–0.035 ms；两向 down 调用返回差为 27.6/29.9 ms。该值不是系统事件 tap 的接收时间，也不是显示器呈现时间。正向结束网页 `body.light=true` / macOS AX “浅色”；反向结束 `false` / “深色”。
- 逐帧目视结论：source-reference 参数下两向拖动中的月亮/太阳粒子、点阵重组、玻璃边缘暖/冷光持续变化，运动方向与端点均吻合。当前同屏样本仍可见原生开关外围焦点环，而网页无此层；WebGL 与 MetalSDF 光栅也不能视作同一像素输出。这里没有共享页面时钟，截图同刻不等于两套动画内部相位同刻；本次不签收 1:1、原视频复原或 display-present FPS，UI-6.8 继续部分验收。
- 截图位于 `/Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-8-web-native-sync/`。所选双向相位与稳定帧 SHA-256：

| 方向/进度 | PNG | SHA-256 |
| --- | --- | --- |
| 深→浅 25% | `source-model-dark-to-light-p25-pressed.png` | `b3df6c9cb5e75cf65eec0ecfbc479d6d80e731f79316329c583621a3f65d55fd` |
| 深→浅 50% | `source-model-dark-to-light-p50-pressed.png` | `5949d4890d6abf37bc638235f39b7c0c428ee95d07249d987f549b4ea05c9bc6` |
| 深→浅 75% | `source-model-dark-to-light-p75-pressed.png` | `5091ce20408c2fac36d153ebb0af332d4535ba8d0a7e05fc30a83d39a545a0e3` |
| 深→浅 稳定 | `source-model-dark-to-light-settled.png` | `0a29acc95d07a5a3c631ce0fb7ab1868ef9044fdca45bca7d74329ce8ef256ea` |
| 浅→深 25% | `source-model-light-to-dark-p25-pressed.png` | `124233842936e978004ca3dda57a18409032da0646a381c88b852df3e51650fb` |
| 浅→深 50% | `source-model-light-to-dark-p50-pressed.png` | `ddbb6c89a04f11cbef301eb197c692e31bb39831ee4baf589653b5167c54608a` |
| 浅→深 75% | `source-model-light-to-dark-p75-pressed.png` | `e95f9995b4636d67554e40eac73cbaac4552d0c68f5f4b263693eb3b36eca729` |
| 浅→深 稳定 | `source-model-light-to-dark-settled.png` | `80064c1bfaa1bff362f2a7146f093ce83a62926e4009c23b8dcc5f83f058ee23` |


### 2026-11-19 UI-6.7 暗色生产按钮短时序采样

- 环境沿用隔离 `lib/preview/ui6_inspection_main.dart` macOS Profile fixture（窗口 800×632 logical px、DPR 2）；`Ui6InspectionRuntime` 仅委托给当前进程内 `PreviewRuntime`。通过 `CGEvent` 在生产按钮 AX 矩形中心按住 240ms，再用 ScreenCaptureKit 的 `desktopIndependentWindow` filter 只采 Aggregate 窗口。PNG 为 1600×1264。每张图记录截图请求与返回相对 MouseDown 或计划 MouseUp 时刻的 monotonic 时间；采集调用实际耗时约 28–96ms，故这些是有限时点的窗口内容样本，不是显示器 present 时间戳。
- B001 搜索：按下样本请求于 MouseDown 后 86.664ms、调用完成于 179.274ms；[截图](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B001-search-held-80ms.png>) SHA-256 `351b5212db98abe0c85ae241a7c28476de077326f4658450ce35c3d50f1c7191` 可见按钮按下态。释放后应用已进入“所有功能”，其余截图不能继续观察原搜索图案。本按钮路由行为另见上一节。
- B005 活动刷新：截图 API 请求相对计划释放时刻为 +23.789、+118.026、+202.397、+288.738、+381.620ms，返回时刻为 +63.722、+149.287、+234.365、+321.514、+415.064ms。按住样本[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B005-refresh-held-80ms.png>) SHA `ef9d086fa71cf81b5c1cd33b8ef504f520c30511fa23465e4bd61664a1b3cc12`；请求约 +202ms 的旋转样本[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B005-refresh-pulse-160ms.png>) SHA `40f2c614c8e320c5c67dffc9a8b5a6f1f1ef0860f269c6445478829c14871152`，可见回转箭头处于旋转相位。AX 回读仍在活动页。完整六点时序表为[`dark-B005-refresh-timing.tsv`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B005-refresh-timing.tsv>)，SHA `10e751f2a95826907f55074d5e939eceb9900a3a75ba471f76cc4746fe183e41`。
- B050 暂停播放“运行”：按下样本[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B050-run-held-80ms.png>) 请求 +85.031ms、完成 +174.904ms，SHA `e3aaaa693e7d7430bf522cf66f425bf9e213a832ad67c4527c9ab717e527f37a`。释放后请求约 +23.749ms、完成 +55.433ms 的样本仍显示运行表单，SHA `3fe385987115f2e32d8996b102f7a3e161aa84dd68eb3e8aea82aca4d3e84555`；约 +160.324ms 请求、+188.934ms 完成的样本已显示权限确认框，SHA `9dc8925d5e067d721c61ace628163a447cf6aa4490f97bd1037c4fced2b93904`。随后点击“取消”，AX 确认返回表单且仍为“尚未运行”；未点“执行”、未调用音乐或外部命令。时序表[`dark-B050-run-timing.tsv`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-click-pulse/dark-B050-run-timing.tsv>) SHA `7d236df7595ca2c7646360c7858c4d572b3d7279364854ab18aad1970e6b89d9`。
- B001/B005/B050 仅补暗色生产实例的有限时点视觉和路径结果；图像捕获可能跨过短动画状态，不能据此推导精确位移曲线、时长、帧率或物理显示 FPS。浅色三实例既有截图与回调证据仍见上一节；UI-6.7 其他生产实例和 VoiceOver 仍未全验收。本批没有代码或测试变更。

### 2026-11-19 UI-6.7 运行、刷新、搜索轮廓比例再设计

- 用户指出 96 dp 样本中的运行、刷新和搜索图案仍显得别扭。将运行从高窄轮廓改为 7×7 横向更均衡的实心播放三角；刷新改为圆环加一个右侧箭头尖；搜索改为近圆镜片并让右下斜柄从镜片边缘连续伸出。核心点数分别为 25、16、18，仍用同一 9×9 网格、圆角点颗粒、材质和动效 profile。未改按钮尺寸、命中区、业务回调或太阳/月亮状态机。
- macOS Profile `glass_buttons_fixture_main.dart` 在 DPR 2 的 96 dp 按钮实窗中核对浅/深主题。截图为 1824×1488：[深色](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-icons-soft-redesign/native-profile-three-glyphs-dark.png>)，SHA-256 `e92ebf25836c827f685e86a4871d5685ccc556b34e51fe8413fe573fc93d797f`；[浅色](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-icons-soft-redesign/native-profile-three-glyphs-light.png>)，SHA-256 `64c44eb8b13d515f801c6279d4fd0ad12bb28ffbefa1401a9577f31ba9a749a3`。夹具主题按钮由 AX 从“深色”读回“浅色”，夹具随后正常退出；样例回调为空，没有触发产品服务。
- 验证：`flutter test --no-pub --reporter compact test/glass_glyph_golden_test.dart test/glass_action_button_test.dart test/glass_motion_test.dart test/glass_theme_switch_test.dart` 40 项通过；`flutter analyze --no-pub` 无问题；Dart 格式检查和 `git diff --check` 通过；`flutter build macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart` 成功（62.9 MB）。四组点阵 golden 已更新。
- 限制：本轮签收静置轮廓浅/深实窗外观、网格断言与既有动效/主题状态机回归；没有采集三个图案的原生点击关键帧、精确动效相位或 display-present FPS，也没有覆盖全部生产调用点。UI-6.7 继续部分验收。


### 2026-11-19 UI-5.5 设置页玻璃按钮标签窗口/DPR矩阵扩展

- 将设置页生产 `AggregateApp` 的六类按钮文字（普通、禁用、禁用说明、禁用来源、忙碌、危险）采样扩到 800×600、1024×768、1440×900 三种逻辑窗口，各测 1×/2× DPR；深色、浅色初始偏好都运行。每种组合覆盖 14 个临界主题相位（0.46–0.535），共 12 组窗口/DPR/偏好、168 组相位组合。每类文字在同一按钮面上取三个未覆盖像素，合计 3,024 个文字/背景色对比样本，均不低于 4.5:1。
- 验证：`flutter test --no-pub test/macos_dynamic_backdrop_text_contrast_test.dart` 三项通过；`flutter analyze --no-pub` 无问题；`git diff --check` 通过。仅扩展 `app/test/macos_dynamic_backdrop_text_contrast_test.dart` 与本验收文档，无生产颜色、按钮交互或主题切换状态机改动。
- 边界：像素来自 `PreviewRuntime` 设置页的 Widget 离屏 shader 合成，在按钮面上采邻近背景色，不是原生 Profile/display-present 捕获，也不能代表所有生产按钮调用点、其他页面材质/状态矩阵或 VoiceOver。UI-5.5 保持部分验收。


### 2026-11-19 UI-6.7 刷新箭头与搜索柄接点精修

- 放大复核 96 dp Profile 样本后，刷新符号的箭头尖与圆环难以分辨，搜索柄同镜片的斜接点显得断开。刷新图案补为三点箭头头部；搜索图案重排右下两颗点，使镜片边缘与手柄路径接续。播放轮廓、9×9 网格、圆角点、shader 材质、动作 profile、按钮尺寸和回调保持；没有改动 `GlassThemeSwitch` 的手势、主题提交或状态逻辑。
- macOS Profile 使用 `glass_buttons_fixture_main.dart`，800×796 logical px 窗口、DPR 2。截图由 agent-desktop 按应用窗口单独捕获，PNG 为 1824×1816。静置浅/深图：[深色](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-redrawn-click-samples/native-final-dark-idle.png>)，SHA-256 `ea2fc617fe2699fcd3bd8c60e25129639762dd645e82994d4a3440f584a39381`；[浅色](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-redrawn-click-samples/native-final-light-idle.png>)，SHA-256 `61be1a7bf43498a651bf9c94aa6994ccc19660bb2fd771849b230abd7657dc9e`。夹具 AX 分别读回“深色”和“浅色”；三个按钮回调均为空。
- 自动验收：`flutter test --no-pub --update-goldens test/glass_glyph_golden_test.dart` 6 项通过；随后 `flutter test --no-pub --reporter compact test/glass_glyph_golden_test.dart test/glass_action_button_test.dart test/glass_motion_test.dart test/glass_theme_switch_test.dart` 40 项通过；`flutter analyze --no-pub` 无问题；Dart format、`git diff --check` 通过；macOS Profile fixture 构建成功（62.9 MB）。
- 边界：本轮签收两个轮廓的静态浅/深实窗可读性、9×9 坐标与回归套件；没有可计时的新版点击关键帧或 display-present FPS，109 个生产调用点和 VoiceOver 仍未全验收。UI-6.7 继续部分验收，网页参考与 macOS 动画也没有被判为逐帧 1:1。


### 2026-11-19 UI-6.7 运行、刷新、搜索点击呈现时序补验

- 使用隔离 macOS Profile 的 96 dp `GlassActionButton` fixture，800×720 logical px 窗口、DPR 2；每个按钮在 AX 中心以 CGEvent 物理点击，按住约 81–85 ms 后释放。点击回调均为空。鼠标释放作为时序零点；ScreenCaptureKit 仅采 Aggregate 窗口，输出 1600×1440。帧附件的 display-time 是 WindowServer 对该帧的显示时间（mach absolute time），见[Apple 的 `SCStreamFrameInfo.displayTime` 文档](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime)；它不是面板像素响应时间。
- 按释放后 0、16.7、33.3、50、66.7、83.3、100、133、167、200、250、333、450、550、650 ms 请求对照帧；表内使用实际 WindowServer 时间戳。窗口采样流在约 +5 至 +649 ms 观察到的相邻样本中位间隔约 17.0–17.3 ms，最大约 19.5–19.9 ms。缺帧已单列，不用插值填补：

| 图案 | 实际选中帧 | 未采到的目标时点 | 实际时间范围 | 相邻样本间隔（中位数 / 最大值） |
| --- | ---: | --- | --- | --- |
| 运行 | 15/15 | 无 | +4.95 至 +643.18 ms | 17.03 / 19.51 ms |
| 刷新 | 14/15 | 0 ms | +14.06 至 +644.48 ms | 17.22 / 19.92 ms |
| 搜索 | 14/15 | 83.3 ms | +5.38 至 +648.71 ms | 17.29 / 19.68 ms |

- 暗色实窗序列中，运行三角的点位轮廓轻微伸缩/偏移，刷新箭头绕环转动，搜索镜片大小有细微变化。合成对照图 [final-contact.png](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-stream-current/final-contact.png>) SHA-256 `e264e4ca99b102ca68f430c48117201c2741b70c5e82748a10bd2bd85333516d`；时序数据：[运行 JSON](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-stream-current/play-final-timing.json>) SHA `0060474b8abc36608afc3692141a187c6350fc55b7bee18ff5f240aa78183f15`、[刷新 JSON](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-stream-current/refresh-final-timing.json>) SHA `68cd5d846aa8e6aa9b45069146fe0a52c7ea9a4e677aaf8af472c17eb13d5a59`、[搜索 JSON](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-stream-current/search-final-timing.json>) SHA `8826480e13ef1f5f61aa3585a2d2e040be05391327e4bb80a514f45f7445e7f9`。
- `app/test/glass_motion_test.dart` 新增点击触发注册 glyph pulse、布局后可见 glyph 仍注册两项回归。`flutter test --no-pub --reporter compact test/glass_motion_test.dart` 13 项通过；`flutter analyze --no-pub` 无问题；Dart 格式和 `git diff --check` 通过。没有改产品代码或切换状态逻辑。
- 结论边界：这是暗色 96 dp fixture 对共享动作模型的呈现证据，不覆盖所有生产调用点、浅色、VoiceOver 或物理面板 FPS；ScreenCaptureKit 时间戳不等于面板刷新/光子时刻。原 MP4 已删除，当前网页参考不构成原视频逐帧对照。UI-6.7 仍部分验收。


### 2026-11-19 UI-6.7 按用户目标图重绘运行、刷新、搜索

- 目标来源：用户最新提供的 96 dp 三按钮图。当前网页 `https://experiments.thisiswhitespace.com/glass-light-toggle` 继续只作为太阳/月亮主题开关的参考；该网页不提供这三枚动作图案的轮廓依据。新目标图取代上一条有效记录中的三种旧轮廓。
- 实现：运行改为细长的 9 行右指楔形（25 点）；刷新改为左右箭头构成的断环（25 点）；搜索改为圆镜片与连续两点斜柄（21 点）。均保留原 9×9 点阵坐标、圆角点、颗粒光效、各自动画 profile、按钮尺寸/命中区、回调及原主题开关逻辑。修改集中在 `app/lib/widgets/glass/glass_glyph.dart` 的三组点阵行与 `app/test/glass_action_button_test.dart` 的坐标/计数断言；浅深色 golden 已更新。
- 静态实窗：Flutter 3.47.8 / Dart 3.13.7，macOS 27.2.1，独立 Profile fixture，800×796 logical px、DPR 2。浅色截图为[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-precise-glyphs/native-light.png>)，SHA-256 `dd458ec2d18c1c99c0d13f143727969850124fe01a09307f627b8cafd1b1d34e`；深色为[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-precise-glyphs/native-dark.png>)，SHA-256 `8912f99ca33c6259696487e18c0fef3b8815293ce46481ca2e8e72bab354fbe1`。主题开关由原生 AX 读回浅色及深色；fixture 点击回调为空。
- 点击呈现：同一 Profile fixture 的浅色 96 dp 三按钮各做一次约 83–88 ms 按住点击，并在释放后约 0–650 ms 捕获窗口。运行、刷新、搜索各取得 42、41、42 个 WindowServer 窗口帧，相邻采样间隔中位数约 17.06–17.10 ms、最大 19.18–19.76 ms。按 15 个目标时点选帧；目标时点并非都对应唯一 WindowServer 帧（相邻目标可能选中同一帧），没有插值。截图联系表为[PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-precise-glyphs/three-glyph-click-contact.png>)，SHA-256 `6cf13a0fb7c5fe2428ab6a13002b2da4c51ed38d267abe8eb3a8c15588aabf3b`；原始窗口样本和时间 JSON 在 `/Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-glyph-reference-align/`。运行轮廓轻微位移/形变、刷新环箭头转动、搜索镜片尺寸细变仍可见；捕获时间是 WindowServer 帧时间，不是面板像素响应或物理 display-present FPS。
- 验证：`flutter test --no-pub --reporter compact test/glass_glyph_golden_test.dart test/glass_action_button_test.dart test/glass_motion_test.dart test/glass_theme_switch_test.dart` 42 项通过；`flutter analyze --no-pub` 无问题；`dart format --set-exit-if-changed lib/widgets/glass/glass_glyph.dart test/glass_action_button_test.dart`、`git diff --check` 通过；`flutter build macos --profile --no-pub -t lib/glass_buttons_fixture_main.dart` 成功。构建后的 AOT `App.framework/App` 时间戳晚于改动文件，并在该构建上启动 fixture 完成浅深主题和按钮静置/按下复核；fixture 已正常关闭。
- 范围：本轮依据新目标图签收三枚共享 glyph 的静态轮廓、浅深表现及一次组件级点击采样；没有覆盖 109 个生产调用点、VoiceOver、物理显示呈现、网页与 Aggregate 的同步时钟，或被删除 MP4 的逐帧匹配。UI-6.7 与 UI-6.8 继续部分验收，不能据此宣称原视频 1:1。


### 2026-11-19 UI-6.7 B012 工作台清除搜索深色 Profile 验收

- 使用 `flutter run -d macos --profile --no-pub -t lib/preview_main.dart` 启动 Aggregate 的 `PreviewRuntime` 内存样例；macOS 27.2.1、Flutter 3.47.8 stable、窗口 800×632 logical px、DPR 2。未连接真实服务。
- 所有功能页默认样例中，物理键盘输入 `Git` 后，AX 读回输入值 `Git`，标题显示 1 个功能，结果为“查看 Git 状态”。清除按钮存在且可操作；悬停窗口截图可见“清除搜索”提示。对清除按钮执行一次物理点击后，AX 读回搜索值为空，页面恢复 12 个默认预览功能。清除后图像中列表下半部受窗口可视范围裁切，但 AX 快照确认恢复 12 项。
- 截图均为 agent-desktop 按 Aggregate 单窗口捕获的 1824×1488 PNG：[输入 Git](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b012-dark-profile/search-git.png>) SHA-256 `8b6c7e32089b96b38607bdc579a8f4930e20ab2ce99dcd913772e1b554b9ccf7`；[清除按钮悬停](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b012-dark-profile/clear-hover.png>) SHA-256 `55068386880a63cb82354fd56b781db6366670c26aa6839d8875edeebf47af4a`；[清除后恢复](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b012-dark-profile/clear-after.png>) SHA-256 `088ec0748e1d7efb3a49219302ebed1c037d1c7d4ee844f6838c15219de7afb0`。
- 边界：本次深色使用的是默认 `PreviewRuntime` 目录，基数为 12；之前浅色 UI6 检查夹具的 17 项是另一份数据集，因此只比较各自“过滤后清除并恢复”的行为，不比较两夹具计数。截图仅证明静态深色外观和悬停提示，未采到可靠的按下/松开动效帧或物理 display-present。UI-6.7 继续部分验收。


### 2026-11-19 UI-6.7 B016 无匹配结果清除筛选深色 Profile 验收

- 使用 `flutter run -d macos --profile --no-pub -t lib/preview/ui6_inspection_main.dart` 启动隔离的 `Ui6InspectionRuntime`；macOS 27.2.1、Flutter 3.47.8 stable、窗口 800×632 logical px、DPR 2。所有状态均为内存预览，没有真实服务。
- 所有功能页点选“资源”后，AX 列表只剩“读取预览说明”一项；物理键盘输入 `NEVER_MATCH_4207` 后 AX 读回该值，结果进入无匹配空态。空态的“清除筛选”与搜索框内的“清除搜索”是两个不同按钮；本次按 B016 目标点击空态“清除筛选”。点击后 AX 读回搜索框为空，类型筛选复位为“全部”，页面显示“全部功能 · 17”，与清除前的夹具基数一致。
- 单窗口 1824×1488 PNG：[无匹配空态](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b016-dark-profile/no-match.png>) SHA-256 `a3b8cd81aff8e39d44951acd1306c81c2f39a99c857fcd6b13bb94d569f17c80`；[清除筛选悬停](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b016-dark-profile/clear-filter-hover.png>) SHA-256 `a4337fa3dda8738d239b75f71a5f112701e7874caa29f25511959165068f8dcb`；[点击后恢复 17 项](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b016-dark-profile/clear-filter-after.png>) SHA-256 `7ddb0f7eb6bde6daeb82df82636a139795c07f87dc4ad79bd44027c9255ac4bd`。
- 边界：截图记录深色无匹配静态样式、按钮悬停样式和清除后的列表结果；未采集可靠按下/松开时序帧或物理 display-present。Profile 在关闭时已退出；UI-6.7 仍部分验收。


### 2026-11-19 UI-6.7 B017 工作台类型筛选深色 Profile 验收

- 使用 `flutter run -d macos --profile --no-pub -t lib/preview/ui6_inspection_main.dart` 启动隔离 `Ui6InspectionRuntime`；macOS 27.2.1、Flutter 3.47.8 stable、窗口 800×632 logical px、DPR 2。使用物理点击逐项切换筛选，并在每次点击后重新读取 AX 树；按功能行的“来源”语义计数。未调用真实服务。
- 深色状态结果与浅色基线一致：工具 3、资源 1、提示 1、CLI 12；“全部”恢复 17。截图均为 Aggregate 单窗口 1824×1488 PNG：

| 筛选状态 | AX 功能数 | 截图 SHA-256 |
| --- | ---: | --- |
| 工具 | 3 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b017-dark-profile/tools.png>) `d74b609ce7531ef14148680b4a87df207db2271acc83397029cb393c8a6257cf` |
| 资源 | 1 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b017-dark-profile/resources.png>) `ed21660ee6c8b7e060a71d9a391d9fd04b799531ac8b2a12b6b717fdcef12dfe` |
| 提示 | 1 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b017-dark-profile/prompts.png>) `528008fcb2ef238cafb66c5da9f08d949e8f85e87b5b0744fff450eb1ac08e06` |
| CLI | 12 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b017-dark-profile/cli.png>) `4201cb432d6cd6646759abfe1e28ee3a0f933fcee5103a0cb62e9a9a9ec4f460` |
| 全部（恢复） | 17 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-b017-dark-profile/all-restored.png>) `48e32321d000cf006b286031219fea0fcccfb03f873adb928c11fd27af803036` |

- 边界：记录深色各筛选下的静态呈现及结果数，不代表分段按钮的点击/悬停动画逐帧验收，也不代表物理 display-present 时序。Profile 已优雅退出；UI-6.7 继续部分验收。


### 2026-11-19 UI-6.7 B013–B015 空工作区连接入口深色 Profile 验收

- 使用 `lib/preview/ui6_inspection_main.dart` 的 macOS Profile 内存夹具：B013/B014 设 `UI6_EMPTY_WORKSPACE=true` 与本机可用的 CLI、stdio MCP；B015 另外设 `UI6_HTTP_ONLY_WORKSPACE=true`。macOS 27.2.1、Flutter 3.47.8 stable、窗口 800×632 logical px、DPR 2。连接/Host 状态均为内存样例，没有真实设备、外部进程或服务。
- B013/B014 初始深色空态同时有“添加 CLI”“添加 MCP”。点击入口后出现目标选择；选择“本机 Mac（预览）”后分别读回配置表单适配器“预览 CLI”及“预览 stdio MCP”。表单默认名称由夹具预填，未改字段；CLI 程序路径为空、启动参数为 `[]`。各自点击“取消”后回到连接管理页，再进“所有功能”仍见原空工作区的两个添加入口，未保存连接。B015 HTTP-only 空态只出现“添加 HTTP MCP”；选择本机预览目标后表单适配器为“预览 MCP HTTP”，URL 与 Bearer Token 都保持空白；点击“取消”后仍可从空工作区看到 HTTP MCP 入口。
- 目标选择弹层上的全窗 `Dismiss` 静态文本会让 agent-desktop 的语义点击报告 `receives_events` 遮挡、且未发出动作；随后按可见目标中心使用 headed 物理点击，下一次 AX snapshot 确认进入对应本机预览表单。取消动作也用物理点击并经下一次 AX 状态确认返回；未点“测试连接”或“保存连接”。
- Aggregate 单窗口 1824×1488 PNG：

| 状态 | 截图 | SHA-256 |
| --- | --- | --- |
| 本机 CLI / MCP 空态 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-empty-forms-dark-profile/empty-local-desktop.png>) | `cac27a2911591255623a6ba6a1b948188f603cc7255145623963d692bc58851c` |
| CLI 预览配置表单 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-empty-forms-dark-profile/cli-form.png>) | `11d14c7ac314ac031ac9e2e24c19b86f6960f58a85b24854630d42c0b3bf4b72` |
| stdio MCP 预览配置表单 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-empty-forms-dark-profile/stdio-mcp-form.png>) | `f2f0be4e515afe34c955bf8eecbc0f969a870b84860c061f0c6cb288dfe14993` |
| HTTP-only 空态 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-empty-forms-dark-profile/empty-http-only.png>) | `986c717be553ccf7b96ce8539282ec750540124193405cebb9ceb556637e6bf2` |
| HTTP MCP 预览配置表单 | [PNG](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-empty-forms-dark-profile/http-mcp-form.png>) | `368c8019cc6cba2eb0f648e03a0b6b273f326e3d65614051aa11919c05e82ca5` |

- 边界：本轮签收深色静态空态、三个入口到对应配置表单的路由以及取消返回；不含连接测试/保存、深色按钮动效时序或物理 display-present。各 Profile 已关闭，B013–B015 继续部分验收。


### 2026-11-19 UI-6.7 B018–B021 动作编辑对话框深色 Profile 验收

- 使用 `lib/preview/ui6_inspection_main.dart` 的 `Ui6InspectionRuntime` Profile 打开“UI 检查 · Git CLI”的动作编辑器；macOS 27.2.1、Flutter 3.47.8 stable、窗口 800×632 logical px、DPR 2。连接 executable 为 `仅内存预览`，没有执行外部程序。
- B018 初次打开的清单只有 `version`。点“新增动作”后 AX 读回清单有 `action1`、预览动作下拉为“新动作 · action1”。随后使用“取消”关闭；重开并聚焦 JSON 文本框后，从 AX value 解析出的动作 ID 只有 `version`，确认草稿已丢弃，没有点击“保存动作”。
- B019 点“导入”后 macOS `Open` 面板出现；没有选择文件，按 `Cancel` 返回。B020 点“导出”后 macOS `Save` 面板出现，随后按 `Cancel`；没有选保存路径、创建或写出文件。
- B021 选中临时 `action1`，输入样例默认 `{}` 并点“检查并预览参数”；页面显示参数数组 `["仅内存预览", "--help"]` 与提示“清单有效。下方是最终参数数组；此操作不会运行程序。”源码 `_preview` 只解析 manifest/sample、展开参数并格式化结果，不调用 Runtime 执行端口。
- 单窗口 1824×1488 PNG：[动作编辑器初始状态](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-action-editor-dark-profile/open.png>) SHA-256 `053bb7c4482f1ac67e7859c979b3981340cfc3376044840c06fa4ce35c886cdb`；[新增 action1](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-action-editor-dark-profile/action1-added.png>) SHA-256 `fafe8222eaca1ba3adab59de358610927f18fdaf353888bb504fc26b4cdc9267`；[预览结果](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-action-editor-dark-profile/preview-scrolled.png>) SHA-256 `48fe41e592067f9de41354f73b009b21d448cf891d564e7d436168df5a67ec29`；[取消后重开](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-action-editor-dark-profile/reopened-clean.png>) SHA-256 `67cd60b4d43c41b1a3c3f248c0a3eb63f0f5ddfb948a673ce20e849c050f0edd`。Open/Save 面板只做 AX 出现与取消读回，没有保存面板截图。
- 边界：签收对话框静态深色样式、草稿新增/取消回滚、原生导入/导出面板取消路径及不执行的参数预览；未选文件、未写文件、未运行命令，也没有测按钮逐帧动效或物理 display-present。Profile 已关闭；B018–B021 继续部分验收。


### 2026-11-19 UI-6.7 B022–B023 动作编辑取消与保存深色 Profile 补验

- 环境沿用 `lib/preview/ui6_inspection_main.dart` 隔离 Profile、暗色主题、800×632 logical px、DPR 2。B022 取消后重开并读回动作 ID 仅 `version` 的证据为同日 B018–B021 节记录中的 `reopened-clean.png`，SHA-256 `67cd60b4d43c41b1a3c3f248c0a3eb63f0f5ddfb948a673ce20e849c050f0edd`。
- B023 新增 `action1` 后点击“保存动作”，编辑器关闭；重开并聚焦 JSON 文本框，AX value 含 `version` 与 `action1` 两项。打开“预览动作”下拉，菜单可见“查看版本 · version”与“新动作 · action1”。单窗口图 [`保存后重开的动作菜单`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-action-editor-dark-profile/saved-action-menu.png>) 1824×1488 PNG，SHA-256 `1fca1129d4e6ad2fb77546d4d67d2cfe69d6787f576609694fa653203b667006`。
- 保存实现调用 `Ui6InspectionRuntime.saveActionManifest`，只将 JSON 暂存到进程内 `_actionManifests`；Profile 已关闭，暂存数据随进程退出销毁。未选文件、未导出、未运行外部命令或访问真实服务。
- 范围：签收 B022 深色取消回滚的既有实窗证据，以及 B023 深色保存后重开可见两项动作；未采集取消/保存按钮动效关键帧或物理 display-present，UI-6.7 继续部分验收。


### 2026-11-19 UI-6.7 B024–B032 连接配置与目标选择深色 Profile

- 环境：`lib/preview/ui6_inspection_main.dart` 深色 `Ui6InspectionRuntime`，本机 macOS Profile。连接列表始终是 3 条进程内样例。Host 查找、连接测试与设置保存均由内存 stub 处理；没有连设备、读取文件、执行命令、访问网络/凭据或保存连接。
- B024/B031：目标 picker 选择“配对 Mac（样例）”，CLI 表单 AX 读回该目标；在 Host 程序名框物理键入虚构值 `git`，点击“在 Mac Host 查找程序”，页面显示“Mac Host 未找到该程序，请检查名称或授权”。两张单窗口图分别为[输入 git](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/paired-cli-host-git-input.png>) SHA `8fdecf920be58356e5fd368d19a38bca786061ef8b0799e242f5fcdbd9d98caf`、[查找未命中](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/paired-cli-host-git-after-lookup.png>) SHA `b99e98049b4e6eac69221a3d0b5825cb2996d6d900f06639f0df180b45832252`。Host stub 返回 `null`，不会启动本机或远端程序。
- B025/B030：深色目标选择器图[`target-picker.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/target-picker.png>) SHA `b041e796f9d549a0a5eda75b5e39e44961a6dfa07c72adfa5dcf2c46e2643a66`；本机 Mac 表单图[`local-cli-form.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/local-cli-form.png>) SHA `8c743fcc75cf10e59025143c87e2d7bfda28c65d7474145f8753aa4ded6486f8`。点击程序路径的文件选择按钮后系统 Open sheet 出现，按 Cancel 退出；未选文件或读取内容。原生面板未截图，避免保存系统文件列表。
- B026/B027：只在表单内输入虚构路径 `/tmp/ui6-preview-cli` 并点击“测试连接”。stub 返回“已通过：预览安全检查。未访问本机命令、网络或凭据存储。”AX 读回“保存连接” enabled=true，但没有保存。测试前图[`local-cli-test-input.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/local-cli-test-input.png>) SHA `dfd244d96d9bb07ad2cfd7fa4df4b33b130821ffbd370cd661865ea8e1c280b3`；通过与按钮启用图[`local-cli-test-passed.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/local-cli-test-passed.png>) SHA `221f9960dff4bf28f4842b6c5115613b28e8b0ff73a35dbd9a62836d8d75319c`。
- B028：窗口请求尺寸 540×700pt 后进入全屏紧凑表单，AX 可见“关闭添加连接”。单窗口截图[`compact-form.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/compact-form.png>) 为 1304×1624 PNG，SHA `9d037734f1f046767a3ba36ef21d6de339cb9b2d461b364d6be248630d8e3ab7`。点击关闭后表单消失，未保存草稿。B029 深色取消按钮已由同日 B013–B015 本机 CLI、stdio MCP 和 HTTP MCP 表单取消返回的实窗路径覆盖（对应截图见上方记录）。
- B032：目标 picker 按 Escape 后消失；回到连接管理页，AX 仍读回 Git CLI、MCP、音乐 3 条样例，没有新连接。回到列表截图[`connections-after-cancel.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/connections-after-cancel.png>) SHA `e12c69c026db8010430d662a61cabf90066445a4e09e51fba04f09415cef4c87`。
- Profile 已通过 Flutter `q` 正常退出，并确认 Aggregate 与 `ui6_inspection_main` runner 均无残留。范围：签收 B024–B032 这些深色配置和路由状态；没有签收按钮动效逐帧或物理 display-present，UI-6.7 继续部分验收。


### 2026-11-19 UI-6.7 B033–B043 连接详情深色紧凑布局验收

- 环境：`lib/preview/ui6_inspection_main.dart` 的隔离 `Ui6InspectionRuntime`，macOS Profile，深色主题。窗口由 800×632 调至 540×700 logical px 验收紧凑分支；完成后恢复 800×632 并通过 Flutter `q` 退出。Host/连接/动作清单均为进程内样例，没有真实设备、文件、网络、命令或凭据访问。
- B033/B034/B042：Git CLI 详情点击“删除连接”显示暗色确认框；截图[`git-delete-confirm.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-rows-dark-profile/git-delete-confirm.png>) SHA-256 `664da789cc1ffc3eac5c139fea95f5202eaf5daea729f63aa19a5aae7d1dda56`。危险“删除”按钮可见但没有点击；取消按钮先通过 Escape 收起，再用按钮实际点击重新核对，确认后返回原详情；Git CLI 仍在。取消后的截图[`git-delete-after-cancel.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-rows-dark-profile/git-delete-after-cancel.png>) SHA-256 `678fc78e5038bce6e6975586a20bc3a28ca5d2f4ad69aca35e26bb21f34af3d5`。
- B035/B036/B043：添加连接目标选择器及配置入口沿用同日 B024–B032 的暗色[`target-picker.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-setup-dark-profile/target-picker.png>)。暗色紧凑 Git CLI 详情的操作区见[`git-detail-actions.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-rows-dark-profile/git-detail-actions.png>) SHA-256 `18f7577fcd8338472865ef1acd0ee9a654752cd8ca3c923c00ed8e2d8dbdc023`；点击“返回连接”后 AX 重新读回 Git CLI、MCP、音乐三行。
- B038/B039：首行 Git CLI 的上移图标在暗色截图里呈灰暗禁用外观，源码按 `selectedIndex > 0` 提供 `enabled=false`；agent-desktop 的 `states` 属性为空，故没有据其宣称原生 AX disabled 已通过。点击下移后 AX 列表顺序为 MCP、Git CLI、音乐；截图[`connections-after-move.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-rows-dark-profile/connections-after-move.png>) SHA-256 `676ef32bec4388633b6776165b4e4f135120cfe19ebae4b060c6ad55da5a4eef`。再点击上移恢复 Git CLI、MCP、音乐；截图[`connections-restored.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-connection-rows-dark-profile/connections-restored.png>) SHA-256 `ede406ff2698318b44d263f404ac306c6d88b36fe304470bfe78ef690378c6c1`。顺序只在内存 fixture 中变更并已复原。
- B040：从 Git CLI 详情打开动作编辑器，AX 显示已有 `version` 项；点击“取消”返回同一连接详情，未保存。暗色编辑器静态、草稿取消与保存的对照见上方 B018–B023 记录。
- B041：打开 MCP 详情并点击“测试连接”；操作前后 AX 均显示同一 MCP 详情、`preview.invalid`、样例日期 `2026-07-28` 与 5 项能力。`Ui6InspectionRuntime.refreshConnection` 只返回 `_findConnection` 的内存对象，没有执行真实刷新或网络请求。
- `compact-list.png` 作为初始暗色紧凑列表记录，SHA-256 `8fc9fed84bf04c65233e9c4fec2a434e027f915a0a581476b667e43607a38078`。Profile 已正常退出，退出后没有 Aggregate 或 `ui6_inspection_main` runner 进程。仅更新验收文档，没有产品代码变化或运行测试。
- 边界：本批补签暗色连接删除取消、重排可逆、动作编辑取消、MCP 内存测试和返回路由；删除没有确认执行。上移按钮的视觉禁用态有截图和源码条件，但 AX disabled 状态未读到。没有捕获按钮按下逐帧动画或物理 display-present，UI-6.7 继续部分验收。
