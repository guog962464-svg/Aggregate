# Android A1：宿主与共享界面实施记录

> 实施：2026-11-10 至 2026-11-11；对应[阶段规划](android-adaptation-plan.md) A1 和[契约说明](android-a1-contract.md)。本报告只记录实际完成与验证的范围。

## 实施

- 同一个 `AggregateApp` 由平台工厂连接运行端：macOS 继续使用 `LocalRuntimePort`，Android 使用 `AndroidRuntimePort`。Android 壳不声明连接或终端能力；HTTP MCP 在 A2 接入。
- `app/android/` 由 Flutter 3.47.8 模板生成；包名 `io.github.guog962464.aggregate`，`minSdk 24`、`compileSdk/targetSdk 36`、NDK `28.2.13676358`，Gradle 9.3.1、AGP 9.1.0、Kotlin 2.4.0。Debug APK 已构建成功。
- 共享契约新增 `ExecutionTarget`；旧 JSON 无目标时读取为当前运行端设备。Mac Runtime 拒绝 Host 目标。适配器携带目标，向导产生的草稿保留该目标。
- 共享 `ConnectionSetupDialog` 在窄屏使用全屏可滚动表单与底部操作按钮；Host 程序路径标明归属，Android/Host 不提供本机路径选择按钮。Android 无连接能力时隐藏添加入口，页面显示待开放说明。手机搜索框隐藏桌面快捷键提示及不可用的 CLI 筛选。

## 验证与边界

| 项目 | 当前结果 |
| --- | --- |
| 共享契约 JSON 迁移、Host 身份校验 | 单元测试通过。 |
| Android 空能力声明、手机导航、向导窄屏布局与 Host 路径归属 | Widget/单元测试通过。 |
| macOS 连接向导与 App 回归 | Flutter 测试通过。 |
| Android 构建 | `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn flutter build apk --debug --no-pub --target-platform android-arm64` 成功。默认 Flutter 制品地址首次构建时发生 TLS 握手失败；切换镜像后成功。 |
| 真机启动与 UI | LGE AN10 / Android 15 / API 35 / arm64 / 4 KB：APK 安装成功，工作台、抽屉、连接管理页实测可浏览，无明显溢出；更新后搜索框不再显示 `Ctrl+K`。未启动模拟器。 |

A1 的 Android Runtime 仅用于宿主与导航验证，偏好暂存内存且在界面提示。它未实现连接、文件、调用或终端；Node、npm、本地 CLI、Host 和 HTTP MCP 的真机运行均不由 A1 证明。手机文档 URI、持久化凭证与连接属于 A2；Host 草稿 TTL/配对属于 A5。

由于 A1 不开放任何连接类型，连接向导的手机全屏布局、系统返回丢弃草稿和按钮名称由手机尺寸的 Widget 测试验证；真机中的实际输入法遮挡及 TalkBack 操作需要在 A2 开放 HTTP 向导后再复查。

NDK 的 SDK 管理器安装首次报告压缩包读取错误；改从 [Android 官方 NDK 下载地址](https://developer.android.com/ndk/downloads)取得 r28c ZIP，完成压缩包完整性测试并检查 `source.properties` 为 `28.2.13676358`，再安装到 SDK 的 side-by-side 路径。该设备只覆盖 arm64、API 35 和 4 KB 页；16 KB 页及其他 ABI 留到 A3/A8。
