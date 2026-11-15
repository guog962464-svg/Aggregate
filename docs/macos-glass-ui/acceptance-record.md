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
| 结果 | 自动化、键盘、语义、参数保护、reduced motion、放大文字与两种 DPR 的页面布局回归通过。主题开关焦点边框现由 Widget 回归确认绘制在 artwork 前景。UI-5.7 的系统 VoiceOver 语音走查未完成；不以自动化结果代替这些证据。 |
| 环境 | MacBook Pro，Apple M5 Pro，24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7；Xcode 27.2；内置 Liquid Retina XDR，逻辑 1512×982 点、60 Hz、DPR 2。App 自动化运行于 Flutter test；原生 AX 树抽查使用 Profile `Aggregate.app`。 |
| 页面矩阵 | `app/tool/ui_review_test.dart` 固定 `ManualGlassMotionClock`，以 `FakeAccessibilityFeatures(disableAnimations: true)` 固定装饰相位但保留路由动画。800×600、1024×768、1440×900 × 浅/深 × DPR 1/2 × 9 个音乐/连接/设置/目录/运行预览状态；DPR 1 用 `work/ui-review/` 的 54 张金样比对，DPR 2 同样走完整路由和布局错误检查。12 项通过。图像使用测试字体，中文字符可能呈方框，仅用于结构与路由回归；不能作为中文字体验收。原生 Profile 窗口已目视确认中文可读，但 CUA 截图未导出归档。 |
| 组件覆盖 | `glass_action_button_test.dart` 检查所有点阵在浅/深主题和 DPR 1/2 的绘制、200% 文字操作、Enter 激活、Tab/Shift-Tab 顺序和回调次数。完整 UI-2 glyph golden 仍在原阶段验证；UI-5 的整页面金样没有 DPR 2。`accessibility_test.dart` 以 token 组合覆盖浅深材质端点的文字/图形目标；不含 shader 像素读回。 |
| 键盘与安全 | `widget_test.dart`、`capability_run_page_test.dart`、`glass_action_button_test.dart` 验证 ⌘K 搜索焦点、⌘↵打开确认但不执行背景任务、显式确认一次、Esc 取消并恢复输入焦点、Enter 激活一次及 Tab 顺序；相关断言通过。 |
| 原生语义 | Profile 原生 AX 树确认设置主题按钮值、搜索入口、导航项、音乐控制、清空操作和 Mac Host 控件的可读名称/状态。未启用系统 VoiceOver，也未听取或记录 VoiceOver 实际朗读顺序。 |
| 对比度边界 | 修正深色 muted token 后，`accessibility_test.dart` 的静态色值对比断言通过。2026-11-15 新增真实 macOS Profile 设置页合成像素样本，浅/深主题的正文对比度为 10.16:1 / 14.27:1，主题按钮标签为 7.47:1 / 4.74:1，当前太阳/月亮点阵核心为 7.65:1 / 4.93:1。按 sRGB 线性亮度与局部材质采样计算；深色截图 [settings-dark-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-dark-profile.png) SHA-256 `ab5379655f333d9e9b26232349711c9b8cf5171bd24a8139a994bb6e76644554`，浅色截图 [settings-light-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-light-profile.png) SHA-256 `56aaf4a3e1b000112ef0f56f8f7f6a5c4813f011b5c988bc7de85cd85aafaa96`。选中态光弧探索性局部亮度比为深色 2.32:1、浅色 1.15:1；该弧目前仅作次要装饰，非键盘焦点环或唯一状态提示。主题开关原焦点边框绘制在会覆盖它的 artwork 下方；现已用前景绘制层修正，并由 Widget 回归验证 2px 主题色边框存在且在前景。焦点环现已完成浅深主题的原生合成像素抽样并达到 3:1 目标；中间态、禁用态及其他页面材质仍未完成，UI-5.5 继续部分验收。 |
| 测试 | `flutter analyze --no-pub`：无问题；`flutter test --no-pub test`：272 项通过；`flutter test --no-pub tool/ui_review_test.dart`：6 项通过；`dart format --output=none --set-exit-if-changed app/lib app/test packages spikes/phase0/bin`：230 文件无变化；`sh spikes/phase0/check_boundary.sh`：通过；公共包 `dart test ...`：15 项通过；`flutter build macos --debug --no-pub`：成功。 |
| 完整脚本 | `sh tool/check.sh` 在工作树现有锁文件下退出码 65，因为 `flutter pub get --enforce-lockfile` 会改动 106 个依赖。为不改写该文件，另将已提交的 `HEAD:pubspec.lock` 临时放入验证工作树，原样运行完整脚本：退出码 0，格式、分析、公共边界、15 项公共包测试、272 项 App 测试与 macOS Debug 构建全通过；结束后逐字节恢复原锁文件。当前保留锁文件 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未纳入阶段提交。 |
| 真实服务 | 未连接真实连接、Host、账号或外部服务；所有状态/错误回归均由 Preview Runtime 或 mock Runtime 覆盖。 |
| 提交 | `f453980dc5a8dcf6d7b589ff4e7ecdc432013553`，`完成 macOS 玻璃 UI 功能验收`。 |

