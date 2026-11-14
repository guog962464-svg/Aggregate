# UI-5：功能、布局与无障碍回归

> 状态：阶段实施完成，验收部分通过。未完成项按实记录在文末；UI-6 可继续测性能，但不会替代这些验收。前置：[UI-4](stage-4-page-adaptation.md)通过。

## 具体流程

1. 先运行受影响测试组，再执行完整项目闸门。新增测试聚焦公共点阵、键盘遍历、放大文字和真实状态边界，不以大量重复快照替代行为断言。
2. 对新按钮建立可控时钟的组件测试；按 UI-2/UI-3 核对图案、中间态、连击、反向、可见性、减少动态效果和独立业务回调次数。
3. 更新截图工具，使装饰时钟可控、截图相位固定；明确执行 `app/tool/ui_review_test.dart`，因为它不在 `flutter test test` 的自动范围内。截图检查使用独立的 `ManualGlassMotionClock`，不关闭产品动画时钟。
4. 用 Profile 预览与自动化 fixture 覆盖中文、长内容、错误、取消、超时和未知终态；不触发真实连接、Host 授权或有副作用的 Runtime 操作。
5. 通过 widget 键盘测试和原生 macOS AX 树检查焦点顺序、按钮名称和状态表达；未直接启用系统 VoiceOver 朗读。图案装饰不能成为重复的可访问节点或每帧朗读内容。
6. 将自动测试、原生目视、AX 树、VoiceOver 和真实 Runtime 的结果分别记录；当前只验证了配置色值在静态材质端点上的对比度，没有测量实际 shader 合成像素。

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
- [x] **UI-5.4** 图标按钮有准确名称，播放/暂停等状态名称随真实状态更新；禁用/忙碌可被识别，状态不只靠颜色，装饰节点不重复朗读。由 Flutter semantics 测试与原生 macOS AX 树抽查验证；未播放 VoiceOver 语音。
- [ ] **UI-5.5** 实际合成背景上，项目目标为普通文字对比度至少 4.5:1、关键图形/焦点提示至少 3:1；分别抽查最亮光弧附近与最暗材质区域。静态 token 端点检查通过，但 shader 合成像素、过渡中间态和禁用态没有采样。
- [x] **UI-5.6** 参数错误不调用 Runtime；权限拒绝不执行；取消/失败/超时/未知终态正确；复制使用真实结果，音乐与 Host 由真实状态驱动。以完整 App 回归和现有 Preview Runtime fixture 测试验证；未连接用户真实服务。
- [ ] **UI-5.7** 增大系统文字或辅助显示设置后，主要操作仍可访问；减少动态效果停止装饰但保留功能；VoiceOver 主要流程走查记录齐全。200% widget 文字和 reduced-motion 测试通过；原生 AX 树名称/状态已抽查，但直接系统 VoiceOver 走查未执行。
- [x] **UI-5.8** 新 idle 没有造成截图超时或测试永不归稳；固定相位测试与产品动效的边界明确，未用全局永久禁用动画掩盖问题。固定相位预览快照 6 项通过。

对比度是本方案采用的项目验收目标；本轮未测量新 Flutter 叠层，也未完成软件无障碍认证。UI-6 通过前不能将本阶段截图/Debug 构建称为流畅度验收。详细执行结果见 [验收记录](acceptance-record.md#ui-5功能与无障碍回归)。
