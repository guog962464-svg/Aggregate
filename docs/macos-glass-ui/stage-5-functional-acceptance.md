# UI-5：功能、布局与无障碍回归

> 状态：待执行 · 前置：[UI-4](stage-4-page-adaptation.md)通过 · 后续：[UI-6](stage-6-native-performance-and-delivery.md)

## 具体流程

1. 先运行受影响测试组，再执行完整项目闸门。新增测试聚焦公共点阵、时钟连续性、组合布局和真实状态边界，不以大量重复快照替代行为断言。
2. 对新按钮建立可控时钟的组件测试；按 UI-2/UI-3 核对图案、中间态、连击、反向、可见性、减少动态效果和独立业务回调次数。
3. 更新截图工具，使装饰在确定相位冻结；明确执行 `app/tool/ui_review_test.dart`，因为它不在 `flutter test test` 的自动范围内。它当前使用 `pumpAndSettle()`，持续 idle 接入后必须先处理这一点。
4. 在真实 Mac 核对中文、长路径、长连接/能力名、复杂 schema、空结果、失败、权限不足、取消、超时和未知终态。fixture 通过后再验证已有真实 Runtime 入口。
5. 用键盘与 VoiceOver 逐页走查。检查焦点顺序、按钮名称、状态表达、弹窗焦点限制与返回；图案装饰不能成为重复的可访问节点或每帧朗读内容。
6. 将自动测试、原生目视、VoiceOver 和真实 Runtime 的结果分别记录；当前基础色对比测试不能代表所有玻璃叠层状态已经达标。

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

- [ ] **UI-5.1** 原主题组、相关业务组、新组件组和完整项目闸门均通过；三模拟/校准文件不变，其余主题文件只有 UI-0/UI-1 规定的呈现差异，逻辑与默认参考路径原期望值保持。
- [ ] **UI-5.2** 所有矩阵项没有文字/按钮遮挡、不可达操作、非预期横向溢出；装饰光晕由正确层裁剪，不遮挡相邻控件或焦点。
- [ ] **UI-5.3** Tab/Shift-Tab 顺序符合视觉顺序；按钮可按其原生键盘语义激活且只调用一次；⌘K 聚焦搜索，⌘↵只运行当前可用任务，弹窗不触发背景任务，Esc 后焦点恢复。
- [ ] **UI-5.4** 图标按钮有准确名称，播放/暂停等状态名称随真实状态更新；禁用/忙碌可被识别，状态不只靠颜色，装饰节点不重复朗读。
- [ ] **UI-5.5** 实际合成背景上，项目目标为普通文字对比度至少 4.5:1、关键图形/焦点提示至少 3:1；分别抽查最亮光弧附近与最暗材质区域。禁用态单独审阅可辨识度，不用基础 token 结果代替叠层测量。
- [ ] **UI-5.6** 参数错误不调用 Runtime；权限拒绝不执行；取消/失败/超时/未知终态正确；复制使用真实结果，音乐与 Host 由真实状态驱动。
- [ ] **UI-5.7** 增大系统文字或辅助显示设置后，主要操作仍可访问；减少动态效果停止装饰但保留功能；VoiceOver 主要流程走查记录齐全。
- [ ] **UI-5.8** 新 idle 没有造成截图超时或测试永不归稳；固定相位测试与产品动效的边界明确，未用全局永久禁用动画掩盖问题。

对比度是本方案采用的项目验收目标；本轮未测量新 Flutter 叠层，也未完成软件无障碍认证。UI-6 通过前不能将本阶段截图/Debug 构建称为流畅度验收。
