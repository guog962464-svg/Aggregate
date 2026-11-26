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

- [x] **UI-5.1** 原主题组、相关业务组、新组件组和完整项目闸门均通过；主题控件手势、状态映射、提交/取消语义及两个校准文件保持 UI-0 基线。`ThemeSwitchSimulation` 的实时帧积分有 UI-6.8 记录的参考网页时钟例外，详见[基线边界复核](stage-0-baseline.md#原主题基线与逻辑冻结范围)。其余呈现差异逐项记录，默认参考路径期望值未放宽。完整 `sh tool/check.sh` 使用已提交的基线锁文件在隔离验证后通过；还原后工作树中的原有锁文件改动仍会使依赖恢复步骤退出，见验收记录。
- [x] **UI-5.2** 覆盖三种逻辑尺寸、浅深主题、DPR 1/2 与 9 个预览路由状态；DPR 1 对照 54 张金样，DPR 2 对所有状态运行布局/渲染错误检查。640 px 紧凑窗口沿用既有回归；这不代表原生 1× 显示器验收。
- [x] **UI-5.3** Tab/Shift-Tab 顺序符合视觉顺序；按钮可按其原生键盘语义激活且只调用一次；⌘K 聚焦搜索，⌘↵只运行当前可用任务，弹窗不触发背景任务，Esc 后焦点恢复。完整双向顺序由 Widget 测试验证；另在真实生产应用壳层 macOS Profile 实窗确认前向 Tab 将焦点环从全局搜索移至“添加连接”。原生 Shift-Tab 未验证；2026-11-26 两桌面输入通道复核仍未实际送达 Shift 修饰键，见[补测记录](acceptance-record.md#2026-11-26-ui-53-shift-tab-输入路径补测保持未验)。
- [ ] **UI-5.4** 部分通过：Flutter semantics 回归覆盖图标名称、播放/暂停状态名称、禁用/忙碌与装饰节点隔离；原生 AX 抽查覆盖主要控件名称。Flutter 3.50.0 Profile 曾将禁用控件导出为不可读 AX 节点，3.47.8 最小 Profile fixture 则稳定复现禁用 `GlassActionButton`、显式 `Semantics` 与 Material `TextButton` 的 `AXEnabled=true`；框架语义为 `isEnabled=false` 且没有 tap action，agent-desktop 查询三次和直接 AX API 结果一致。16 项定向 Widget 语义测试通过，但不覆盖原生导出。**引擎版本对照**：[记录](acceptance-record.md#2026-11-19-flutter-3478-engine-ax-restriction-conversion-source)显示 Flutter 3.47.8 未将 `is_enabled=false` 转为 `AXNodeData::Restriction::kDisabled`，与该版本实测 `AXEnabled=true` 一致。官方 [PR #190353](https://github.com/flutter/flutter/pull/190353) 已在 Flutter 3.50.0 stable engine 中加入 disabled/read-only restriction 映射，本地 3.50.0 SDK 源码也包含该分支。但 2026-11-17 的精确 Profile 复测在 `AXEnhancedUserInterface=true` 下仍读到禁用节点的 AX 角色、名称等属性不可读；这项 bridge 变更没有解决当前观察到的原生 AX 导出问题。3.50.0 的具体导出缺陷仍未定位，尚无经验证的无损应用层修复；禁用态原生 AX 仍未通过。2026-11-19 的 VoiceOver 实测只能取得嵌套 group 导航提示，未读出主题或搜索控件名称；实际朗读顺序未完成，本项保持部分验收。2026-11-21 起，共享 `GlassActionButton` 从同一 `WidgetStatesController` 显式导出 `focusable/focused`；单个隔离 macOS Profile 样本经 AX SetFocus 后，原生节点出现 `focused` 且画面同时出现焦点环。随后在真实生产应用壳层 Profile 中，Flutter 实际收到 Tab，焦点环依次到全局搜索与“添加连接”；同日启用系统 VoiceOver 后，字幕只确认应用根 group 与嵌套 group 提示，组内导航没有取得控件朗读回执。原生 Shift-Tab、VoiceOver 控件朗读、禁用态 AX 和全部生产实例仍未完成，故本项保持部分验收。
- [ ] **UI-5.5** 实际合成背景上，项目目标为普通文字对比度至少 4.5:1、关键图形/焦点提示至少 3:1。macOS Profile 设置页浅/深静态截图像素抽样：正文 14.27:1 / 10.16:1，主题按钮文字 4.74:1 / 7.47:1，太阳/月亮点阵核心 4.93:1 / 7.65:1，均达到目标。选中态光弧的局部探索值为深色 2.32:1、浅色 1.15:1；目前把它视为次要装饰（状态另由图案、滑块位置和 AX 值表达），不能单独作为焦点/关键图形通过。主题开关的 2px 焦点环已绘于 artwork 前景；2026-11-15 的原生 Profile 实窗相邻像素抽样，浅/深主题最低分别为 3.30:1 / 3.93:1，达到 3:1 目标。2026-11-17 的 `ThemeData.lerp` 探针曾测得进度 0.25/0.50/0.75 的玻璃文字对 `surface` 为 3.747:1 / 1.015:1 / 3.917:1。macOS 插值文字对比修正会保留已达标颜色，低于 4.5:1 时在黑/白中取较高对比色；作用于语义表面、列表/标题文字；玻璃 `text`/`muted` 令牌保留当前主题端点色，为按钮材料提供稳定前景，浅深端点色不变。101 个等距插值点及 macOS 主题转场 Widget 测试通过。2026-11-18 设置页文字颜色接入实际 `switchDaylight` 亮暗侧，只在 0.5 阈值跨越时重建页面主题；560 ms `easeInOutCubic`、任意拖动和切换逻辑未改。`macos_reduce_motion_test.dart` 双向逐 16 ms 检查 40 帧，原文字颜色交接仍在 0.5，背景 shader 仍逐帧更新。后续用生产设置页的实际文字区域采样了 1024×768、DPR 1 shader 背景，在 201 个均匀进度点及 9×3 背景位置上以指定黑/白前景色重算对比度：白字在 0.475–0.495 的最低值为 4.478:1、4.415:1、4.353:1、4.292:1、4.233:1；黑字在 0.5 为 4.493:1，两个交接位置均有低于目标的区间。现仅在 0.46–0.55 为正文、标题和列表文字加 1px 对比描边；文字色交接仍在 0.5，正文描边不作用于按钮标签、shader 背景、太阳/月亮轨迹和业务逻辑。新增生产 shader 采样与双向实时帧回归，检查中段描边相对背景至少 3:1、正文/描边至少 7:1，并确认光晕窗口外所测正文色对达到 4.5:1；对音乐首页、工作台、连接管理、活动和设置页标题，以及设置页副标题、分节标题、正文和两条快捷操作 ListTile 标题共十个文字矩形采样，覆盖 800×600、1024×768、1440×900 三种窗口尺寸的 1×/2× 共六组组合。2026-11-18 补充两种初始偏好：深色与浅色启动均运行上述六组尺寸/DPR、14 个临界转场相位的生产 shader 采样回归，通过 12 组窗口/DPR/初始偏好组合（共 168 组相位组合）；每相位另断言页标题、分节标题、正文/副标题和 `ListTile` 标题/副标题使用当前前景与 8 向描边，按钮标签维持无描边。这些新增断言验证主题样式应用范围，不等同这些位置的独立像素对比采样。 同日另在 `AggregateApp` 设置页的玻璃按钮上采样普通、禁用、忙碌、危险标题，以及禁用按钮说明和来源六类文字：深/浅初始偏好各 14 个临界相位，1024×768、DPR 1，共 168 组文字/相位组合；每个文字基线右侧的同一按钮面取 3 个未覆盖像素，均达到 4.5:1。禁用/忙碌标题按当前主题正文色，说明/来源色向正文色调整 18%；玻璃面透明度、图标状态、交互和动效规则未改。该样本是 PreviewRuntime 设置页离屏合成，不代表全部按钮调用点或原生显示捕获。同日补测从深到浅 `ThemeData.lerp` 的 101 个等距点：页面标题/正文/ListTile 样式在 `surface`、`surfaceContainerLow`、`surfaceContainer` 三种内容面上均通过直接对比或 8 向轮廓的 7:1/3:1 约束；普通、禁用、说明、来源、忙碌、危险六类按钮文字共 12 个标签样本，覆盖 secondary、primary、reference 三类尺寸，在 1024×768 DPR 1 离屏合成中逐点取同按钮面三个相邻像素，直接文字达到 4.5:1，或使用 8 向零模糊描边并满足文字/描边至少 7:1、描边/按钮面至少 3:1。禁用材质仍为 0.52 透明度，切换/拖动/点击逻辑未改。此为 ThemeData 模型和 Widget 离屏证据，不是原生 display-present 或全部页面材质签收。2026-11-19 将上述六类设置页按钮文字矩阵扩展到 800×600、1024×768、1440×900 三种窗口和 1×/2× DPR，深/浅初始偏好各运行 14 个临界相位。12 组尺寸/DPR/偏好组合、168 组相位组合中，每组采 6 类标签、每类 3 个同按钮面未覆盖像素，共 3,024 个文字/背景色对比样本；`flutter test --no-pub test/macos_dynamic_backdrop_text_contrast_test.dart` 三项通过，`flutter analyze --no-pub` 无问题。测试只扩展 PreviewRuntime 的 Widget 离屏 shader 采样矩阵，没有改颜色规则、按钮交互或主题切换逻辑；不能替代 macOS Profile/display-present、所有生产按钮实例、VoiceOver 和全页面状态矩阵验收。其他页面材质、完整按钮调用点状态矩阵、原生显示捕获与 VoiceOver 仍待完成，UI-5.5 保持部分验收。详细执行结果见 [验收记录](acceptance-record.md#ui-5功能与无障碍回归)。
  - 2026-11-26 补测当前连续设置页：旧“Mac Host”标签页/副标题定位器改为当前 section key 与文案，按钮按可见实例分组滚动取样。深/浅起始偏好 × 三窗口 × 两 DPR 共 12 组、20 个临界相位 `0.46–0.56` 全通过；描边关闭后的 `0.551`、`0.555`、`0.56` 也达标。首次在 `0.545`、深色起始 `800×600@1x` 量得正文最低 `4.4288:1`，因此仅将普通正文/标题/ListTile 的对比描边终点从 `0.54` 延至 `0.55`。三项离屏测试、静态分析、工作台几何、格式和 diff 检查通过；不代表原生 Profile/display-present 或全部生产调用点，故 UI-5.5 仍部分验收。
- [x] **UI-5.6** 参数错误不调用 Runtime；权限拒绝不执行；取消/失败/超时/未知终态正确；复制使用真实结果，音乐与 Host 由真实状态驱动。以完整 App 回归和现有 Preview Runtime fixture 测试验证；未连接用户真实服务。
- [ ] **UI-5.7** 增大系统文字或辅助显示设置后，主要操作仍可访问；减少动态效果停止装饰但保留功能；VoiceOver 主要流程走查记录齐全。200% widget 文字测试通过；2026-11-17 的 macOS Profile 实窗验证 AppKit Reduce Motion 已传播到 Flutter、装饰停止且主题切换/按钮点击仍有效。禁用态 AX 有已记录的 Flutter/macOS 导出缺陷。本次已开启系统 VoiceOver 并尝试导航隔离 Profile 应用；页面 AX 树可读，但 VoiceOver 焦点停留在系统 group，未能移到应用控件并产生有效控件朗读，因此主流程走查仍未完成，本项保持部分验收。2026-11-19 通过系统设置实际启用 VoiceOver 后，AX 树可读但 VO+Right 未得到可验证的应用控件播报；字幕面板仍显示启动提示，故本次无法确认光标目标或主流程朗读，VoiceOver 走查仍未完成。随后一轮确认字幕面板能读出嵌套 group 操作提示；发送 VO+Shift+Down、VO+Right、Tab 和 VO+U 后仍没有控件标签或转子内容，Tab 只改变了键盘焦点。2026-11-21 在真实 `lib/main.dart` Profile 壳层重测，字幕再度读到应用根/嵌套 group，但没有取得控件名称或状态的语音回执；本次输入路径未确认送达，记录仅证明 VoiceOver 当前仍无法签收主流程。测试结束将开关关闭并读回 0，VoiceOver 服务退出。本项保持部分验收。
- [x] **UI-5.8** 新 idle 没有造成截图超时或测试永不归稳；固定相位测试与产品动效的边界明确，未用全局永久禁用动画掩盖问题。固定相位预览快照 6 项通过。2026-11-17 的 UI review 将 `ThemeSwitchArtwork` shader 预加载移到 `setUpAll`，避免各 `testWidgets` 异步区等待同一个 Future；12 个完整页面用例重复通过，54 个 DPR 1 金样断言稳定。

对比度是本方案采用的项目验收目标；新 Flutter 叠层已有设置页静态 Profile 像素样本，但未覆盖完整材质/状态矩阵，也未完成软件无障碍认证。UI-6 通过前不能将本阶段截图/Debug 构建称为流畅度验收。详细执行结果见 [验收记录](acceptance-record.md#ui-5功能与无障碍回归)。