## UI-6：原生性能与最终验收（部分验收）

| 字段 | 记录 |
| --- | --- |
| 项目 | UI-6.1～UI-6.12 |
| 结果 | 已测的浅/深色静置、刷新/复制/添加、播放控制和 800/1024/1440/1512 logical px 固定宽度滚动交互子场景，各自三轮活动窗的 build/raster P95 均低于 16.667 ms，超预算比例低于 1%。本轮修复页面栈在窗口尺寸变化时被重复创建的问题；24 个 CLI 样本连接下，800↔1440 logical px 原生连续缩放完成三轮，build/raster P95 均低于 13.9/9.9 ms，超预算比例均低于 0.3%。宽度场景未见 >100 ms build/raster 帧；一次隐藏恢复样本出现 102.132 ms raster，重复轮为 24.851 ms。主题开关在 1024 宽另完成三轮、每轮 18 次深浅端点往返拖动，AX 值逐次交替且帧时达标；UI-0 同机端点点击基线也完成三轮，帧时数据已对照。另完成 20 轮页面往返与 RSS 时间序列。本轮新增活动页惰性列表，并完成工作台、连接、活动、设置四页与连续窗口缩放联合负载三轮；build/raster 帧时均达门槛。随后对七个长列表/表单场景各做三轮 Profile 滚动，六类场景无 >100 ms 帧；90 字段表单首组三轮中一轮出现 112.742 ms build 峰值，三轮补充滚动未复现，仍作为未定位的间歇性异常保留，未标通过。精确原生手势时序/取消对照、生命周期对象审计、像素/关键帧对照与用户视觉签收仍待完成；生产页面双主题静态截图样本已归档但未逐项签收，因此 UI-6 保持部分验收。 |
| 环境 | MacBook Pro Apple M5 Pro、24 GB；macOS 27.2；Flutter 3.47.8 stable、Dart 3.13.7、Xcode 27.2；内置 Liquid Retina XDR，1512×982 logical px、60 Hz、DPR 2。既有窗口样本为 800 与 1512 logical px；本轮另测 1024×632 和 1440×632 logical px 固定窗口。1440 宽实际 NSWindow frame 由临时原生诊断日志确认；诊断代码已恢复，未保留在提交中。 |
| 运行方式 | 临时 `lib/ui6_profile_main.dart` 启动生产 `AggregateApp`，运行时由 `Ui6ProfileRuntime` 返回合成数据：24 个 CLI 连接、1 个 MCP 连接、1 个本地音乐样本连接、90 个 CLI 能力、60 个 MCP 工具、2 个音乐能力和 60 条活动记录；不启动外部进程、不访问网络、不触达真实连接、账号或 Host。窗口扫宽使用临时 Runner frame 注入，测试后恢复 `MainFlutterWindow.swift`；临时入口、Runtime 和原生诊断均未提交。 |
| 回归检查 | 首轮活动页/工作台子阶段全量 `flutter test --no-pub` 274 项通过；2026-11-15 后续连接首页与管理连接惰性列表变更后全量 279 项通过，音乐搜索长列表加入后 281 项通过，运行参数表单加入后 282 项通过；主题 450 ms 实时指针及取消恢复用例后全量 284 项通过；焦点环前景层回归后全量 285 项通过，`flutter analyze --no-pub` 无问题。活动页惰性构建回归曾在旧实现上失败（屏外第 60 条已构建），改后通过；连接首页 90 项桌面/紧凑目录、管理连接页 90 个连接/能力的桌面/紧凑滚动回归均通过；音乐搜索 90 首桌面/紧凑宽度滚动和对应播放回调、原有短结果无障碍语义回归均通过；参数表单 90 字段回归覆盖屏外必填校验、滚动后行内提示和最终参数值。主题焦点测试将 `FocusManager` 固定为传统键盘焦点模式，确认焦点边框存在并置于绘制前景；未采集更新后的原生焦点图像。Widget 回归仅证明构建边界、行为和可达性；新增长列表场景的帧时见下方原生 Profile 记录。 |
| 采样 | `app/tool/sample_theme_switch_frames.cjs` 监听既有 Mac Profile VM `Flutter.Frame` 事件；没有更改 Profile flags。帧时轮次录 40 秒，按首帧后的 5–35 秒选取 30 秒活动窗。1024/1440 结果逐轮列于下方；1440 滚动第三轮在 29.783 秒活动窗内记录 932 帧，其他宽度滚动轮次约 1,795–1,800 帧；主题拖动三轮均为 1,800 帧。隐藏恢复轮次记录约 12.9 秒无帧空档。七类长列表/表单在临时 worktree（被测源码基线 `7d28c476ec4094784c39053c303c0abe7d29bb8b`）的 Profile `PreviewRuntime` 夹具中另采三轮：每轮录 40 秒、首帧后 5–35 秒活动窗，主动滚动约 30 秒；其中参数表单一轮只有 1,502 个活动窗帧，另两轮各 1,800。夹具用本地合成数据，不接服务；原始 JSON 保存在本机 `/tmp/aggregate-ui6-schema-profile/`（权限 0600，不随提交）。JSON `protocolErrors=0` 且未断连。指标是 Flutter build/raster 提交帧，不等于显示器实际呈现 FPS；临时 VM URI 不归档。 |
| 负载 | 静置样本覆盖完整工作台的 12 类按钮及浅/深色，各三轮。浅色刷新、复制、添加分别三轮。播放/暂停、上一首/下一首、停止与切页循环三轮，每轮约 31.6–31.8 秒、5 组循环/31 次按钮动作，以本地 Preview 数据运行。原有滚动/缩放三轮在 800↔1512 logical px 之间操作；本轮另以 1024、1440 固定窗口各做三轮、约 30 秒目录长列表往返滚动，穿插设置/管理连接/活动/音乐页切换。另以独立 Profile 夹具分别滚动工作台 92 项、连接首页单连接 91 项能力、管理连接 90 个连接、管理连接明细 91 项能力、活动 60 条、音乐结果 90 首和运行参数表单 90 字段。原有 800 宽主题端点切换三轮各 26 次；1024 宽另做三轮每轮 18 次端点往返拖动，AX 深浅状态逐次交替，当时未能通过 CUA 控制精确 450 ms 手势时长，也未执行拖动取消；2026-11-15 后续在隔离 Profile 实窗用 `agent-desktop drag --duration 450` 分别请求浅→深、深→浅各一次，两方向 AX 端点均符合预期，命令级总耗时为 811/822 ms。该轨迹只记录命令边界，不含每个指针事件的时间戳，故不能证明实际输入节奏恰为 450 ms；原生取消仍未执行。修复后联合负载每轮在 800↔1440 logical px 扫宽时往返滚动工作台、管理连接、活动、设置四页 40–44 个 down/up scroll pair；每页每轮至少两次 AX 路由校验。 |
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
| 生命周期与内存 | CUA 明确隐藏并 Raise 恢复两轮，各观察到约 12.9 秒 Flutter.Frame 空档；一轮恢复后的 raster 为 102.132 ms，重复轮为 24.851 ms，故原生 lifecycle 只记部分验证。`flutter test --no-pub test/glass_motion_test.dart test/glass_theme_switch_test.dart` 定向 18 项通过，覆盖 `TickerMode`、应用 lifecycle 暂停/恢复、完全离屏注销、reduced-motion 注销并保留点击，以及主题开关 reduced-motion snap；原生离屏/reduced-motion 设置未覆盖。另完成 20 轮页面往返（每轮“所有功能→管理连接→活动→设置”，共 80 次导航）。进程 RSS 约 176 MiB 起、页面循环中升至约 203 MiB、循环结束约 199 MiB；随后 30 秒静置在约 195–208 MiB 波动，未见单向增长。源码所有权审阅核对了 `GlassMotionScope` 单共享 Ticker/timers/lifecycle listener、按钮 motion/state controllers、主题开关 Ticker/FocusNode、主题 artwork 的 shader 与两张 `ui.Image`、窗口背景 shader/frame 的 dispose 路径；SDK 对 `FragmentProgram.fromAsset` 持有进程级缓存。RSS 与源码审阅都不能代替原生 controller/图像对象数量，恢复帧 >100 ms 原因仍未定位。 |
| 原生视觉与动效 | CUA 实窗观察到深色月亮态、浅色太阳态与一次中间拖动态；中间态显示了点阵内部变化、背景过渡与局部光弧。12 类 dot glyph、背景连续性及主题 AX 值均可见。1024 宽三轮往返拖动各 18 次，AX 状态 54 次逐次交替；另用方向键确认 AX 值可在深/浅端点间切换。2026-11-15 另导出同一 Profile 设置页的深浅窗口 PNG，实际 sRGB 像素抽样中正文、主题按钮文字和活动点阵核心均达到对比度目标；图像和哈希见上一行。Widget 指针回归覆盖 450 ms 拖动期间的中间态、抬手才提交以及中途取消恢复原端点。焦点环现按主题开关轨道尺寸/圆角绘制于 artwork 前景，Widget 检查其 2px 线宽、中心和几何尺寸；真实键盘焦点 Profile 实窗的浅/深主题合成像素最低对比度为 3.30:1 / 3.93:1，截图及 SHA-256 见后续焦点环记录。按钮 fixture 截图 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-buttons-fixture-disabled.png` 可见复制按钮灰化。2026-11-15 在隔离 Profile 最小夹具中对照玻璃按钮、裸 `Semantics`、语义包裹 `TextButton` 和普通禁用 `TextButton` 四种控件：Flutter Widget Semantics 均报告 `isEnabled=false` 且没有 tap action，但 `agent-desktop` 与直接 `AXUIElementCopyAttributeValue(kAXEnabledAttribute)` 均读到 `AXEnabled=true`。当前 Flutter 3.47.8 / Engine revision `cf636b1dfb` 的桌面 `AccessibilityBridge::SetStateFromFlutterUpdate` 未将 `is_enabled=false` 映射为 `Restriction::kDisabled`，macOS `AXEnabled` 则根据该 restriction 计算；故确认是 engine 桥接缺口，当前应用层 Semantics 结构不是原因。Flutter 官方主干已有相应转换（[bridge](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/common/accessibility_bridge.cc#L2297-L2304)、[macOS AX 映射](https://github.com/flutter/flutter/blob/master/engine/src/flutter/third_party/accessibility/ax/platform/ax_platform_node_mac.mm#L3239-L3244)），本机稳定版仍缺此转换。原生禁用语义未通过，需待使用包含修复的稳定 engine 后重验。视频帧对照页 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/theme-switch/stage6-keyframes.html` 展示原视频帧和 fitted Flutter 渲染的 9 组位置样本，包括静置、近似 0.25/0.5/0.75/1 和视频实际的部分反向轨迹；反向段约从 0.77 到 0.08 后再次前进，图像是离线逐帧对照，不是生产 macOS 实窗录屏。按钮尺寸/状态 fixture 现已在浅深两主题归档；生产页面 Profile 静态样本见下节。焦点环合成像素对比已通过。2026-11-15 的原生双向主题拖动以 450 ms 参数请求并成功抵达浅/深 AX 端点，但 811/822 ms 是整条 agent-desktop 命令耗时，未采集指针事件级时间戳；原生取消对照与最终用户签收仍未完成。 |
| 按钮样式/尺寸双主题 Profile fixture | 隔离 bundle `io.github.guog962464.aggregate.ui6focusafter`，macOS Profile，800×600 logical px 内容区、截图 scale factor 2。深色：`/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-all-buttons-profile.png`、`stage6-all-buttons-profile-scroll-1.png` 至 `scroll-5.png`；浅色：`stage6-all-buttons-profile-light-top.png`、`stage6-all-buttons-profile-light-glyphs.png`、`stage6-all-buttons-profile-light-states.png`、`stage6-all-buttons-profile-light-states-2.png`、`stage6-all-buttons-profile-light-states-3.png`。覆盖 12 类 96dp glyph reference、primary/secondary/icon/playback/reference 五种尺寸，以及 navigation/segmented/danger/busy/disabled 状态；临时 fixture 以浅色初始值构建以便导出，未改生产入口/偏好。截图记录静置材质样貌，不代表原生 click 动画逐帧或生产页面覆盖。选择截图 SHA-256：深色首屏 `9de4825c0fbb60593006ce8c399022bc5f8330ef59a4ec57bd1fd2094130aa66`，深色状态 `a7a9fcbbbb87b083c18d0cb921f30606d597bdf4dbed5b299d1748b19f6f6c33`，浅色 glyph `b7bcee23123f056e97576508187d75697828269ba5a17cedc0242347af30f7a4`，浅色状态 `eae16cdb21decc8b33682fe1f8f935e8644722fcfcb77abf68290a746118fb60`。 |
| 结果边界 | UI-6.1 的固定宽度目录滚动、1024 主题拖动、800↔1440 连续缩放、工作台/连接/活动/设置四页联合滚动缩放及七类长列表/表单均有三轮 Profile 数据；90 字段表单原始三轮有一轮超 100 ms build 长帧，另补三轮未复现，原因未定位。450 ms 实时指针序列和取消已由 Widget 回归覆盖；原生实窗双向拖动以 450 ms 参数请求后 AX 状态正确，精确事件时序和取消仍未完成。UI-6.2 的宽度/主题/连续缩放与六类长列表场景无 >100 ms build/raster 帧，但表单原始样本和隐藏恢复各有一次超过 100 ms 的帧，表单另三轮未复现；帧数据不证明实际显示呈现 FPS。UI-6.3 已完成 UI-0 同机端点点击基线与当前拖动场景的方向性对照，输入不完全相同；视频关键相位已有离线对照，真实呈现 FPS 未验证。UI-6.4 有对应 Widget 覆盖但原生恢复长帧未定位；UI-6.5 完成资源所有权审阅但无原生对象数。UI-6.6/6.7/6.8 仍部分通过，UI-6.9 待用户复核，UI-6.10 尚未完成。 |
| 变更范围 | 修改共享 Flutter 页面栈布局、主题开关焦点环的绘制层级、玻璃按钮的可见性复核调度、工作台长目录、连接首页/管理连接长目录与能力明细、音乐长搜索结果、活动长列表和大型运行参数表单的惰性构建；表单校验覆盖全部 schema 字段，没有改 Android 专用代码、主题模拟/校准算法、Runtime 协议、主题映射或切换逻辑。临时 Profile fixture、Runner 窗口注入和诊断分支均已清理。`pubspec.lock` 保留任务前 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 提交/远端 | 首次 UI-6 报告提交 `98749bb2536420c3e43acd6a4f3409ccac608bcf` 只包含验收文档；既有工作台/活动子阶段提交 `fd11345ff311a52eaf1bce9d180498b001729be1`。本轮 90 字段参数表单实现、回归与验收记录提交 `490d13d390e3b6521e07e63e8e2ddddff75899ec`；主题开关焦点环绘制层级修正另提交 `fa4e90ec55a612af39729840f499c1b39b535e5e`，GitHub 与 Gitee 分支均核对为该 SHA。后续生命周期和资源所有权审阅继续只按其实际证据记为部分验证，该性能子任务交付不代表 UI-6 或整套 UI 适配已完成。

