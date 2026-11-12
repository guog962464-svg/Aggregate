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
