# UI-6：macOS 原生性能与最终交付

> 状态：部分验收，最终交付待完成 · 前置：[UI-5](stage-5-functional-acceptance.md)自动化与原生 AX 抽查已完成；VoiceOver 开启且 AX 增强接口激活时，Flutter 3.47.8 禁用按钮仍报告为 enabled；Flutter 3.50.0 的精确 Profile 复测中，标准/玻璃禁用按钮和禁用说明文本均没有可读 role/名称，即使在应用启动前开启 AX 增强树也一样。禁用态原生语义未通过，实际 VoiceOver 语音走查也未完成。Profile 子场景和未完成项见[验收记录](acceptance-record.md#ui-6原生性能与最终验收部分验收)。

## 1. 原生测量流程

1. 使用真实 Mac 的 Profile 构建；记录设备、系统、Flutter/Dart、commit/锁文件、显示器与实际刷新率、DPR、窗口尺寸、主题、减少动态效果和采样方式。Debug 的统计只用于调试，浏览器结果不作为原生门槛。
2. 先在 fixture 入口复核材质，再验证正式入口；同一机器、构建模式和场景与 UI-0 基线比较。两者的数据分别归档。
3. 通过 DevTools/Flutter 帧时记录，或后续新增并验证的 Mac 采样工具，分别采集 UI build 与 raster。每轮先预热 5 秒，再采样至少 30 秒；每个场景至少 3 轮，不能只保留最好的一轮。交互负载按固定周期重复直到覆盖整个采样窗口，最后一个动作结束后再停采样。
4. 同时记录实际完成操作的次数、输入序列、提交帧数、p50/p95/p99/max 与超预算比例。另标记每次输入至装饰/状态过渡结束的活动时间窗口，合并重叠区间，分别统计全轮、活动窗口和静置；不能用长时间 idle 稀释操作卡顿。录屏/截图可能改变性能，应与纯测量轮次分开。
5. 用原生目视和必要的屏幕呈现观测补查明显顿挫。Flutter 提交帧数据不能直接等同显示器实际呈现 FPS。

在 `app/` 启动 Profile：

```sh
flutter run -d macos --profile -t lib/preview_main.dart
```

fixture 验证后，对正式入口使用：

```sh
flutter run -d macos --profile -t lib/main.dart
```

`preview_main.dart` 是现有入口；新材质样本需在实施阶段加入合适的 preview 组合。以上命令不表示样本已接入。使用正式入口时保留现有连接和偏好，不清除用户数据。

`app/tool/profile_theme_switch.py` 是 Android/adb 专用工具，不能当成 Mac 命令使用。若复用相邻 VM-service 帧监听器，必须先验证 Profile Mac 确实产出所需事件、数据完整且操作完成；无数据、断连或场景未覆盖记失败/未验证，不能返回通过。

## 2. 固定工作负载

| 场景 | 每轮操作 | 关注点 |
| --- | --- | --- |
| 多按钮静置 | 12 类样本全部可见，持续 30 秒，深浅色分别测 | idle 成本、缓存复用、图案与光照同步 |
| 连续点击 | 每 2 秒一组：按 100 ms 间隔点 10 次，等待本组归稳；对刷新/复制/添加分别测，重复至覆盖 30 秒 | 视觉接续、无重复资源、业务规则未改变 |
| 播放反向 | 固定时点快速播放/暂停，穿插上一首/下一首/停止及切页；记录周期并重复至覆盖 30 秒 | morph、busy 与真实状态一致、mini player 会话共享 |
| 滚动与缩放 | 七个视图中的长列表/表单持续往返滚动，并在 800、1024、1440 宽度间缩放，覆盖 30 秒 | 离屏暂停、无全页持续重绘、无光标/布局丢失 |
| 原主题 | 每组 6 次约 450 ms 往返拖动，间隔约 650 ms；含中途反向与取消，连续重复组至覆盖 30 秒 | 原实时控件持续流畅，背景换肤无新增卡顿 |
| 生命周期 | 后台停留、隐藏页、离屏，再恢复；按记录的周期重复至覆盖 30 秒，减少动态效果开关分别检查 | 装饰停止、无补播积压、计时器/纹理不重复注册 |

状态型真实业务按钮不得为了凑次数绕过其禁用条件；密集触发的视觉测量优先使用 fixture，同时单独核对正式入口的回调与状态结果。滑块拖动坐标按实际布局记录，不复用旧设备绝对坐标。

## 3. 本轮执行摘要（2026-11-15）

Mac Profile 的多按钮浅/深静置、刷新/复制/添加、播放反向与滚动缩放各三轮，逐轮统计见[验收记录](acceptance-record.md#ui-6原生性能与最终验收部分验收)。新增 1024、1440 logical px 固定窗口滚动/路由交互各三轮；两种宽度的 build/raster P95 均低于 16.667 ms，超预算比例最高 0.429%，宽度场景没有 >100 ms Flutter build/raster 帧。1440 宽第三轮有 932 个采样帧，活动窗覆盖 29.783 秒。1024 宽主题开关另完成三轮往返拖动，每轮 18 次端点拖动、AX 深浅值交替，帧时均满足门槛。2026-11-15 用只读 macOS CGEvent tap 记录原生输入时间戳：`agent-desktop --duration 450` 两向实际移动跨度为 524.0/517.9 ms；校准到 `--duration 397` 后，六次交替拖动的实际跨度为 455.4–466.1 ms（均值 460.8 ms、中位数 460.2 ms），六次 AX 端点均正确。按下到首个移动事件为 189–201 ms，属于工具的拖动拾取等待，应与移动跨度分开看。另在独立 Profile PreviewRuntime 中按原视频测得的指针中心轨迹和采样时刻执行一次实时拖动，并同步录屏与只读事件 tap：55 个拖动点的坐标误差最大 0.00003 px、事件时差为 -5.87 至 +4.12 ms；控件从深色切到浅色。实窗捕获在同一轨迹时刻与原视频目标帧的 ROI MAE 为 72.05/255，而前一源帧的 MAE 为 5.41/255，最近源帧估计相位偏差约 -55.69 ms。该结果说明连续实窗动效尚未逐帧对齐，不能标通过；由于源轨迹只从可见滑块中心重建、录屏有 33.33 ms 间隔，且不是物理显示呈现测量，这个相位偏差只作估计。后续用同一轨迹按 60/120 Hz 插值并由只读系统 tap 复核后，点位时刻仍吻合；60 Hz 下全量/背景/开关/点阵偏移分别为 `-46/-46/-46/-42 ms`，120 Hz 下为 `-52/-48/-60/-60 ms`。另在同一路径终点加入 500 ms 按住窗口：只读 tap 收到 70 个拖动事件，最后一个目标点后约 4 ms 的捕获帧仍呈现反向前的位置，约 54 ms 后画面已进入稳定位置，实际抬起发生在约 513 ms 后。该结果把按住期间的可见跟随间隔与释放动画分开，但只能说明采集序列里的输入到可见更新间隔，不能定位为 Flutter、窗口合成器或物理呈现延迟。稀疏源采样与 120 Hz 过密输入不足以单独解释；原生连续动效仍未通过逐帧相位验收。新证据和方法限制见[验收记录](acceptance-record.md#2026-11-15-原视频轨迹输入采样率复核)与末端停留响应复核。2026-11-17 另验证隐藏应用期间的取消：系统未发出 Flutter `PointerCancelEvent`，应用级隐藏生命周期回调现在会走既有取消收尾路径；释放不再误提交主题，恢复后下一次点击正常。

针对连续缩放时整页卡顿，本轮修正 `AppShell` 在 `LayoutBuilder` 每次收到新宽度时重建整个 `IndexedStack` 的问题：页面栈引用现在跨纯布局尺寸变化保持稳定，页面仍按新约束布局，页面状态和主题切换逻辑不变。同一 24 个 CLI 样本连接、90 项 CLI 能力、60 项 MCP 工具和本地样本活动记录下，Mac Profile 原生窗口 800↔1440 logical px 连续缩放完成三轮，每轮采样 40 秒，build/raster P95 均低于 13.9/9.9 ms，超预算帧比例最高 0.292%，没有 >100 ms 帧。

联合负载首次暴露活动页 60 条点阵操作按钮一次性构建导致的 build 抖动。活动页改为有界 `ListView.builder` 后，单页活动记录往返滚动的 40 秒样本由 13.523% 降至 0.085% 超预算帧；两轮 scroll pair 数分别为 86 和 109，因此这组前后数据仅作方向性定位，不视为相同输入 A/B。随后在 24 个 CLI 样本连接、152 项功能和 60 条活动记录下，用原生窗口扫宽与工作台、连接、活动、设置四页往返滚动完成三轮 40 秒联合采样；build/raster P95 均低于 11.2/14.9 ms，超预算帧比例为 1.281%–1.495%，没有 >100 ms build/raster 帧。之后为连接首页桌面/紧凑目录、管理连接页桌面/紧凑连接目录和选中连接的 90 项能力明细添加 widget 回归；音乐搜索结果在 40 项以上切换到有界惰性列表，也以 90 首样本验证末项可滚动且播放回调仍正确。本轮又将 40 字段以上的运行参数表单改为 420 logical px 有界惰性列表，用 90 字段样本确认屏外必填项仍被校验、滚动后可显示行内错误且参数值保持一致；全量 282 项测试和静态分析通过。

随后在隔离的 macOS Profile PreviewRuntime 夹具中，对七个长列表/表单场景分别进行三轮 40 秒采样（5 秒预热，后续 30 秒反复滚动，按首帧后 5–35 秒活动窗统计）：工作台 92 项、连接首页单连接 91 项能力、连接管理 90 个连接、管理明细 91 项能力、活动 60 条、音乐结果 90 首、参数表单 90 字段。除参数表单其中一轮的单次 112.742 ms build 峰值外，所有场景均无 >100 ms build/raster 帧；各轮 P95、超预算计数和异常见[验收记录](acceptance-record.md#ui-6原生性能与最终验收部分验收)。夹具使用本地合成数据，不连接真实服务；数据是 Flutter 提交帧，不等于显示器实际呈现 FPS。

针对 90 字段表单的异常，在同一隔离 Profile 进程中按 40 秒采样再做三轮 paced scroll 复测；其中两轮严格执行 20 组下/上滚动、每组间隔 1.2 秒。三轮均采到 1,800 帧活动窗，build/raster P95 为 0.288–0.341/0.673–0.763 ms，未出现超预算帧。原始一轮 112.742 ms build 和同轮采样空档仍保留，补测只能说明该长帧未复现，不能证明根因已消除或将场景判为完全通过。

新增 UI-0 同机帧时基线：在临时 worktree `297762e82730b8a99f324b190796c80aae426a9` 使用相同 Mac、Profile 模式、1024×632 logical px 窗口、DPR 2、60 Hz 和当前锁定的依赖版本，完成三轮各 30 秒活动窗、每轮 18 次主题端点往返点击。基线 build P95 为 4.799–4.918 ms，raster P95 为 0.775–0.812 ms；当前版本 1024 宽 18 次实时拖动三轮的 build P95 为 4.939–4.968 ms、raster P95 为 5.900–5.944 ms。两组都没有超过 16.667 ms 的 build/raster 帧。基线使用端点点击，当前使用连续拖动，因此仅用于同机方向性对照，不视为相同输入的 A/B，也不代表实际显示呈现 FPS。

2026-11-15 在隔离 PreviewRuntime 的 macOS Profile 包中抽查生产连接首页（示例网易云音乐）、工作台（侧栏“所有功能”）、管理连接、活动和设置五个页面。每页分别捕获浅/深主题首屏，另外捕获工作台与设置页底部、设置页侧栏焦点及主题开关焦点，共 17 张静态窗口截图；窗口 AX bounds 为 800×632 logical px，PNG 为 1824×1488 像素。图片文件及 SHA-256 见[验收记录](acceptance-record.md)的“生产页面双主题实窗抽查”。先前标为 home 的两张截图经 OCR 复核实际是设置页，已重新捕获连接首页并替换；全部页面截图按页名和内容复核。代理按本阶段静态截图范围完成自验，未发现明显的整体背景断层、材质层级或主要控件位置问题。截图使用本地合成 PreviewRuntime 数据，不代表真实服务数据、全部按钮实例逐项签收、点击/静置动效逐帧、VoiceOver 或屏幕呈现 FPS；动态状态与完整原生验收仍未完成。

新增 20 轮原生页面往返（80 次导航）及进程 RSS 时间序列：RSS 从约 176 MiB 增至约 203 MiB，循环结束约 199 MiB；后续 30 秒静置在约 195–208 MiB 间波动，未见单向增长。另用 Dart VM `getAllocationProfile(gc=true)` 在第 0、1、5、10、20 轮采样：`Ticker` 200、`_WidgetTicker` 29、`AnimationController` 222、`ui.Image` 2、`FragmentProgram` 2、`FragmentShader` 2 均保持稳定；`_NativePicture` 从 144 增至 181 后稳定。GC 后 heap 从约 16.29 MB 升至约 16.50 MB，并在后续循环保持稳定。该采样只统计 Dart VM 托管对象，不计 GPU、Skia/native 纹理等原生资源，也不说明 controller 是否正在 tick；证据与范围见[验收记录](acceptance-record.md#2026-11-18-ui-65-dart-vm-资源对象采样)。

源码资源所有权审阅确认：`GlassMotionScope` 每个作用域持有一个共享显示帧 Ticker，并在静置时使用一个 33 ms idle Timer；dispose 时取消该 Timer 与 viewport/size timers、移除生命周期监听、dispose Ticker 并 detach clients。`GlassActionButton` dispose 自己的 motion/state controllers；`GlassThemeSwitch` dispose Ticker 和 FocusNode；`ThemeSwitchArtwork` dispose shader 及两张 `ui.Image`，更新贴图后在 post-frame dispose 旧图；`GlassScene` dispose 全窗 shader 与 frame notifier。Flutter 的 `FragmentProgram.fromAsset` 由 SDK 进程级缓存，因此按进程生命周期保留。源码没有额外 `AnimationController` 或 `Texture` widget。现有 `glass_motion_test.dart` 覆盖 reduced-motion 注销、离屏滚动/视口注销和生命周期暂停恢复；新增测试验证 idle Timer 与交互 Ticker 的切换及连续 33 ms 通知；`glass_theme_switch_test.dart` 覆盖主题开关 reduced-motion snap。新增 Dart VM Profile 计数显示 20 轮导航中主要托管对象在一次预热后没有继续增长；此结果不覆盖 GPU/native 资源数、controller 活跃状态或真实显示呈现。

以下情况使本阶段仍不能结束：

- 800↔1440 logical px 原生连续窗口缩放已完成三轮；工作台、连接、活动、设置四页与连续缩放的联合负载也完成三轮并达到帧时门槛。七个长列表/表单场景各完成三轮原生 Profile 滚动；参数表单原始其中一轮记录到 112.742 ms build 峰值，另五轮不同轮次复测未重现，原因仍未定位，故该场景保留为部分通过。主题开关已完成三轮往返；只读 CoreGraphics 事件时间戳另实测六次交替拖动，实际移动跨度为 455.4–466.1 ms；拖动取消和固定动画关键帧对照仍缺。现有“四页联合负载”具体指窗口连续缩放时往返滚动工作台、连接、活动、设置；另完成三轮各 60 秒的跨类别组合压力，包含上方动作按钮、播放控制、主题往返拖动、滚动、原生窗口 Fill/Restore 和一次隐藏/恢复。每轮输入活动窗 39.129–39.459 秒，build/raster 超预算率为 0–0.0434%；完整统计见验收记录。
- 两轮明确的隐藏/恢复采样各出现约 12.9 秒 Flutter.Frame 空档；一次恢复后的 raster 为 102.132 ms，重复轮为 24.851 ms。现有 Widget 测试覆盖 TickerMode、应用生命周期、离屏和 reduced motion。UI-6.5 的路由循环、RSS、源码所有权审阅和 Dart VM 托管对象数量已按条款通过；GPU/native 对象、Texture/Skia 分配与 controller 活跃状态未测，作为明确范围限制保留。
- 已观察浅深主题与中间拖动态并归档 Profile 截图；已另建 9 组视频原帧/Flutter 拟合渲染对照，覆盖静置端点、近似 0.25/0.5/0.75/1 位置及视频中实际发生的部分反向轨迹。反向轨迹只到约 0.08 后再次向前，不伪称完整 1→0；关键帧对照不能代替原生连续手势与用户最终材质确认。
- CUA 已通过 AX 状态逐次确认 54 次主题深浅端点拖动并观察过一次中间光效。焦点环已按实际轨道圆角定位，Profile 实窗截图显示其位于 artwork 上方；Widget 回归检查 2px 线宽、中心、大小与圆角。2026-11-15 新增真实键盘焦点下浅深主题焦点环合成像素测量，最低对比度分别为 3.30:1 / 3.93:1，达到 3:1 项目目标；截图及 SHA-256 见验收记录。按钮 fixture 截图能看到禁用态变暗。2026-11-15 进一步用 Profile 最小夹具检查玻璃按钮、裸 `Semantics`、语义包裹 `TextButton` 与普通禁用 `TextButton` 四种控件；Flutter Widget Semantics 均为禁用且没有 tap action，但 `agent-desktop` 与直接 `AXUIElementCopyAttributeValue(kAXEnabledAttribute)` 均报告原生 `AXEnabled=true`。原因定位到 Flutter 3.47.8 / Engine revision `cf636b1dfb`：桌面 AccessibilityBridge 的 `SetStateFromFlutterUpdate` 没有把 `is_enabled=false` 转成 `Restriction::kDisabled`，而 macOS 的 `AXEnabled` 根据该 restriction 计算。Flutter 官方主干已有对应转换（[bridge](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/common/accessibility_bridge.cc#L2297-L2304)、[macOS AX 映射](https://github.com/flutter/flutter/blob/master/engine/src/flutter/third_party/accessibility/ax/platform/ax_platform_node_mac.mm#L3239-L3244)）；本机稳定版尚未包含，现有应用层语义无法修复此桥接缺口。禁用态原生 AX 验收仍不通过，需待项目使用包含修复的稳定 engine 后重验。原生输入事件已逐次计时，约 450 ms 移动跨度有六次实测；仍缺 pointercancel 原生对照与逐帧关键相位，既有 `glass_motion_test.dart` 覆盖拖出取消、路由暂停/恢复、离屏注销与减少动态效果，不能代替本机 pointercancel 对照。

## 4. 性能门槛

以下是本方案拟定的项目验收门槛，不是平台性能保证。当前仅部分场景取得实测；逐项范围见上方摘要和验收记录。预算 `B=1000/实际刷新率`：60 Hz 约 16.67 ms，120 Hz 约 8.33 ms。没有对应设备/有效刷新率证据时，120 Hz 标记未验证。

- [ ] **UI-6.1** 部分通过：静置、按钮点击、播放、800/1024/1440/1512 固定宽度目录滚动交互、800↔1440 连续缩放、四页联合滚动缩放及 1024 主题往返拖动均有三轮门槛数据；工作台、连接首页、连接管理目录/能力明细、活动、音乐结果及 90 字段表单等七个长列表/表单场景也各有三轮原生 Profile 滚动数据。另有六次原生双向拖动事件时间戳、原视频轨迹的稀疏采样及 60/120 Hz 实时插值输入对照；输入点位吻合，但动态图像序列仍有约 `42–60 ms` 的估算偏移。另完成三轮各 60 秒跨类别组合压力：上方 6 个动作按钮、3 个播放控制、刷新状态、主题往返拖动、滚动、原生窗口 Fill/Restore 及隐藏/恢复均纳入同一轮；每轮 39.129–39.459 秒为输入活动窗，build/raster 超预算率为 0–0.0434%，细节见验收记录。隐藏应用的取消回退现已实窗通过，但 OS 发出的 `PointerCancelEvent` 未观测到；动态关键帧未通过。
- [ ] **UI-6.2** 部分通过：固定宽度滚动和三轮连续缩放样本没有 >100 ms Flutter build/raster 帧；长表单原始三轮中有一轮出现 112.742 ms build 峰值，另五轮不同轮次复测均未复现，原因未定位。两轮隐藏恢复样本出现约 12.9 秒 Flutter.Frame 空档，其中一次恢复样本有 102.132 ms raster，重复轮为 24.851 ms。2026-11-19 又对 800×632 logical px 的主题开关进行三轮 30 秒 Profile 拖动采样，每轮 26 次约 450 ms 往返拖动；三轮共 5,416 帧，build/raster P95 分别为 4.997–5.011/6.330–6.404 ms，均无超过 16.667 ms 的帧。该 60 Hz macOS Profile 夹具只记录 Flutter build/raster 耗时，不能用于判断 LGE AN10 Android 实机上的主观卡顿是否复现或已修复，也不覆盖真实显示呈现时序。2026-11-19 按同进程 macOS Hide/Activate 原生复测一次，13.083 秒帧空档后的首帧 raster 为 13.479 ms，未重现 >100 ms；历史 102.132 ms 仍作为未定位异常保留。
- [ ] **UI-6.3** 部分通过：已完成 UI-0 同机 Profile 基线与主题往返拖动对照，P95/超预算数据见验收记录；当前拖动与基线端点点击的输入不同。新一轮三轮 800×632 Profile 采样中，每轮交替拖动 26 次、每次 27 个移动事件，请求时长 450 ms；CoreGraphics 输入跨度为 450.12–454.15 ms，三轮均值为 452.59–453.18 ms，最终 AX 主题值均回到深色。Widget 测试覆盖 450 ms 实时指针过程和取消恢复；只读 CGEvent 时间戳显示，`agent-desktop --duration 397` 的六次交替原生拖动跨度为 455.4–466.1 ms，均值 460.8 ms、中位数 460.2 ms，AX 端点逐次正确。`--duration 450` 的两次校准样本实际跨度为 517.9/524.0 ms，因此按系统事件测量而非 CLI 请求值报告节奏。另以原视频可见指针中心轨迹进行 60/120 Hz 连续实时输入，事件位置误差均约 0.00003 px，事件时差约在 4.4 ms 内；同时间图像比较仍更接近约早 `42–60 ms` 的源帧，未通过动态相位对照。另以离线工具固定输入采样时刻、仅将渲染时钟前移 46 ms；200 帧全图 MAE 从 `7.337185` 变为 `7.337683/255`，稳定视野从 `4.427293` 变为 `4.428351/255`，没有实质改善，因此未据此修改产品时钟。该偏移仍受重建轨迹、录屏采样和无 display-present 时间戳限制，只表示图像序列偏移估计。hidden/paused 生命周期的 app-level 取消回退已原生验证；OS 未发出 `PointerCancelEvent`，真实显示呈现帧率仍缺。
  - 2026-11-18 另拟合太阳射线频率/相位候选 `2.218/.333937`，在 16 个留出帧上亮度 RMSE 略降，但完整 200 帧稳定视野 MAE 仅从 `4.42729291` 降至 `4.42728696/255`，控件 ROI 从 `7.82858628` 降至 `7.82855220/255`。收益可忽略，拒绝候选，产品仍用 `2.2/.5050001`；完整方法见[验收记录](acceptance-record.md#2026-11-18-ui-63-太阳射线频率相位交叉验证)。
- [ ] **UI-6.4** 部分验证：2026-11-17 本轮新增 app-level 系统偏好绑定和 macOS `NSWorkspace` Reduce Motion 事件流；全量 `flutter test --no-pub` 298 项、`flutter analyze --no-pub` 和 macOS Profile 构建通过。独立 800×632 logical px Profile 窗口、macOS 27.2.1（Mac17,9 arm64）、Flutter 3.47.8 / Dart 3.13.7；系统设置开启时 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion=true`，窗口读到 `SYSTEM_REDUCE_MOTION true`，主题按钮切换至浅色、点阵动作按钮回调从 0 增至 1。另有 34 项定向测试覆盖 `TickerMode`、应用生命周期暂停/恢复、完全离屏注销、reduced-motion 点击功能及主题取消/反向；新增 app-level 回归验证系统值开关时 `MediaQuery` 更新且主题操作仍生效。Reduced Motion 运行时通知已接线。2026-11-18 在隔离原生 Profile 预览的运行期间，通过系统设置界面将该选项由关闭切为开启再关闭；临时 AX 标签同时观察 `MacReduceMotionPreference` 与根 `MediaQuery.disableAnimations`，两者在两秒内按 `false/false → true/true → false/false` 更新。仅此一项补验通过；隐藏恢复帧空档、102.132 ms 原始 raster 长帧根因和混合生命周期负载仍未完成。2026-11-17 原生隐藏/恢复拖动测试确认 `hidden` 生命周期会取消主题拖动；恢复后迟到的 mouseUp 不再提交，下一次点击正常；但系统没有发出 `PointerCancelEvent`。此前两轮隐藏恢复仍各有约 12.9 秒帧流空档，一次恢复帧为 102.132 ms；长帧根因与离屏/生命周期混合交互仍未完成。
- [x] **UI-6.5** 通过（路由循环与 Dart VM 托管对象审计范围）：完成 20 轮页面往返（80 次导航）、进程 RSS 时间序列、源码资源所有权审阅及原生 macOS Profile 进程中的 Dart VM GC 后对象计数。第 1、5、10、20 轮的 `Ticker`（200）、`_WidgetTicker`（29）、`AnimationController`（222）、`ui.Image`（2）、`FragmentProgram`（2）、`FragmentShader`（2）与 `_NativePicture`（181）均持平；第 0 轮 `_NativePicture` 为 144。预热后没有观察到 Dart 管理对象持续增长。计数不代表 GPU/native 图片、纹理、Skia 分配，也不显示 controller 是否正在 tick；这些未测项作为范围限制记录，不扩展成该项的通过声明。

静置装饰可有意按约 30 Hz 更新；这不等于页面只能响应 30 Hz。原主题的固定模拟步进不因显示器刷新率而修改。帧时门槛与真实显示流畅度需同时检查。

## 5. 视觉对照与质感验收

1. 对设计稿和原生样本使用相同逻辑显示尺寸、外观、DPR、背景坐标和固定动画相位。对齐控件外框后比较，标注引擎采样/字体造成的差异，不能通过整体模糊、任意校色或遮罩藏掉材质问题。
2. 保存 idle 与点击归一化时刻 0、0.25、0.5、0.75、1，以及反向切换关键帧；另看真实时间连续动作，静态对齐不能替代节奏验收。
3. 本轮布局对齐目标：关键按钮外框、中心与相邻控件基线相对确定的设计尺寸偏差不超过 1 个逻辑像素；点阵采用 UI-2 同一设计坐标。跨引擎颜色/光栅差异单列，不以一个全图平均误差代表质感已一致。

原 MP4 删除后，用户指定的 [Glass Light Toggle 网页](https://experiments.thisiswhitespace.com/glass-light-toggle) 作为当前可访问机制/观感参照。2026-11-18 复核确认当前 Next.js 页面通过 iframe 加载 `/standalone/glass-light-toggle/index.html`，其中 `main.js?v=3` 的 SHA-256 与此前快照和仓库独立 oracle 一致；此前对两个错误根路径的 404 不代表线上实验源码不可用。实时模型和光学回归在相同源码快照范围内通过；另以固定 LCG 种子核验官方脚本生成的全部 113 组粒子初始化系数，实时/模拟 10 项定向回归通过。按网页 `requestAnimationFrame` 单帧 `1/30 s` 上限，也移除了本地超过 2 秒暂停后直接吸附端点的分支。产品网页仍会随机生成系数，线上运行与 Flutter 产品也不共享随机数或动画时钟；本次仅在隔离 Chromium Profile 中固定测试种子。2026-11-19 已补充四段真实正反向线性拖动、两个独立窗口的 WindowServer displayTime 帧索引与共同主机 Mach 时钟校准，详见下方验收记录。两窗口操作是顺序执行而非同时输入，displayTime 也不是面板扫描时间；UI-6.8 动态相位只获关键进度点补证，整体逐帧 1:1 仍待验收。

- [ ] **UI-6.6** 部分目视：浅深设置页 Profile 实窗已导出并归档；正文、主题按钮文字与太阳/月亮点阵核心的合成像素对比度抽样均达到各自目标。选中态光弧仅有探索性局部值（深色 2.32:1、浅色 1.15:1），按次要装饰处理。焦点环按实际轨道的中心、尺寸和圆角在 artwork 前景绘制，Widget 几何断言通过；真实键盘焦点下浅深主题的合成像素最低对比度为 3.30:1 / 3.93:1，截图见验收记录。按钮 fixture 已在 Profile 实窗分别归档深浅主题中的 12 类 96dp 点阵和五种 `GlassButtonSize`/导航、分段、危险、忙碌、禁用样式，截图列在验收记录。生产连接首页、工作台（侧栏“所有功能”）、管理连接、活动和设置页均有双主题 Profile 静态截图并完成代理自验；范围与限制见[验收记录](acceptance-record.md)。静态样本不能代替 VoiceOver 语音、所有控件实例的逐项复核或动态状态验收。禁用按钮视觉为灰化；在 VoiceOver 已开启、`AXEnhancedUserInterface=1` 的 3.47.8 Profile 探针中，玻璃禁用按钮、禁用 `Semantics` 包装项及其子按钮均报告 `AXEnabled=true`，该项不通过；3.50.0 精确定位复测中各类禁用节点仍无可读 AXRole/名称，启动前开启 AX 增强树无改善，不能作为已修复的版本。具体对照见验收记录。视频原帧/拟合渲染选帧对照为 `/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/theme-switch/stage6-keyframes.html`，选帧进度由实测开关中心推算，拟合渲染不代表 macOS 实窗逐帧捕获。
- [ ] **UI-6.7** 部分目视：源码审计扫描到 109 个生产玻璃动作/图标按钮调用点（20 个文件）；macOS 正式入口提供 `GlassMotionScope`，平台包装器与直接 `GlassActionButton` 调用最终共用同一渲染器，Material 按钮处于非 macOS 或无玻璃作用域的回退分支。Profile fixture 覆盖五种按钮尺寸、七种按钮类型和 selected、busy、disabled 等变体；`flutter test --no-pub test/glass_motion_test.dart test/glass_action_button_test.dart` 21 项通过，全部 60 个 glyph 的唯一 idle/click 动作模型、点击采样和双主题图案测试均通过。2026-11-18 隔离 Profile 暗色实窗补证覆盖首页、工作台、运行表单/确认/结果、终端、连接设置、音乐账户/搜索授权/歌曲播放确认/迷你播放器，以及 Mac Host 停止、运行、配对、邀请详情、权限、撤销/轮换确认和批准只读后的状态；另外查看 JSON 展开和本地模拟错误结果。随后补拍浅色设置页、运行表单/确认、音乐播放器样例态、错误恢复状态，以及连接列表、目标选择、连接配置和动作编辑器的浅深静态实例；本批另目视浅色连接详情和深色删除确认弹窗，删除操作未确认执行，内存连接未删除。浅色错误恢复页另有原生 Profile 末尾位置截图 `61-error-result-light-scroll-end.png`；错误卡片和恢复操作完整位于 MiniPlayer 上方，额外滚动后 AX 位置不变。Widget 回归也验证嵌入运行页最大滚动范围可达；未发现此处生产布局缺陷。Host 与音乐交互使用进程内 stub，连接配置仅打开内存预览，没有网络监听、Keychain、外部音乐服务、命令运行或真实 Android 配对。工作台 B012–B017 的搜索、筛选和空态已补浅色 Profile/Widget；动作编辑器 B018–B023 另在浅色 Profile 实窗验证新增、取消草稿、参数预览、保存到进程内 fixture，以及原生导入/导出面板取消。回归测试确认取消不写入草稿；预览没有运行程序，保存不触碰磁盘。连接设置 B024–B032 在浅色 Profile 实窗核对目标选择、本机原生文件面板取消、Host 查找未命中及本机安全 stub 测试；紧凑表单后续在 540×700pt 的 Profile 实窗进入小于 600pt 分支并点击关闭，收起后未保存；这更正了此前基于另一轮 768pt 窗口的误判。连接详情的浅色紧凑返回、重排、编辑器取消、测试刷新及删除确认取消另已实窗操作（见验收记录 B033–B043）。2026-11-19 又在暗色紧凑 Profile 复核删除确认取消、详情返回、重排并恢复原序、编辑器取消及 MCP 内存测试；未确认删除。首行上移按钮视觉呈禁用态，但当前 AX 读取未提供 enabled 状态，仍未签收禁用语义。B037 只在移动端呈现；B044–B047 属通用 AddConnectionDialog，macOS 正式路由不使用。细节见验收记录和逐实例矩阵。仍未核对其余浅色页面、深色连接删除确认动态、搜索授权弹窗、所有调用点的动态/静置状态及其他未覆盖实例；共享组件、变体测试及局部截图只能提供部分覆盖，不能替代全部视觉签收；UI-6.7 保持部分验收。活动页隔离 Profile fixture 可用 `UI6_SEED_ACTIVITY=true` 预置成功、校验失败和取消样例，并可用 `UI6_SEED_ACTIVITY_RUNNING=true` 另加合成运行中记录，`UI6_SEED_ACTIVITY_FILTER_STATES=true` 补入合成超时和结果待确认状态；浅深实窗查看活动筛选、紧凑详情与返回列表，点击过滤/返回及刷新只作用于内存预览。浅色 Profile 逐个点击六类状态筛选，每次仅显示对应记录，点击“全部”恢复六类样例；具体按钮状态及证据见验收记录。暗色和浅色实窗中的运行中记录均可将“取消运行”滚入操作区并触发，详情 AX 状态转为“已取消”；浅色取消按钮底边至 MiniPlayer 暂停按钮上缘相隔 11 个逻辑像素，未发生按钮遮挡。此为本地 fixture 反馈，不替代真实运行服务异步终态核验。逐调用点状态见[UI-6.7 按钮实例核对表](ui-6.7-button-instance-matrix.md)，Profile 证据与缺口见[验收记录](acceptance-record.md)。
  - 2026-11-19 另用 540×700pt macOS Profile 隔离夹具，在浅/深主题实点 B002 连接导航（Git CLI）和 B003 分区导航（活动），两种主题均进入对应页面。页面图及 AX 刷新延迟边界见[验收记录](acceptance-record.md#2026-11-19-ui-67-b002-b003-应用外壳导航浅深-profile)与[实例矩阵](ui-6.7-button-instance-matrix.md)。本批只签收路由结果，不代表点击动画、选中态差异或物理 display-present 已通过。
  - 2026-11-19 B009「重新打开功能」在独立 bundle 浅色 macOS Profile 中取得失败详情截图并 AX 点击，进入“两整数相加”参数页，状态仍为“尚未运行”；深色 Profile 也取得失败详情静态截图并读到 139×40pt hit target。深色 AX 点击后窗口立即从可访问窗口清单消失，未取得目的页证据。已有 Widget 回归覆盖名称、≥40×40 hit target 和只搜索/打开行为。按下动画时序与显示呈现仍未验，B009 仍部分验收；详情见[验收记录](acceptance-record.md#2026-11-19-ui-67-b009-深色-profile-静态复验)及[实例矩阵](ui-6.7-button-instance-matrix.md)。
  - 2026-11-19 B011「复制诊断」新增 macOS Widget 回归：测试通道截获唯一 `Clipboard.setData`，精确验证脱敏运行 ID/状态/时间和成功提示；系统剪贴板未读写。Profile 点击动画与原生剪贴板接线仍待验，B011 保持部分验收，见[验收记录](acceptance-record.md#2026-11-19-ui-67-b011-复制诊断widget回归)及[实例矩阵](ui-6.7-button-instance-matrix.md)。
- [ ] **UI-6.8** 部分通过：播放/暂停、前后曲、翻页和 54 次主题端点拖动已实窗观察，AX 状态逐次交替；Widget 测试验证 450 ms 拖动途中不提交、释放后提交，且 pointer cancel 回到原端点。隔离 Profile 实窗六次交替拖动由只读 CGEvent 逐事件计时，实际移动跨度为 455.4–466.1 ms，AX 端点逐次正确；按下到首个移动事件另有 189–201 ms 拾取等待。原视频轨迹的 60/120 Hz 实时输入路径均由系统 tap 复核，图像序列最佳偏移仍约 `42–60 ms`。2026-11-17 原生隐藏应用期间 `hidden` 生命周期回调取消正在进行的拖动；恢复后迟到的释放事件到达，主题仍保持原端点，随后正常点击仍可切换。该实测中 OS 没有发出 Flutter `PointerCancelEvent`，因此只证明隐藏/暂停生命周期的取消回退，不证明原生 pointercancel 对照。关键帧 HTML 对照保留来源时间与估计位置，不能作为实时对照通过凭据。2026-11-18 将实时积分改为逐刷新使用实际 `dt`，并按原版上限截断到 `1/30 s`；删除固定 `1/60 s` 累积步进，避免 120 Hz 下动力状态隔帧不更新。随后按当前网页补齐长间隔恢复规则：暂停超过两秒时也只执行一次单帧上限积分，不吸附未完成的动画；定向实时/模拟回归 10 项通过。另使用官方脚本 SHA 对应源码和固定 LCG 种子逐项核验全部 113×7 粒子初始化参数。2026-11-18 的旧生产路由断言曾检查 `videoFittedThemeSwitch`；用户指定网页参考后，2026-11-19 macOS 设置路由已改用 `ThemeSwitchCalibration.reference`，Android 默认仍为 `videoFittedThemeSwitch`。另用独立 66 帧映射导出的 +19.78669 ms 渲染时钟候选复核，200 帧离线对照未降低误差，候选已拒绝，未改产品时钟（细节见验收记录）。2026-11-18 又从当前实验 iframe 通过 CDP 真正执行正、反向拖动，并在 320×240 logical 的隔离 Profile fixture 中用生产 `GlassThemeSwitch` 与 `videoFittedThemeSwitch` 参数执行两向 3 秒真实拖动，每次手势期间按五个时点采集应用窗口；内部粒子、太阳/月亮形态与边缘光持续变化，端点 AX 状态正确。网页与该历史原生捕获未共享输入时钟、帧时间戳或随机种子，renderer 亦不同，且没有物理 display-present 时间戳；所以这补充了实时机制和方向性证据，不是同步逐帧签收，也没有解决原视频约 `42–60 ms` 相位差。详情见[验收记录](acceptance-record.md#2026-11-18-ui-68-当前网页与原生拟合组件实时拖动复核)、[长间隔恢复规则](acceptance-record.md#2026-11-18-ui-68-长间隔恢复遵循网页单帧上限)及[粒子初始化源码对照](acceptance-record.md#2026-11-18-ui-68-官方脚本-113-组粒子初始化参数对照)；动态相位仍未签收。
  - 2026-11-18 将官方脚本固定种子下的 113 颗粒子完整 151 帧 x/y/size/alpha 轨迹存为校验过 SHA 的压缩 oracle，Dart 模型逐项通过，粒子状态共 17,063 组。相同状态下比较完整 151 张官方 WebGL 与 Flutter widget-test shader 图片，平均 MAE `0.0631750/255`、最大 `0.0747111/255`；另用 macOS Profile / Impeller `MetalSDF` 逐帧导出生产 `ThemeSwitchArtwork`，对齐到 center (360,267) 后平均 MAE `0.3868485/255`、最大 `0.4163683/255`。Profile 捕获不是 display-present 实际显示时间；录屏种子、线上网页实时同步仍未完成，见[轨迹对照](acceptance-record.md#2026-11-18-ui-68-官方脚本全-151-帧粒子轨迹对照)、[widget-test 图像对照](acceptance-record.md#2026-11-18-ui-68-官方-webgl-与-flutter-shader-同状态图像对照)及[Profile 图像对照](acceptance-record.md#2026-11-18-ui-68-macos-profile-impeller-全-151-帧同状态图像对照)。
  - 2026-11-19 用户用当前网页替代已删除 MP4 后，macOS 设置路由改用 `ThemeSwitchCalibration.reference` 的默认连续模型和种子；`AppearanceSelector` 的默认配置及 Android 路由仍用 `videoFittedThemeSwitch`。太阳/月亮状态机、手势、回调和 Android 行为未改。用与 macOS 控件同宽的网页本地确定性夹具（`main.js?v=3`、LCG seed `1831565813`），在 Profile 真实窗口以 30 个移动点、每向 500 ms 双向拖动；全屏同一张捕获同时含网页与应用，并采集按下、25/50/75/100% 和松手稳定态。网页 DOM 主题与应用 AX 端点在两向结束后相符。粒子与光弧持续变化，目视形态接近当前网页默认模型；原生焦点环仍是网页没有的额外视觉层。CDP/CGEvent 调用时间、截图及 SHA 见[同步参考记录](acceptance-record.md#2026-11-19-ui-68-网页与-macos-profile-同屏双向对照)。此证据不是共享渲染时钟、逐帧逐像素验收或物理 display-present 时间测量；UI-6.8 仍部分通过。
  - 2026-11-19 按用户随后提供的参考 URL 再做逐窗口连续采集：当前 iframe 的 `main.js?v=3` SHA `7f7b5d15…`；隔离网页与 macOS Profile fixture 各捕获 694/690 张 WindowServer 帧，所有帧成功写盘，实际 CGEvent 轨迹每向 30 个等距水平点。正反向共四次手势顺序执行，以实际轨迹进度和 displayTime 为每个窗口选 9 个关键样本；最近帧对目标事件时刻的最大偏差 7.970 ms。全流帧间隔中位数 17.213/17.302 ms，P95 19.207/19.055 ms；窗口内观察到最多 36.400 ms 间隔，仍有少数采样空档。目视检查两方向接触表，粒子形态、光效和过渡节奏在所选进度上接近，原生焦点环仍是额外视觉层。详细时钟校准、事件路径、SHA 与限制见[WindowServer 连续拖动记录](acceptance-record.md#2026-11-19-ui-68-网页与-macos-profile-windowserver-时间关联的双向拖动复验)。这补足共同主机 Mach 时间轴与 displayTime 关键帧关联，不是同时输入、逐帧逐像素零差异或物理面板测量；UI-6.8 仍部分通过。
- [x] **UI-6.9（代理静态截图自验范围）** 通过：已逐张查看五个生产页面的浅/深首屏、工作台与设置页底部、侧栏焦点和主题开关焦点截图，并核对页名与截图内容；当前范围内未发现明显的整体背景断层、材质层级或主要控件位置问题。源码映射和共享变体测试提供 UI-6.7 的部分覆盖证据，但该截图组只覆盖五个生产页面，未完成其他按钮实例的布局签收。静态自验仍不覆盖静置/点击动画逐帧、VoiceOver、原生帧呈现或用户对动态质感的主观确认；这些缺项不因本项通过而关闭。

### 2026-11-17 按钮图案 Profile 检查页补充

隔离 Profile fixture 已将原 60 项静态 glyph 字典改为 60 个可点击的 `GlassActionButton`，保留 12 类参考样本与动作状态样本。Flutter 3.47.8 的 macOS AX 树能够按 `GlassGlyph` 顺序枚举全部 60 个 glyph 按钮及名称。深色 800×632 和浅色样本已目视检查；1512×949 logical px 的完整网格及左右半屏视图已检查全部 60 个静态图案，点阵颗粒、按钮材质与排列整体一致，未发现明显错位或渲染异常。静态检查没有逐一检查每个图案的静置/点击光效、运动相位或真实生产实例，故不关闭 UI-3 的原生动效逐项验收、UI-6.7 或 UI-6.9。

截图保存在本机视觉证据目录，PNG SHA-256 如下：

- [深色完整 glyph 网格截图](/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-native-review/button-glyph-grid-dark-max-1512x949.png)：`94b94482010c2a40b6028205e2d8c6533dbcb90a7e73bda7f5e52e6c77d05280`。窗口 AX bounds 为 1512×949 logical px；截图包含原生窗口框。
- [深色按钮样本](/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-native-review/button-samples-dark-800x632.png)：`72ee7dc973616cb2d2a05262d3c0abcf1e705ab645baac305207271d5f476baf`。
- [浅色按钮样本](/Users/guo/.codex/visualizations/2026/11/13/01a1d606-f887-7930-ad30-645440d89f65/stage6-native-review/button-samples-light-800x632.png)：`6aa7a202f3dc0c994e0d58620a9b7b1f700dae2ab6cdffbce56eac0911af3207`。

### UI-6.8 焦点环隐藏后的网页/Mac 双向连续帧复核（2026-11-23）

为排除指针焦点环对材质观察的遮挡，在隔离网页与 macOS Profile 窗口中用 CDP/CGEvent 按同一预定起点执行正反向拖动；每向 48 个等距移动点、780 ms，释放后移出指针。两窗口的完整 display frame 分别为 395/391，视频到 display frame 的时间关联 RMS 为 0.477/0.465 ms。每方向 49 对关键进度样本，配对时间差最大值为 17.88 ms（正向）与 16.21 ms（反向）。接触表显示轨道和光弧整体接近；中段太阳点阵仍有可见形态差异，故不签收逐帧 1:1。原始视频、时间戳及 SHA 见[验收记录](acceptance-record.md#2026-11-23-ui-6-8-焦点环隐藏后的网页mac-双向连续帧复核)。页面不是已删除的 MP4，displayTime 也不是物理面板呈现时间。

### 2026-11-24 设置页双主题背景连续性复核

隔离 Profile 设置页通过 AX 将主题从深色切到浅色并恢复；两张实窗截图未见开关绘制区域周围的清晰矩形边，背景渐变连续。仅签收静态背景连续性，不代表动画或逐帧差异通过；详情和截图哈希见[验收记录](acceptance-record.md#2026-11-24-ui-6-设置页双主题背景连续性实窗抽查)。

## 6. 最终交付与回退

提交前检查所有阶段记录，确认没有将待验收项填成通过。交付代码和必要测试基线、设计参数/实现对应表、原主题逻辑冻结证明与仅呈现差异说明、测试日志索引、原生深浅截图/动效证据和三轮性能报告。原始大量录屏、构建产物与敏感配置放在合适的本地证据目录，不直接纳入源码提交。

按项目提交规则只提交本轮文件，使用简洁中文提交信息，正常推送当前上游和 `origin`，分别读取远端分支 SHA 并与本地比较。远端拒绝时保留本地提交并记录阻塞，不强推。回退通过逐阶段反向提交恢复 macOS 呈现，不改连接数据、凭证、Runtime 或原主题实现。

- [ ] **UI-6.10** 未完成：未验收的项与证据边界均已如实登记，待补齐后才能完成阶段关闭。
- [x] **UI-6.11** 通过：仅修改共享 Flutter 页面布局与长列表构建方式；没有改 Android 专用代码、主题模拟/校准算法、业务协议或切换逻辑。连接首页桌面目录改用 SliverList builder，紧凑目录在 40 项以上切换惰性 PageFrame；管理连接目录与能力明细在少于 40 项时保留自然高度，达到 40 项时改用有界 `ListView.builder`/`ListView.separated`，并以 1 项自然高度和 90 项懒构建回归；音乐搜索结果 40 项以上改用有界惰性列表，较短结果保留原自然展开语义；运行参数 40 字段以上启用有界 ListView.builder，逻辑校验仍遍历全部字段；Profile 入口、窗口扫宽代码已清理；`pubspec.lock` 的任务前 SHA 保持不变且不纳入阶段提交。全量 App 测试 289 项、UI review 12 项、连接列表专项 4 项均通过，静态分析无问题；此项不关闭 UI-6 的动态视觉、VoiceOver、原生取消或帧呈现验收缺项。
- [x] **UI-6.12（部分报告）** 已提交前序验收文档 `98749bb2536420c3e43acd6a4f3409ccac608bcf`；工作台/活动与连接、管理、音乐目录子阶段分别有独立提交。本轮 90 字段参数表单惰性构建及回归提交 `490d13d390e3b6521e07e63e8e2ddddff75899ec`。由于其他 UI-6 验收项仍待补，未将整套 UI 适配登记为已交付。

### UI-6.7 补证：设置活动记录清理按钮（2026-11-18）

隔离 macOS Profile 夹具中对 B081–B083 完成浅/深静态截图与内存活动样例交互：取消保留三条记录，确认清空后活动页为空。截图、哈希、环境和回调隔离范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-设置活动记录清理按钮-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。本补证不含按下动画关键帧或 FrameTiming，不关闭 UI-6.7 全量生产实例验收。

### UI-6.7 补证：运行、刷新、搜索点击态（2026-11-18）

共享 `GlassActionButton` 的 96 dp Profile fixture 已在浅色、深色中对三枚主图标分别完成合成指针点击；本地回调计数逐个增加，截图显示运行右移、刷新旋转、搜索镜片扩张。`glass_motion_test.dart` 新增位移/缩放阈值回归，与按钮、glyph golden 定向套件共 29 项通过；Flutter 3.47.8 Profile 构建成功、清理临时入口后的 `flutter analyze --no-pub` 无问题。截图与哈希、指针投递边界及实际覆盖范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-三枚主图标点击反馈增强与-profile-复核)。这只证明共享组件在参考尺寸上的动作模型和隔离实窗反馈，不签收全部 109 个生产调用点；UI-6.7 保持部分验收。


### UI-6.7 补证：Mac Host 设置控件（2026-11-18）

隔离 Profile 中对 B088–B090 做了浅/深 Host 启停、轮换确认取消和邀请生成检查。Host 假实现没有开启监听；44321 端口无 listener。B088 两主题启停状态已读回；B089 只验证取消保持状态；B090 滚动实窗截图显示完整二维码和复制按钮。后续 Debug 语义树将复制按钮的本地语义矩形读为 40 px，但同状态 live macOS AX 仍只有 1 px 高；这排除了按钮本地语义框尺寸错误，但没有定位坐标/裁剪差异的具体责任层。截图 SHA、配置和隔离范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-mac-host-启停轮换确认与邀请-profile-验收)、[B090 语义对照](acceptance-record.md#2026-11-18-ui-67-b090-flutter-semantics-与-macos-ax-边界对照)及[逐实例表](ui-6.7-button-instance-matrix.md)。未采按下帧或 FrameTiming；没有触发网络配对，UI-6.7 仍部分验收。


### UI-6.7 补证：Mac Host 配对与设备权限（2026-11-18）

B092–B098 在隔离 macOS Profile 中覆盖待配对/已配对卡片、只读审批、连接向导审批、自定义批准、逐连接权限保存和撤销取消。`Ui6InspectionHost` 只改当前进程内 fake grant；Host 端口 44321 无 listener。AX 状态树确认审批、编辑和取消结果；所有 AXPress 回执均未单独验证物理输入。完整环境、截图 SHA 与覆盖限制见[验收记录](acceptance-record.md#2026-11-18-ui-67-mac-host-配对与设备权限-profile-验收)和[逐实例表](ui-6.7-button-instance-matrix.md)。本次只有暗色静态/交互态，没有按下关键帧或帧率数据，UI-6.7 仍部分验收。


### UI-6.7 补证：权限弹窗按钮 B099–B101（2026-11-18）

已在前一节 B096/B097 同一 Profile fixture 中实窗点击 B099 取消、B100 保存和 B101 逐连接权限 chip；取消保持 grant，保存更新假 grant，chip 的 AX 选择态符合读取/控制/外部写入约束。截图复用[验收记录](acceptance-record.md#2026-11-18-ui-67-mac-host-配对与设备权限-profile-验收)。没有物理按下帧或帧率证据，UI-6.7 仍部分验收。


### UI-6.7 补证：工作台功能行 B102–B103（2026-11-18）

暗色 Profile fixture 中点击能力行只进入未运行的参数页；收藏按钮在 PreviewRuntime 内增加收藏，再取消并复核恢复为空集合。没有执行 MCP/CLI 操作或写持久偏好。截图及 SHA、AX 回读和覆盖边界见[验收记录](acceptance-record.md#2026-11-18-ui-67-工作台功能行-b102b103-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。无按下帧或帧率数据，UI-6.7 仍部分验收。


### UI-6.7 补证：通用页面错误态 B104（2026-11-18）

临时暗色 Profile 夹具直接呈现生产 `PageState.error`，点击“重试”后 AX 计数从 0 变为 1；夹具回调只计数，没有触发数据加载或网络请求。静置截图 SHA、AX 回读、清理结果和验收限制见[验收记录](acceptance-record.md#2026-11-18-ui-67-通用页面错误态-b104-临时夹具验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。无按下关键帧、浅色状态或 FrameTiming，UI-6.7 仍部分验收。


### UI-6.7 补证：错误结果恢复操作 B106（2026-11-18）

暗色 Profile 中本地模拟失败结果可滚动到 MiniPlayer 上方并完整显示“检查活动状态”入口。点击后 AX 状态不变：假 Runtime 在返回 RunHandle 前抛错，恢复回调因没有 handle 直接返回；这只限定本地模拟路径，不能代表真实 Runtime 活动查询。截图、SHA 与覆盖边界见[验收记录](acceptance-record.md#2026-11-18-ui-67-错误结果恢复操作-b106-profile-补证)和[逐实例表](ui-6.7-button-instance-matrix.md)。无按下帧或 FrameTiming，UI-6.7 仍部分验收。


### UI-6.7 补证：本地文件结果 B108–B109（2026-11-18）

临时暗色 Profile 夹具呈现生产 `ResultPanel` 文件结果；B108 预览只通过 PreviewRuntime 返回内存说明文本，B109 的 fixture Finder 揭示回调为空实现，前后均没有 Finder 窗口。截图、SHA 与未覆盖生产文件行为的范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-本地文件结果-b108b109-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。未触及复制按钮或剪贴板，无按下帧/FrameTiming，UI-6.7 仍部分验收。


### UI-6.7 补证：结果待确认恢复 B107（2026-11-18）

隔离 Profile 只读恢复内存中的 `outcomeUnknown` 样例；点“检查活动状态”后状态仍待确认，并出现不自动重跑的提示。没有访问真实执行端或重放操作。截图与范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-结果待确认恢复-b107-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。没有按下帧/FrameTiming；UI-6.7 仍部分验收。


### UI-6.7 补证：Mac Host 撤销与身份轮换确认 B085/B087（2026-11-18）

Profile fake Host 中确认撤销后配对卡片消失；确认身份轮换后 AX 提示成功、Host 关闭且列表清空。44321 无 listener，未读 Keychain 或连接手机。截图 SHA、状态回读和限制见[验收记录](acceptance-record.md#2026-11-18-ui-67-mac-host-撤销与身份轮换确认-b085b087-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。无按下帧/FrameTiming，不代表真实设备或证书操作；UI-6.7 仍部分验收。


### UI-6.7 补证：暂停播放权限确认 B048–B050（2026-11-18）

暗色隔离 Profile 验收了无参“暂停播放”动作的权限确认取消与确认执行：取消后状态保持“尚未运行”；确认后 `PreviewRuntime` 返回内存预览结果“暂停播放”。未控制播放器或触碰外部服务。截图哈希和验收边界见[验收记录](acceptance-record.md#2026-11-18-ui-67-暂停播放权限确认暗色-profile-验收)及[逐实例表](ui-6.7-button-instance-matrix.md)。未点击复制或访问剪贴板，无按下帧/FrameTiming；UI-6.7 与 UI-6.8 仍部分验收。


### UI-6.7 补证：运行三角视觉居中（2026-11-18）

Profile 浅/深静置对照确认，运行三角先前锚在 9×9 网格最左列，已将其右移两格；点阵形状、共享圆点风格、刷新/搜索轮廓、动效与按钮逻辑保持不变。按钮、glyph、motion 联合回归 29 项，静态分析和 Profile 构建通过。截图与哈希见[验收记录](acceptance-record.md#2026-11-18-ui-67-运行刷新搜索图案居中微调)。只签收组件静置图案位置，没有按下帧或 FrameTiming；UI-6.7 仍部分验收。


### UI-6.7 补证：结果复制的隔离 Widget 回调 B105（2026-11-18）

通过 macOS Widget 变体将生产 `Clipboard.setData` 平台调用截获至内存，验证一次点击、文本/JSON 拼接内容和成功提示；系统剪贴板未读取或改写。定向测试 1 项通过，详情见[验收记录](acceptance-record.md#2026-11-18-ui-67-b105-复制结果-widget-级拦截验收)和[逐实例表](ui-6.7-button-instance-matrix.md)。此证据不替代原生 Profile 系统剪贴板动作，UI-6.7 仍部分验收。


### UI-6.7 补证：Mac Host 邀请复制 B091（2026-11-18）

macOS Widget 测试使用 fake Host/邀请，将生产 `Clipboard.setData` 截获到内存；复制一次后 payload 与对应二维码 payload 一致，成功提示可见。定向测试 1 项和静态分析通过。没有写入系统剪贴板、启动真实 Host 或进行网络配对；不是原生按下帧验收。详情见[验收记录](acceptance-record.md#2026-11-18-ui-67-b091-mac-host-配对信息复制-widget-验收)和[逐实例表](ui-6.7-button-instance-matrix.md)。UI-6.7 仍部分验收。


### UI-6.7 补证：Mac Host 邀请二维码完整可见 B090（2026-11-18）

暗色隔离 Profile 中启动 fake Host 并生成邀请，滚动到详情后实窗截图显示完整二维码、过期时间、地址数量和复制按钮；最终截图同一状态下 live AX 读取仍返回 `x=602,y=749,width=139,height=1`。Debug Flutter Semantics 本地节点矩形为 40 px，说明按钮本地语义尺寸正常，但原生 AX 几何仍不符；当前证据不能定位坐标/裁剪差异发生在哪一层。图像 SHA 与范围见[验收记录](acceptance-record.md#2026-11-18-ui-67-b090-mac-host-邀请二维码完整可见性复核)、[语义对照](acceptance-record.md#2026-11-18-ui-67-b090-flutter-semantics-与-macos-ax-边界对照)及[逐实例表](ui-6.7-button-instance-matrix.md)。没有按下动画关键帧，故只通过截图可见性，不提升 B090 总体状态；UI-6.7 仍部分验收。


### UI-6.7 补证：高优先级生产按钮 B001/B005/B050（2026-11-19）

在暗色 Profile 中核对了全局搜索、活动刷新与暂停播放运行表单的实际上下文；之后补齐三者的浅色生产实例。B001 两主题均 AX 192×40，点击后 AX 确认进入“所有功能”；B005 两主题均 46×46；B050 两主题均 87×40，浅色实鼠标点击后取消权限确认，AX 仍为“尚未运行”。本轮没有确认执行，既有 B049 内存预览结果保持独立记录。浅色窗口截图、SHA、AX 回执和 fixture 边界见[验收记录](acceptance-record.md#2026-11-19-ui-67-高优先级生产按钮-b001b005b050-profile-核对)及[逐实例表](ui-6.7-button-instance-matrix.md)。现有按住/释放截图不带 display-present 时间戳，不作为动画相位或帧时长证据；FrameTiming/FPS、全量 109 个生产调用点仍待验，UI-6.7 保持部分验收。


### UI-6.8 补证：当前网页作为已删除视频的参考（2026-11-19）

用户指定的[Glass Light Toggle 页面](https://experiments.thisiswhitespace.com/glass-light-toggle)作为已删除 MP4 的后续参照。当前 standalone `main.js?v=3` SHA 与旧源码基线一致；隔离 Chromium/SwiftShader 中完成暗态到亮态的真实拖动并采集中段。截图哈希、部署 ID 与适用范围见[验收记录](acceptance-record.md#2026-11-19-ui-68-当前-glass-light-toggle-网页复核-替代已删除视频)。该网页不是原录屏，未同步采集 Flutter/macOS 物理呈现时钟；UI-6.8 仍部分验收。


### UI-6.7 补证：B001/B005/B050 暗色按下与释放附近样本（2026-11-19）

新增仅捕获 Aggregate 窗口的 ScreenCaptureKit 样本，覆盖全局搜索、活动刷新、暂停播放运行按钮。B005 的约 +202ms 截图请求可见刷新点阵进入旋转相位；B050 释放后依次出现原表单和执行确认框，确认框取消后状态仍为“尚未运行”。请求和截图返回时间均已记录。ScreenCaptureKit 没有 display-present 时间戳，单次捕获耗时约 28–96ms；该批只补有限时点状态观察，不签收精确动画相位、FPS、VoiceOver 或 109 个调用点全覆盖。详细证据与 SHA 见[验收记录](acceptance-record.md#2026-11-19-ui-67-暗色生产按钮短时序采样)。

### UI-6.7 补证：运行、刷新、搜索图案点击时序（2026-11-19）

96 dp 共享 `GlassActionButton` Profile fixture 的暗色点击样本现在用 ScreenCaptureKit 的 WindowServer display-time 对齐释放时点；运行、刷新和搜索在 0–650 ms 目标时序中分别采到 15、14、14 个选中帧，刷新漏 0 ms、搜索漏 83.3 ms。样本显示三种图案有对应的轻微位移/伸缩、旋转和大小变化。Widget 触发/注册回归 13 项、`flutter analyze --no-pub`、格式与 diff 检查通过；夹具回调为空，没有产品代码改动。截图与间隔统计见[验收记录](acceptance-record.md#2026-11-19-ui-67-运行刷新搜索点击呈现时序补验)。该证据不代表 109 个生产实例、浅色、VoiceOver、面板 FPS 或原视频逐帧通过；UI-6.7 继续部分验收。

### UI-6.7 补证：侧栏 B002/B003 selected 双主题外观（2026-11-21）

隔离 macOS Profile 中分别选中“示例 Git CLI”和“活动”，在 800×632pt 浅/深主题将指针移至内容空白区后，侧栏选中底板仍可见；AX 页面标题、路由与样例动作状态可读。完整截图、SHA 与隔离边界见[验收记录](acceptance-record.md#2026-11-21-ui-67-b002-git-cli-导航选中态浅深主题复核)、[B002/B003 矩阵](ui-6.7-button-instance-matrix.md)。只补签静置 selected 外观与路由；没有采集这两个导航项的点击动画、FrameTiming 或面板 display-present/FPS。UI-6.7 仍部分验收。

### UI-6.7 补证：B005 活动刷新双主题显示时序（2026-11-21）

在隔离 macOS Profile 的活动页对生产调用点 B005 实际点击刷新，分别采集浅/深主题释放后 0–650ms 的指定时点。ScreenCaptureKit `SCStreamUpdateFrameDisplayTime` 提供 WindowServer 窗口帧显示时间；两主题采集各有 96 个回调，深色漏掉 133.3ms 目标点、浅色目标点齐全。释放后将指针移至空白侧沟以排除持续 hover；只使用 `Ui6InspectionRuntime` 进程内样例记录，按钮原有 `reload()` 仅重新读取列表。证据、哈希及采样范围见[验收记录](acceptance-record.md#2026-11-21-ui-67-b005-活动刷新双主题显示时序补核)。这些指定时点截图不是完整连续帧流，也不测 Flutter FrameTiming、物理面板呈现或 FPS；UI-6.7 仍部分验收。

### UI-6.7 补证：B007 活动页七个筛选按钮双主题点击状态（2026-11-21）

在隔离 macOS Profile（800×720pt、DPR 2）对七个活动筛选各实鼠标点击一次，浅/深共 14 次；每个状态都采到 +200ms WindowServer 窗口帧，截图显示对应筛选仍为 selected，且夹具列表/空态随筛选更新。指针在释放后移至空白侧沟。逐时点缺失、timing JSON SHA-256 与截图见[验收记录](acceptance-record.md#2026-11-21-ui-67-b007-活动页七个筛选按钮双主题点击验收)。该项只签收 B007 的七个筛选实例与 fixture 路由，采样仍是指定时点而非连续帧，且不能替代 FrameTiming、面板 FPS 或其余生产按钮实例；UI-6.7 仍部分验收。

### UI-6.7 补证：B009 重新打开功能双主题实鼠标验收（2026-11-21）

隔离 Profile 的失败详情“重新打开功能”按钮先滚动到完整可见，再用真实鼠标点击；深浅主题都回到对应参数页，AX 读回“尚未运行”。源码只检索同一能力并打开页面，不执行调用。窗口帧在点击后 0–650ms 指定时点捕获，深色全采到、浅色漏 66.7ms。完整证据与 SHA 见[验收记录](acceptance-record.md#2026-11-21-ui-67-b009-重新打开功能双主题实鼠标验收)。此项关闭 B009 的目标路由与不执行检查，但不覆盖连续动效、面板 FPS 或其他生产按钮；UI-6.7 仍部分验收。

### UI-6.7 补证：B008 返回记录双主题实鼠标验收（2026-11-21）

从失败详情实鼠标点击“返回记录”，浅/深主题均回到失败筛选列表，AX 确认详情关闭且筛选状态保留。每个主题的 0–650ms 目标帧均采到；源码仅清空当前详情选择。完整截图、时序和 SHA 见[验收记录](acceptance-record.md#2026-11-21-ui-67-b008-返回记录双主题实鼠标验收)。只签收 B008 的路由和局部时序；不签收连续动画、面板 FPS 或全按钮矩阵，UI-6.7 仍部分验收。

### UI-6.7 补证：B010 取消运行双主题实鼠标验收（2026-11-21）

相同 800×720pt、DPR 2 的隔离 Profile 中，从运行中样例详情对“取消运行”实际点击；两主题 AX 均确认取消操作消失，窗口画面状态变为“已取消”。ScreenCaptureKit 指定目标时点深色漏 0ms、浅色漏 50ms。取消仅更新 `Ui6InspectionRuntime` 进程内 fixture，没有真实运行任务。图片、计时与 SHA 见[验收记录](acceptance-record.md#2026-11-21-ui-67-b010-取消运行双主题实鼠标验收)。只签收该 `_macDetail` 实例的局部动作与状态；连续动画、真实服务响应、FrameTiming、面板 FPS 和全矩阵仍待核，UI-6.7 继续部分验收。

### UI-6.7 补证：B013 添加 CLI 双主题实鼠标验收（2026-11-21）

800×720pt、DPR 2 隔离 Profile 中实鼠标点击工作台宽窗空态“添加 CLI”；浅/深均进入目标选择器，选本机预览目标进入 CLI 表单，取消后 AX 确认回到空连接管理页。没有测试、保存或运行 CLI；只读 `Ui6InspectionRuntime` 内存 fixture。两主题窗口帧采样各 14/15，缺帧分别为深色 200ms、浅色 0ms；完整截图、哈希和逐时点范围见[验收记录](acceptance-record.md#2026-11-21-ui-67-b013-添加-cli-双主题实鼠标验收)。这不是连续动画、FrameTiming 或物理面板 FPS 验收，UI-6.7 仍部分验收。

### UI-6.7 补证：B014 添加 stdio MCP 双主题实鼠标验收（2026-11-21）

800×720pt、DPR 2 隔离 Profile 中实鼠标点击工作台宽窗空态“添加 MCP”；浅/深均进入目标选择器，选本机预览目标进入 stdio MCP 表单，取消后 AX 确认回到空连接管理页。没有测试、保存或连接服务；只读 `Ui6InspectionRuntime` 内存 fixture。两主题窗口帧采样各 14/15，缺帧分别为深色 0ms、浅色 33.3ms；完整截图、哈希和逐时点范围见[验收记录](acceptance-record.md#2026-11-21-ui-67-b014-添加-stdio-mcp-双主题实鼠标验收)。这不是连续动画、FrameTiming 或物理面板 FPS 验收，UI-6.7 仍部分验收。

### UI-6.7 补证：B015 添加 HTTP MCP 双主题实鼠标验收（2026-11-21）

800×720pt、DPR 2 隔离 HTTP-only Profile 中实鼠标点击工作台宽窗空态“添加 HTTP MCP”；浅/深均进入目标选择器，选本机预览目标进入 HTTP MCP 表单，取消后 AX 确认回到空连接管理页。URL/token 未改，没有测试、保存或连接服务；只读 `Ui6InspectionRuntime` 内存 fixture。两主题窗口帧采样各 14/15，缺帧分别为深色 16.7ms、浅色 166.7ms；完整截图、哈希和逐时点范围见[验收记录](acceptance-record.md#2026-11-21-ui-67-b015-添加-http-mcp-双主题实鼠标验收)。这不是连续动画、FrameTiming 或物理面板 FPS 验收，UI-6.7 仍部分验收。

### UI-6.7 补证：B016 清除无匹配筛选双主题实鼠标验收（2026-11-22）

在 800×720pt、DPR 2 的浅/深 Profile 中实选资源筛选并输入无匹配查询，点击生产“清除筛选”后 AX 与画面均恢复“全部功能 · 17”，搜索内容与空态操作消失。两主题 0–650ms WindowServer 帧时点均采全 15/15。截图、SHA 与稀疏采样边界见[验收记录](acceptance-record.md#2026-11-22-ui-67-b016-清除无匹配筛选双主题实鼠标验收)。未签收连续曲线、FrameTiming 或物理面板 FPS，UI-6.7 仍部分验收。

### UI-6.7 补证：B017 类型筛选五按钮双主题实鼠标时序（2026-11-22）

隔离 Profile 中逐个实鼠标点击“全部、CLI、MCP 工具、资源、提示”，AX 能力行数浅/深均为 `17/12/3/1/1`。10 次点击均有 WindowServer 0–650ms 定点采样；深色提示漏 0ms，浅色缺 4 个目标时点，其余没有插值。AX 功能结果、每个窗口帧覆盖数及截图/timing SHA 见[验收记录](acceptance-record.md#2026-11-22-ui-67-b017-类型筛选五按钮双主题实鼠标时序)。目标点采样不是连续动画曲线或显示器 FPS，UI-6.7 仍部分验收。

### UI-6.7 补证：B018 新增动作按钮双主题点击时序（2026-11-23）

动作编辑器“新增动作”在浅/深 Profile 实鼠标操作均新增 `action1` 草稿；取消重开后恢复仅有原动作。ScreenCaptureKit 显示释放后 +0、+16.7、+33.3ms 的窗口帧仍见暖色反馈，+50ms 回到中性；深/浅目标时点均采集 15/15。完整截图哈希与时序见[验收记录](acceptance-record.md#2026-11-23-ui-67-b018-新增动作按钮双主题点击显示时序补验)。这是离散窗口帧反馈，不覆盖按下期间连续过程、完整动画曲线、Flutter FrameTiming 或物理面板 FPS；UI-6.7 仍部分验收。

### UI-6.7 补证：B019 导入动作双主题按下与取消（2026-11-23）

“导入”在浅/深 Profile 中按下并释放后均打开原生 Open 面板，AX 取消后回到动作编辑器，没有选择/读取文件。按下期间采集到两主题窗口帧；深色 +0ms 样本早于按下 0.555ms，其他深色四点与浅色五点位于按住期。悬停对照显示相近暖色，不能据此签收专属点击变化；原生面板随释放打开，故释放动画未测。截图及时序详见[验收记录](acceptance-record.md#2026-11-23-ui-67-b019-导入动作双主题按下样本与取消路径)。无连续曲线、Flutter FrameTiming 或面板 FPS 证据，UI-6.7 仍部分验收。

### UI-6.7 补证：B020 导出动作深色悬停与保存取消（2026-11-23）

深浅 Profile 均以 AX 打开“导出”的原生 Save 面板并取消；未选路径或写文件。双主题 Profile 构建通过，悬停窗口帧各采到 4/5，均缺 +0ms；物理按下未能确认回调，样本排除。图片、SHA 与边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b020-导出动作双主题悬停与保存取消补记)。物理按下/释放曲线、Flutter FrameTiming 和面板 FPS 仍未验，UI-6.7 继续部分验收。

### UI-6.7 补证：B020 Flutter 3.50.0 Profile 原生 Save sheet 取消（2026-11-24）

在隔离的 Flutter 3.50.0 / Dart 3.14.0 macOS Profile（bundle `io.github.guog962464.aggregate.ui6buttons350`，800×796 logical px、DPR 2）中，用内存 `Ui6InspectionRuntime` 打开“示例 Git CLI”的动作编辑器。通过 AX 激活“导出”后，原生 Save sheet 出现；AX 读到默认文件名及 Cancel/Save 控件。激活 Cancel 后 sheet 消失、编辑器仍在、未选路径或写文件。截图与 SHA 见[验收记录](acceptance-record.md#2026-11-24-ui-67-b020-flutter-350-profile-save-sheet-取消复核)。这是动作路径与取消回退的补证，不是实鼠标点击、悬停或按下帧验收；没有 Flutter FrameTiming 或物理面板 FPS，UI-6.7 继续部分验收。

### UI-6.7 补证：B020 前台实鼠标重试被 SecurityAgent 遮挡（2026-11-24）

用户允许隔离 Profile 占用前台后再次打开同一内存样例。`agent-desktop --headed hover` 两次在事件发出前超时并返回 `not_delivered`；随后对按钮中心发送的 CoreGraphics 鼠标事件未打开 Save sheet。复查发现系统 `SecurityAgent` 窗口（PID 25593，434×186pt，位置 `(539,225)`）覆盖 B020 目标；`agent-desktop --headed click` 因 `receives_events: occluded by window` 在发送前安全拒绝。早先坐标事件是否被该系统窗口接收无法确认，不能归为按钮点击或动效证据。隔离 Profile 已优雅退出；系统窗口未被操作。排查截图、SHA 和边界见[验收记录](acceptance-record.md#2026-11-24-ui-67-b020-前台物理输入重试与securityagent遮挡)。B020 仍只有 AX 打开/取消路径通过补核，鼠标悬停/按下/释放继续未验。

### UI-6.7 补证：B020 避开遮挡后的真实悬停/按下与保存取消（2026-11-24）

后续在复核 `SecurityAgent` bounds 与按钮位置后，将同一隔离窗移到 `(0,186)`，目标中心 `(398,351)` 不再被系统提示覆盖。真实悬停截图可见按钮暖色光面增强；真实鼠标按压约 80.219 ms，随后打开原生 Save sheet 并取消，未选择路径或写文件。完整窗口截图 SHA、ScreenCaptureKit 采样和时间戳边界见[验收记录](acceptance-record.md#2026-11-24-ui-67-b020-重定位后前台实鼠标悬停按下与保存取消补验)。按下态全窗口差异不够明确，仍不签收该视觉状态；窗口服务器时戳不等于物理 scan-out，未测面板 FPS。前一条遮挡记录保留为历史，当前补证只替代其中“没有实鼠标成功证据”的结论；UI-6.7 仍部分验收。

同一静置动作编辑器 Profile 两组进程 CPU 样本（预热值后约 63–84%）及 `sample` 中 Metal command queue 栈显示待查的可见渲染负载；原始 sample 哈希见验收记录。此 OS 级信号没有 Flutter `FrameTiming`、受控动画 A/B 或物理呈现数据，不能据此判定原因/通过性能门槛；UI-6.1/6.2 的相关性能问题继续待查。

### UI-6.7 补证：B021 深色 Profile 参数预览结果（2026-11-23）

深色 Profile 中临时新增 `action1`，输入 `{}` 后点击“检查并预览参数”；AX 读回 `["仅内存预览", "--help"]`，界面注明不运行命令。未执行外部程序或服务，临时清单只在进程内存。浅色路径沿用 2026-11-18 实窗记录。按下/悬停动效和 FrameTiming 未验，详见[验收记录](acceptance-record.md#2026-11-23-ui-67-b021-深色参数预览结果复验)。

### UI-6.7 补证：紧凑窗口动作编辑器布局（2026-11-23）

800×632pt Profile 低于定制编辑器 `760×720pt` 门槛时改用滚动式 `AlertDialog`，取消/保存区可见。紧凑布局中 B021 参数预览读回 `["仅内存预览", "--help"]`，B022 取消后重开仅保留 `version`。Profile 内 B023 保存会关闭编辑器，但保存后紧凑布局的原生 AX 回读因窗口枚举失去响应而未签收；新增 800×632 Widget 回归则验证保存后重开仍包含 `action1`。`action_editor_test.dart` 5/5、Profile 构建通过，完整边界与截图 SHA 见[验收记录](acceptance-record.md#2026-11-23-ui-67-b022-紧凑窗口动作编辑器自适应布局复验)。

### UI-6.7 补证：B070 深色音乐暂停确认框（2026-11-23）

从设置页底部的全局迷你播放器打开深色暂停确认框，AX 读到 46×46pt 暂停按钮及 89×41pt 取消/执行按钮；只点取消，截图确认仍为“播放中”内存样例。补充 B071 深色静态外观。没有执行播放控制。截图与 SHA 见[验收记录](acceptance-record.md#2026-11-23-ui-67-b070-深色音乐暂停确认框补验)。仅签收静态框、取消回退和 B071 暗色静置外观；点击动画和真实播放仍未验，UI-6.7 继续部分验收。

### UI-6.7 补证：B072 MusicRunPanel 深色静态与取消路径（2026-11-23）

独立 Profile 的音乐能力运行页中，AX 区分出 `MusicRunPanel` 五个动作和底部全局迷你播放器控件。暗色静置画面和暂停确认框完成截图；仅取消确认，未执行播放操作或“运行”。证据、截图 SHA 与 800×632pt 控件尺寸见[验收记录](acceptance-record.md#2026-11-23-ui-67-b072-musicrunpanel-深色静态与取消路径)。这没有覆盖浅色对照、逐按钮动效、Flutter `FrameTiming` 或面板 FPS，UI-6.7 仍部分验收。

### UI-6.7 补证：B073 B074 音乐搜索授权提示（2026-11-23）

隔离 Profile 中输入搜索词 `IU` 并按回车，原生深色授权框可见并完成截图；未点击取消或允许。窗口重激活后提示消失、AX 未枚举按钮，所以原生分支仍未验。`flutter test --no-pub test/music_search_permission_test.dart` 当前工作树 2/2 通过，搜索用例证明 Widget runtime 取消不授权，允许后由 PreviewRuntime 返回两条 fixture 结果；没有执行音乐 CLI 或网络请求。截图 SHA 和边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b073-b074-音乐搜索授权原生提示复验)。本项只签收原生静态呈现，UI-6.7 继续部分验收。

### UI-6.7 补证：B075 B076 音乐播放授权 Widget 回归（2026-11-23）

`music_search_permission_test.dart` 当前 2/2 通过；新增非 Preview 权限门用例确认播放弹窗取消不授权/不调用，允许后只向进程内 PreviewRuntime 调用一次。Widget 测试不替代原生 Profile 动作：B075 沿用历史暗色原生取消记录，B076 原生“执行”仍未点击；没有真实 CLI、网络或账号操作。原生图和测试边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b075-b076-音乐播放授权-widget-回归)。UI-6.7 继续部分验收。

### UI-6.7 补证：B073–B076 B079 原生授权流程实点（2026-11-23）

深色隔离 Profile 中实点完成搜索授权取消/允许、播放确认取消/执行，并从 B079 结果行进入 B075 播放确认。允许搜索显示 2 首内存样例；播放执行后画面仍为“正在启动/正在确认播放状态”，没有确认播放成功。未连接真实 CLI、网络、账号或音频服务。截图哈希、操作环境和边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b073-b074-b075-b076-b079-原生深色授权路径实点复验)。本轮只补深色弹框静态与路径，不覆盖浅色、点击动画、`FrameTiming` 或物理面板 FPS，UI-6.7 仍部分验收。

### 桌面前台偏好与后续更正（2026-11-23）

用户先要求打开 Profile 应用和截图时不要占用前台。按此尝试 `open -g -n` 后台启动：浅色副本起初可见且未聚焦，一次 AX 导航后仍未聚焦；再一次导航后窗口从枚举中消失。第二次后台冷启动时，窗口在首次 AX snapshot 前就消失。没有激活恢复；第二次启动前后前台都读为 ChatGPT，第一次过程中前台读数曾变化且原因不明。该历史说明后台路径不稳定。

用户随后明确说“还是占用前台吧”，因此当前授权允许将隔离 Profile 窗口置前，继续桌面验收。只操作临时 Profile 副本，不操作原应用 PID 1564。此前后台失败记录仅作为历史，不再构成停止前台验证的限制。

### UI-6.7 补证：B088 B089 Mac Host 深色启动及取消轮换（2026-11-23）

深色隔离 Profile 的进程内 Host stub 经语义动作启动后，AX 与窗口画面均显示“运行中”和两台样例设备；“轮换 Mac Host 身份”原生确认框能够打开，AXPress 取消后 Host 和样例设备仍保留。没有执行轮换，也未访问真实 Host、Keychain、证书或网络。取消通过无障碍语义动作，不构成鼠标按下动画验收；截图、SHA 与详细限制见[验收记录](acceptance-record.md#2026-11-23-ui-67-b088-b089-mac-host-深色启动与轮换取消复验)。B081/B082 首次深色复验未见预置活动，随后通过全新构建和隔离进程补验，见下节。UI-6.7 继续部分验收。

### UI-6.7 补证：B081/B082 深色活动清理路径（2026-11-23）

全新暗色隔离 Profile 正确显示三条 `UI6_SEED_ACTIVITY` 内存记录。B081 原生确认框取消后仍见成功/失败/已取消三条样例；B082 确认后活动页显示空态。此次均由 AXPress 激活；只影响 `Ui6InspectionRuntime` 内存样例。此前失败运行的原因没有证据定位。一次性启动入口 Widget 反馈环 1/1 通过后已移除；静态截图、SHA 与详细边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b081-b082-深色清理路径干净-profile-补验)。未采集按下/释放动画、Flutter `FrameTiming` 或物理面板 FPS；UI-6.7 继续部分验收。

### UI-6.7 补证：B073–B079 浅色音乐授权与结果入口（2026-11-23）

浅色隔离 Profile 中实测搜索授权取消/允许、滚动后结果行真实指针入口、播放确认取消与执行关闭路径。短窗口的结果行可通过真实滚轮进入可视区；按钮遮罩下 AX hit-test 会拒绝执行按钮，但明确坐标的指针点击关闭了确认框。两首歌曲在搜索前已是预置样例，播放前的“播放中”状态也已存在，因此没有把它们当作本轮搜索输出或实际播放成功。完整构建环境、截图 SHA 与行为边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b073-b074-b075-b076-b079-浅色音乐授权与结果入口复验)。没有按下/释放动画、连续帧、Flutter `FrameTiming` 或物理面板 FPS 证据；UI-6.7 继续部分验收。

### UI-6.7 补证：B090 浅色邀请二维码当前 Profile 复核（2026-11-23）

浅色隔离 Profile 中以本地 Host stub 启动并生成邀请，真实滚动后二维码、有效期、地址数与复制按钮完整可见；按钮 live AX bounds 为 150×40pt，屏外时则曾为 150×1。旧深色 Profile 的 139×1 读数仍作为历史保留，本轮未确定差异成因。无 Host listener、Keychain 或系统剪贴板操作；未点击复制按钮或采集按下动画。截图与范围见[验收记录](acceptance-record.md#2026-11-23-ui-6.7-b090-浅色邀请二维码实窗复核)。UI-6.7 继续部分验收。

### UI-6.7 补证：B092 B093 B094 B097 浅色 Host 配对卡（2026-11-23）

浅色隔离 Profile 的内存 Host fixture 显示 Pixel 9 待处理卡和 LGE AN10 已配对卡；实鼠标“批准只读”后，Pixel 9 仅获得读取连接权限。首轮修改权限弹窗取消因失焦未确认送达；随后新隔离进程 PID 5734 通过物理坐标点击取消，fresh snapshot 确认弹窗消失，AX 仍读到 Pixel 9 仅有读取连接，未保存。没有真实 Host listener、设备或网络操作。单次失焦 CPU 读数未受控，不作性能结论；窗口帧、Flutter FrameTiming 和面板 FPS 仍待验。截图 SHA 及详细边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b092-b093-b094-b097-浅色-host-配对卡补核)与 B097 取消复验条目。UI-6.7 继续部分验收。

### UI-6.7 补证：B092/B095 浅色拒绝与连接向导批准（2026-11-23）

浅色隔离 Profile 前台实点拒绝待审批 Pixel 9 后，AX 显示待审批空态；重启进程内 Host stub 重新注入样例，再实点“允许连接向导”后，AX 读回“读取连接 · 连接向导”，既有 LGE AN10 权限不变。详细环境、截图 SHA 与边界见[验收记录](acceptance-record.md#2026-11-23-ui-67-b092-b095-浅色拒绝与连接向导批准)。仅改变隔离进程内存 fixture，不访问真实 Host/设备/网络；没有按钮动效或性能时序数据，UI-6.7 继续部分验收。

### UI-6.7 补证：B096/B097/B100/B101 浅色自定义权限与保存回读（2026-11-23）

浅色隔离 Profile 前台实鼠标对 Pixel 9 配置连接向导及 Git CLI 本机控制；随后修改已配对授权，增加连接管理和 Git CLI 外部写入，保存并重开验证权限仍选中。AX 回读确认本机控制/外部写入同时包含读取权限；Pixel 9 卡片显示读取连接、连接向导和连接管理，LGE AN10 原授权未变。操作只作用于 `Ui6InspectionHost` 内存 fixture。详细截图 SHA、Profile 身份与边界见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b096-b097-b100-b101-浅色自定义权限批准与保存回读)。没有真实设备权限结果、按钮连续动效或性能时序证据；UI-6.7 继续部分验收。

### UI-6.7 补证：B098 浅色撤销确认取消（2026-11-23）

浅色隔离 Profile 实鼠标打开 LGE AN10 撤销确认，再取消；fresh AX 读回卡片及原权限仍在。取消仅作用于 `Ui6InspectionHost` 内存 fixture；未撤销真实设备。AX click hit-test 被 native Dismiss 覆盖层挡住，使用按钮 bounds 中心的单次物理点击完成取消。确认框/取消后截图 SHA、环境与边界见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b098-浅色撤销确认取消复验)。没有按钮连续动效或性能时序证据；UI-6.7 继续部分验收。

### UI-6.7 补证：B099 浅色权限弹窗取消（2026-11-23）

浅色隔离 Profile 实鼠标点权限弹窗“取消”，截图显示弹窗关闭且 LGE AN10 原权限摘要仍在；未点击保存。取消后的 AX 树仅返回 `Dismiss`，故只签收当前截图所示关闭/保留状态，AX 回读部分未验。另在这次有 MiniPlayer 播放中的 Profile 观察到较高 OS `ps %CPU` 读数，4 秒 sample 含 Flutter BeginFrame/Dart 与 Metal command queue 栈；无暂停基线、帧时序和物理 FPS，不据此归因或判性能不通过。完整截图、哈希、采样文件与限制见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b099-浅色权限弹窗取消补验)。UI-6.7 继续部分验收。

### UI-6.7 补证：B102/B103 浅色功能页与收藏回退（2026-11-23）

浅色隔离 Profile 打开“两整数相加”表单后 AX 仍为“尚未运行”，没有提交参数或调用 Runtime；同一进程中收藏再取消后，AX 读回收藏区移除且收藏动作恢复。截图 SHA、进程与 fixture 限制见[验收记录](acceptance-record.md#2026-11-23-ui-67-b102b103-浅色功能页与收藏回退)。只补当前功能行的浅色页面/收藏状态，不含按钮动画、Flutter `FrameTiming` 或面板 FPS，UI-6.7 仍部分验收。

### UI-6.7 补证：B104 通用错误态浅色复验（2026-11-23）

生产 `PageState.error` 的浅色 Profile 夹具在真实指针点击“重试”后，AX 本地计数从 0 变为 1；不代表真实加载或网络请求。截图 SHA、构建环境与限制见[验收记录](acceptance-record.md#2026-11-23-ui-67-b104-通用页面错误态浅色复验)。仅补 B104 浅色状态及本地回调，按下关键帧、Flutter `FrameTiming` 和面板 FPS 仍未验，UI-6.7 仍部分验收。

### UI-6.7 补证：B106 浅色错误恢复动作（2026-11-23）

浅色隔离 Profile 通过本地 `StateError` 呈现“运行失败”；实鼠标点击“检查活动状态”后 AX 仍为失败。该 fixture 在生成 `RunHandle` 前报错，生产 handler 因 `handle == null` 直接返回，所以只补错误卡、按钮位置与返回状态，不代表真实活动查询。截图 SHA 与限制见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b106-浅色错误结果恢复动作补验)。没有按钮连续帧、Flutter `FrameTiming` 或面板 FPS，UI-6.7 仍部分验收。

### UI-6.7 补证：B107 浅色待确认结果恢复查询（2026-11-23）

对浅色隔离 Profile 的唯一“查看 Git 状态”内存样例运行后，页面显示 `outcomeUnknown` 和不可直接重跑提示；该 fixture 生成进程内 `RunHandle`。真实指针点“检查活动状态”后，AX 仍为“结果待确认”，并读到“结果仍未知；请先在执行端确认，不要直接重跑。”。详见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b107-浅色结果待确认恢复查询)。没有调用真实 Git CLI/执行端/网络，没有连续按钮动画、Flutter `FrameTiming` 或面板 FPS；Profile 已关闭，UI-6.7 仍部分验收。

### UI-6.7 补证：B108/B109 浅色文件结果动作（2026-11-23）

浅色隔离 Profile 的临时内存 RunSummary 返回文件路径字符串；实鼠标点 B108“预览文件”后 AX 显示该路径的说明文本，没有读取文件。点 B109“在访达中显示”后没有错误，Finder 仍无窗口；fixture 回调为空，所以实际生产 Finder 行为未验。完整截图 SHA、临时 fixture 源码恢复核对与范围见[验收记录](acceptance-record.md#2026-11-23-ui-6-7-b108b109-浅色本地文件结果动作)。没有连续动效、FrameTiming 或面板 FPS，Profile 已关闭，UI-6.7 仍部分验收。


### UI-6.7 补证：B108/B109 生产本地文件路径复验（2026-11-23）

随后将同一浅色 Profile 夹具委派到生产 MacRuntime 本地文件方法，并使用隔离 Runtime 目录与一次性普通文件。B108 AX 读回文件真实两行内容；B109 的 Finder 窗口 AX 将该精确文件标为 selected。临时源码已恢复并与 HEAD 校验一致，Profile、Finder 窗口和样例文件已清理。截图 SHA 与验收边界见[记录](acceptance-record.md#2026-11-23-ui-67-b108b109-浅色生产本地文件路径复验)。此项仅覆盖该普通文件和浅色 800×720pt Profile；其他文件边界及按钮连续动效、Flutter FrameTiming、物理面板 FPS 未验，UI-6.7 仍部分验收。

### UI-6.8 补证：主题开关键盘/指针焦点环（2026-11-23）

为避免键盘焦点框影响玻璃主题开关的指针材质对照，指针按下时隐藏该框，Space、Enter 和方向键操作时恢复。11 项定向 Widget 测试、macOS Profile 构建及隔离原生窗口交互均通过；实窗 AX 验证鼠标点击可在深浅主题间切换，键盘动作显示整轨焦点环，鼠标再次操作后隐藏。太阳/月亮模拟、拖动与业务回调保持原实现。窗口截图和 SHA、原生实例范围见[验收记录](acceptance-record.md#2026-11-23-ui-6-8-主题开关键盘与指针焦点环实窗复验)。该项不替代原 MP4（已删除）逐帧对照、display-present FPS、VoiceOver 实际语音、UI-6.7 全量调用点或最终用户签收；UI-6.8/阶段 0–6 仍未完成。

2026-11-24 重采样校正了网页完整把手行程，并确认 macOS 设置页实际使用 `ThemeSwitchCalibration.reference`。后续用只监听的 `CGEventTap` 记录系统输入时戳；在计时前预热隔离 helper 后，正反向 48 个移动点相对网页发送时间的中位差为 +0.7/+0.5 ms，原生 down→up 为 782.0/780.5 ms，网页计划 780 ms。把手归一化后，点阵轨迹接近；玻璃边缘光和背景折射仍有可见差异，因此不签收逐帧 1:1。完整坐标、帧配对、时间映射与证据 SHA 见[验收记录](acceptance-record.md#2026-11-24-ui-68-cgeventtap-输入时序校准后复核)。网页是已删除 MP4 之后的当前参照；displayTime 不等于物理面板呈现时间，UI-6.8、UI-6.7 及阶段 0–6 继续部分/未完成。

2026-11-24 另复跑固定模型状态下官方 WebGL/Flutter 全帧比对：151 帧导出测试通过，平均 MAE `0.06317496/255`、最大单帧 `0.07471108/255`。这只验证相同输入状态下离屏 shader 的光学接近度；不能替代实时窗口拖动对照，实窗边缘光和背景折射仍有可见差异。详情见[验收记录](acceptance-record.md#2026-11-24-ui-68-官方-webgl-与-flutter-同状态全帧复核)；原 MP4 已删除，UI-6.8 与 UI-6 总体验收仍未完成。

同日还在 800×632 logical px 的隔离 Profile 中检查设置页滚动到底部的“跟随 macOS 系统”按钮：AX `ScrollTo` 可将完整 178×40pt 按钮带入可见区，至 MiniPlayer 操作目标的边界间隔为 6pt，深浅主题截图均未见遮挡。该静态位置抽查不覆盖手动滚动手感或全部控件动态；截图与 SHA 见[验收记录](acceptance-record.md#2026-11-24-ui-68-设置页滚动后与-miniplayer-间距抽查)。

### 2026-11-24 UI-6 ThemeSwitch Profile frame timing

三轮 800×632 logical px Profile 拖动负载，每轮 30 秒、26 次交替方向拖动，60 Hz 屏幕；三轮 build/raster P95 分别为 7.238/8.676、7.676/9.262、7.420/9.327 ms。全量 5,394 帧中一帧 raster 为 18.291 ms，另两轮没有超过 16.667 ms 的 build/raster 帧；没有 >100 ms 长帧。输入时长、活动窗、帧间隔、运行环境及证据 SHA 见[验收记录](acceptance-record.md#2026-11-24-ui-6-themeswitch-profile-frame-timing)。历史长帧、display-present FPS、VoiceOver、逐项动态签收和用户视觉签收仍待完成；UI-6 阶段状态保持部分验收。

### 2026-11-24 UI-6.2 90 字段表单全行程 Profile 复验

在隔离 worktree 用 Flutter 3.50.0 / Dart 3.14.0 构建 macOS Profile 诊断入口；Flutter 3.47.8 的 AOT `_Rect` 快照失败与上游记录的问题一致，原 SDK 未改动。800×632 logical px、DPR 2 的合成 `PreviewRuntime` 对 90 字段表单完成三轮全行程上下滚动，每轮 630 个滚轮事件、1,584/1,584/1,585 帧。build/raster P95 分别为 2.690–2.738/1.869–1.872 ms，所有最大值低于 16.667 ms；历史 112.742 ms 单帧异常仍未复现但原因未定位，因此 UI-6.2 仍部分验收。原始帧、事件、构建日志和字段 85–89 的范围校准截图见[验收记录](acceptance-record.md#2026-11-24-ui-62-90-字段表单全行程-profile-复验)。UI-6 阶段总体仍未完成。

### 2026-11-24 玻璃按钮待机动效成本补验

隔离 Profile A/B 找到两项可控成本：闲置时仍运行的共享 Ticker 与动态图标逐帧高斯模糊。动态图标保留外扩抗锯齿点阵光晕，跳过每帧 `MaskFilter.blur`。交互过渡仍启用逐显示帧 Ticker，静置使用 33 ms Timer；旧 100 ms Timer 的 `_lastDelivery` 重复限速会把实际通知降至约 200 ms，已移除。原 B020 单页面静置 `top` 方向性结果和源码 SHA 仍保留在[首次诊断记录](acceptance-record.md#2026-11-24-ui-6-按钮待机动效-cpu-诊断与优化)，但该 9 秒单轮结果不代表最终节拍。之后对 12 种生产按钮变体的隔离夹具在浅/深主题各完成三轮 30 秒 Profile：Flutter 提交帧估算约 30.30 Hz，build/raster P95 均低于 16.667 ms、超预算帧为零；进程 CPU 中位数约 31.8%（深）与 28.7%（浅）。新增 33 ms 连续通知回归，按钮/点阵/主题开关回归与静态分析通过；太阳/月亮组件和状态映射未改。完整环境、六轮数据、证据 SHA 和限制见[最终节拍复验](acceptance-record.md#2026-11-24-ui-6-按钮待机节拍双主题多轮-profile-复验)。`Flutter.Frame` 是 build/raster timing，不是 display-present/物理面板 FPS；该 12 按钮夹具也不能代替实际产品页面或用户对动态质感的签收。此项只通过 12 按钮双主题待机 Profile 子场景，UI-6.1/6.2 与阶段 0–6 继续部分完成。

### UI-6.7 补证：音乐账户面板 B060/B063/B065（2026-11-24）

深/浅色隔离 Profile 实窗确认 B060 可打开生产账户面板；B063 悬停光效/提示及实鼠标关闭回页；B065 悬停玻璃表面及实鼠标刷新后的内存预览账号 AX 回读。B060 只用 AXPress 验路由，刷新仅作用于进程内 stub。没有连续按下帧、Flutter FrameTiming 或物理面板 FPS，UI-6.7 仍部分验收。完整环境和逐图 SHA 见[验收记录](acceptance-record.md#2026-11-24-ui-67-b060b063b065-音乐账户面板深浅主题实窗补验)。

### UI-6.7 补证：B063/B065 双主题按下窗口帧（2026-11-24，修订前）

修订前的隔离 Profile 对 B063 与 B065 各进行真实鼠标 down/up，按住 80–84 ms；当时全窗口帧未显示稳定可辨的 pressed 外观，因此只签收动作路径和离散取帧，不签收 pressed 视觉。此结论适用于共享 pressed 反馈修订之前。采样帧时间戳不是物理屏幕帧率；刷新使用内存预览账号。历史时点和 SHA-256 见[验收记录](acceptance-record.md#2026-11-24-ui-67-b063b065-双主题物理按下帧补验)。

### UI-6.7 补证：B063/B065 共享 pressed 反馈修订后复验（2026-11-24）

在 `978a395` 的共享按钮 pressed 反馈上，B063 双主题 hover/press 对照都可见面层下压与暖光收敛；B065 深色对照通过，浅色 quiet 按钮在按住时显示内衬面和边缘。浅色 B065 按后 fresh AX 仍读到预览账号和刷新控件；深色 press-run 的 interactive AX 不含静态账号文本，状态依据引用同日先前的 full-AX 刷新记录。四组各按住约 80–85 ms，WindowServer 离散样本和缺失目标逐项记录在[修订后复验](acceptance-record.md#2026-11-24-ui-67-b063b065-按下反馈修订后复验)。没有连续帧、Flutter `FrameTiming` 或物理面板 FPS；仅内存预览账号。此项签收 B063/B065 的按下视觉子场景，UI-6.7 其他实例与阶段 0–6 继续部分验收。

### UI-6.7 补证：B064 取消扫码双主题按下窗口帧（2026-11-24）

独立 Profile 的深/浅主题均实鼠标取消进程内模拟扫码会话，fresh AX 确认会话关闭并回到未登录状态。深浅 80–85 ms 按下各采得 5 帧；浅色另采 254 ms 长按的 15 帧。长按仍没有与 hover 明确区分的稳定按钮压下外观，因此只通过取消动作和离散窗口帧，B064 按下视觉继续未签收。没有真实二维码、外部命令或网络；窗口帧时间戳不代表物理面板 FPS、连续动画曲线或 Flutter `FrameTiming`。证据摘要与 SHA-256 见[验收记录](acceptance-record.md#2026-11-24-ui-67-b064-取消扫码按钮双主题实窗补验)。UI-6.7 和 UI-6 阶段 0–6 仍部分完成。

### UI-6.7 补证：B064 pressed 反馈修订后复验（2026-11-24）

前次窗口帧没有显出稳定按下变化，后调整共享按钮为约 0.9 logical px 下沉，按住时减少暖光并移除 hover 提亮。深浅 Profile 中约 80 ms 短按都采到按住期帧，约 251 ms 长按各采齐 15 个时点；同次 hover baseline 对照显示两种主题均有清晰内压面。B064 的取消动作仍回到“扫码登录”，命中区域未随视觉位移变化。ThemeSwitch 来源逻辑不改，主题开关相关 27 项及玻璃按钮/动效 30 项回归、静态分析通过。仅签收 B064 的模拟流程与共享按压外观；其他按钮实例、连续整段动画和物理面板 FPS 未签收。证据见[验收记录](acceptance-record.md#2026-11-24-ui-67-b064-按下反馈修订后双主题复验)。UI-6.7 和阶段 0–6 仍部分完成。

### UI-6.7 补证：B020 实鼠标导出打开原生保存面板（2026-11-24）

深色隔离 Profile 中，B020 导出按钮经真实 CGEvent down/up（84.013 ms，释放后指针留在目标）打开 macOS Save sheet；AX 读到 `Documents` 与默认文件名，Cancel 后 surface 消失，未写文件。此前释放后移开指针的采样没有观察到 sheet；本轮确认物理回调可用，但不能由两次不同采样方式单独归因先前漏观察的原因。完整环境、离散帧、AX 观察及 SHA-256 见[验收记录](acceptance-record.md#2026-11-24-ui-67-b020-cgevent-实鼠标导出保存取消复验)。未单独签收 hover/pressed 视觉、连续动画、Flutter `FrameTiming` 或物理面板 FPS；UI-6.7 与阶段 0–6 仍部分完成。

### UI-6.7 补证：B020 暗色 Profile 按下态选定帧（2026-11-26）

同一暗色隔离 Profile 先做 hover-only，再以指针留在按钮上的首帧作 press baseline；真实 CGEvent down/up 按住 `83.482 ms`。按钮中心来自 fresh AX bounds `(654,343,89,40)`；WindowServer 目标帧中 13/15 有效，缺 `+83.3 ms`、`+250 ms`，结束时隔离 Profile 仍在前台。按住 `+55.794 ms` 的按钮面暖光收敛并变暗；按钮 178×80 px 区域平均绝对 RGB 差异 `0.11732`，整窗 `0.00118`、邻区 `0.00000`，只作为局部变化佐证，不是视觉阈值。物理导出打开原生 Save 面板后取消，默认文件未写入。证据及 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b020-暗色-profile-按下视觉实窗补验)。这只签收 B020 暗色按住期选定帧；释放后面板遮暗窗口，release 曲线、连续动画、Flutter `FrameTiming` 与物理面板 FPS 仍未验，UI-6.7 和阶段 0–6 继续部分完成。


### UI-6.7 补证：B019 浅色 Profile 按下态（2026-11-26）

浅色隔离 Profile 对 B019“导入”采集 hover 与真实 CGEvent press：按住 85.049 ms，press 14/15 个离散目标帧有效（缺 +66.7 ms）；+58.133 ms 按住帧比 hover baseline 更暗、暖光收敛，+77.090 ms 帧仍在按下窗口。hover 11/15（缺 +0/+450/+550/+650 ms）。物理导入打开 Open sheet，AX 确认后取消，没有选择/读取文件。B019 浅色按下期选定帧与取消路径通过；完整动画、Flutter FrameTiming 和物理面板 FPS 仍未验。证据与 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b019-浅色-profile-按下态复验)。UI-6.7 与阶段 0–6 继续部分验收。


### UI-6.7 补证：B020 浅色 Profile 按下态（2026-11-26）

浅色隔离 Profile 对 B020“导出”采集 hover 与真实 CGEvent press：按住 85.043 ms，press 13/15 个离散窗口目标帧有效（缺 +66.7/+333 ms）；+57.161 ms 按住帧比同轮 hover baseline 更暗、暖光收敛，+75.641 ms 帧仍在鼠标按下期间。导出打开原生 Save sheet，AX 确认后取消，未选路径或写文件。B020 浅色按下期选定帧与取消路径通过；释放回弹、完整按压曲线、Flutter FrameTiming 和物理面板 FPS 仍未验。证据及 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b020-浅色-profile-按下态复验)。UI-6.7 与阶段 0–6 继续部分验收。


### UI-6.7 补证：B021 参数预览暗色 Profile 动效与结果可见性（2026-11-26）

暗色隔离 Profile 中，B021 hover-only 14/15 个目标窗口帧有效；实鼠标按住 85.089 ms，15/15 帧有效。按住期按钮面暖光收敛并变暗，释放后约 75 ms 的选定帧恢复至近似基线。参数预览 AX 显示“仅内存预览”与“--version”，提示明确表示不会运行程序；源码路径只更新本机预览状态。结果初次落在编辑器视口下方，滚动内容区后才可见。此项只签收暗色 B021 的离散交互帧和安全预览，浅色、完整连续曲线、FrameTiming、物理面板 FPS 与其余按钮仍未验收，UI-6.7 和阶段 0–6 继续部分完成。时序、截图及 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b021-参数预览按钮暗色-profile-交互补验)。


### UI-6.7 补证：B021 窄窗参数预览结果自动可见修正（2026-11-26）

首次 B021 复验发现 800×632pt macOS 紧凑编辑器在点击检查后把预览数组与提示放在滚动视口之外。本轮改为仅在 macOS 的紧凑编辑器中，生成成功或错误反馈后将结果滚入视口；普通状态使用 180 ms ease-out，Reduce Motion 使用即时定位。Flutter Widget 定向测试、静态分析和隔离 Profile 构建均通过；真实 Profile AXPress 后 AX 读到结果数组高度 81pt、提示高度 20pt，两者在视口内，实窗截图完整可见。主题切换组件和逻辑未改。AXPress 首验只覆盖暗色 800×632pt 隔离 Ui6InspectionRuntime；浅色未覆盖。真实物理滚入后续补验见下节。完整环境与 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b021-窄窗参数预览结果自动可见修正)。

后续在全新无预览结果的隔离 Profile 中用 CGEvent 实鼠标复验：按住 83.074 ms，14/15 离散目标帧有效（漏 down +0 ms，状态码均为 0）；相对 down +100 ms 结果尚未露出、+167 ms 开始露出、+333/+650 ms 数组与安全提示完整。fresh AX 再确认两项反馈均位于滚动视口内；取消动作后没有保存样例，隔离进程已优雅关闭。从初始空状态触发自动滚入的物理路径现有离散帧证据，仍不等同于完整连续动画或面板 FPS。此前结果已可见状态的 press 83.359 ms、15/15 采样和 hover 13/15（另有 hover 14/15 样本）保留为补充数据。详情与 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b021-窄窗参数预览结果自动可见修正)。

另在浅色 800×632pt 隔离 Profile 以 CGEvent 首次触发，按住 82.680 ms、15/15 个离散目标帧有效；+100 ms 仍无结果，+167 ms 开始滚入，+333/+650 ms 数组和安全提示完整，fresh AX bounds 在视口内。样例未保存，隔离进程已优雅退出。浅深两套首次露出样本现已具备，连续曲线、FrameTiming、物理面板 FPS 与其他按钮仍未验。详情与 SHA 见[浅色物理复验](acceptance-record.md#2026-11-26-ui-67-b021-窄窗参数预览浅色物理复验)。

### UI-6.7 补证：B018 浅色 Profile 按下态（2026-11-26）

浅色隔离 Profile 对 B018“新增动作”采集 hover-only 与真实 CGEvent press：按住 85.041 ms，hover 与 press 均有 14/15 个离散目标帧有效（分别缺 +16.7 ms、+0 ms），有效帧状态码均为 0。hover +200 ms 按钮偏暖；按下后实际显示于 +41.418 ms 和 +76.872 ms 的两帧表面更中性、暖光收敛。动作只加入未保存草稿；取消后返回管理页，重开仅有 `version`，Profile PID 16044 已优雅退出。选定按下期帧和取消路径通过；连续回弹、完整动画、Flutter FrameTiming 和物理面板 FPS 未签收。环境、帧证据及 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b018-浅色-profile-按下态复验)。UI-6.7 与阶段 0–6 继续部分验收。

### UI-6.7 补证：B022/B023 浅色 Profile 按下态与保存回读（2026-11-26）

B022“取消”真实 CGEvent 按住 84.611 ms，hover 14/15（缺 +0 ms）、press 15/15；+55.204/+72.091 ms 按住帧比 hover 更中性、暖光收敛，释放后 fresh AX 回到管理连接详情且三条示例连接未变。B023“保存动作”真实 CGEvent 按住 81.407 ms，hover 14/15（缺 +0 ms）、press 15/15；+52.708/+70.990 ms 按住帧也比 hover 更中性。保存只更新 `Ui6InspectionRuntime` 的进程内清单；重开后 JSON AX value 含 `version` 与 `action1`，原生菜单截图同时显示两个选项；隔离 PIDs 16498 与 16992 均优雅退出。两按钮浅色按下期选定帧、B022 取消路径及 B023 内存保存回读通过；释放回弹、完整连续动画、Flutter FrameTiming 和物理面板 FPS 未签收。完整环境、截图和 SHA 见[验收记录](acceptance-record.md#2026-11-26-ui-67-b022b023-浅色-profile-按下态与保存回读)。UI-6.7 与阶段 0–6 继续部分验收。