## 后续阶段

UI-0～UI-5 已按阶段独立提交；未通过的对比度与 VoiceOver 项仍保留为限制。UI-6 新增联合滚动缩放三轮、活动页长列表性能回归、UI-0 同机方向性基线、隐藏恢复观察和 RSS 页面循环证据；完整生命周期资源/动效证据、像素对照与用户主观签收仍为待办，阶段仍未交付。

### 2026-11-15 生产页面双主题实窗抽查

- 构建：macOS Profile，入口 `lib/preview_main.dart`，隔离 bundle `io.github.guog962464.aggregate.ui6focusafter`。使用 PreviewRuntime 本地合成数据，不加载真实账户、连接或 Host。产品代码来自 `931008b340bc9c42abf3d1741e00876ac548c28b`；临时 bundle 配置只用于隔离应用身份。主题开关文件与当前工作区一致。
- 视口：窗口 AX bounds 为 800×632 logical px；导出 PNG 为 1824×1488 像素。每页采集浅/深主题首屏，共 10 张；所有功能与设置页各补底部滚动样本，共 4 张；另采设置页深色侧栏焦点和主题开关焦点样本，共 3 张。合计 17 张。
- 生产页面样本能核对工作台、所有功能、管理连接、活动、设置五页的主要材质、页面层级和控件位置。截图均为静置状态，不能证明页面内全部按钮实例已逐项复核，也不构成点击动画逐帧、帧呈现率、VoiceOver 或最终视觉签收。
- 证据目录：`/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-production-pages/`。文件与 SHA-256（`shasum -a 256`）：

