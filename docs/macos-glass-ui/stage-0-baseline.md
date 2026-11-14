# UI-0：设计基线与行为冻结

> 状态：待执行 · 前置：无 · 后续：[UI-1](stage-1-background-and-tokens.md)

## 目标

确认实施的是 revision 5，列清每个现有操作的状态与副作用，保存原主题控件和实施前性能的可比较基线。

## 具体流程

1. 从[总览](README.md)定位设计资料，核对 HTML 的 SHA 与 JSON revision。保存深浅色的界面、材质板以及 12 类按钮关键时刻参考。每张图记录尺寸、相位与用途；不能只留一张静态缩略图。
2. 记录当前 commit、工作树、Flutter/Dart、锁文件摘要和 Mac 环境。先标记已有改动；当前文档编写时 `pubspec.lock` 已有用户修改，不将其纳入 UI 任务提交。
3. 为实际出现的每个操作建立清单：所在页面、可见标签、图案、回调、启用条件、忙碌条件、权限入口、成功/失败来源、键盘入口。覆盖工具栏、列表操作、分页/筛选、弹窗、音乐队列、Host 和危险操作，不能只盘点 12 个材质板样本。
4. 按下表核对当前源码。为 MCP 桌面组合布局标记“需重组”；为玻璃按钮、点阵工厂、共享动效层标记“计划新增”。
5. 跑原主题和当前主要业务的基线测试，保留原始结果。出现基线失败时先确认是否与环境/已有改动有关，不把失败悄悄改成新期望。
6. 在 Profile 构建下采集当前页面的性能基线，场景与未来 [UI-6](stage-6-native-performance-and-delivery.md)一致；此时只记录实施前表现，不提前判定新 UI 通过。

## 当前代码入口

| 区域 | 现有文件（仓库根目录相对路径） | 保留内容 |
| --- | --- | --- |
| 主题与偏好 | `app/lib/app/aggregate_app.dart`、`app/lib/app/theme.dart` | 偏好保存/回滚、系统模式、macOS 当前 560 ms 页面换肤 |
| 外壳与快捷键 | `app/lib/app/app_shell.dart`、`app/lib/app/shortcut_scheme.dart` | 连接导航与恢复、搜索、添加、迷你播放器、窄窗入口 |
| 连接首页 | `app/lib/features/connections/connection_home_page.dart`、`connection_experience.dart` | 元数据分流；当前 CLI/MCP 是能力列表，运行页为单独路由 |
| 参数与执行 | `app/lib/features/invocation/capability_run_page.dart`、`schema_form.dart`、`terminal_page.dart` | 校验、权限、调用、取消、终端与真实事件 |
| 音乐 | `app/lib/features/music/music_player_page.dart`、`music_mini_player.dart`、`music_search_results.dart`、`music_session.dart` | 同一会话、队列、可用性与真实播放确认 |
| 全局功能/管理/活动 | `app/lib/features/catalog/workspace_page.dart`、`app/lib/features/connections/connections_page.dart`、`app/lib/features/activity/activity_page.dart` | 搜索、来源、收藏、配置、诊断、脱敏记录 |
| 共用展示 | `app/lib/widgets/page_frame.dart`、`capability_row.dart`、`result_panel.dart`、`page_state.dart` | 结果复制、恢复与文件能力边界、空态/错误入口 |
| 设置/Host | `app/lib/features/settings/settings_page.dart`、`app/lib/platform/macos/mac_host_settings_panel.dart` | 设置偏好；Host 通过平台区块注入，不下沉到公共 UI |

## 原主题基线与逻辑冻结范围

以下六个文件记录实施前基线。冻结的是实时控件逻辑，不能简单要求全部文件零 diff：`AppearanceSelector` 内还有需要统一样式的“跟随系统”按钮；主题 shader 当前又在局部 viewport 内绘制不透明背景。逐文件允许范围如下：

