# A4 npm 包与 CLI 兼容性实验

> 2026-11-11 启动。仅在 Debug 独立探针上验证真实 npm 包；A3.6 尚未完成，本记录不构成发布资格或设备端 npm/通用 CLI 支持。

## 首个样本：JSON5 2.2.3

- `npm view json5@2.2.3` 报包入口 `lib/index.js`、bin `lib/cli.js`、无运行依赖，tarball integrity 为 `sha512-XmOWe7eyHYH14cLdVPoyg+GOH3rYX++KpzrylJwSW98t3Nk+U8XOl8FWfxasyg==`；本地 tarball SHA-256 为 `08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b`。`nodeprobe/prepare_a4.sh` 校验该摘要、名称/版本/入口后，把源码、分发文件、包元数据与 MIT LICENSE 暂存于忽略目录。包源不入 Git。
- 独立 Debug App 通过 `--es probe a4-json5` 选择实验入口；Service 把包复制至应用私有 `files/node_modules/json5`，在隔离的 `:node` 进程运行固定脚本。Flutter 产品界面和 `ConnectionSetupPort` 未开放该入口，现有能力查询仍只声明 `a3-fixed`。
- LGE AN10、Android 15/API 35、arm64、4 KB 页：原始包 `require`、运行时拼接路径的动态 `require`、包自带 `dist/index.js`、`dist/index.mjs` 的动态 `import` 均成功解析同一 JSON5 输入；`package.json` 资源读取正确，配置写在应用私有目录并可读回。整 App `force-stop` 后第二次运行成功且 Service generation 不同。`verify_a4.py` 用固定结果断言复现；没有独立外部实现对照。
- 首次样本验收只覆盖源码与 JSON5 自带分发文件；esbuild 对照、固定 bin 的版本/帮助调用和实际包版本升级随后在下方补充验收。bin 取消/并发以及设备端 `npm install` 和任意 CLI 仍未验证。

## A4.1 / A4.2 补充验收（2026-11-12）

- 固定 JSON5 2.2.3 tarball SHA-256 校验通过；esbuild 0.25.12 生成 bundle 45,044 字节，JSON5 包文件树为 235,198 字节。bundle 与包自带 dist、源码 `require`、动态 `require`、ESM 的固定 JSON5 输入结果一致；真机结果事件断言 bundle 一致，且 bundle 小于源包文件树。
- LGE AN10、Android 15/API 35、arm64、4 KB 页真机上，源码/动态加载/包内 CJS/ESM/esbuild bundle、`package.json` 读取和私有配置写读通过；整 App force-stop 后再次成功，Service generation 改变。首次运行后注入的旧包目录标记在重启重复制包后消失。
- 同一真机完成两个不同包版本的 APK 原位升级：JSON5 2.2.2 / versionCode 1 首次运行通过；升级前在应用私有配置写入 `userValue=keep-me`，并在旧包目录放入陈旧文件；安装 JSON5 2.2.3 / versionCode 2 后，新 Service generation 加载 2.2.3，配置用户字段保留、配置版本更新为 2.2.3、陈旧包文件移除，`files/` 根目录文件集合不变。脚本为 `nodeprobe/verify_a4_upgrade.py`。
- `json5` bin `lib/cli.js` 由 Node 入口函数调用，`--version` 与 `--help` 两组参数均正确；`--version` 输出 `2.2.3\n`，`--help` 包含 Usage，stderr 为空，退出码 0。限制参数来自固定 allowlist。
- 错误路径也在真机验收：给 JSON5 bin 一个固定的非法 JSON5 文件，stdout 为空，stderr 为 `JSON5: invalid character '}' at 1:12\n`，`process.exit(1)` 请求和 Node 返回码均为 1。探针暂时拦截 `process.exit` 以收集输出，再将捕获到的返回码写入结果。
- 并发与取消：首个 `--version` 运行期间立即提交第二个 bin 请求，Service 返回 `Node instance already started`（busy），首个请求随后成功完成，未并行启动第二个 Node 实例。取消样本通过 `--validate` 解析应用私有目录里的 4 MiB JSON5 文件；Activity 收到 Node `ready` 事件后发取消，日志观察到 `cancelRequested` 与 Service 断开，未返回终态结果；重新启动后新 generation 的 `--version` 成功。当前取消实现是杀掉隔离的 Node Service 进程，不是 bin 内部的协作式取消。
- 曾用 32 MiB 输入尝试压测；观察到 Service 断开且没有终态结果，原因未确认，因此不计入通过项。最终并发项使用两个同时提交的 `--version` 请求，取消项使用上述 4 MiB 输入。
- A3 固定探针的进程崩溃、整 App 重启、重装和后台 `am kill` 后恢复回归通过。普通 Flutter Debug APK 构建并安装成功，包内无 `libnode.so`、JNI 探针或 A4 包资源。
- **状态**：A4.1 与 A4.2 的 JSON5 样本在上述 4 KB Debug 真机范围内通过，包含实际 APK 包版本升级、文件树清理、配置保留、bundle 对照、成功/非零退出、输出采集、并发拒绝及进程级取消/恢复。该结果不代表设备端 `npm install`、任意 CLI、其他包或产品适配器已经通过。