| 截图 | SHA-256 |
| --- | --- |
| `activity-dark-top.png` | `e7ed2dafdf3620e55b4ba196585ba1bccb30eeea23151d7a69fcb8bb2d480c8b` |
| `activity-light-top.png` | `dfa1a3befe41a32bffe4e77a5b5f311098842b65caf3236f5f6868a892d7ac5f` |
| `all-functions-dark-bottom.png` | `2bb661cdc1ded614832dfc38cb04f4392d012bf60c0e2af0f05e739b82e605c7` |
| `all-functions-dark-top.png` | `4f0f6e10f499282813d2b1c59e86d6f74dd9d490f0fb3f5d951c034545a998f6` |
| `all-functions-light-bottom.png` | `68d93e6792d580c6021d686d7ed67c7210abf386960591d5c3f5b6c521c68d64` |
| `all-functions-light-top.png` | `821476fac8c4699675f956e2cae58078c050cf5c04b14eada4c4e8e4d3a2d41f` |
| `home-dark-top.png` | `9203e86fc7ef4c772698230f714af109080d85f67be0b1adc95cf1a272c06904` |
| `home-light-top.png` | `6eb6c40791bc11a371f4e6df4a9ba9a068ea19f5ce29a7d004fb8375c71fe3d5` |
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
- 状态：生产页面静态截图抽查完成；UI-6 仍部分验收。禁用态原生 AX 语义、精确原生拖动事件时序/取消、间歇性长帧原因、原生资源对象数量及最终视觉签收仍待补齐。焦点环浅深主题合成像素对比已通过下方新记录。