- 三个模拟/校准文件 `theme_switch_simulation.dart`、`theme_switch_fitted_calibration.dart`、`theme_switch_calibration.dart` 保持不变。
- `glass_theme_switch.dart` 的手势、坐标到状态映射、模拟调度、提交时机、光学状态与语义不变。尺寸优先在父层调整；若消除背景接缝确需渲染接线，仅可增加 UI-1 规定的可选背景场景参数。
- `glass_theme_switch.frag` 的玻璃几何、折射/散射、内部点阵、光弧公式及参数不变。仅允许原背景/颗粒的场景坐标与合成适配，保留默认参考路径；不能以改亮度或光效来掩盖接缝。
- `appearance_selector.dart` 可调整布局及“跟随系统”按钮的材质/图案，继续复用 `GlassThemeSwitch(calibration: videoFittedThemeSwitch)`；主题映射、`onChanged`、跟随系统选择、可访问名称/选中语义及单次激活行为保持。

所有仅呈现的差异都要逐项记录和审阅；新通用按钮不能替换实时主题滑块。默认参考路径的模型/光学期望值不得因新背景接线被重录或放宽。

| 文件 | revision 5 设计审阅时的 SHA-256 |
| --- | --- |
| `app/lib/features/settings/glass_theme_switch.dart` | `4abf596b74a438620c886b7a4ad5784017a1790ecb54febfac792b68008ec012` |
| `app/lib/features/settings/theme_switch_simulation.dart` | `2bfa354d3b5511247d213284e36de18b418a7f332545c57f5d3e2625a8906a03` |
| `app/lib/features/settings/theme_switch_fitted_calibration.dart` | `11ffe7ea41b5ebd26d4a59f91dc2c7e98b18dcc794e054d89b6956b4c1febaa7` |
| `app/lib/features/settings/theme_switch_calibration.dart` | `c0f9cc70fa69462434e62c4ca577576ae03b6dd242d4a2a8a3eb1909cf0cadbd` |
| `app/shaders/glass_theme_switch.frag` | `a2f527f4d01cc44917b0cb1650df6b2e5368ee448db1f9e5f17b30ed65359094` |
| `app/lib/features/settings/appearance_selector.dart` | `83ff338b760c6635eae4ff693acebb92d077baa2f2a939c03fbc4452a5b1ab9f` |

实施开始时若已被其他任务修改，记录差异来源并核对其行为，不覆盖他人内容。后续以确认后的实施起点判定本轮是否动过这些文件；不能直接重置为上表版本。

## 基线命令

在仓库根目录记录环境与工作树：

```sh
git rev-parse HEAD
git status --short
flutter --version
dart --version
shasum -a 256 pubspec.lock
```

在 `app/` 执行原主题组；业务组按 [UI-5](stage-5-functional-acceptance.md)执行：

```sh
flutter test --no-pub test/glass_theme_switch_test.dart test/theme_switch_simulation_test.dart test/theme_switch_realtime_test.dart test/theme_switch_calibration_test.dart test/theme_switch_optics_test.dart
```

`--no-pub` 以当前依赖已准备好为前提。缺依赖时按项目锁文件恢复，不为 UI 改版顺手升级 SDK 或依赖。

## 交付物与验收

- [ ] **UI-0.1** 设计版本、SHA、关键时刻参考和真实源码入口齐全；历史连续图案版本没有混入。
- [ ] **UI-0.2** 原主题六文件起点与逐文件允许范围已核验；原交互、模型及默认光学路径有可复跑基线，未将仅呈现适配扩展为逻辑修改。
- [ ] **UI-0.3** 所有实际按钮均进入操作清单；装饰动作与业务状态一一对应。
- [ ] **UI-0.4** 主要测试与 Profile 实施前记录已保存；失败或未测项明确标记，不借用旧报告填“通过”。
- [ ] **UI-0.5** 实施范围明确为 macOS 呈现，不修改 Runtime 契约、账号/授权或 Android 行为。

以上交付写入总览规定的验收记录；本阶段不以浏览器检查替代软件基线。
