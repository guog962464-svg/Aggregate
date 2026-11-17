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
| 页面矩阵 | `app/tool/ui_review_test.dart` 固定 `ManualGlassMotionClock`，以 `FakeAccessibilityFeatures(disableAnimations: true)` 固定装饰相位但保留路由动画；在 `setUpAll` 预加载主题开关 shader，使六个测试用例共享已完成的加载 Future，不在各自的异步测试区内等待。800×600、1024×768、1440×900 × 浅/深 × DPR 1/2 × 9 个音乐/连接/设置/目录/运行预览状态；DPR 1 用 `work/ui-review/` 的 54 张金样比对，DPR 2 同样走完整路由和布局错误检查。12 项通过。2026-11-17 按实际 shader 渲染更新了 5 张设置页金样；第六张 800×600 浅色设置金样本次已与稳定截图一致，无需改动。逐张检查六种设置页尺寸/主题后，主题控件均正常显示。图像使用测试字体，中文字符可能呈方框，仅用于结构与路由回归；不能作为中文字体验收。原生 Profile 窗口已目视确认中文可读，但 CUA 截图未导出归档。 |
| 组件覆盖 | `glass_action_button_test.dart` 检查所有点阵在浅/深主题和 DPR 1/2 的绘制、200% 文字操作、Enter 激活、Tab/Shift-Tab 顺序和回调次数。完整 UI-2 glyph golden 仍在原阶段验证；UI-5 的整页面金样没有 DPR 2。`accessibility_test.dart` 以 token 组合覆盖浅深材质端点的文字/图形目标；不含 shader 像素读回。 |
| 键盘与安全 | `widget_test.dart`、`capability_run_page_test.dart`、`glass_action_button_test.dart` 验证 ⌘K 搜索焦点、⌘↵打开确认但不执行背景任务、显式确认一次、Esc 取消并恢复输入焦点、Enter 激活一次及 Tab 顺序；相关断言通过。 |
| 原生语义 | Profile 原生 AX 树确认设置主题按钮值、搜索入口、导航项、音乐控制、清空操作和 Mac Host 控件的可读名称/状态。未启用系统 VoiceOver，也未听取或记录 VoiceOver 实际朗读顺序。 |
| 对比度边界 | 修正深色 muted token 后，`accessibility_test.dart` 的静态色值对比断言通过。2026-11-15 新增真实 macOS Profile 设置页合成像素样本，浅/深主题的正文对比度为 10.16:1 / 14.27:1，主题按钮标签为 7.47:1 / 4.74:1，当前太阳/月亮点阵核心为 7.65:1 / 4.93:1。按 sRGB 线性亮度与局部材质采样计算；深色截图 [settings-dark-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-dark-profile.png) SHA-256 `ab5379655f333d9e9b26232349711c9b8cf5171bd24a8139a994bb6e76644554`，浅色截图 [settings-light-profile.png](/Users/guo/.codex/visualizations/2026/11/15/aggregate-ui6-contrast/settings-light-profile.png) SHA-256 `56aaf4a3e1b000112ef0f56f8f7f6a5c4813f011b5c988bc7de85cd85aafaa96`。选中态光弧探索性局部亮度比为深色 2.32:1、浅色 1.15:1；该弧目前仅作次要装饰，非键盘焦点环或唯一状态提示。主题开关原焦点边框绘制在会覆盖它的 artwork 下方；现已用前景绘制层修正，并由 Widget 回归验证 2px 主题色边框存在且在前景。焦点环现已完成浅深主题的原生合成像素抽样并达到 3:1 目标。2026-11-17 Flutter 3.47.8 `ThemeData.lerp` 比较当前玻璃主题与 UI-0 等效基础主题：进度 0.25/0.50/0.75，当前 `GlassDesignTokens.text/surface` 分别为 3.747:1 / 1.015:1 / 3.917:1；UI-0 `onSurface/surface` 为 4.250:1 / 1.094:1 / 3.603:1。UI-0 源码的 macOS 全局 560 ms `easeInOutCubic` 过渡在当前版仍保留，并非本轮新增；当前 palette 在过渡早段对比度更低、中点相近、后段更高，均低于 4.5:1。临时对照探针已删除；这些是 ThemeData 模型值，不是 shader 实窗像素读数，未改主题或开关逻辑。过渡中间态、禁用态及其他页面材质仍未完成，UI-5.5 继续部分验收。 |
| 测试 | `flutter analyze --no-pub`：无问题；`flutter test --no-pub test`：272 项通过；`flutter test --no-pub tool/ui_review_test.dart`：6 项通过；`dart format --output=none --set-exit-if-changed app/lib app/test packages spikes/phase0/bin`：230 文件无变化；`sh spikes/phase0/check_boundary.sh`：通过；公共包 `dart test ...`：15 项通过；`flutter build macos --debug --no-pub`：成功。 |
| 完整脚本 | `sh tool/check.sh` 在工作树现有锁文件下退出码 65，因为 `flutter pub get --enforce-lockfile` 会改动 106 个依赖。为不改写该文件，另将已提交的 `HEAD:pubspec.lock` 临时放入验证工作树，原样运行完整脚本：退出码 0，格式、分析、公共边界、15 项公共包测试、272 项 App 测试与 macOS Debug 构建全通过；结束后逐字节恢复原锁文件。当前保留锁文件 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未纳入阶段提交。 |
| 真实服务 | 未连接真实连接、Host、账号或外部服务；所有状态/错误回归均由 Preview Runtime 或 mock Runtime 覆盖。 |
| 提交 | `f453980dc5a8dcf6d7b589ff4e7ecdc432013553`，`完成 macOS 玻璃 UI 功能验收`。 |

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
| 原生视觉与动效 | CUA 实窗观察到深色月亮态、浅色太阳态与一次中间拖动态；中间态显示了点阵内部变化、背景过渡与局部光弧。12 类 dot glyph、背景连续性及主题 AX 值均可见。1024 宽三轮往返拖动各 18 次，AX 状态 54 次逐次交替；另用方向键确认 AX 值可在深/浅端点间切换。2026-11-15 另导出同一 Profile 设置页的深浅窗口 PNG，实际 sRGB 像素抽样中正文、主题按钮文字和活动点阵核心均达到对比度目标；图像和哈希见上一行。Widget 指针回归覆盖 450 ms 拖动期间的中间态、抬手才提交以及中途取消恢复原端点。焦点环现按主题开关轨道尺寸/圆角绘制于 artwork 前景，Widget 检查其 2px 线宽、中心和几何尺寸；真实键盘焦点 Profile 实窗的浅/深主题合成像素最低对比度为 3.30:1 / 3.93:1，截图及 SHA-256 见后续焦点环记录。按钮 fixture 截图 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-buttons-fixture-disabled.png` 可见复制按钮灰化。2026-11-15 在隔离 Profile 最小夹具中对照玻璃按钮、裸 `Semantics`、语义包裹 `TextButton` 和普通禁用 `TextButton` 四种控件：Flutter Widget Semantics 均报告 `isEnabled=false` 且没有 tap action，但 `agent-desktop` 与直接 `AXUIElementCopyAttributeValue(kAXEnabledAttribute)` 均读到 `AXEnabled=true`。当前 Flutter 3.47.8 / Engine revision `cf636b1dfb` 的桌面 `AccessibilityBridge::SetStateFromFlutterUpdate` 未将 `is_enabled=false` 映射为 `Restriction::kDisabled`，macOS `AXEnabled` 则根据该 restriction 计算；故确认是 engine 桥接缺口，当前应用层 Semantics 结构不是原因。Flutter 官方主干已有相应转换（[bridge](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/common/accessibility_bridge.cc#L2297-L2304)、[macOS AX 映射](https://github.com/flutter/flutter/blob/master/engine/src/flutter/third_party/accessibility/ax/platform/ax_platform_node_mac.mm#L3239-L3244)），本机稳定版仍缺此转换。原生禁用语义未通过，需待使用包含修复的稳定 engine 后重验。视频帧对照页 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/theme-switch/stage6-keyframes.html` 展示原视频帧和 fitted Flutter 渲染的 9 组位置样本，包括静置、近似 0.25/0.5/0.75/1 和视频实际的部分反向轨迹；反向段约从 0.77 到 0.08 后再次前进，图像是离线逐帧对照，不是生产 macOS 实窗录屏。按钮尺寸/状态 fixture 现已在浅深两主题归档；生产页面 Profile 静态样本见下节。焦点环合成像素对比已通过。2026-11-15 用只读 CoreGraphics session event tap 记录系统实际收到的鼠标事件：`--duration 450` 的两向移动跨度为 524.0/517.9 ms；校准参数 `--duration 397` 的六次交替移动跨度为 455.4–466.1 ms（均值 460.8 ms、中位数 460.2 ms），六次 AX 浅深端点均正确。按下到首个移动事件为 189–201 ms，属于输入工具的拾取等待，不计入移动跨度。隐藏/暂停生命周期取消回退已于 2026-11-17 原生复核通过；OS 未发出 `PointerCancelEvent`，故系统 pointercancel 对照与最终用户签收仍未完成。原始事件和 SHA-256 见末尾时间戳记录。 |
| 按钮样式/尺寸双主题 Profile fixture | 隔离 bundle `io.github.guog962464.aggregate.ui6focusafter`，macOS Profile，800×600 logical px 内容区、截图 scale factor 2。深色：`/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-all-buttons-profile.png`、`stage6-all-buttons-profile-scroll-1.png` 至 `scroll-5.png`；浅色：`stage6-all-buttons-profile-light-top.png`、`stage6-all-buttons-profile-light-glyphs.png`、`stage6-all-buttons-profile-light-states.png`、`stage6-all-buttons-profile-light-states-2.png`、`stage6-all-buttons-profile-light-states-3.png`。覆盖 12 类 96dp glyph reference、primary/secondary/icon/playback/reference 五种尺寸，以及 navigation/segmented/danger/busy/disabled 状态；临时 fixture 以浅色初始值构建以便导出，未改生产入口/偏好。截图记录静置材质样貌，不代表原生 click 动画逐帧或生产页面覆盖。选择截图 SHA-256：深色首屏 `9de4825c0fbb60593006ce8c399022bc5f8330ef59a4ec57bd1fd2094130aa66`，深色状态 `a7a9fcbbbb87b083c18d0cb921f30606d597bdf4dbed5b299d1748b19f6f6c33`，浅色 glyph `b7bcee23123f056e97576508187d75697828269ba5a17cedc0242347af30f7a4`，浅色状态 `eae16cdb21decc8b33682fe1f8f935e8644722fcfcb77abf68290a746118fb60`。 |
| 结果边界 | UI-6.1 的固定宽度目录滚动、1024 主题拖动、800↔1440 连续缩放、工作台/连接/活动/设置四页联合滚动缩放及七类长列表/表单均有三轮 Profile 数据；该四页联合场景在缩放时往返滚动；另已完成三轮跨类别混合压力，包含按钮点击、播放控制、主题拖动、滚动、原生窗口 Fill/Restore 和隐藏/恢复，详见 2026-11-17 专项记录。90 字段表单原始三轮有一轮超 100 ms build 长帧，另补三轮未复现，原因未定位。450 ms 实时指针序列和取消已由 Widget 回归覆盖；原生六次双向拖动以逐事件时间戳核验，移动跨度 455.4–466.1 ms。2026-11-17 实窗确认应用隐藏时会取消活动拖动，迟到释放不会切换主题；OS 未发出 `PointerCancelEvent`，故原生 pointercancel 对照仍未完成。UI-6.2 的宽度/主题/连续缩放与六类长列表场景无 >100 ms build/raster 帧；表单原始样本和隐藏恢复各有一次超过 100 ms 的帧，表单另三轮未复现，隐藏恢复的原始单次 102.132 ms 在三次约 12.9 s 定向复测中未复现，根因仍未定位；帧数据不证明实际显示呈现 FPS。UI-6.3 已完成 UI-0 同机端点点击基线与当前拖动场景的方向性对照，输入不完全相同；视频关键相位已有离线对照，真实呈现 FPS 未验证。UI-6.4 的 hidden/paused 主题拖动取消回退已原生验证，但隐藏恢复长帧仍未定位；UI-6.5 已增加 Dart VM 托管对象计数，20 轮导航预热后主要计数持平，但 GPU/native 对象和 controller 活跃状态仍未知。UI-6.6/6.7/6.8 仍部分通过；UI-6.9 的代理静态截图自验已完成，但全部产品按钮实例和动态状态未逐项覆盖；UI-6.10 尚未完成。 |
| 变更范围 | 修改共享 Flutter 页面栈布局、主题开关焦点环的绘制层级、玻璃按钮的可见性复核调度、工作台长目录、连接首页/管理连接长目录与能力明细、音乐长搜索结果、活动长列表和大型运行参数表单的惰性构建；表单校验覆盖全部 schema 字段，没有改 Android 专用代码、主题模拟/校准算法、Runtime 协议、主题映射或切换逻辑。临时 Profile fixture、Runner 窗口注入和诊断分支均已清理。`pubspec.lock` 保留任务前 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未暂存。 |
| 提交/远端 | 首次 UI-6 报告提交 `98749bb2536420c3e43acd6a4f3409ccac608bcf` 只包含验收文档；既有工作台/活动子阶段提交 `fd11345ff311a52eaf1bce9d180498b001729be1`。本轮 90 字段参数表单实现、回归与验收记录提交 `490d13d390e3b6521e07e63e8e2ddddff75899ec`；主题开关焦点环绘制层级修正另提交 `fa4e90ec55a612af39729840f499c1b39b535e5e`，GitHub 与 Gitee 分支均核对为该 SHA。后续生命周期和资源所有权审阅继续只按其实际证据记为部分验证，该性能子任务交付不代表 UI-6 或整套 UI 适配已完成。