### 2026-11-15 VoiceOver 增强树复测

- 环境：macOS 隔离 Profile 探针；VoiceOver 在系统设置中从关闭切到开启，并确认应用原生属性 `AXEnhancedUserInterface=1` 后再查询。3.47.8 / Dart 3.13.7 / Engine revision `cf636b1dfb`；测试入口和依赖修改均在 `/private/tmp/aggregate-ui6-focus-after`，未改本仓库文件。
- 探针含一个禁用 `GlassActionButton`、一个 `Semantics(enabled: false, button: true)` 包裹的禁用 `TextButton` 和一个可用 `TextButton`。屏幕上三者均可见；增强 AX 树提供四个按钮节点（语义包装节点与其子节点重复暴露同一标签）。直接读取 `kAXEnabledAttribute` 时四个节点全部为 `true`，`agent-desktop` 快照也没有禁用状态；这确认了 3.47.8 当前构建下的禁用态原生 AX 失败，而不是只在 VoiceOver 关闭时出现的空树假象。
- 同一夹具用 Flutter 3.50.0 / Dart 3.14.0 / Engine revision `371f77202a` 补做对照。VoiceOver 开启、`AXEnhancedUserInterface=1` 时，两个禁用语义节点在 AXChildren 中存在，但 `AXRole` 及名称属性不可读；`agent-desktop` 仅识别可用按钮。3.50.0 因而也未通过此项，不能仅凭 bridge 源码变更认定语义已修复。
- 已在系统设置关闭 VoiceOver，退出并重新启动隔离探针；复核开关为关闭且新进程的 `AXEnhancedUserInterface=0`。本次没有录制/验证实际朗读音频，因此不把它记为 VoiceOver 语音走查通过。没有修改 Flutter 页面、切换按钮逻辑或生产配置；`pubspec.lock` 继续保留原工作区用户修改并未纳入任务。
- 结论：UI-6 禁用态原生语义仍失败；应用层 Widget Semantics 测试不能代替 macOS engine AX 导出结果。需要项目采用经实机 VoiceOver 验收通过的 Flutter engine 后再关闭该缺陷。


