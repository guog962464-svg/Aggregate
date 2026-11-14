# 玻璃主题切换与逐帧对照

## 验收范围

用户明确要求保留可任意拖动的实时控件，不采用固定帧序列回放；继续对照录屏的每一帧，还原月亮和太阳内部的变化、光效与动画节奏。原先的双固定图标、均匀阴影和 480 ms 隐式动画不满足此要求，已替换为单个可拖动滑块、粒子状态模型与光学着色器。

视觉源头是 Zsolt Kacso 的 [Glass Light Toggle](https://experiments.thisiswhitespace.com/glass-light-toggle)。官方独立实现可用于核对机制：[main.js](https://experiments.thisiswhitespace.com/standalone/glass-light-toggle/main.js?v=3)。本仓库的 Dart 模拟和 Flutter runtime shader 按这些可观测机制及参数独立重建；原站资源用于临时对照。

“与原算法在相同状态下一致”和“已恢复录屏中的每个状态”是两项独立验证。现有数值与光学回归覆盖前者。录屏中粒子的随机初始化状态、完整指针输入、早期变形，以及被遮挡/与背景等亮的粒子尚未完全恢复，不能据此宣布逐帧零误差。

## 当前实现

- `AppearanceSelector` 继续使用既有外观偏好及跟随系统入口。
- `GlassThemeSwitch` 处理点击、拖动、释放、反向、键盘操作、无障碍标签与减少动态效果。
- `ThemeSwitchSimulation` 用一个时间轴驱动滑块、形变、光带与 113 组粒子；17×17 点阵在同一滑块内部从月亮重组为太阳。太阳端点有 65 个可见点，其余配对粒子逐渐隐藏。
- `ThemeSwitchArtwork` 接收显式快照；点阵和模糊点阵纹理经玻璃折射、色散与边缘散射采样。两个 sampler 使用线性滤波，与参考的 WebGL 采样一致。
- `glass_theme_switch.frag` 用圆角矩形距离场计算凹槽、玻璃倒角、移动光弧和页面光晕。光带具有独立的滞后相位。
- 设置页不可见时通过 `TickerMode` 停止帧调度；系统减少动态效果时直接显示稳定端点。

共享 UI 和模拟未导入系统进程、文件或 macOS API。解码和截图工具位于 `app/tool/`，不进入产品运行路径。

## 实时参数拟合续做

产品使用 `theme_switch_fitted_calibration.dart` 的 113 组连续粒子系数。每一组保存 delay/curl/lift/stiffness/drag/phase/twinkle；没有录屏图片、逐帧进度表或媒体解码运行路径。控件仍接受任意指针输入，并即时积分惯性、弹簧和光带。`ThemeSwitchCalibration.reference` 继续保留独立原算法 oracle，拟合配置不会替换测试期望值。

先搜索 10,001 组初始化参数，再用部分 Hungarian 对应与有界 least squares 优化轨迹。79 个动态源帧用于训练，每第五帧的 20 个样本单独交叉检查；112 颗粒子的轨迹系数获得更新，未观测的部分保留初始化约束。静态暗态另有 52/13 个训练/验证样本用于 7 颗星的闪烁拟合。

| 检查项 | 原参数 | 拟合参数 | 范围 |
| --- | --- | --- | --- |
| 动态粒子位置/尺寸损失 | 2.93005 | 2.07704 | 20 个验证源帧，设计像素，截尾双向近邻损失 |
| 星点亮度变化 RMSE | 0.20623 | 0.05104 | 13 个验证样本，局部对比度；光度 gain/bias 为分析干扰项 |
| 太阳射线亮度变化 RMSE | 0.07597 | 0.04949 | 16 个验证源帧，20 个射线格点；频率保持 2.2，只拟合相位 |
| 光带角度 RMSE | 0.04782 | 0.03145 | 39 个验证源帧，弧度 |
| 光带/玻璃 RGB MAE | 5.24512 | 5.18602 | 同 39 个源帧，0–255，独立轮廓/主题状态固定 |

后续 11 起点/16 轮的训练误差更低，但验证误差升至 2.12714，因此没有替换前述 8 轮的粒子配置。这些结果不等于已找回录屏原始随机种子；对比度、轮廓、重叠点和录屏颜色编码仍有限制。完整画面的差分与上述局部指标分开报告。

实时调度改用固定 1/60 s 累积积分，20/30/60/120 Hz 下的相同输入得到一致状态。原 `advance` 保留源实现每帧最多 1/30 s 的策略，专用于 oracle 和显式参考工具。超过 2 s 的隐藏间隔会使未持有滑块进入目标稳定态，并推进真实星点/着色器时钟。拖住超调中的滑块使用未施加阻尼的指针锚点，消除零位移跳变；取消拖动会恢复最新外观偏好。极端越界拖动保持有限状态与合法玻璃尺寸。

`THEME_SWITCH_CALIBRATION` 可为导出工具提供严格校验的数值 JSON；`THEME_SWITCH_MOTION_INPUT` 可提供独立玻璃轮廓的 60 Hz 输入，替代有粒子偏移的图形中心估计。这些文件只参与离线验证。录屏 PTS + 6.5 s 是初始时间假设。逐帧图像匹配发现活动段的中位偏差约 19.8 ms，部分帧重复保持或混合相邻源帧，单一线性公式仍有约 18.5 ms 残差。`THEME_SWITCH_TIME_MAPPING` 因此可为离线对照显式指定观测源帧时间；它不进入产品。产品挂载使用 6.5 s 相位起点，模拟与着色器只加一次，未宣称已恢复浏览器 performance 时钟。参考工具以源 60 Hz 整步积分，分数 PTS 只更新显示状态，不额外积分一小步。光带采用 stiffness=59.0863951、damping=.9446930；太阳射线额外相位 .5050001 rad。

静态 scene 候选在局部背景/轨道验证中改善约 9%，但完整原生图像 A/B 没有净提升，因此产品保留原有 scene。分析中的摄影 gain/bias 也未进入着色器。开头约 0–1.5 s 的媒体冻结/缩放/叠层与结尾循环叠化保留在全量差分里；没有用这些外层现象修改控件弹簧或添加固定播放逻辑。

### 完整图像复核

同一独立轮廓输入、同一整数源帧时间匹配、同一背景/玻璃测量下，光带仍由实时 ODE 推导，没有采用实测 theta 覆写。以下对照均未配准、未校色、未遮罩：

| 范围 | 原参数 MAE | 产品拟合 MAE |
| --- | --- | --- |
| 全量 200 帧 | 7.33939 | 7.33719 |
| 单列结尾循环后的 171 帧 | 6.28652 | 6.28355 |
| 稳定视野 1.52–4.25 s，79 帧 | 4.43557 | 4.42729 |
| 同 79 帧控件固定区域 | 7.90530 | 7.82859 |

单位为 0–255 RGB。整体改善较小，不能由局部粒子/闪烁指标推断整体达到 1:1。此前的 5.9181/4.9670 使用了实测 theta 覆写，输入与本表不同，不能直接横向比较。当前图像验证仍固定独立测量的 theme 与合格玻璃几何，用于分离内部粒子与实时光带的误差，并不证明产品自动重现了录屏指针输入。保留的差异还包括媒体缩放、暂停/保持、相邻帧混合、压缩、未恢复粒子对应与输入速度滤波。严格逐帧一致仍未完成。

## 独立期望值

`app/test/fixtures/theme_switch_model.json` 保存原实现的固定输入 oracle，并记录来源 SHA256、LCG 种子和事件顺序。60 Hz、151 个时间步中，比较位置、速度、形变、光弧相位、强度及粒子；观测到的最大浮点差约 `2.7e-13`。

`theme_switch_optics.json` 的颜色探针来自原 WebGL 输出。另导出了 6 个相同状态的完整图像作 RGB 差分；线性采样修正后的平均 MAE 约 `0.0066/255`。剩余差异集中在点阵纹理边缘的光栅化/采样。这个数据不代表与用户录屏的直接差分。

完整录屏基线按原始尺寸比较 200 帧，未配准、未校色、未遮罩。用背景与轮廓拟合校准后，全量 RGB MAE 为 `5.9181/255`；单列播放器循环段后的 171 帧为 `4.9670/255`。这两个结果均非逐帧零误差。每帧的几何输入保留质量分数及回退标记：167 帧使用达到门槛的轮廓观测，33 帧沿用低置信估计。

## 录屏的实际结构与时间

顺序解码得到 200 帧及不规则 PTS。不能用带 seek 容差的静态抽帧来推断时序。

| 录屏时间 | 可见行为 |
| --- | --- |
| 0–1.1 s | 暗态；卡片较窄，蓝光主要在左侧与左下 |
| 1.12–1.51 s | 卡片向正面形态展开，光带移到底边 |
| 约 2.10 s | 开始向右拖动 |
| 2.39–2.64 s | 月亮解体、粒子散开，背景逐渐变亮 |
| 2.72–2.90 s | 深色粒子开始组成太阳 |
| 约 2.97 s | 中途反向到暗态 |
| 约 3.32 s | 再次反向到亮态 |
| 约 3.75 s | 太阳成形，随后轻微超调并稳定 |
| 4.29–4.63 s | 播放器循环交叉淡化；会同时看到两张滑块和两个指针 |

最后的双影由两张完整画面的混合产生，不是实时控件结构。对照工具仍显示这部分帧的差分，但将其单列为播放器行为。指针、压缩、颜色转换及无法观测的随机状态均保留在原始差分中，没有用遮罩消除误差来提高数值。

## 重复执行

在 `app/` 下顺序解码本地参考视频：

```sh
swift -suppress-warnings tool/extract_theme_reference.swift input.mp4 /tmp/theme-reference/frames
```

实测时间表是显式外部输入 `measured-timeline.csv`。其中的图形中心、几何与角度估计带有置信范围；图形中心有粒子惯性偏移，不能直接视作滑块中心。背景拟合 `fitted-optics.csv` 另外保存从远场 RGB 得到的主题混合值与残差。

按 PTS 导出截图；邻近观测之间以不大于 1/60 s 的步长积分：

```sh
flutter test --no-pub tool/theme_switch_reference_frames_test.dart \
  --dart-define=THEME_SWITCH_REFERENCE_ROOT=/tmp/theme-reference \
  --dart-define=THEME_SWITCH_EXPORT_DIR=/tmp/theme-rendered
```

`THEME_SWITCH_USE_MEASURED_THETA=true` 可显式使用实测光晕角度；`THEME_SWITCH_USE_FITTED_THEME=true` 可显式使用背景拟合值；`THEME_SWITCH_USE_FITTED_GEOMETRY=true` 仅采用轮廓质量分数至少 0.65 且不含播放器叠化的几何观测。manifest 记录所有实际采用的输入及不确定性。未指定输出目录时，这个工具测试跳过。

生成未配准、未校色的参考/渲染/4 倍差分以及逐帧 HTML 报告：

```sh
uv run --python 3.13 --with pillow==13.0.0 --with numpy==2.5.4 \
  python tool/compare_theme_switch_frames.py /tmp/theme-rendered/manifest.json /tmp/theme-comparison
```

普通行为与物理回归：

```sh
flutter test --no-pub test/theme_switch_calibration_test.dart test/theme_switch_realtime_test.dart test/theme_switch_simulation_test.dart test/theme_switch_optics_test.dart test/glass_theme_switch_test.dart test/widget_test.dart
flutter analyze --no-pub
flutter build macos --debug --no-pub
```

继续校准时应保留原始 PTS 和实际误差。固定种子只使回归可重复，不等于找回录屏的随机种子；相同进度值也不唯一决定中途反向后的粒子形态。

验证环境为 Flutter 3.47.8 / Dart 3.13.7。上一轮 22 项相关测试及原生 Metal/Impeller 两端点目视检查通过；实时拟合续做后的 35 项相关测试、静态分析和 macOS Debug 构建通过。未使用模拟器。
