# A4.4：Android 设备端 npm 安装可行性先验

查阅日期：2026-11-12。范围是 Aggregate 当前 nodejs-mobile Android Debug 探针上的 npm CLI、包安装和 Google Play 分发边界。这里记录官方资料与工程推断，不构成 Google Play 预审或法律意见。

## 官方资料确认的事实

1. **nodejs-mobile 文档支持的是开发期装包工作流。** FAQ 说明 npm 模块可以与 nodejs-mobile 一起使用，但建议在开发时把模块安装到含 Node 项目文件的应用源码目录；原生 addon 需要针对目标平台/CPU 交叉编译，含自定义构建步骤或平台代码的包可能需要适配。[nodejs-mobile FAQ](https://nodejs-mobile.github.io/docs/guide/faq/)

2. **移动版 Node API 不是完整桌面环境。** nodejs-mobile 将 `child_process` 和 `cluster` 标为不支持；Android 不支持 `fs.link()` 硬链接；运行时的 `cwd` 是 `/`，`process.stdin` 默认不可用。应用必须提供可写的沙箱目录。[Node.js Mobile API differences](https://nodejs-mobile.github.io/docs/api/differences/) [nodejs-mobile FAQ](https://nodejs-mobile.github.io/docs/guide/faq/)

3. **npm 安装不只是下载和解包。** npm install 会解析依赖并处理 lockfile；lockfile 可记录 registry tarball 的 `resolved` 地址及其 `sha512`/`sha1` `integrity`。npm 还提供 `npm audit signatures` 来验证 registry 签名和 provenance attestation。[npm install](https://docs.npmjs.com/cli/v12/commands/npm-install/) [package-lock.json](https://docs.npmjs.com/cli/v12/configuring-npm/package-lock-json/) [npm audit signatures](https://docs.npmjs.com/cli/v12/commands/npm-audit/)

4. **安装脚本是运行时能力的一部分。** npm install 会触发适用的 `preinstall`、`install`、`postinstall`、`prepare` 等生命周期；有 `binding.gyp` 且没有自定义 install hook 时，npm 会尝试调用 `node-gyp rebuild`。POSIX 上生命周期命令通过 `/bin/sh` 执行，`--ignore-scripts` 可禁止 package scripts。[npm scripts](https://docs.npmjs.com/cli/v12/using-npm/scripts/) [npm install](https://docs.npmjs.com/cli/v12/commands/npm-install/)

5. **npm 缓存会占用持续增长的应用私有空间。** npm 文档说明缓存数据会在写入和提取时校验，并提供 `npm cache verify`；npm 不会自动删除缓存数据，缓存目录会随安装增长。缓存只作缓存，不保证一定留存。[npm cache](https://docs.npmjs.com/cli/v12/commands/npm-cache/)

6. **当前 npm 12.2.2 声明的 Node 引擎范围覆盖现有 Node v24.22.1。** npm 12.2.2 的 `engines.node` 为 `^22.22.2 || ^24.15.0 || >=26.0.0`，因此从版本声明看可选作本项目 Debug 探针的候选版本；这不等于它已在 nodejs-mobile 上运行。[npm 12.2.2 package.json](https://github.com/npm/cli/blob/v12.2.2/package.json)

7. **Android 与 Google Play 对动态代码加载有额外要求。** Android 建议尽量避免动态加载代码；确有需求时，建议使用可信来源、应用内部/Scoped Storage，并在加载前做完整性校验。Android 也指出动态代码会在宿主 APK 相同的应用权限下运行。[Android Dynamic Code Loading](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)

8. **Google Play 当前政策不是对任意 npm 安装的通用许可。** 2026-10-29 生效的政策禁止应用从 Google Play 以外下载 dex/JAR/`.so` 等可执行代码；文本对运行在 VM/解释器中的代码列出例外，同时要求应用或第三方代码在运行时加载的 JavaScript、Python、Lua 等不得允许潜在政策违规。政策还将下载可执行代码、安装其他应用和恶意软件分发列为违规示例。[Google Play Developer Program Policy](https://support.google.com/googleplay/android-developer/answer/18265346?hl=en)

## 对 Aggregate 的工程推断

- **普通纯 JS 包的“无脚本、无原生模块安装”值得做受限设备验证。** npm 的包解析、下载、完整性校验和解包是可单独观察的环节；nodejs-mobile 的文档并未称这些环节必然失败。但 npm 上存在 `child_process` 不可用的明确限制，所以不能从 A4.1/A4.2 APK 随包结果推断 npm CLI 能在设备端启动或完成安装。
- **通用依赖安装脚本与当前 runtime 能力存在直接冲突风险。** npm 官方 [`@npmcli/run-script`](https://github.com/npm/run-script) 通过子进程 runner 执行生命周期脚本，npm 也说明 POSIX 脚本默认交给 `/bin/sh`；nodejs-mobile 明确不提供 `child_process`。因此依赖 install hook、`node-gyp`、shell 命令或其他子进程的包很可能失败；具体首个失败点必须由固定 Debug 样本测出。不能据此宣称所有 npm install 都会失败。
- **`--ignore-scripts` 只减少一类安装行为，不是安全沙箱。** JavaScript 包仍在 Aggregate 所在进程及其应用权限下运行；单纯设置 npm 配置不能把依赖代码隔离到另一 Android UID。
- **允许任意 registry 包会带来比 A4.3 静态 allowlist 更大的信任面。** 锁文件和 integrity 能固定/校验下载内容，但不能证明包的行为适合 Aggregate 的功能或 Play 政策。Play 资格需要结合具体用途、发行渠道、包集合和产品交互审查，不能从解释器例外本身推导通过。

## 建议的 A4.4 真机验收顺序

所有实验继续留在独立 Debug APK 和应用私有目录；先固定 npm CLI、registry、包版本和 tarball integrity，再逐层扩大样本。建议采用有界结果而不是直接安装 `latest` 或用户任意包。

| 顺序 | 实验 | 通过条件 |
| --- | --- | --- |
| 1 | npm CLI 启动 | 固定 npm 版本在 Node v24.22.1 内启动；记录其解包体积、依赖树、Node API 首个错误与 stdout/stderr |
| 2 | 纯 JS、无 install scripts 的固定小包 | 从指定 registry 安装到 `files/a4-npm-workspace`；校验 lockfile 的 resolved/integrity，包可从该私有路径加载；APK 既有 JSON5 探针目录不受影响 |
| 3 | 完整性拒绝 | 错误 SRI、损坏 tarball 或不匹配的版本信息应在提交前失败；旧安装仍可用，不能留下半成品树 |
| 4 | cache 与断网 | 同包重复安装观察 cache 命中；先联网填充缓存后断网做有界离线安装；测缓存体积上限、清理与断点恢复 |
| 5 | 生命周期边界 | 使用本地、无害、只写一个测试标记的 fixture，分别检查脚本被禁用、被允许运行时的返回码和确切失败点；不从公网任意包直接执行安装脚本 |
| 6 | 不兼容能力拒绝 | 固定带 `binding.gyp` 或必需安装脚本的 fixture，确认设备侧能显示明确错误并回滚；不尝试在应用沙箱里编译/加载任意 native binary |
| 7 | 升级/删除/强杀恢复 | 更新、卸载、进程强杀后重启；核对 profile 引用、旧包清理、缓存配额、回滚和没有孤儿目录 |

完成后只报告这套 npm 版本、固定样本、设备及 Debug 路径的结果。若后续要评估 Play 发布，需另做发行渠道和允许包清单的产品审查；不要把 A4.4 的实验结果直接升格为可安装任意 npm 包的产品承诺。

## A4.4 Debug 真机结果（2026-11-12）

设备为 LGE AN10、Android 15/API 35、arm64、4 KB 页；使用独立 Debug APK。APK 中固定 npm 12.2.2 tarball SHA-512 为 `KglgbZyacf7jH+FHuNRqVuCzQi8VhI2a7J87Ix43FsPTuZoGWmIXXGdZtBUOA79vwL+IJREqURVzupA7PsQTcA==`，Node 报告版本为 v24.22.1。此设备不代表 16 KB 页或其他 ABI。

| 样本 | 设备结果 |
| --- | --- |
| npm CLI 启动 | `npm --version` 输出 12.2.2。 |
| Registry 安装与依赖解析 | `supports-color@7.2.0` 与传递依赖 `has-flag@4.0.0` 安装成功；两项均写入 registry `resolved` URL 和 SHA-512 lockfile integrity，之后从应用私有目录 `require` 成功。 |
| 完整性失败 | 对 `json5@2.2.3` 的 `npm ci` 使用错误 SHA-512，npm 返回失败并报告 integrity 错误，`node_modules/json5` 未生成。 |
| 离线恢复 | 前一安装缓存可供全新 workspace 的 `npm install --offline` 使用；两个依赖重新安装并可 `require`。 |
| 安装脚本 | `--ignore-scripts` 安装成功且 marker 不存在；默认安装也报告 npm 12 的 `allowScripts` 阻止脚本，安装返回 0 但不执行 marker。明确授权本地 tarball 的精确 `file:` 来源后，npm 尝试执行 `sh -c node install.js`，以 127 退出且 marker 不存在。该结果与 nodejs-mobile 不支持 `child_process` 的官方说明一致；pointer-tag fatal 的具体根因尚未定位。 |
| 升级、卸载与缓存 | `json5` 从 2.2.2 升至 2.2.3、卸载，以及 `npm cache verify` 均在同一 Debug 探针流程通过。 |

首次整轮探针 11 个操作均生成了带 npm 退出码的应用私有结果文件。首次统计 Messenger 终态时，验证器在 `npmResult` 事件到达后立即读取 Logcat，存在先后时序竞争；该轮 `0/11` 数字作废。修正为最多等待 3 秒后，下一轮日志确认普通 registry 安装与离线安装都收到 Messenger `kind=3`；单独清除 app-private CLI 目录后再次运行 `npm --version`，也确认了资源重拷贝和 `kind=3` 正常。另一轮在 `script-ignored` 操作中 Service 断开，Android crash buffer 记录 `Pointer tag ... was truncated`；单独运行精确授权的 `script-allowed` 时，结果文件写出 npm 127，但随后也记录该 fatal。故不把问题归结为所有 npm 结果都无法通过 Messenger 传递；失败集中在本地生命周期脚本样本附近，根因尚未定位。单次实验能完成缓存/版本用例不代表该边界稳定。

**A4.4 结论：**受限实验已证明该固定 npm 版本能在这台 4 KB arm64 真机执行 CLI、安装普通纯 JS 包、验证 lockfile integrity、复用缓存并升级/卸载包；npm 12 的默认脚本门控也确实阻止未批准脚本。但显式允许后的 shell 依赖以 127 失败，本地生命周期脚本样本触发一次 Node Service fatal，且该次样本没有观察到终态 Messenger 回复。因此只把 A4.4 记为 Debug 可行性实验完成；不把设备端 npm、任意依赖脚本或通用 CLI 加入产品能力。产品决定仍需 A4.7，Play 政策结论、16 KB 真机和其他 ABI 未覆盖。

## 2026-11-17 Node 24.22.3 test-signed Release npm 补验

在上一节生成的 NodeProbe arm64 Release APK 上追加固定 npm 样本。APK SHA-256 `497a13780722206cce30e88c327457dffd6cddb12d193a834b943ff5c070a632`，使用一次性本地测试证书；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页。包内 Node 主版本为 v24.22.3，npm CLI 为 12.2.2。APK 非 debuggable，原 `verify_a4_npm.py` 使用 `run-as` 读取结果文件会被拒绝；本次临时执行器从 ProbeActivity 的 `kind=3` Messenger 日志读取同一 JSON 结果，没有修改仓库中的验证脚本。

| 固定动作 | Release 实测 |
| --- | --- |
| `version` | 终态收到；Node `v24.22.3`、npm `12.2.2`，npm 退出码 0。 |
| `install` | 终态收到；registry 安装 `supports-color@7.2.0` 与 `has-flag@4.0.0`，SHA-512 lockfile integrity 完整，包可从应用私有目录加载；退出码 0。 |
| `offline` | 使用前一步预热的应用私有 npm cache，在全新 workspace 离线重装同一依赖并加载成功；退出码 0。这不是首次启动离线验证。 |
| `integrity-bad` | 错误 SHA-512 被拒绝，npm 退出码 1，integrity 错误可见且 package 未生成。 |
| `upgrade-old` / `upgrade-new` | `json5` 2.2.2 安装、升级到 2.2.3 均退出码 0，lockfile 版本符合目标。 |
| `uninstall` / `cache-verify` | 卸载移除了固定 `json5` 包；npm cache verify 退出码 0。 |
| `script-ignored` | 两次隔离 Release 执行均先发出 `npmResult`（npm 退出码 0），随后 Node Service 断开；没有 Messenger `kind=3` 终态，因此 Release harness 未取得完整结果 JSON，脚本 marker 状态未知。`adb logcat -b crash` 同期记录 fatal pointer-tag 文本（`Pointer tag ... was truncated`）。第一次发生在 version/install/offline 后的整轮；第二次为新安装后的单独复现。 |

Release 测试只证明表列固定动作。`script-default` 与 `script-allowed` 没有在 Release APK 执行；Debug 版此前的 `script-allowed` 仍是 `sh -c node install.js` 退出 127，不能外推成 Release 通过。本次 pointer-tag fatal 文本与脚本样本有时间关联，但没有足够堆栈证据定位到 `libnode`、Android framework 或 Probe teardown 根因，不能把 npm 的 `exitCode=0` 事件当作完整成功，也不能把该 fatal 直接归因为 Node runtime 缺陷。隔离 NodeProbe 测试包已卸载，主 Aggregate 包仍安装。

**结论：**Node 24.22.3 test-signed Release 已验证 npm 版本、普通 registry/预热 cache 离线安装、integrity 拒绝、版本升级/卸载和 cache verify；本地生命周期 fixture 在 `script-ignored` 阶段两次未取得终态。A4.4 原复选仍表示固定 npm Debug 可行性实验完成；该 Release 补验扩展了候选证据，不批准用户任意 npm、安装脚本、通用 CLI 或产品 Node 入口。无 16 KB 真机、无 Aggregate 产品签名或发布验证。

- **verified_scope：**NodeProbe `24.22.3-0` arm64 test-signed Release APK、Android 15/API 35/4 KB LGE AN10、npm 12.2.2 固定 action intents；Messenger terminal JSON 对所有标记为“终态收到”的动作均从 kind=3 Activity log 取得。脚本 fixture 的两次 action 只有 kind=7 npmResult、无 kind=3；其完整 result file/marker 未读取。未运行 Release `script-default`/`script-allowed`、16 KB 设备、其它 ABI 或 Aggregate 产品包。
- **retrieval_feedback：**复核本项目 A4.4 的固定 fixture、`verify_a4_npm.py` assertions、NodeProbe Service 的 intent allowlist/result protocol 和 2026-11-12 Debug 结果；复用相同 package versions、registry integrity 与升级检查，但不把 Debug 结论外推至本次 Node 24.22.3 Release。A3.6 的测试签名 APK/hash 与现场 logcat 核对，Release private result 改从既有 Messenger kind=3 Activity detail 读取；脚本 action 没有 kind=3 时保持未知。未检索其他项目。


## 2026-11-18 Debug npm lifecycle `node` 别名补验

- **复验条件：**以隔离 NodeProbe Debug APK 为底制作 test-signed APK，targetSdk 36、包名 `io.github.guog962464.aggregate.nodeprobe.a3exec`；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB。APK SHA-256 `7165e5e80f7a4a8ef6efa0a624c1b83942b33ff4cb62c946128f44e4569e8575`，APK 静态对齐与签名验证通过。Node 为 v24.22.1，npm 为 12.2.2。
- **结果：**临时 APK 的 Node 启动代码把 app-private `files/node-bin` 前置到 PATH；ADB 在该目录创建 `node` 符号链接指向 APK `nativeLibraryDir/libnode_cli.so`，并同目录链接 `libnode.so`/`libc++_shared.so`。固定本地 npm 授权 tarball 的 install script 调用 `spawnSync('node', ['--version'])`，npm 退出 0，子进程退出 0 并返回 `v24.22.1`。这补充了“仅在提供别名及 PATH 后，该固定 lifecycle 脚本可运行”的证据；旧 Debug 实验未提供该别名时的 127 结果仍成立。
- **测量修正：**npm global prefix 把安装内容写到 `lib/node_modules/`；NodeProbe 原 `scriptAllowedMarker` 检查路径漏掉 `lib/`，导致结果字段报 false，尽管标记文件存在。已修复 `app/android/nodebridge/src/main/assets/a4-npm-probe.js` 并在本轮 test APK 验证字段为 true。
- **范围：**别名目录、PATH 前置和带 `spawnSync` 的 fixture 均只在一次性 APK/测试输入中修改；NodeBridge 未自动生成别名。本次不证明任意 npm 安装脚本、registry 安装、通用 CLI/TUI、当前安全版 Node、正式签名或 16 KB 兼容。测试包卸载、临时 APK 与文件删除；普通 Aggregate 包未触碰。A4.4 的产品边界不变。
- **verified_scope：**固定 Debug npm 12.2.2、本地授权 tarball、手动 nativeLibraryDir 符号链接、Android 15 4 KB arm64 实机；实际 result JSON 的 `npmExitCode=0`、`scriptAllowedMarker=true` 和安装标记的 child status/stdout。未运行完整 npm suite 或生产业务。
- **retrieval_feedback：**沿用本文件 2026-11-12 npm Debug 无别名 127 与 A3.6 2026-11-18 native executable 记录；对照 Android 包路径、npm global prefix 实际安装目录及当前探针结果字段。新证据带有手动 PATH/别名前提，不替换无别名历史记录，也不将其上推为产品支持。

## 2026-11-18 NodeProbe 自动别名补验

NodeProbe Debug 专用实现现会在固定 `a4-npm` action 中将 APK `nativeLibraryDir/libnode_cli.so`、`libnode.so` 和 `libc++_shared.so` 映射到应用私有 `files/node-bin/`，并在 npm 进程启动脚本中把该目录前置到 PATH。NodeProbe 的 `prepare.sh` 使用 NDK C++20 为三种 ABI 构建 PIE launcher；默认 APK 仍只含 arm64。固定本地授权 fixture 调用 `spawnSync('node', ['--version'])`，将 child 退出状态和版本写进安装 marker。生产 NodeBridge 与 ADR 0003 未变。

- 构建命令：`nodeprobe/prepare.sh "" "$ANDROID_NDK_HOME" ""`、`nodeprobe/prepare_a4_npm.sh`、`./gradlew :nodeprobe:assembleDebug --offline -Pa3Probe=true`。
- arm64 Debug APK SHA-256：`7073f75cddc263127fd319a08f8f8f2314adee353aa87c794a7dbdce0b56d9f5`。包内含 `libnode_cli.so`；manifest `extractNativeLibs=true`；`zipalign -c -P 16 4` 与 `apksigner verify` 通过。三个 ABI launcher 的静态检查均确认 Android linker、`RUNPATH=$ORIGIN`、Node/C++ 依赖及全部 `PT_LOAD` 为 16 KB 对齐。
- LGE AN10 / Android 15/API 35 / arm64 / 4 KB 页真机上，本地授权 `script-allowed` 的 npm result 文件记录 `npmExitCode=0`、`scriptAllowedMarker=true`；marker 显示 `node --version` 子进程 status 0、版本 `v24.22.1`。但 Node `:node` service 随后在 Messenger `kind=3` 前断开。crash buffer 只有 `Pointer tag for 0x6767612e34363432 was truncated`，无可定位堆栈。两次复验一致，故生命周期命令已实际执行，但 service 稳定性未通过；不能把安装 marker 或 npm 事件单独记为完整验收通过。
- `verify_node_alias.py` 要求单台实体 arm64/4 KB 设备，拒绝模拟器和已安装 NodeProbe 包，并在自身安装后清理隔离包。验收后 NodeProbe 已卸载，普通 Aggregate 仍安装。无 16 KB 真机、其他 ABI 运行、Node 安全版本/provenance 或正式发布验收。

该结果把“PATH 找到 `node` 并实际执行”与“Node Service 正常完成并返回 Messenger 终态”拆分记录。A4.4 仍只代表受限 npm Debug 可行性实验；生命周期稳定性继续开放，任意 npm/CLI 和产品 Node 入口仍关闭。

## 2026-11-18 NodeProbe argv 修正与 npm 复验结论

初始 `script-allowed` marker 已写出后，Node `:node` service 在 JNI 返回阶段触发 pointer-tag fatal。对比仅增加 argv 空指针与改用单块可写连续 argv 缓冲区的真机结果后，后者消除了该 fatal；`verify_node_alias.py` 及 `script-default → script-allowed` 转换收到 Messenger `kind=3` 并等到 Node 关闭 `kind=5`。这修复的是 NodeProbe 的 `node::Start` 参数存储方式，不代表产品 NodeBridge 或任意 Node embedder。

当前 NodeProbe APK SHA-256 为 `fe9dc80087c113e9967374b06428422464cd117fc4efe8e2a4981c04aded87fc`；`zipalign -c -P 16 4`、`apksigner verify` 通过。LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机上，固定 npm 12.2.2 / Node v24.22.1 的自动 `node` alias lifecycle 专项通过。一轮完整 11 项 suite 也通过，终态 11/11；在验证器逐项等待 Node `kind=5` 之前，一次完整重跑在 `script-allowed` 前没有新 Service 事件并于 120 秒超时；加入关闭等待后，lifecycle 转换专项和一轮完整 11 项 suite 通过。

错误 SHA-512 场景在 5 次全新隔离安装中均被 npm 拒绝并返回 integrity failure，Service 终态均到达。关闭 Node worker 后 2/5 次仍留有 `json5/lib` 部分文件，3/5 次目录没有残留。验证器现在等待每个 action 的 Messenger 终态与匹配 Node 关闭事件，并在 worker 关闭后查验包树；只要残留仍出现就令套件失败，不跳过后续升级、卸载和缓存检查。完整结果与 JNI 对照见 [A3.6 NodeProbe 后续记录](android-a3-runtime-research.md#2026-11-18-nodeprobe-argv-修正与-npm-稳定性复验)。

结论：该探针证明设备端 Node 命令 alias 与一个固定本地 lifecycle child 可工作；npm integrity 拒绝后的清理及完整动作序列仍不稳定。A4.4 只保留 Debug 可行性实验结论，不开放通用 npm/CLI 或产品 Node 入口；没有 16 KB 真机、其他 ABI 实机、正式产品签名或当前安全版 Node 证据。

## 2026-11-18 npm integrity 部分解包诊断

- 在同一 NodeProbe APK（SHA-256 `fe9dc80087c113e9967374b06428422464cd117fc4efe8e2a4981c04aded87fc`）和 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页真机上，把最小场景缩到单个 `integrity-bad` npm ci 操作。两组各 8 轮；每轮先删除应用私有 integrity workspace、npm cache 与 npm home。每一轮均以 npm exit 1 报 integrity mismatch，并收到 Messenger `kind=3` 和匹配 Node 关闭 `kind=5`。第一组 1/8 留下 `json5/lib/unicode.d.ts` 与 `json5/lib/util.d.ts`；第二组 2/8 留下相同文件。没有据此推断为完整或可加载的包。
- 第二组使用已有 `integrityPackageExistsAtFinalize` 结果字段观测收尾时机：两次残留轮在 Probe `beforeExit` 结果写入时已存在包目录，立即检查、等待 500 ms 和 3 秒后文件均保持不变。通过同一 app UID 的 `run-as rm -rf` 可删除它们。由此排除读取过早、延迟清理及 UID 无删除权限作为这次残留的解释；每轮清除 workspace/cache 后仍复现，也不支持单纯旧状态污染。
- 核对本地准备出的固定 npm 12.2.2 `pacote/lib/fetcher.js`：`extract()` 先对目标目录执行 `#mkdir()`，再启动 tarball stream 和 tar extractor；stream/extractor 出错时 rejection handler 记录并拒绝 Promise，没有清理目标目录的分支。这个源码路径与真机在 `beforeExit` 看到的部分解包吻合。该判断针对本地固定 npm 资产，不外推其他版本。
- **该轮处理结论：**这是被测 npm tarball 解包失败留下部分文件的行为，不是 NodeProbe Messenger 终态或设备文件权限故障。保留 `verify_a4_npm.py` 的失败断言，不通过改写预期将套件置绿；截至该轮，NodeProbe/产品 NodeBridge 未增加安装回滚代码，ADR 0003 的“Android 用户 npm 安装不开放”决定不变。A4.4 仍仅表示受限 Debug 可行性样本已运行，不能宣称原始 npm integrity 失败保证无半成品。
- 清理回读：NodeProbe 独立包已卸载，普通 Aggregate 仍安装，ADB reverse 为空；没有启动生产 Mac Host。只跑上述固定 integrity action，没有重跑完整 11 项 npm suite。

## 2026-11-18 Debug npm 暂存失败回滚原型

- supersedes：上节“截至该轮，NodeProbe/产品 NodeBridge 未增加安装回滚代码”只在 NodeProbe 的固定 Debug 诊断范围内更新；上节关于原始 npm 解包失败会遗留部分文件的观察仍有效，产品 npm 决定不变。
- **实现范围：**新增固定 allowlist 动作 `integrity-transaction`，只在独立 `:nodeprobe` / `:nodebridge` Debug 探针中运行。它把 `npm ci` 的 prefix 指向独立 `.staging`，以一份 527,123-byte 合成包和错误 SHA-512 lockfile 经本机 `127.0.0.1` fixture 测试；设备到主机只通过 `adb reverse`，npm registry 设置也指向该 loopback。探针在 `beforeExit` 先记录 npm 暂存包树，失败后只删除 `.staging`，再核对另一目录内预置的 0.9.0 包及标记文件未变。原 `integrity-bad` action 和 npm CLI 本身未修改，产品 NodeBridge 未加入安装回滚逻辑。
- **真机验收：**构建 `:nodeprobe:assembleDebug --offline -Pa3Probe=true` 成功，测试 APK SHA-256 为 `6f508baeb617840dc645bb2056113942fe5854ee376e39bf18d1a172bba2635e`；执行 `python3 nodeprobe/verify_a4_npm.py --integrity-transaction-only`。LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机上的 npm 12.2.2 / Node v24.22.1 返回 `EINTEGRITY`、npm exit 1，并收到 Messenger `kind=3` 和 Node close `kind=5`。本轮第 1/16 次干净 cache 尝试在 `.staging/node_modules/aggregate-a4-integrity-fixture` 观察到 `lib/fixture-059.d.ts` 至 `lib/fixture-063.d.ts` 的部分解包；清理后 `.staging` 不存在，预置包仍为 0.9.0，标记内容前后均为 `old-install-preserved`。验证器最多尝试 16 次以处理 npm 部分解包的非确定性，并要求本轮至少捕获一次暂存包残留。
- **结论与限制：**该原型证明固定失败场景下，隔离暂存清理可以清除实际观测到的部分解包并保留既有目录。它没有验证成功安装后的 promotion/原子切换，也不改变 npm 自身的行为；不支持任意用户 npm 包、生命周期脚本或产品 Node 入口。只覆盖这一台 4 KB arm64 真机；16 KB、其他 ABI、产品 Release 与正式发布资格仍未验证。
- **清理回读：**独立 NodeProbe 测试包已卸载，`adb reverse --list` 为空；未启动 Mac Host、未连接外网 registry，用户 `pubspec.lock` 修改未纳入任务变更。原始完整 npm suite 未重跑。

## 2026-11-18 Google Play 动态代码政策复核

本次只核对 Google Play 与 Android 官方公开政策文本，不构成 Google 对 Aggregate 的个案审批、法律意见或 Play Console 审核结果。

### 官方政策事实

- Google Play 当前 [Device and Network Abuse policy](https://support.google.com/googleplay/android-developer/answer/16559646) 规定：Play 分发应用不得绕过 Play 更新机制自行修改/替换/更新；一般也不得从 Play 以外下载 dex、JAR、`.so` 等可执行代码。文本明确为“运行在 VM 或 interpreter 中的代码”列出例外，同时要求运行时加载、未随应用打包的 JavaScript、Python、Lua 等解释型代码不得允许潜在 Play 政策违规。政策示例还禁止下载/分发恶意软件以及未获授权访问设备、网络、API 或服务。政策页说明摘要不替代完整政策；本记录按同页完整条款复核。
- Android 官方 [Dynamic Code Loading 安全指引](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading) 建议没有业务必要时避免动态代码加载；需要加载时使用可信来源和应用内部/Scoped Storage，并在加载前校验完整性。官方 [Security checklist](https://developer.android.com/privacy-and-security/security-tips) 明确动态代码与 APK 享有相同的应用权限，解释器本身不是 Android 应用沙箱边界。

### 对 Aggregate 的结论

- 官方条文没有把“npm”作为名称整体列为禁止项；解释型代码条款也不等于对任意 npm 包的预先许可。是否合规取决于具体代码、下载内容、执行能力、面向用户的用途，以及其是否可能违反其他 Play 政策。
- Aggregate 当前 NodeProbe 的 npm 流程是隔离探针；Gradle 仅在显式 `a3Probe=true` 时将 `:nodebridge` 加入 `debugImplementation`，Flutter/Dart 产品代码没有 `aggregate/node_probe` 调用路径，主 App 产品 Release 验收记录确认 APK/AAB 不含 NodeProbe、NodeBridge、`libnode.so` 或 npm assets。NodeProbe 的 npm action 仍为固定 allowlist；Android 产品决定仍按 [ADR 0003](decisions/0003-android-local-execution.md) 保持关闭。
- 若未来提交 Play 版本，当前证据支持继续不提供用户任意安装包、任意生命周期脚本或从 registry 下载并加载 native `.so`。如果以后评估受控 JS，应先限定随 APK 打包或可审计的固定包清单、来源与摘要，在加载前验证，限制可调用能力并说明用途；这些是工程风险控制建议，不代表 Google 已批准。
- **门槛状态：**官方文档级预审已完成；Play Console 个案审查/实际上架结果未知。任意 npm 仍不进入 Android 首版；此复核不关闭 A3.6 的 Node 来源、SBOM/许可、正式签名和 16 KB 真机门槛。
