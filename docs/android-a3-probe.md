# Android A3：Node 原生桥探针记录

> 2026-11-11。A3 已启动；A3.1 候选库盘点完成，独立 Android 实验模块已在 4 KB 真机运行最小 JNI 探针。探针与 Aggregate 用户可见 CLI 能力保持隔离。

## 当前基线

- 工程：Flutter Android 宿主，AGP 9.1.0、Kotlin 2.4.0、`minSdk 24`、`targetSdk 36`、NDK 28.2.13676358。当前 `:node` Service 与 JNI 桥位于独立 `:nodeprobe` 实验 App，不在 Flutter 产品 App 内。
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
| 16 KB 页 | arm64 ELF 四个 `LOAD` 段对齐均为 `0x1000`（4 KB），不满足 Android 的 16 KB ELF 对齐要求；该预编译库不能作为 16 KB 设备发布构建。尚未检查 APK/AAB ZIP 对齐或 16 KB 真机加载。 |
| 维护性 | [Node.js 官方版本表](https://nodejs.org/en/about/previous-releases)显示 Node 18 已于 2025-03-27 EOL；当前 nodejs-mobile Release 最新仍为 18.20.4。其[构建指南](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/BUILDING.md)仍以 NDK r24 为例。需要验证从维护中的 Node 分支构建移动库及 16 KB 对齐的可行性。 |

Android [16 KB 页指南](https://developer.android.com/guide/practices/page-sizes)要求预编译共享库的 ELF 段也满足 16 KB 对齐；AGP/NDK 升级不会自动修复已下载的旧 `.so`。因此 v18.20.4 只能作为 4 KB 真机功能探针，不能据此通过 A3 发布门槛。

## 最小真机探针

- `app/android/nodeprobe` 是单独的 Debug 实验 App，不接入 Flutter 产品 UI 或 `AndroidRuntimePort`。`prepare.sh` 下载或接收上述 ZIP，校验 SHA-256，只将 arm64 `libnode.so`、头文件及项目锁定 NDK 的 `libc++_shared.so` 放入本机忽略目录；二进制和头文件不入 Git。首次加载失败准确报缺少 `libc++_shared.so`，补齐后成功。
- 实验 App 的 `:node` Service 在工作线程通过 C++ JNI 调 `node::Start`，固定 JS 入口复制到应用私有目录；JS 输出 Node 版本、写文件、完成 `127.0.0.1` HTTP 请求。Service 以 Android `Messenger` 返回 `STARTED`、`RESULT` 或 `ERROR`，每次 Service 进程有新的 generation。当前协议是一次性请求，`STARTED` 只代表工作线程开始，不代表 Node 已就绪；尚无取消、实时 console 事件或 Dart 平台通道。
- LGE AN10 真机返回 `v18.20.4`、`file=ok`、`network=network-ok`、退出码 0。一次启动到结果的观测为 326 ms；后续两次为 196/178 ms，均包括复制入口、加载库和 JS 调用，不是整 App 冷启动计时。空闲 Service 一次 `dumpsys meminfo` 为 PSS 53,877 KB、RSS 108,872 KB；Debug 探针 APK 约 96 MB。
- `verify_device.py` 安装 Debug APK，运行一次，单独杀 `:node` 进程并等待新代际再次成功；主进程 PID 保持不变，测试结束卸载实验 App。真机先后两次脚本通过；其中一次初版脚本在后台等待 15 秒没有收到第二个结果，后续改为必要时将 Activity 带回前台再等待。该现象需要 A3.5 继续测后台恢复，不能称为稳定自动重连。
- `flutter build apk --debug --no-pub` 通过，Aggregate 主 APK 不含 Node 探针库。NDK r28c 构建的 JNI 桥和 `libc++_shared.so` ELF `LOAD` 段均为 `0x4000` 对齐，`zipalign -c -P 16 4` 对实验 APK 通过；但旧 `libnode.so` 仍为 `0x1000`，整包不满足 16 KB 页原生加载门槛。

复现：在 `app/android` 运行 `nodeprobe/prepare.sh [Android ZIP] [NDK 路径]`、`./gradlew :nodeprobe:assembleDebug --offline`、`python3 nodeprobe/verify_device.py`。脚本使用当前连接的真机；没有启动模拟器。

## 后续实验门槛

1. 将 Service/JNI 桥作为可选实验能力接入 Flutter 宿主，设计带请求 ID、进程 generation、就绪/事件/关闭的 Binder 与 Dart 协议；继续隐藏 `cli`、`mcp-stdio` 适配器。
2. 验证 console、文件、网络、异常与取消事件，处理 Node 单实例、请求超时、旧请求失效、重复进入/退出和后台重连；测系统杀进程与升级后的资源清理。
3. 寻找或构建维护中的 Node 移动库，逐 ABI 检查 ELF、APK/AAB 对齐，并取得 16 KB 真机验证。未通过这些门槛前不进入 A4 产品化，也不声称设备端 npm/CLI 可用。