## `@music163/ncm-cli` 0.1.7 静态包审查

- npm registry 当前 latest 仍为 0.1.7，要求 Node >=18，bin 为 `dist/index.js`；直接包 1,299,976 字节、解包 3,164,804 字节，仅 4 个文件，未捆绑依赖。运行依赖包括 `@clack/prompts`、`commander`、`fluent-ffmpeg`、`ffprobe-static`、`qrcode-terminal` 等。
- npm README 将本地播放的 mpv 列为系统要求；`fluent-ffmpeg` 2.1.3 的 `lib/processor.js` 调用 `child_process.spawn`。`ffprobe-static` 3.1.0 的 tarball 为 121,756,431 字节、解包 351,499,535 字节；其 `index.js` 只接受 darwin/linux/win32 并按平台/架构拼接二进制路径，tarball 仅含 macOS arm64/x64、Linux ia32/x64、Windows ia32/x64 二进制，没有 Android 或 Linux arm64 目录。由包清单推断，当前依赖链不能直接构成手机本地播放器；Android 上 `os.platform()` 的实际值和安装/调用失败阶段仍须在真机确认。
- 上述内容最初是包清单/README/依赖源码静态审查；随后已增加下方独立 Debug 真机样本。静态结果本身不代表登录、搜索、播放或出声通过。
- 2026-11-13 重新核对 npm registry 并下载 `@music163/ncm-cli@0.1.7` 发布 tarball：SHA-512 与 registry integrity `sha512-2J1FKl8BxdNDjC9aAJ8WiTypWsfhyKUcS7UErYbNDNOhqD7eXCyGSOfUeMZYWhHy+CcxNllNFDhdFLqq5zS3tw==` 一致；解包仍为 4 个文件，tarball 约 1.3 MB、解包约 3.2 MB，入口 `dist/index.js` 约 1.99 MB、TUI bundle 约 1.17 MB，两个 JS 文件 `node --check` 通过。package 声明 Node >=18、14 个直接运行依赖、没有 `preinstall`/`install`/`postinstall` 生命周期脚本；依赖版本使用范围而非 lockfile，设备样本需固定解析后的 lockfile 并禁用安装脚本。
- 同日 registry 元数据确认 `ffprobe-static@3.1.0` 为 11 个文件、解包 351,499,535 字节，integrity 为 `sha512-Dvpa9uhVMOYivhHKWLGDoa512J751qN1WZAIO+Xw4L/mrUSPxS4DApzSUDbCFE/LUq2+xYnznEahTd63AqBSpA==`。测试安装会涉及约 122 MB 压缩包及约 351 MB 解包内容；连接真机后先检查应用私有存储余量，再运行固定 npm 安装样本。
- 来源：[npm 上的 `@music163/ncm-cli@0.1.7`](https://www.npmjs.com/package/@music163/ncm-cli/v/0.1.7)、[npm 上的 `ffprobe-static@3.1.0`](https://www.npmjs.com/package/ffprobe-static/v/3.1.0)。

## A4.6 `ncm-cli` Debug 真机样本（2026-11-13）

- 设备：LGE AN10 / Android 15 / API 35 / arm64-v8a / 4096-byte pages；Debug 独立 `nodeprobe`，内嵌 Node v24.22.1（`process.versions.mobile=24.22.1-0`），npm 12.2.2。未启动模拟器。
- 真实发布包 `@music163/ncm-cli@0.1.7` 的 registry SHA-512 与元数据相同。测试使用 lockfile v3（75 个包记录，SHA-256 `64b01d9e8f90ea92086d4e8950e891a630b85922528b50224d5c2522e2296f7a`）、`npm ci --ignore-scripts` 和应用私有缓存；首次安装在真机完成，74 个依赖包写入私有目录，node_modules 约 385 MB，npm cache 约 128 MB。固定包完整性、已安装版本和 CLI 文件存在均由设备内摘要/清单确认。后续重复 `npm ci` 的一轮虽写完包文件，但 npm 日志停在 `silly ADD`、Node 未发终态事件；因此重复安装/Node 退出的稳定性不算通过。该样本不执行 npm 生命周期脚本，也不验证 Play 分发资格。
- 固定 CLI 动作均通过 Binder/Messenger 返回终态；结果如下：

| 操作 | 真机观察 | 结论 |
| --- | --- | --- |
| `ncm-cli --version` | stdout 为 `0.1.7`，退出码 0；平台为 `android` | 入口能运行和返回结果 |
| `ncm-cli --help` | 帮助文本有输出，但同时报告 API key 未设置和 `Unsupported platform`，退出码 1 | 初始化阶段已有配置/平台阻断 |
| `ncm-cli configure` | 提示配置向导需要交互式 TTY；本桥接 `stdin/stdout` 均非 TTY；另报告 `Unsupported platform` | 不能在当前 Node Service 直接走交互式配置 |
| `ncm-cli login --help` | 帮助文本有输出，因 API key/平台检查退出码 1 | 只验证帮助，不执行登录；未输入或记录用户凭证 |
| README 示例 `search song --keyword 林俊杰` | `unknown command 'search'`，退出码 1 | README 命令和发布包实际注册命令不一致，未发生搜索请求 |
| `ncm-cli tui` | 报告 mpv 未安装，退出码 1 | TUI/本机播放器无法启动 |

- 依赖定位：Android 下 CLI 输出 `Unsupported platform`；结合 `ffprobe-static@3.1.0` 的平台白名单（不含 Android/arm64）判断，它是当前音频依赖链的确定性兼容阻断。`fluent-ffmpeg` 仍需调用 `child_process.spawn`，而前述 A4.5 已发现 Node Service 不能可靠启动应用私有 Node 子进程；此项是依赖边界证据，不是本轮单独调用 ffmpeg 的结果。TUI 明确因缺少 mpv 退出。由于平台检查、API key 和播放器三项前置条件未满足，本轮不执行实际登录、播放控制、音频请求或出声测试，也不保存任何账号/App 密钥。
- **阶段结论：A4.6 部分真机验收完成，整体未通过。** 单台 4 KB arm64 真机证明 npm 安装后可以启动并调用此包的版本/帮助入口；当前包无法在 Android 上完成可用的配置、搜索和本地播放链路。真实登录、搜索、播放控制、声音仍未验收；不应把此 npm 包列为 Android 本地能力。A4.7 需依据该边界形成 T1/T2/T3 的本地/Host/不支持决策。A3.6 的稳定维护库与真实 16 KB 设备门槛仍未完成。
- 复现入口：`app/android/nodeprobe/prepare_a4_ncm.sh`、`app/android/nodeprobe/verify_a4_ncm.py`。从 `app/android/` 运行 `./gradlew :nodeprobe:assembleDebug --offline -Pa3Probe=true`，再运行 `nodeprobe/prepare_a4_ncm.sh` 和 `python3 nodeprobe/verify_a4_ncm.py`。验证器只对固定 action 开放运行；成功后卸载独立 Debug 探针。应用不使用或归档用户登录凭证。

## A4.4 分发与安全规则（2026-11-12 查阅）

- Android 安全文档建议尽量避免从 APK 外加载代码；动态加载代码会以宿主 App 权限运行。应用私有目录和完整性校验可以降低篡改风险，但不会缩小 Node 脚本可获得的宿主权限。
- Google Play Device and Network Abuse 规则限制从 Play 以外下载 dex/JAR/`.so`，同时对解释型语言运行时脚本列出条件性例外：这些脚本不能使应用违反 Play 政策。该文字不等于远程 JS 一概禁止，也不意味着任何内嵌 Node/npm 安装器自动符合政策；Node 能调用文件、网络、子进程和原生扩展，具体包能力与产品用途需按发行渠道审查。
- 当前建议：A4 先验证随 APK 打包、版本固定、摘要可复现的纯 JS 包；运行时 npm install 保持未决，直至确定发行渠道、包来源/签名/摘要、安装脚本策略、缓存清理/回滚、权限隔离及 Play 审查结论。未进行 Play 预审或法律判断。
- 来源：[Android 动态代码加载安全指南](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)、[Google Play Device and Network Abuse 政策](https://support.google.com/googleplay/android-developer/answer/16559646)。

## A4.4 Debug 真机实验（2026-11-12）

- 复现入口为 `nodeprobe/prepare_a4_npm.sh`、`nodeprobe/verify_a4_npm.py`；固定 npm 12.2.2 tarball SHA-512，并在 LGE AN10 Android 15/API 35、arm64、4 KB 页运行 Node v24.22.1。Debug APK 约 102 MB；不代表 16 KB 页、其他 ABI 或发布包。
- `npm --version`、Registry 安装 `supports-color@7.2.0`（含 `has-flag@4.0.0`）、lockfile SHA-512/registry URL、包加载、离线缓存重装、错误 integrity 拒绝、`json5` 2.2.2→2.2.3 升级/卸载和 `npm cache verify` 均有真机通过结果。
- `--ignore-scripts` 安装完成但不产生 fixture marker；默认 npm 12.2.2 也把脚本列为未授权并阻止执行。对固定本地 tarball 按精确 `file:` 来源授权后，npm 确实尝试 `sh -c node install.js`，返回 127，marker 未生成。该失败与 nodejs-mobile 不支持 `child_process` 的文档限制一致；实际 127 的底层子进程路径仍未隔离确认。
- 整轮 11 个 npm 操作均能写出 app-private JSON 结果。首轮验证器把 `npmResult` 到达后立即读取 Logcat，`0/11` 终态统计有时序竞争，不计为有效结果；修正为等待最多 3 秒后，下一轮日志确认普通 registry 安装和离线安装都收到 Messenger `kind=3`。清除 app-private npm CLI 目录后再次运行 `npm --version`，资源重拷贝与终态 Messenger 结果也通过。另一轮在本地 tarball 的 `script-ignored` 阶段 Service 断开，单独运行精确授权的 `script-allowed` 也写出 npm 127 结果后触发 Android tagged-pointer fatal；根因未确认。当前证据指向本地生命周期脚本样本附近的不稳定，不能泛化为全部 npm 操作都没有 Messenger 终态。
- **验收结论：**A4.4 的 Debug 可行性样本完成，证明受限纯 JS 安装路径在单台 4 KB arm64 设备可工作，也明确暴露脚本执行和本地 tarball 样本附近的 Service 稳定性缺口。手机端 npm 与任意 CLI 不进入产品能力；后续产品白名单/Host/不支持决策留在 A4.7。未覆盖 Play 预审、16 KB 真机、其他 ABI、缓存配额/清理策略或长期稳定性。

## A4.5 nodejs-mobile API 文档与真机边界（2026-11-12）

- LGE AN10、Android 15/API 35、arm64、4 KB 页上的 8 个固定 Debug 样本全部完成，Node v24.22.1 / `process.versions.mobile=24.22.1-0`；每项均写出结果并收到 Messenger `kind=3` 终态。探针结束后卸载。该结果不覆盖其他设备、ABI、Node 构建或 16 KB 页。
- `node:child_process` 与 `child_process` 均可导入，`spawn`/`fork` 均为函数；`spawn('/system/bin/sh', ['-c', 'exit 0'])` 正常退出 0。`spawn(process.execPath, [应用私有目录中的 JS])` 和 `fork(私有 JS)` 都创建了子进程，但子进程以 `SIGABRT` 结束；Android crash buffer 记录 `app_process64` 的 abort message 为 `Error changing dalvik-cache ownership : Permission denied`。这不是“所有 spawn 都不可用”，也不证明任意系统命令或工具链可运行。
- 当前 nodejs-mobile API 差异文档仍将 `child_process`/`cluster` 标为不支持，并指出 Android 的 stdin 需要宿主原生管道。与本机样本存在差异，需保留文档声明和当前构建实测，不能推广到其他构建。实测 `process.stdin` 对象存在且 readable，但 350 ms 观察窗口收到 0 字节，桥接没有把 MCP initialize 写入 fd 0；stdin/stdout 均非 TTY，`setRawMode` 不存在，交互式 TUI 条件不满足。`cwd` 为 `/`，`PATH` 仅为系统目录。
- `ffmpeg`、`ffprobe`、`mpv` 在 `PATH` 及固定系统目录均未找到，因此本轮未启动这些程序。此前静态审查指出 `ncm-cli` 需要 `mpv`，`fluent-ffmpeg` 使用 `child_process.spawn`；A4.6 仍须单独验证 CLI 安装/启动和依赖在哪一步失败，不能用本轮缺少系统二进制代替 CLI 运行结果。
- 用 NDK r28c、arm64/API 24、Node-API 8 头文件编译的自有最小 `.node` 样本，显式链接 `libnode.so` 后在应用私有目录成功加载，导出函数返回 N-API 10。此前不带 `libnode.so` 动态依赖时加载报 `ERR_DLOPEN_FAILED` / `cannot locate symbol napi_create_function`。这只证明该 ABI/Node 构建/最小 N-API 样本的加载路径成立；不代表第三方扩展、V8/C++ addon 或通用 npm 原生依赖可用。
- 复现入口：`app/android/nodeprobe/prepare_a4_boundary_addon.sh`、`app/android/nodeprobe/verify_a4_boundary.py`；在 `app/android/` 运行 `./gradlew :nodeprobe:assembleDebug --offline -Pa3Probe=true` 后执行 `python3 nodeprobe/verify_a4_boundary.py`。生成的 `.node` 是忽略的临时 APK 资源。
- 来源：[nodejs-mobile 移动端 API 差异](https://nodejs-mobile.github.io/docs/api/differences/)、[nodejs-mobile FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)、[fogtape Node 24 移动版 README](https://github.com/fogtape/nodejs-mobile/blob/recipe/README.md)、[Android 10 执行权限行为变化](https://developer.android.com/about/versions/10/behavior-changes-10)。

复现：在 `app/android/` 运行 `nodeprobe/prepare.sh`、`nodeprobe/prepare_a4.sh [/path/to/json5-2.2.3.tgz]`、`./gradlew :nodeprobe:assembleDebug --offline -Pa3Probe=true` 和 `python3 nodeprobe/verify_a4.py`；两个版本 APK 升级验收可运行 `python3 nodeprobe/verify_a4_upgrade.py`。A4.3 profile 生命周期可运行 `python3 nodeprobe/verify_a4_profiles.py`。脚本使用当前连接真机，不启动模拟器，实验结束卸载独立探针 App。

CLI runner 的手动入口为 `adb shell am start -n io.github.guog962464.aggregate.nodeprobe/.ProbeActivity --es probe a4-json5-cli --es cliArgsJson '["--version"]'`；将 `--version` 换成 `--help` 可选另一个固定样本。

## 下一步

1. A4.3 的 profile 契约和隔离 Debug 生命周期验收已通过；结果与限制记录在 [A4.3 内置包入口契约](android-a4-bundled-package-contract.md)。产品连接器仍不开放此探针。
2. A4.4 受限 Debug npm 实验、A4.5 固定 API 边界样本已完成；A4.6 已在 LGE AN10 Android 15/API 35、arm64、4 KB 页运行固定包和 CLI 样本，但配置 TTY、Android 平台依赖、README 搜索命令差异和 mpv 阻断了业务链路，真实账号/搜索/播放/声音未验证。A4.7 的本地/Host/不支持决策已记录于 [ADR 0003](decisions/0003-android-local-execution.md)。A4.4/A4.5/A4.6 的失败、设备范围和文档差异不得反向打开用户可见适配器。后续产品门槛为 A3.6 维护版运行时与真实 16 KB 页设备，以及 A5/A6 Host 交付。
