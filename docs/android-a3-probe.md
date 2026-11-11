# Android A3：Node 原生桥探针记录

> 2026-11-11。A3 已启动；本记录先完成 A3.1 的候选库盘点，尚未接入或运行 Node。探针与用户可见 CLI 能力保持隔离。

## 当前基线

- 工程：Flutter Android 宿主，AGP 9.1.0、Kotlin 2.4.0、`minSdk 24`、`targetSdk 36`、NDK 28.2.13676358；尚无 `:node` Service、JNI 桥或 `libnode.so`。
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

## 后续实验门槛

1. 在独立 `:node` Service 进程接入最小 JNI 桥，先用上述候选包验证 `node::Start`、就绪/退出、Flutter 请求与事件，不暴露 `cli`、`mcp-stdio` 连接适配器。
2. 记录冷启动、内存、崩溃重连、重复进入、后台/杀进程及升级行为；明确 Node 单实例、请求 ID 与代际隔离。
3. 寻找或构建维护中的 Node 移动库，逐 ABI 检查 ELF、APK/AAB 对齐，并取得 16 KB 真机验证。未通过这些门槛前不进入 A4 产品化，也不声称设备端 npm/CLI 可用。
