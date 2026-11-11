# Android A3：Node 原生桥探针记录

> 2026-11-11。A3 进行中；A3.1–A3.3 的固定探针范围已在 4 KB 真机通过。探针与用户可见 CLI 能力保持隔离；A3.4–A3.6 尚未验收。

## 当前基线

- 工程：Flutter Android 宿主，AGP 9.1.0、Kotlin 2.4.0、`minSdk 24`、`targetSdk 36`、NDK 28.2.13676358。`:nodebridge` Android 库由独立 `:nodeprobe` App 验证，也可通过显式 Gradle 属性加入 Flutter Debug APK；普通及 Release 包不依赖它。
- 设备：LGE AN10，Android 15/API 35，arm64，4 KB 页。当前没有 16 KB 页真机。
- A1 已完成，故 A3 的工程前置满足；A3 是独立实验，A2 的 HTTP MCP 能力不依赖它。

## A3.1 候选包核验

| 项目 | 结果 |
| --- | --- |
| 来源 | [nodejs-mobile v18.20.4 Android Release](https://github.com/nodejs-mobile/nodejs-mobile/releases/tag/v18.20.4)，2024-10-07 发布；Android ZIP 57,287,354 字节。 |
| 本次下载 SHA-256 | `bd7321eaa1a7602fbe0bb87302df2d79d87835cf4363fbdd17c350dbb485c2af`。这是本地下载的完整性锚点，Release API 未提供官方 digest；不能当作独立签名验证。 |
| ABI/头文件 | ZIP 含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 的 `libnode.so`，各约 62.5/58.7/65.4 MB；含 `include/node/node.h`，声明 `node::Start(int,char**)`。本次只检查 arm64 ELF。 |
| 版本/许可证 | `node_version.h` 为 18.20.4。仓库 [v18.20.4 LICENSE](https://github.com/nodejs-mobile/nodejs-mobile/blob/v18.20.4/LICENSE) 含 Node.js 及依赖许可文本；ZIP 未附 LICENSE，若分发需随包保留相应声明并复核完整依赖许可。 |
| 链接依赖 | arm64 ELF 需要 `libc++_shared.so`、`libm.so`、`libdl.so`、`liblog.so`、`libc.so`。JNI/NDK 构建须保证 C++ 运行库与 APK 打包一致。 |
| 16 KB 页 | arm64 ELF 四个 `LOAD` 段对齐均为 `0x1000`（4 KB），不满足 Android 的 16 KB ELF 对齐要求；该预编译库不能作为 16 KB 设备发布构建。实验 APK 的 ZIP 对齐另已检查，AAB 与 16 KB 真机加载仍未验证。 |
| 维护性 | [Node.js 官方版本表](https://nodejs.org/en/about/previous-releases)显示 Node 18 已于 2025-03-27 EOL；当前 nodejs-mobile Release 最新仍为 18.20.4。其[构建指南](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/BUILDING.md)仍以 NDK r24 为例。需要验证从维护中的 Node 分支构建移动库及 16 KB 对齐的可行性。 |

Android [16 KB 页指南](https://developer.android.com/guide/practices/page-sizes)要求预编译共享库的 ELF 段也满足 16 KB 对齐；AGP/NDK 升级不会自动修复已下载的旧 `.so`。因此 v18.20.4 只能作为 4 KB 真机功能探针，不能据此通过 A3 发布门槛。

## 最小真机探针

- `app/android/nodeprobe` 是单独的 Debug 验证 App；共用的原生实现放在 `app/android/nodebridge`。`prepare.sh` 下载或接收上述 ZIP，校验 SHA-256，只将 arm64 `libnode.so`、头文件及项目锁定 NDK 的 `libc++_shared.so` 放入本机忽略目录；二进制和头文件不入 Git。首次加载失败准确报缺少 `libc++_shared.so`，补齐后成功。
- `:node` Service 在工作线程通过 C++ JNI 调 `node::Start`，固定 JS 入口复制到应用私有目录；JS 输出 Node 版本、写文件、完成 `127.0.0.1` HTTP 请求。Service 以 Android `Messenger` 返回带请求 ID 和进程 generation 的启动、实际就绪、事件、结果、错误及关闭消息。当前协议只运行固定入口，`STARTED` 代表工作线程开始，JS 发出的 `ready` 事件才表示脚本已执行。
- LGE AN10 真机返回 `v18.20.4`、`file=ok`、`network=network-ok`、退出码 0。一次启动到结果的观测为 326 ms；后续两次为 196/178 ms，均包括复制入口、加载库和 JS 调用，不是整 App 冷启动计时。空闲 Service 一次 `dumpsys meminfo` 为 PSS 53,877 KB、RSS 108,872 KB；Debug 探针 APK 约 96 MB。
- `verify_device.py` 安装 Debug APK，运行一次，单独杀 `:node` 进程并等待新代际再次成功；主进程 PID 保持不变，测试结束卸载实验 App。真机先后两次脚本通过；其中一次初版脚本在后台等待 15 秒没有收到第二个结果，后续改为必要时将 Activity 带回前台再等待。该现象需要 A3.5 继续测后台恢复，不能称为稳定自动重连。
- `flutter build apk --debug --no-pub` 通过，Aggregate 主 APK 不含 Node 探针库。NDK r28c 构建的 JNI 桥和 `libc++_shared.so` ELF `LOAD` 段均为 `0x4000` 对齐，`zipalign -c -P 16 4` 对实验 APK 通过；但旧 `libnode.so` 仍为 `0x1000`，整包不满足 16 KB 页原生加载门槛。

复现：在 `app/android` 运行 `nodeprobe/prepare.sh [Android ZIP] [NDK 路径]`、`./gradlew :nodeprobe:assembleDebug --offline`、`python3 nodeprobe/verify_device.py`。脚本使用当前连接的真机；没有启动模拟器。

## Flutter Debug 测试通道

- `app/android/app` 仅在 Gradle 属性 `a3Probe=true` 时为 Debug 构建依赖 `:nodebridge`；Release 构建不加入该库。`MainActivity` 的 `aggregate/node_probe` 平台通道只在可调试 App 中提供固定 `run`、`cancel`、`crash` 测试命令，不接用户界面或 `AndroidRuntimePort`。未打入库时 `run` 明确返回 `unavailable`。
- `NodeProbeChannel` 经 Binder 发送请求，核对请求 ID 与 generation；Service 把固定 JS 写入应用私有目录的有界 JSONL 事件（上限 64 KB）实时转发到 Dart，包含 `ready`、`console`、`network`、`fileWrite`、`fileRead` 和 `exception`。这是实验传输方式，未将 JSONL 文件或回环端口暴露给其他 App。固定脚本支持最多 5 秒延迟；Service 在完成后关闭自身进程，下一次请求启动新代际。
- 主动 `cancel` 发送 `cancelRequested` 事件并终止 `:node` 进程；与意外崩溃一样，Dart 报 `outcomeUnknown`，不会自动重放。此结果不能证明脚本在终止前没有产生外部副作用。
- LGE AN10 真机 `integration_test/android_node_probe_test.dart` 的探针构建通过两次连续调用、新代际、上述实时事件、脚本异常、主动取消、运行中崩溃及后续恢复。另一次用 HOME 键把 App 放到后台约 5 秒，进行中的固定请求仍完成。普通构建通过“探针不可用”；实验 APK 包含 `libnode.so`，普通 Flutter Debug APK 不含 `libnode.so` 或 JNI 桥，测试后已重新安装普通 Aggregate 包。`flutter analyze --no-pub` 无问题，独立 `:nodeprobe` 真机回归通过。

| Binder 消息 | 含义 |
| --- | --- |
| `RUN` 1 | 固定入口、请求 ID、最多 5 秒延迟及失败样本开关。 |
| `STARTED` 2 | Service 工作线程启动；不等于 JS 就绪。 |
| `RESULT` 3 / `ERROR` 4 | 成功结果或失败；Dart 核对请求 ID 和 generation。 |
| `CLOSING` 5 | 单次运行后将退出 Service 进程。 |
| `CRASH` 6 / `CANCEL` 8 | 仅用于 Debug 的崩溃注入或进程级取消。 |
| `EVENT` 7 | JSONL 事件或取消请求；其中 `ready` 是固定 JS 入口实际开始执行的信号。 |

真机探针构建命令：在 `app/` 运行 `ORG_GRADLE_PROJECT_a3Probe=true flutter test --no-pub integration_test/android_node_probe_test.dart -d <设备序列号> --dart-define=A3_PROBE_ENABLED=true`。后台专项测试另加 `--dart-define=A3_BACKGROUND_TEST=true`，在输出 `A3_BACKGROUND_READY` 后由主机发送 HOME 键。普通构建用相同测试路径而不设置 Gradle 属性与 Dart define。该过程只验证固定 JS 样本，不证明 npm 安装、任意 CLI 或可发布的 Node 运行时。

## 后续实验门槛

1. 明确运行端能力查询与受控包入口；当前事件流和进程级取消只针对固定脚本，不支持 npm 或 CLI。继续隐藏 `cli`、`mcp-stdio` 适配器。
2. 验证 Node 单实例、请求超时、旧草稿/profile 引用、长时间退后台、系统杀进程及升级后的资源清理。短暂后台请求通过不等于后台长期运行稳定；后台自动重连仍未知。
3. 寻找或构建维护中的 Node 移动库，逐 ABI 检查 ELF、APK/AAB 对齐，并取得 16 KB 真机验证。未通过这些门槛前不进入 A4 产品化，也不声称设备端 npm/CLI 可用。
