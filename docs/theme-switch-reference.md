# 玻璃主题切换与逐帧对照

## 验收范围

用户要求对照录屏的每一帧，还原月亮和太阳内部的变化、光效与动画节奏。原先的双固定图标、均匀阴影和 480 ms 隐式动画不满足此要求，已替换为单个可拖动滑块、粒子状态模型与光学着色器。

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
flutter test --no-pub test/theme_switch_simulation_test.dart test/theme_switch_optics_test.dart test/glass_theme_switch_test.dart test/widget_test.dart
flutter analyze --no-pub
flutter build macos --debug --no-pub
```

继续校准时应保留原始 PTS 和实际误差。固定种子只使回归可重复，不等于找回录屏的随机种子；相同进度值也不唯一决定中途反向后的粒子形态。

本轮验证环境为 Flutter 3.47.8 / Dart 3.13.7；22 项相关测试通过，静态分析和 macOS Debug 构建通过，并目视检查原生 Metal/Impeller 的两种主题。未使用模拟器。
