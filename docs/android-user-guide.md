# Android 内部测试指南

> 更新：2026-11-14。Android 仍是实验版，当前没有可供分发的 Release APK/AAB；本指南用于开发和验收人员。仓库当前产品发布目标仍为 macOS。不要把 Debug 包上传应用商店或作为正式安装包传播。

## 能力与执行位置

| 能力 | 运行位置 | 当前状态 |
| --- | --- | --- |
| Streamable HTTP MCP | Android 手机 | 已在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机完成回环与外部 HTTPS 连接闭环。外部地址使用 HTTPS；不要把 Token 放进 URL。 |
| Mac CLI、TUI、stdio MCP | 已配对的 Mac Host | Android 不在手机上启动这些命令。Mac 必须在线、Host 服务必须启动，且本次配对授权必须覆盖目标连接和操作。 |
| 网易云 CLI 与音乐 | 配对 Mac Host | 账号配置、CLI 和播放由 Mac 持有；实际声音从 Mac 的音频输出设备播放。 |
| Android 本机 Node/npm/任意 CLI | 不支持 | Node/npm 与固定样本仅用于独立 Debug 探针。用户不能在正式 Android App 中执行 `npm install`、任意 npm CLI、TUI 或 stdio Server。 |

手机界面按 Android 的连接、调用、活动和播放器场景组织；它和 macOS 共用 Flutter/Dart 产品代码、领域模型及运行契约。共享页面不代表两端具有相同的本机执行能力。

## 安装内部 Debug 包

在开发机仓库根目录执行：

```sh
cd app
flutter build apk --debug --no-pub
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

该 APK 使用 Android Debug 测试签名，仅供授权的内部设备验证。当前主 App Debug APK 为 99,506,706 字节（2026-11-14 本地构建）；实际大小会随构建依赖和 Flutter 工具链变化。不要将这份包称为 Release 候选包。

当前 Release 构建尚不能作为分发包：`app/android/app/build.gradle.kts` 把 Release 指向 Debug 签名；本机 `flutter build apk --release --no-pub` 又因生成注册表引用 Release classpath 中不存在的 `integration_test` 而失败。仓库没有有效的发布签名身份或可验证的 Android Release AAB。

## 配对 Mac Host

1. 在 Mac 上启动 Aggregate Host，在 Host 设置中生成配对邀请。
2. 在 Android App 的“设备”/Host 页面扫描邀请二维码。
3. 在 Mac 上核对设备名和配对码，只批准当前需要的最小权限。连接向导、连接读取和逐连接执行权限分别控制；不需要的权限不要授予。
4. 等待 Android 显示 Host 在线，再回到功能页选择标有该 Mac 执行目标的能力。

正常使用要求手机和 Mac 能通过局域网访问彼此、Host 正在运行且配对证书仍有效。USB ADB reverse 只用于开发验收，不是常规连接方式。撤销配对后，Android 不会把原本指定 Mac 的连接悄悄切换到手机本地执行。

## 使用边界

- 手机上的 HTTP MCP 请求由 Android App 发出；在连接详情确认服务地址、HTTPS 和授权范围后再使用。
- 远程 Mac 工具只有在 Host 在线且权限足够时才可运行。运行前检查连接名、执行设备、权限和操作参数。
- 网易云搜索、账号和播放由 Mac CLI 执行；检查 Mac 上的账号/播放状态，并从 Mac 连接的耳机或扬声器听声音。手机只显示远程状态与控制结果。
- 运行显示“结果待确认”时，先到活动页查询服务端状态；不要直接重复可能产生副作用的命令。
- Android 15 / API 35 / arm64 / 4 KB 真机通过了已列明的 UI、HTTP MCP 和稳定性验收。未有 16 KB 页实体设备、生产音乐账号与直接 LAN/Bonjour production Host 的完整验收；这些都不是已通过能力。

## 常见故障

| 现象 | 处理 |
| --- | --- |
| 无法安装或系统提示安装来源 | 只在内部测试设备安装本地 Debug APK，并核对包来源。当前没有正式 Release 签名或 Play 发布包。 |
| 连接页没有手机 CLI/npm 适配器 | 这是当前能力边界。把普通 CLI、TUI 或 stdio MCP 配置在 Mac Host，再从手机选择 Mac 执行目标。 |
| HTTP MCP 握手失败 | 检查 URL、服务进程、网络、HTTPS 证书、Token 和 Streamable HTTP 支持；Token 单独填写，不放入 URL。远程服务不要使用明文 HTTP。 |
| Mac Host 离线或找不到 | 确认 Mac 和 Host 服务仍运行、两端网络可达、邀请未过期且配对未撤销；需要时从 Mac 重新生成邀请并批准。 |
| 功能显示无权限 | 检查 Mac 上本设备的授权范围及该连接的逐项权限。仅重新连接不会自动扩大授权。 |
| 网易云没有声音 | 播放输出在配对 Mac。检查 Mac CLI 登录状态、mpv、队列和 Mac 当前音频输出；Android 手机扬声器不是当前输出端。 |
| Node 探针/固定 npm 样本失败 | 探针是独立 Debug 实验，不属于主 App 能力。按 [A4 实验记录](android-a4-progress.md)查看适用的固定入口和限制；不要尝试用它安装任意包。 |
| 运行结果待确认 | 到活动页检查目标服务状态。只有确认操作未执行后，才按该功能的恢复步骤再次操作。 |

更多故障处理见[跨平台故障排查中的 Android 内部测试部分](troubleshooting.md#android-内部测试)。A8 验收证据和尚未通过的发行条件见 [Android A8 验收记录](android-a8-acceptance.md)。