### 2026-11-15 浅深主题焦点环合成像素验收

- 构建：隔离 bundle `io.github.guog962464.aggregate.ui6focusafter` 的 macOS Profile；项目 Flutter 3.47.8 / Dart 3.13.7，PreviewRuntime 本地合成数据。窗口 AX bounds 800×632 logical px，DPR 2，导出 PNG 为 1824×1488。通过物理 Tab 到达主题开关焦点，使用左右键切到浅/深端点；焦点状态由实窗完整轨道环可见性与 AX 主题值复核。
- 复测发现原浅色 `glow` 焦点色对玻璃轨道的局部对比未达到 3:1，新增 `GlassDesignTokens.focusRing`：浅色 `#6F3C0D`，深色 `#8B9AFF`。主题开关轨道环与所有玻璃按钮焦点描边共用该语义令牌，太阳/月亮模拟、拖动积分、键盘映射及偏好逻辑没有改动。
- 像素方法：将 PNG 颜色解码为 sRGB 线性相对亮度，在焦点环上、下、左、右直线段各取环像素，并分别与环的内、外相邻材质像素比较；报告 8 组局部比值中的最小值。浅色最低 `3.30:1`（下侧内缘）；深色最低 `3.93:1`（下侧内缘），均高于本项目 3:1 目标。此项只验证静态端点下焦点提示，不覆盖主题拖动中间帧、其他 focus style/材质或 VoiceOver 语音。
- 浅色焦点样本：[settings-light-focus-ring.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-focus-contrast/settings-light-focus-ring.png)，SHA-256 `ea0cd5ce04019ad4c08f1236c3b37f73240bf31d0defc17c222d98d58e0b9ea1`。深色焦点样本：[settings-dark-focus-ring.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-focus-contrast/settings-dark-focus-ring.png)，SHA-256 `af193d0d74499c8a4aef964709b03d9b21b8cb77cd1949629de13b667ad1451b`。
- 验证：`flutter test --no-pub` 全量 286 项通过（含新增 focus ring token 对比测试）；`flutter analyze --no-pub` 无问题；macOS Profile 构建成功；`git diff --check` 通过。本次复测只运行隔离包，未接触正式账户、连接或 Host。
- UI-5.5 / UI-6.6 仍为部分验收：普通文字/端点按钮样本和焦点环目标已达成，中间态、禁用态及其他页面材质的完整合成矩阵仍未完成；UI-6 其他原生性能、资源数量、VoiceOver 与最终视觉签收项不因本记录而关闭。

