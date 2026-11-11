# Android A3：Node 原生桥探针记录

> 2026-11-11。A3 进行中；默认 Debug 实验候选已更新至 fogtape Node 24.22.1 预发布。A3.1–A3.5 的固定探针范围已在 4 KB arm64 真机通过，包括运行中的 60 秒后台、后台进程终止后的重启及升级后陈旧探针文件替换。`am kill` 不等同真实低内存终止。A3.6 的 arm64/x86_64 成品静态对齐通过，16 KB 真机加载尚未验证。探针与用户可见 CLI 能力保持隔离。

## 当前基线

- 工程：Flutter Android 宿主，AGP 9.1.0、Kotlin 2.4.0、`minSdk 24`、`targetSdk 36`、NDK 28.2.13676358。`:nodebridge` Android 库由独立 `:nodeprobe` App 验证，也可通过显式 Gradle 属性加入 Flutter Debug APK；普通及 Release 包不依赖它。
- 设备：LGE AN10，Android 15/API 35，arm64，4 KB 页。当前没有 16 KB 页真机。
- A1 已完成，故 A3 的工程前置满足；A3 是独立实验，A2 的 HTTP MCP 能力不依赖它。

## A3.1 旧官方包核验（历史基线）

| 项目 | 结果 |
| --- | --- |
| 来源 | [nodejs-mobile v18.20.4 Android Release](https://github.com/nodejs-mobile/nodejs-mobile/releases/tag/v18.20.4)，2024-10-07 发布；Android ZIP 57,287,354 字节。 |
| 本次下载 SHA-256 | `bd7321eaa1a7602fbe0bb87302df2d79d87835cf4363fbdd17c350dbb485c2af`。这是本地下载的完整性锚点，Release API 未提供官方 digest；不能当作独立签名验证。 |
| ABI/头文件 | ZIP 含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 的 `libnode.so`，各约 62.5/58.7/65.4 MB；含 `include/node/node.h`，声明 `node::Start(int,char**)`。三个 ABI 的 ELF 均已检查。 |
| 版本/许可证 | `node_version.h` 为 18.20.4。仓库 [v18.20.4 LICENSE](https://github.com/nodejs-mobile/nodejs-mobile/blob/v18.20.4/LICENSE) 含 Node.js 及依赖许可文本；ZIP 未附 LICENSE，若分发需随包保留相应声明并复核完整依赖许可。 |
| 链接依赖 | arm64 ELF 需要 `libc++_shared.so`、`libm.so`、`libdl.so`、`liblog.so`、`libc.so`。JNI/NDK 构建须保证 C++ 运行库与 APK 打包一致。 |
| 16 KB 页 | 三个 ABI 的 `libnode.so` 各有四个 `LOAD` 段，均为 `0x1000`（4 KB）对齐，不满足 Android 的 16 KB ELF 对齐要求；该预编译库不能作为 16 KB 设备发布构建。实验 APK 的 ZIP 对齐另已检查，AAB 与 16 KB 真机加载仍未验证。 |
| 维护性 | [Node.js 官方版本表](https://nodejs.org/en/about/previous-releases)显示 Node 18 已于 2025-03-27 EOL；当前 nodejs-mobile Release 最新仍为 18.20.4。其[构建指南](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/BUILDING.md)仍以 NDK r24 为例。需要验证从维护中的 Node 分支构建移动库及 16 KB 对齐的可行性。 |

Android [16 KB 页指南](https://developer.android.com/guide/practices/page-sizes)要求预编译共享库的 ELF 段也满足 16 KB 对齐；AGP/NDK 升级不会自动修复已下载的旧 `.so`。因此 v18.20.4 只能作为 4 KB 真机功能探针，不能据此通过 A3 发布门槛。

| v18.20.4 Android ABI | `libnode.so` 字节数 | 四个 `LOAD` 段对齐 |
| --- | ---: | --- |
| `arm64-v8a` | 62,475,584 | 全部 `0x1000` |
| `armeabi-v7a` | 58,720,948 | 全部 `0x1000` |
| `x86_64` | 65,361,944 | 全部 `0x1000` |

[Node 上游构建说明](https://github.com/nodejs/node/blob/main/BUILDING.md)仍将 Android 列为非支持平台，也没有 Android CI；[nodejs-mobile 官方 Release](https://github.com/nodejs-mobile/nodejs-mobile/releases)仍以 Node 18.20.4 为最新。官方仓库的 [Node 24 / 16 KB 提案](https://github.com/nodejs-mobile/nodejs-mobile/pull/158)和 [Node 18 / 16 KB 提案](https://github.com/nodejs-mobile/nodejs-mobile/pull/155)均未合并。以下改用独立维护的 fork Release 作为实验候选，不把它称为 Node 官方 Android 支持。

## A3.6 Node 24 候选实物核验

- 来源：[digidem/nodejs-mobile v24.20.0-0 Release](https://github.com/digidem/nodejs-mobile/releases/tag/v24.20.0-0)，2026-09-03 发布的非预发布、不可变 Release；Android full ZIP 77,677,749 字节。Release API 提供 SHA-256 `f5ffbaf4f2679fa9180b0758c637c2f8fc8828300f95129badf213a028fb37bb`，本地下载匹配。其发布说明指向 [recipe 提交 `7c55423d73`](https://github.com/digidem/nodejs-mobile/commit/7c55423d731f7fec83ac52ab158901ce20a57356)；仓库的 [TESTING 说明](https://github.com/digidem/nodejs-mobile/blob/recipe/docs/TESTING.md)描述设备与 CI 测试，但本项目未独立复现该 fork 的完整测试。
- ZIP 含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 的 `libnode.so` 和 Node 24.20.0 头文件，未附独立 LICENSE 文件。[同一发布标签的 LICENSE](https://github.com/digidem/nodejs-mobile/blob/v24.20.0-0/LICENSE) 含 Node 及依赖许可文本；本地 SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`。当时的准备脚本校验并把它打入实验 APK 的 `assets/nodejs-mobile-LICENSE.txt`；错误摘要会在复制库之前失败。正式分发还需核对 NDK `libc++_shared.so`、其他依赖声明及用户可见许可入口。三个 ABI 各四个 ELF `LOAD` 段经 NDK r28c `llvm-readelf -l` 检查均为 `0x4000`；动态依赖包含 `libc++_shared.so`、`libm.so`、`libdl.so`、`liblog.so`、`libc.so`。
- digidem 24.20.0 的历史核验如上。当前 Debug 实验候选为 [fogtape v24.22.1-0](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)，对应 [Node 24.22.1 安全更新](https://nodejs.org/en/blog/release/v24.22.1)。该 Release 标为预发布，不能据此认定可正式分发；发布前仍需稳定维护版本及完整依赖许可审查。

| v24.20.0-0 Android ABI | `libnode.so` 字节数 | 四个 `LOAD` 段对齐 | 加载验证 |
| --- | ---: | --- | --- |
| `arm64-v8a` | 87,472,464 | 全部 `0x4000` | 4 KB 真机通过；16 KB 真机未测 |
| `armeabi-v7a` | 79,439,076 | 全部 `0x4000` | 未有对应真机 |
| `x86_64` | 85,885,640 | 全部 `0x4000` | 未有对应真机 |

fogtape ZIP 为 112,853,733 字节，本地 SHA-256 与 Release API 摘要同为 `d6fd9f610fe5d81fede8f0d400c5a62723247725a19831835f15abf4f0604250`。同标签 LICENSE 的 SHA-256 为 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`，已随实验包打入 assets。头文件为 24.22.1；三个 ABI 的 `libnode.so` 四个 LOAD 段均为 `0x4000`。`prepare.sh` 现在默认校验此候选并准备三 ABI，二进制与头文件仍在忽略目录，不入 Git。JNI 桥以 C++20 编译；脚本会触发 JNI 重编译。独立探针 App 与 Flutter Debug 桥在 LGE AN10 上返回运行时版本及头文件版本 `v24.22.1`、`file=ok`、`network=network-ok`。

## 最小真机探针

- `app/android/nodeprobe` 是单独的 Debug 验证 App；共用的原生实现放在 `app/android/nodebridge`。`prepare.sh` 下载或接收 Node 24 候选 ZIP，校验 SHA-256，将 arm64 库放入默认 `jniLibs`，另外两个 ABI 放入仅供 `a3ProbeAllAbis` 构建的忽略目录，并准备头文件及项目锁定 NDK 的 `libc++_shared.so`；默认构建仅打包 arm64。早期 Node 18 探针首次加载失败准确报缺少 `libc++_shared.so`，补齐后成功。
- `:node` Service 在工作线程通过 C++ JNI 调 `node::Start`，固定 JS 入口复制到应用私有目录；JS 输出 Node 版本、写文件、完成 `127.0.0.1` HTTP 请求。Service 以 Android `Messenger` 返回带请求 ID 和进程 generation 的启动、实际就绪、事件、结果、错误及关闭消息。当前协议只运行固定入口，`STARTED` 代表工作线程开始，JS 发出的 `ready` 事件才表示脚本已执行。
- LGE AN10 真机当前返回 `v24.22.1`、`file=ok`、`network=network-ok`、退出码 0。当前候选单次 Activity 冷启动 `am start -W` TotalTime 515 ms；Service 启动到 Node 结果 416 ms；结果后 Service PSS 58,171 KB/RSS 113,900 KB；arm64 独立 Debug APK 98,126,840 字节。均为单次观测，不是性能分布或产品包指标。旧 Node 18 候选的耗时和内存不用于当前判断。
- `verify_device.py` 安装 Debug APK，运行一次，单独杀 `:node` 进程并等待新代际再次成功；主进程 PID 保持不变。随后整 App `force-stop`、同包重装及 HOME 后 `am kill` 主进程和 `:node` 进程，各自重新进入并成功运行新代际，测试结束卸载实验 App。`am kill` 是系统命令触发的后台终止，不是内存压力下的 LMK；重启由重新进入触发，不证明后台自动重连。
- `verify_upgrade.py` 使用 Gradle 属性将独立探针 App 构建成 `versionCode` 1 和 2，真机安装 1、运行 Node，再把入口、结果和事件文件均改成陈旧标记，保留私有数据原位升级至 2 并再次运行。PackageManager 报告 1→2，新 Service 代际成功运行，三份陈旧文件均被替换且无额外探针文件；测试结束卸载实验 App。两包除了版本元数据没有业务代码差异，尚不覆盖脚本格式迁移或真实产品升级。
- `flutter build apk --debug --no-pub` 通过，Aggregate 普通 APK 不含 Node 探针库。默认 arm64 探针 AAB 经 bundletool 1.18.3 报 `PAGE_ALIGNMENT_16K`，由其生成的 universal APK 通过 `zipalign -c -P 16 4`。另以 `-Pa3ProbeAllAbis=true` 构建三 ABI AAB：九个原生库均进入成品，AAB 配置和 universal APK ZIP 对齐通过；arm64 与 x86_64 的全部库以及 armeabi-v7a 的 JNI/Node 库 ELF LOAD 段为 `0x4000`，但 NDK r28c 提供的 armeabi-v7a `libc++_shared.so` 为 `0x1000`。故不能声称三 ABI 的每个库均通过 16 KB ELF 静态门槛；默认发行范围仍仅 arm64。16 KB 真机及其他 ABI 真机加载未验证。

复现：在 `app/android` 运行 `nodeprobe/prepare.sh [Android ZIP] [NDK 路径] [同标签 LICENSE]`、`./gradlew :nodeprobe:assembleDebug --offline`、`python3 nodeprobe/verify_device.py`。ZIP 和 LICENSE 可省略以下载固定版本；都校验固定 SHA-256。脚本使用当前连接的真机；没有启动模拟器。

## Flutter Debug 测试通道

- `app/android/app` 仅在 Gradle 属性 `a3Probe=true` 时为 Debug 构建依赖 `:nodebridge`；Release 构建不加入该库。`MainActivity` 的 `aggregate/node_probe` 平台通道只在可调试 App 中提供 `capabilities`、固定 `run`、`cancel`、`crash` 测试命令，不接用户界面或 `AndroidRuntimePort`。未打入库时 `capabilities` 返回 `packaged=false`，`run` 返回 `unavailable`。
- `NodeProbeChannel` 经 Binder 发送请求，核对请求 ID 与 generation；Service 把固定 JS 写入应用私有目录的有界 JSONL 事件（上限 64 KB）实时转发到 Dart，包含 `ready`、`console`、`network`、`fileWrite`、`fileRead` 和 `exception`。这是实验传输方式，未将 JSONL 文件或回环端口暴露给其他 App。固定脚本支持最多 90 秒延迟，仅供 Debug 长后台测试；Service 在完成后关闭自身进程，下一次请求启动新代际。
- 主动 `cancel` 发送 `cancelRequested` 事件并终止 `:node` 进程；与意外崩溃一样，Dart 报 `outcomeUnknown`，不会自动重放。此结果不能证明脚本在终止前没有产生外部副作用。
- `capabilities` 由 Service 在加载 JNI 库后返回协议版本 1、唯一受控入口 `a3-fixed`、构建头文件版本 `v24.22.1`，并明确报告 `npm=false`、`cli=false`、`profiles=false`；头文件版本不是一次运行的 `process.version` 验证。Service 拒绝其他入口、任何 `profileRef` / `draftId` 与过期的 `expectedGeneration`。每次调用使用新的 Service 代际；这里验证的是固定探针不接受旧引用，尚未实现真实草稿或 profile 的迁移语义。
- LGE AN10 真机 `integration_test/android_node_probe_test.dart` 的探针构建通过两次连续调用、新代际、上述实时事件、脚本异常、主动取消、运行中崩溃及后续恢复。另一次用 HOME 键把 App 放到后台约 5 秒，进行中的固定请求仍完成。普通构建通过“探针不可用”；实验 APK 包含 `libnode.so`，普通 Flutter Debug APK 不含 `libnode.so` 或 JNI 桥，测试后已重新安装普通 Aggregate 包。`flutter analyze --no-pub` 无问题，独立 `:nodeprobe` 真机回归通过。
- A3.4 真机集成测试还通过能力查询、非法入口/引用/旧代际拒绝，以及拒绝后再次成功运行。服务测试通过整 App 重启和同包重装后的新代际运行。
- A3.5 追加真机集成测试：固定探针先成功运行，App 经 HOME 退后台 60 秒后回前台，新请求在不同 Service 代际成功；另有 20 次连续请求、20 个不同代际均成功。新增 70 秒固定请求在 JS `ready` 后退后台 60 秒，回到前台后同一请求成功完成。系统命令 `am kill` 后重新进入、升级后陈旧文件替换也通过。真实 LMK 压力、系统对更长时间后台执行的限制及产品级配置迁移仍未知。

| Binder 消息 | 含义 |
| --- | --- |
| `RUN` 1 | 固定入口、请求 ID、最多 90 秒延迟及失败样本开关。 |
| `STARTED` 2 | Service 工作线程启动；不等于 JS 就绪。 |
| `RESULT` 3 / `ERROR` 4 | 成功结果或失败；Dart 核对请求 ID 和 generation。 |
| `CLOSING` 5 | 单次运行后将退出 Service 进程。 |
| `CRASH` 6 / `CANCEL` 8 | 仅用于 Debug 的崩溃注入或进程级取消。 |
| `EVENT` 7 | JSONL 事件或取消请求；其中 `ready` 是固定 JS 入口实际开始执行的信号。 |
| `CAPABILITIES` 9 / `CAPABILITIES_RESULT` 10 | 查询实验库与固定入口；不声明 npm、任意 CLI 或 profile 能力。 |

真机探针构建命令：在 `app/` 运行 `ORG_GRADLE_PROJECT_a3Probe=true flutter test --no-pub integration_test/android_node_probe_test.dart -d <设备序列号> --dart-define=A3_PROBE_ENABLED=true`。后台专项测试另加 `--dart-define=A3_BACKGROUND_TEST=true`，在输出 `A3_BACKGROUND_READY` 后由主机发送 HOME 键。普通构建用相同测试路径而不设置 Gradle 属性与 Dart define。该过程只验证固定 JS 样本，不证明 npm 安装、任意 CLI 或可发布的 Node 运行时。

A3.5 长后台测试另加 `--dart-define=A3_LONG_BACKGROUND_TEST=true`，在 `A3_LONG_BACKGROUND_READY` 后主机发送 HOME，等待 60 秒，再把 Aggregate 带回前台；重复调用测试加 `--dart-define=A3_REPEAT_TEST=true`。在 `app/android/` 运行 `python3 nodeprobe/verify_upgrade.py` 可复现独立 App 的两版本原位升级；脚本只使用当前连接的真机，不启动模拟器。

运行中后台专项测试另加 `--dart-define=A3_ACTIVE_BACKGROUND_TEST=true`，在 `A3_ACTIVE_BACKGROUND_READY` 后发送 HOME，等待 60 秒再回前台。三 ABI 静态验收可在 `app/android/` 运行 `./gradlew :nodeprobe:bundleDebug -Pa3ProbeAllAbis=true`；该开关不改变默认 arm64 包，不代表其他 ABI 已在设备上运行。

## 后续实验门槛

1. 扩展固定探针之外的受控包入口之前，逐包验证 A4 门槛。当前能力查询只声明 `a3-fixed`，继续隐藏 `cli`、`mcp-stdio` 适配器。
2. 取得可复现的真实 LMK 压力测试、产品级配置迁移和目标后台策略证据；现有 `am kill`、一分钟运行中后台与陈旧探针文件替换只覆盖已记录的范围。
3. 取得稳定维护、许可齐备的 Node 移动库及 16 KB 真机加载验证；如果扩展到 32 位 ABI，需解决其 `libc++_shared.so` 的 4 KB ELF 对齐并在对应设备加载。当前实验 APK 已携带 Node LICENSE，但完整分发许可仍待审。未通过这些门槛前不进入 A4 产品化，也不声称设备端 npm/CLI 可用。