## 后续阶段

UI-0～UI-5 已按阶段独立提交；未通过的对比度与 VoiceOver 项仍保留为限制。UI-6 新增联合滚动缩放三轮、活动页长列表性能回归、UI-0 同机方向性基线、隐藏恢复观察、RSS 页面循环证据及 Dart VM 对象计数；GPU/native 资源与完整生命周期动效证据、动态视觉对照仍为待办，阶段仍未交付；生产页面静态截图自验已完成。

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


### 2026-11-18 UI-6.5 Dart VM 资源对象采样

- 环境：隔离 macOS Profile bundle `io.github.guog962464.aggregate.ui6resources`，产品代码基于 commit `4aa7f457bc42cc0e99652d36e905b2e1a2065080`；Flutter 3.47.8 stable / Dart 3.13.7。临时 worktree 只用于设置隔离 bundle id 和启动预览，产品代码未在主工作区修改。
- 方法：在“所有功能、管理连接、活动、设置”间循环导航 20 轮、共 80 次；通过 VM Service `getAllocationProfile(gc=true)` 在第 0、1、5、10、20 轮后读取存活对象数和 heap/external usage。样本是预热后的 Dart VM 存活对象快照。
- 结果：第 1、5、10、20 轮的 `Ticker` 均为 200、`_WidgetTicker` 29、`AnimationController` 222、`ui.Image` 2、Flutter `widgets.Image` 0、`FragmentProgram` 2、`FragmentShader` 2、`_NativePicture` 181；第 0 轮 `_NativePicture` 为 144，其余列出的主要对象计数相同。GC 后 heap 为 16,498,064–16,499,872 bytes（约 16.50 MB），external usage 稳定为 26,816 bytes；未见预热后随路由循环单向增加。
- 证据：紧凑 JSON `/Users/guo/.codex/visualizations/2026/11/18/aggregate-ui6-resource-audit/allocation-counts.json`，SHA-256 `540df947169126c15075dce30798499b2f6039c75804ed28933596b2156d4dc4`。
- 结论与限制：补足 Dart VM 管理对象数量证据；`_NativePicture` 等是 Dart VM 类型快照，不是 GPU/Skia/native texture 的分配计数，也不揭示 controller 是否正在 tick。结合源码所有权审阅和 RSS 记录，只能判定此导航负载预热后没有观察到 Dart 管理对象持续增长；UI-6.5 仍部分验收。
- 清理：关闭隔离 Aggregate Profile 应用并中断 Flutter runner；进程查询无应用/runner 残留；删除 `/private/tmp/aggregate-ui6-resource-probe` 临时 worktree。主工作区只剩用户原有 `pubspec.lock` 修改，未修改、未暂存。未运行产品测试，本次仅更新验收文档。