### 2026-11-15 原生主题双向 450 ms 参数拖动

- 构建：隔离 Profile 应用 `io.github.guog962464.aggregate.ui6focusafter`，本地 PreviewRuntime 设置页；没有连接真实账户、服务或 Host。
- 输入：在 macOS 屏幕逻辑坐标上运行 `agent-desktop drag --headed --duration 450 --drop-delay 0`，浅色滑块中心 `(896,588)` 拖至深色端点 `(816,588)`，再从深色端点反向拖回浅色。两条 trace 分别记录命令总耗时 `811 ms` 和 `822 ms`；工具报告 `physical_synthetic` pointer drag succeeded。
- 结果：浅→深后辅助树读到 `外观主题=深色`；深→浅后读到 `外观主题=浅色`。Trace 文件为 `/private/tmp/aggregate-ui6-focus-after/native-drag-light-to-dark.jsonl` 和 `/private/tmp/aggregate-ui6-focus-after/native-drag-dark-to-light.jsonl`。
- 边界：`450 ms` 是输入请求参数，trace 的总耗时含事件生成、分发和命令处理开销；trace 不含逐个指针事件时间戳，故不能据此断言系统接收的拖动序列精确持续 450 ms。两次都是完整释放手势，没有触发 native pointer cancel。另一次 1,600 ms 拖动期间尝试发送 Escape，但设置页没有卸载，拖动仍正常释放并切换主题；不将其记作取消通过。Widget 回归仍是取消恢复端点的现有证据；UI-6.1/6.3/6.8 继续部分验收。
- 这次只补充验收记录，没有修改产品源码或主题切换逻辑。
