# Android A8 发布前检查与文档验收

> 检查日期：2026-11-26（安全复扫与 WSS 分片边界复验；最近 Release 复验见下文 9b7c310）。Android 与 Mac Host 现共用 WSS 帧前置检查器：每条消息必须是未压缩、未分片、至多 1 MiB 的单数据帧；在交给 Dart `WebSocket` 解码器前检查，避免其分片累积绕过单帧上限。针对 Android 客户端和 Mac Host 服务端均有原始帧回归测试；完整 Dart 分析、定向测试与 Android Debug 构建通过。Android 仍未达到分发验收：缺少正式签名身份、16 KB 页真机及生产 Host/音乐闭环。Android 仍是实验目标，仓库当前产品发布目标为 macOS。

## A8.4 安全、依赖与分发检查

### 检查范围与方法

此前 Codex Security Standard 扫描目标修订为 `a5dde7507e268c7079b1eea63058636bbe4ed665`，覆盖 Android/Flutter Runtime、配对 Mac Host、Node/npm 探针、密钥/日志、构建与分发配置。该工作台扫描 ID `be3aab55-1467-4e8c-b571-0a56f577389d` 最终标记为 failed，不能作为无漏洞结论。本轮工作树差异审查 ID `96cfdbea-0984-4bc6-8ea5-0e45608ad884` 已完成：审阅 92 项源文件 inventory，0 项可报告漏洞；覆盖状态为 partial。原报告保留外部 HTTPS 当前版本复验、MCP 并发/超时取消语义、Host 账本恢复三个后续问题；其中当前 Android HTTP MCP 代码的外部 HTTPS 用例已于 2026-11-20 在真机单独复验，原扫描本身仍不包含该证据。扫描快照之后，本轮增加了 Android 全局 POST 并发上限和协议级请求 deadline/HTTP abort 回归测试，并补充 Host 账本人工恢复流程；这些后续材料不属于原报告覆盖。扫描针对 base `bd8034286ac168c596def1f09ab3960ce01d4e0e` 的冻结工作树快照，不是全仓库审计，也不能替代 16 KB 设备或生产服务验收。没有正式签名的 Android Release，也没有 16 KB 页实体设备。

### 运行时、npm 与许可证

- 主 Android App 的 Release 不包含 NodeBridge；NodeBridge 通过 `debugImplementation` 和探针开关接入 Debug。固定入口、样本包、独立 NodeProbe 与主 App 的任意 npm/CLI 能力要分别看待。
- 本地生成的 Node 探针运行时为 fogtape `nodejs-mobile` fork `24.22.1-0`，Node 版本显示 `v24.22.1`；随包 npm 为 `12.2.2`，SHA-512 integrity 固定。`@music163/ncm-cli` 样本为 `0.1.7`，锁文件 SHA-256 为 `64b01d9e8f90ea92086d4e8950e891a630b85922528b50224d5c2522e2296f7a`。这些是本地忽略的 Debug 实验资产，不是 Android 产品 Release 依赖。
- 官方 Node 24 安全版本 `24.22.3` 于 2026-11-11 发布；探针低两个补丁版本并且是预发布 fork，不能晋升为产品运行时。上游 `nodejs-mobile` 最新 Android core 仍基于 Node 18.20.4；Node 18 已于 2025-03-27 EOL。升级/迁移前需重新验证稳定维护、Android ABI/页对齐、Node/npm 兼容性、许可证和漏洞响应。
- 在固定 `a4-ncm` Debug 样本锁文件上执行 `npm audit --package-lock-only --json`，结果为 8 条 advisory：2 critical、5 high、1 moderate。受影响依赖树含 `@music163/ncm-cli@0.1.7`、`image-size`、`js-yaml`、`timespan`、`uglify-js`、`zod` 等；锁文件有 74 个依赖，其中 11 个缺少 license 元数据。该锁文件属于实验 fixture，不能据此声称主 Android Release 含这些 npm 包；也不能在未完成上游修复、重新审计和许可证核实前把样本推广为发布能力。
- `prepare.sh` 对 Node 归档、Node License 和 NDK LLVM NOTICE 做 SHA-256 校验，并复制 license/notice；npm CLI 元数据标为 `Artistic-2.0`。本机 NDK 提供的 `libc++_shared.so` 没有独立的仓库校验值。发布前仍需输出完整 SBOM/许可证清单，并固定、审计所有实际随包二进制及依赖。

### 动态代码分发

当前产品路线只开放随 App 构建的受控代码；设备端任意 npm 安装、执行用户下载的 npm 包、通用本地 CLI/TUI/stdio MCP 均未承诺。固定 JS/npm 测试仅在独立 Debug 探针中使用。Google Play 的动态代码规则对 Dex/JAR/`.so` 与解释执行代码有不同条款；解释器能力本身并不豁免其他 Play 政策。Android 官方还建议只从可信来源加载动态代码并限制其存储和完整性风险。Android 发布前必须按选择的渠道复核当时规则，不把 Debug 探针用作 Play 发布依据。

- [Google Play Device and Network Abuse policy](https://support.google.com/googleplay/android-developer/answer/18265346)
- [Android Dynamic Code Loading security guidance](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)
- [Android security best practices](https://developer.android.com/privacy-and-security/security-best-practices)

### APK/AAB 体积、签名与页大小

| 工件 | 大小 | 签名/用途 |
| --- | ---: | --- |
| 主 App Debug APK：`app/build/app/outputs/flutter-apk/app-debug.apk` | 124,368,287 bytes | arm64 本轮构建，`apksigner` 验证通过，使用 Android Debug 证书；仅内部测试 |
| 独立 NodeProbe Debug APK：`app/build/nodeprobe/outputs/apk/debug/nodeprobe-debug.apk` | 290,622,972 bytes | Android Debug 证书；包含实验运行时，不是主 App 产品包 |
| 独立 NodeProbe Debug AAB：`app/build/nodeprobe/outputs/bundle/debug/nodeprobe-debug.aab` | 39,012,187 bytes | Debug 探针 Bundle，不是发布 AAB |
| 主 App Release APK：`app/build/app/outputs/flutter-apk/app-release.apk` | 27,572,424 bytes | Release 构建成功；保持未签名，不能分发 |
| 主 App Release AAB：`app/build/app/outputs/bundle/release/app-release.aab` | 25,305,762 bytes | Bundletool 1.18.3 校验通过；保持未签名，不能上传商店 |

通过 `app/android/app/src/release/java/dev/flutter/plugins/integration_test/IntegrationTestPlugin.java` 为 Flutter 生成注册表中的 dev-only 项提供 Release 专用空实现；测试插件本身仍不进入 Release compile classpath。Release APK/AAB 均成功构建，`GeneratedPluginRegistrant` 注册该空实现，不包含测试通道方法。移除了 Release 使用 Debug 签名的配置；当前 APK/AAB 经 `apksigner`/`jarsigner` 核验为未签名。仓库没有正式发布密钥，因此不生成或宣称签名候选包已通过。[Android app signing](https://developer.android.com/studio/publish/app-signing)

A8.2 普通 arm64 APK 与固定 Node Debug 探针曾通过静态对齐检查。本轮主 App Release APK 和 AAB 各含 7 个 arm64 原生库；NDK 28.2.13676358 `llvm-readobj` 检查全部 `PT_LOAD` 均满足 16 KB 对齐，APK 的 Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过。LGE AN10 实机仍是 4 KB 页，没有 16 KB 页设备，不能声明 16 KB 系统运行通过。正式发行前须在 16 KB 环境做运行验收。[Android 16 KB page-size guidance](https://developer.android.com/guide/practices/page-sizes)

### 仍需处理的安全发现

以下发现来自此前源代码审查。本轮实现并复测对应缓解措施：

| ID | 原严重性 | 本轮处置与剩余边界 |
| --- | --- | --- |
| A8SEC-1 | 中 | **已缓解。** Android Runtime 拒绝所有非回环 `http://` MCP 地址（无论是否带 Token）；Android Network Security Config 全局禁用明文，仅对精确 `localhost` 与 `127.0.0.1` 开放。新建和旧存储配置均经过相同校验；错误配置会备份并拒绝加载。单测与 LGE AN10 实机验证远程 HTTP 拒绝、回环 HTTP 仍可用。 |
| A8SEC-2 | 中 | **攻击放大路径已修复，账本容量仍有限。** 已配对且获 `connectionSetup` 的设备对不存在/过期草稿执行 `setup.discard` 时直接返回幂等成功，不写持久 operation ledger；200 个不同 operation ID 回归测试确认不创建记录。新增临时文件单测将 `maxEntries` 设为 1，验证满额后新的真实 mutation 返回 `operationLedgerFull` 且不改写原账本；重开账本时未完成的旧记录仍变为 `outcomeUnknown`。生产默认仍受全 Host 共享的 10,000 条/4 MiB 硬上限约束。下方定义了人工恢复步骤；操作流程尚未在生产 Host 演练，没有自动压缩或管理员恢复 UI。 |
| A8SEC-3 | 低 | **已缓解并覆盖边界测试。** Android MCP HTTP transport 在 JSON/SSE 解码前限制每个响应 8 MiB、取消超限流并拒绝重定向；跨所有 Android 会话的并发 POST 上限为 16，超额请求在发送前失败。MCP operation/discovery 使用协议级 deadline；超时时触发请求 abort 并关闭该会话，调用仍记录为结果未知，不自动重放。发现层限制每类最多 20 页、总能力 1,000 个、目录总量 4 MiB、schema 256 KiB、字段 16 KiB、cursor 4 KiB、提示参数 64 个。自动化测试覆盖 1,001 个工具目录拒绝、跨客户端并发上限、deadline 后 AbortableRequest 中止；既有 LGE AN10 真机曾验证 8 MiB+1 响应在解码前被拒绝。 |

#### Host operation ledger 达到容量后的人工恢复

`operationLedgerFull` 会拒绝新的真实 mutation；当前没有自动回收或设置页重置按钮。为保留幂等防重放语义，不应在复用原 Host/配对身份的同时直接删除账本。若实验 Host 触顶，按以下维护流程恢复；此流程需 Host 管理员手动执行，尚未做生产演练：

1. 停止 Mac Host 并备份 Host 状态目录和 `operations.json`，将副本放在活动 Host 目录之外并限制访问。
2. 检查账本中的 `started` / `outcomeUnknown` 记录。逐项通过对应服务确认实际结果；仍无法确认的操作保持未解决，不清空账本或重放 mutation。
3. 在 Mac Host 设置中撤销所有已配对设备。对每个客户端轮换本机配对密钥，使其重新配对时生成新的 `deviceId`；Android 需要清理应用数据并重新配置连接/凭证。未能轮换密钥或确认撤权时，不继续维护操作。
4. 将旧 `operations.json` 归档到 Host 活动目录之外，再启动 Host。仅批准新密钥身份，核对新 `deviceId` 后恢复 mutation。不要复用旧设备密钥、旧配对会话或任何未解决操作 ID。
5. 保留旧账本备份和维护记录；若无法确认每台旧设备已撤权或轮换，保持 Host 停止并升级人工处理，不要手工改写账本内容。

这只是容量触顶后的人工恢复方案，不提供无损在线压缩，也不代表已测试的产品 UI。Host ledger 文件在重启时会把残留 `started` 记录标为 `outcomeUnknown`，仍需逐项解决。

A8SEC-1 与 A8SEC-3 的对应风险路径已封闭到上述范围；A8SEC-2 的不存在草稿放大方式已移除，Host 全局账本仍保留有限容量。其它经核对不作为本次漏洞报告：Host stdio 启动受已授权 `connectionSetup` 权限约束；Host 内容读取受配对和逐连接授权约束；npm audit 命中的是独立 Debug fixture；Release 签名身份、16 KB 实机及真实服务闭环仍未完成。

差异审查对 HTTP 响应包装流中的错误完成行为曾记录一个候选：如果下游收到错误但继续监听，原实现不会发出结束事件。逐条检查 `mcp_dart` JSON/SSE 消费路径后确认产品当前消费者会在错误后终止或取消订阅，因此该候选不构成可达安全漏洞。审查快照之后，修正了包装层的 Stream 语义并新增错误/数据/`onDone` 回归；也增加跨 Android 会话的并发 POST 上限，以及 MCP protocol deadline、AbortableRequest 中止和超时会话关闭测试。这些后续变更不属于原扫描快照。

旧 Codex Security 扫描 ID `be3aab55-1467-4e8c-b571-0a56f577389d` 最终为 failed，其 0 findings 不能作为无风险结论。本轮差异扫描 ID `96cfdbea-0984-4bc6-8ea5-0e45608ad884` 已正常完成并生成报告；报告路径见工作区外的 Codex Security scan artifacts。该扫描没有验证 16 KB 设备行为；外部 HTTPS 实机闭环由 2026-11-20 的独立测试补验，详见本记录末尾。

### 官方核验来源

- [Node.js v24.22.3 Security Release](https://nodejs.org/en/blog/release/v24.22.3/)
- [Node.js EOL schedule](https://nodejs.org/en/about/eol)
- [nodejs-mobile releases](https://github.com/nodejs-mobile/nodejs-mobile/releases)
- [Node.js Android build support](https://github.com/nodejs/node/blob/main/BUILDING.md)
- [npm audit documentation](https://docs.npmjs.com/cli/v11/commands/npm-audit/)

## A8.5 Android 用户与故障文档

- 新增 [Android 内部测试指南](android-user-guide.md)，说明只安装 Debug APK、HTTP MCP/Host/音乐的运行位置、配对与最小权限、实际音频输出位置及能力边界。
- 更新[跨平台故障排查](troubleshooting.md#android-内部测试)，加入 Host、HTTPS/Token、任意 CLI/npm、Node 探针、音乐出声和运行结果待确认的处理步骤。
- macOS [用户指南](user-guide.md)仍对应当前产品版本；其中明确 Android 文档仅供内部实验使用。
- A7/A8.1–A8.3 已记录 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机的安装、运行、HTTP MCP、配对、UI/IME、生命周期及存储验证。Android HTTP MCP Integration Test 文件于 2026-11-20 在真机运行 5 项全部通过，其中外部 HTTPS 用例使用公开只读的 [Bommel Bot Agent Gateway](https://bommel.bot/agents)，无账号或 Token。没有 16 KB 真机、生产 Host LAN/Bonjour、实际音乐账号或签名 Release；无障碍/TalkBack 专项测试按用户决定不纳入范围。

## 本轮验证

- Flutter 全量测试：211 项通过，包含 HTTP 包装流错误后继续传递数据和 `onDone`、跨会话并发上限、timeout 后请求 abort 的回归用例。
- `flutter analyze --no-pub`：无问题。
- Dart format、公共层边界检查、15 项共享包测试：通过。
- Android arm64 Debug APK、Release APK/AAB 与 macOS Debug 构建：通过；macOS 构建有 `mobile_scanner` 使用 macOS 10.15 弃用 API 的既有编译警告。
- Bundletool 1.18.3 `validate`、APK `zipalign -P 16`、Release APK/AAB 内 7 个 arm64 原生库的 16 KB ELF `PT_LOAD` 检查：通过。Release 工件未签名；无正式签名身份。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机：既有 HTTP MCP 集成文件 4 项通过，外部 HTTPS 用例当时因未设置环境变量跳过。2026-11-20 改用隔离 `.integration` 包重跑后，5 项（含外部 HTTPS）全部通过；普通 Aggregate 包未被测试 runner 触碰，临时隔离包已卸载。历史上的主包移除/Keystore 数据丢失记录仍保留为早期非隔离运行的风险依据；本次未使用模拟器。
- HTTP 包装流修正发生在差异扫描快照封存之后；本地测试覆盖了修正，但扫描报告不包含该后续变更。
- 用户已有 root `pubspec.lock` 镜像 URL 改动保持未暂存；任务只提交 MCP path override 对应 lock hunk。

## 2026-11-14 主 App Release 干净构建补验

在精确提交 `82b49e42144b4c026456b265695da90e5a555349` 的隔离 worktree 中，初次标准 `flutter build apk --release --no-pub` 因根级任务图同时构建独立 NodeProbe/NodeBridge 而要求忽略的 `libnode.so`，在未准备探针时失败。现把这两个实验模块改为只有显式 `a3Probe=true` 才加入 Gradle 项目图，并更新探针重建/升级说明。修正后标准 Flutter Android Debug APK、Release APK 与 Release AAB 命令均成功；默认项目图没有 NodeProbe，显式 `-Pa3Probe=true` 或 `ORG_GRADLE_PROJECT_a3Probe=true` 时仍包括探针模块。

此 HEAD 的主 App Release APK SHA-256 为 `ed8d595e60593e593c1e1f628a638d681bf5fc2a34d80382786927d4fca1db5c`，大小 27,575,804 bytes；AAB SHA-256 为 `b066e65f77c1b217b45d051731c3dc593df8fe68f99423a0ce15d50b838e6765`，大小 25,362,693 bytes。两种包各含 7 个 arm64 native libraries，不含 `libnode.so`、NodeBridge、npm `node_modules` 或 nodejs-mobile 声明。Build Tools 36.0.0 的 APK `zipalign -c -P 16 4`、每个 ELF 的 `PT_LOAD p_align >= 0x4000` 与 offset/virtual-address congruence 检查、Bundletool 1.18.3 AAB `validate` 和 `PAGE_ALIGNMENT_16K` 配置检查均通过。APK 与 AAB 仍未签名；本检查是 Node-free 主 App 的静态构建证据，不是 Node 候选发行 SBOM、正式签名或 16 KB 真机运行验收。完整哈希和范围见 [A3.6 运行时研究](android-a3-runtime-research.md#2026-11-14-aggregate-release-干净构建与原生库复核)。

## 2026-11-17 当前主线 Release 构建复验

基于当前主线提交 `ea23879034fa8c7bd2a81ff45a98c966f818f152` 重新执行：

- `flutter build apk --release --no-pub --target-platform android-arm64`：通过。APK 27,708,052 bytes，SHA-256 `cf9a0e881594b6d148780bcf7362326271cd1e935e7101612be541b6c33c51bb`。
- `flutter build appbundle --release --no-pub --target-platform android-arm64`：通过。AAB 25,466,264 bytes，SHA-256 `47a476c841492d6c32c87b032a577de6c598d253a10da6afe4843df3b1ad043a`。
- APK `aapt dump badging` 只列出 `arm64-v8a`，versionCode 8、versionName 0.3.7；APK 包含 7 个 arm64 ELF，AAB 也只含 arm64 的这 7 个 ELF。每个 ELF 的所有 `PT_LOAD p_align` 均不小于 `0x4000`；Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。
- Bundletool 1.18.3 `validate` 通过，`dump config` 报告 `PAGE_ALIGNMENT_16K`。`apksigner` 与 `jarsigner` 均确认产物未签名；APK/AAB 均不含 NodeProbe、NodeBridge、`libnode.so` 或 npm `node_modules`。
- 本次只构建并静态检查，没有安装或运行产物。当前 ADB 设备列表为空；这不替代 16 KB 系统实机、正式签名或生产 Host/音乐链路验收。
- 4 KB 真机覆盖新鲜度（2026-11-18 复核）：`aecbd0c` 是 A5.5 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 业务集成验收对应提交。核对 `aecbd0c..c2bb4b0` 后，`app/android` 与 `app/lib/platform/android` 无变化；共享 Flutter App shell、主题、玻璃按钮/页面框架、主题切换及 Android Host 测试/runner 有后续改动。因此旧实机结果仍是有效的历史证据，但不覆盖当前共享 UI 或最新 E2E runner。当前 316 项 Flutter 测试与 analyze 通过，Android Release APK/AAB 已重建；ADB 列表为空，当前代码未重跑 4 KB 实机 E2E，也未安装本轮 Release 工件。

## 2026-11-18 当前主线 Release 与主题对比回归

在 `34d9c9ebc6be2d269e6bd271de4d8b93597161ab` 基础上，修复 macOS 玻璃背景文本对比调整覆盖 `ColorScheme.onSurface/onSurfaceVariant` 的问题。移动背景采样可把颜色设为黑或白，而 Material surface 仍可能处于主题插值的中间值；实测 `onSurface` 与当前 surface 对比度降到 `3.289:1`。现在背景上的动态正文、AppBar、图标和列表文本仍按背景更新，surface 语义色则保留经 surface 对比修正的值。设计令牌测试分别验证背景文本随动以及三个 Material surfaces 上语义色达到 4.5:1。此变更修复共享 Flutter/macOS 主题层，不改 Android Runtime 或原生桥接。

- 全量 `flutter test --no-pub --reporter compact`：316 项通过；`flutter analyze --no-pub`：无问题。主题切换、surface 对比和动态玻璃文字专项测试通过。
- `flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK 为 27,708,052 bytes，SHA-256 `7ec10656e50f27869dcbd5f384015aa4296d16cd0cea9db7631a3e82b7193273`；AAB 为 25,481,449 bytes，SHA-256 `3b8769328aac58e3563c45fac2d852885f1219b4a098fddaa8952668cc712aae`。`aapt dump badging` 确认 versionCode 8、versionName 0.3.7、仅 `arm64-v8a`。
- Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；APK 与 AAB 各含 7 个 arm64 ELF，每个 `PT_LOAD p_align >= 0x4000` 且 offset/virtual-address congruence 通过。Bundletool 1.18.3 `validate` 与 `PAGE_ALIGNMENT_16K` 配置通过。两种产物均未签名，且 archive entry 中未发现 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules`。
- 当前 ADB 设备列表为空；本轮只构建与静态检查，没有安装或运行新工件。静态对齐结果不替代 16 KB Android 系统实机验证；正式签名、16 KB 真机及 production Host/音乐链路仍未完成。

## 2026-11-18 Current-worktree Android Release rebuild and static checks

The build ran from HEAD `125161e6e649301cfb8a8b6dfb0ed5748dd7e7f3` plus the then-current uncommitted shared Flutter glass UI changes. Those UI and golden files were later committed as `d029ef3b99f052534dbca8720d4b22a0126422a9`; the root `pubspec.lock` change remains uncommitted. The build used `--no-pub`, and neither the lockfile nor UI files were staged in the Android acceptance commit below.

- `flutter test --no-pub --reporter compact`: all 316 tests passed. `flutter analyze --no-pub`: no issues.
- `flutter build apk --release --no-pub --target-platform android-arm64`: passed. APK: 27,779,264 bytes, SHA-256 `3d46271c2c32db9f52fadd22b33cd6737cddef95efc326ee6a341da65c825ec2`.
- `flutter build appbundle --release --no-pub`: passed. AAB: 25,521,790 bytes, SHA-256 `2fe1f90d5175730a1005e80c177be5754764d5db9db957d035437b2816e5858f`.
- Build Tools 36.0.0 `aapt dump badging` reports `io.github.guog962464.aggregate`, versionCode 8/versionName 0.3.7, arm64 only. APK `zipalign -c -P 16 4` passed. Bundletool 1.18.3 `validate` passed and `dump config` reports `PAGE_ALIGNMENT_16K`.
- Both APK and AAB contain the same seven arm64 native libraries. NDK 28.2.13676358 `llvm-readelf` verified every `PT_LOAD` has at least 16 KB alignment and congruent file/virtual offsets. APK/AAB signature entries are absent; `apksigner` reports the APK does not verify, and `jarsigner` reports the AAB is unsigned. Neither archive contains NodeBridge, `libnode.so`, NodeProbe or npm assets.
- The artifacts were not installed or run. The separate A5.5 runner installed only its isolated Debug package on the 4 KB device; this does not establish Release runtime or 16 KB runtime behavior. Formal signing, 16 KB hardware and production Host/music acceptance remain open.

## 2026-11-18 Isolated test-signed Release smoke on 4 KB hardware

At HEAD `f559d7b642b51c2d08135c2ed42144189060b45c`, a detached worktree temporarily added the `.integration` application ID suffix to the Release variant and selected the Android Debug signing config. The current worktree and product Gradle configuration were left unchanged. `flutter build apk --release --no-pub --target-platform android-arm64` passed; the APK is versionCode 8, targetSdk 36, arm64-v8a, and SHA-256 `aa28c7974d093dd1db268fab14529f498306670dd6ab911b98a434f1f2f0ce04`. Build Tools 36.0.0 `zipalign -c -P 16 4` passed; `apksigner verify` confirmed the APK v2 signature from the Android Debug test certificate (SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`).

On LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`, isolated installation succeeded and `am start -W` reported `Status: ok` and `Complete`; the app process remained alive with MainActivity resumed. No `FATAL EXCEPTION` appeared in the inspected recent logcat window; one ART profile-path SELinux read-denied warning was observed and not separately diagnosed. The isolated package was uninstalled, the ordinary app remained installed, ADB reverse was empty, Host port 47321 had no listener, and the detached worktree/build directory was removed. This is a 4 KB test-signed Release startup smoke only; it does not establish production signing, 16 KB runtime behavior, the full Release interaction/permission matrix, Node/npm qualification, or production Host/music acceptance.

## 2026-11-18 Current-main Release static checks and isolated launch recheck

The source baseline was HEAD `014111d6c3bbea4cf3bf00cfbc29b2c315a2044a`, which includes the committed shared Flutter glyph update `a7109e6`. From the current workspace, `flutter build apk --release --no-pub --target-platform android-arm64` and the matching `flutter build appbundle` both passed. The APK is 27,779,264 bytes (SHA-256 `481758cbdec3db6aebfe0980a0b717267044e616dda3d5324abef9a9cba9dd97`); the AAB is 25,528,924 bytes (SHA-256 `7db9f90926ad806fd9b352dcedca0f93bc670bb524a2559f342d7b71033097c4`). `aapt` reports package `io.github.guog962464.aggregate`, versionCode 8/versionName 0.3.7, arm64 only. Each archive contains the same seven AArch64 `.so` files. NDK 28.2.13676358 `llvm-readelf` checks all LOAD alignments/congruence and GNU_RELRO layouts; Build Tools 36.0.0 APK `zipalign -P 16`, Bundletool 1.18.3 `validate`, and AAB `PAGE_ALIGNMENT_16K` all pass. Neither package contains NodeProbe, NodeBridge, `libnode.so`, or npm assets. APK/AAB are unsigned product artifacts.

A detached worktree then built an isolated `.integration` Release APK using the Android Debug test certificate. `flutter pub get --offline --enforce-lockfile` did not succeed in that worktree; for this bounded launch check the existing workspace `.dart_tool` package configuration and Flutter plugin list were copied into the temporary worktree, and the build ran with `--no-pub`. The temporary worktree and all generated files were removed afterward; no tracked source or lockfile was modified.

On LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`, the test-signed APK installed successfully. `am start -W` returned `Status: ok` and `Complete` for `io.github.guog962464.aggregate.MainActivity`. After two seconds, `pidof` and `ps -A` showed no Aggregate process; `dumpsys activity` showed the isolated Activity had been destroyed and the previous foreground Activity resumed. The initial review checked the AndroidRuntime buffer but missed the native crash buffer, so its “no fatal signal” statement was incomplete. The historical launch was not accepted at that point; the later crash-buffer evidence and corrected cold-start result are recorded below.

The `.integration` package was force-stopped and uninstalled; the ordinary Aggregate package remained installed and ADB reverse was empty. This was an isolated test-signing check on a 4 KB device, not a production-signature or 16 KB runtime check. The 16 KB physical device, formal signing identity, and production Host/music workflow remain outstanding.

## 2026-11-18 Android Release startup SIGSEGV correction and recheck

This section corrects the incomplete crash assessment above. The crash buffer contains two native failures from the isolated Release process at `16:47:36` and `16:49:39` on 2026-11-18. Both are `SIGSEGV` / `SEGV_MAPERR` at address `0x0`; the abort message is `JNI is not initialized. Are you trying to invoke a Java API from Dart code too early...`. The first frames are `libdartjni.so` `FindClassUnchecked` and `FindClass`. The app startup path called `getApplicationSupportDirectory()` from `AndroidRuntimePort.open()` before `runApp`; `path_provider_android 2.3.1` implements that lookup through `jni`/`jni_flutter`. This establishes the failing JNI call path. The available trace does not establish why the JNI plugin's process context lacked a JavaVM.

The runtime now obtains Android's app support path over `aggregate/application_directory`. `AndroidApplicationDirectoryChannel` returns `Context.filesDir.absolutePath`; the Dart startup path no longer invokes `path_provider_android`'s JNI-backed implementation. The app storage location and persistence format are unchanged. The isolated Release cold-start runner is [run_android_release_cold_start.py](../app/tool/run_android_release_cold_start.py); it checks process survival, resumed `MainActivity`, and newly emitted crash-buffer lines, then uninstalls only the `.integration` package.

The updated product Release APK and AAB were built with `./gradlew --no-daemon --no-build-cache :app:assembleRelease :app:bundleRelease`. The arm64 APK is 28,262,312 bytes (SHA-256 `091838c61fcdc5322d1bee41bef352a3e4f65c700f26c3a00ed23f5ea20d37f5`); the AAB is 26,018,382 bytes (SHA-256 `b826640064fe584454de8a8028e9124d1f6a623479c1db5c24335d0477be7683`). `aapt` reports package `io.github.guog962464.aggregate`, versionCode 8/versionName 0.3.7. Both artifacts contain seven arm64 native libraries; all 21 `PT_LOAD` segments meet 16 KB alignment and offset/virtual-address congruence. APK `zipalign -c -P 16 4`, Bundletool 1.18.3 `validate`, and AAB `PAGE_ALIGNMENT_16K` checks pass. Both product artifacts are unsigned and contain no NodeProbe, NodeBridge, `libnode.so`, or npm assets.

For device verification, the isolated `.integration` Release APK was signed with the local Android Debug test certificate (certificate SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`; APK SHA-256 `12efe3492dec4d6e9aa8fbf0370beffd42858c0f5fae1b8fc2e661f4253ffcf4`). On LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`, `python3 app/tool/run_android_release_cold_start.py --device AEMN022427001360 --apk app/build/aggregate-isolated-release-smoke.apk` passed three consecutive cold starts. `am start -W` returned `Status: ok` each time; `MainActivity` remained resumed and the process remained alive (PIDs 11163, 13240, 13816; launch wait times 1590 ms, 1383 ms, 1183 ms). No new JNI crash was reported. Each run removed the isolated package; `io.github.guog962464.aggregate` remained installed.

The current-main 4 KB test-signed Release cold start is accepted for this device and build. Android distribution remains open because a 16 KB physical device, production signing identity, and production Host/music end-to-end evidence are still unavailable. The test certificate and this 4 KB smoke do not establish production signing or 16 KB runtime acceptance.

## 2026-11-19 当前主线 Release 重建与静态门禁

- **基线与构建：**当前 `HEAD=3e44b6bca051d124f1495b98c699b33f27acc149`。在 `app/` 分别运行 `flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64`，均通过。`aapt dump badging` 显示包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36；仅包含 arm64。
- **产物：**APK 27,713,728 bytes，SHA-256 `e89b25d45fba39793fd50ab13ff73a345901b94cc39b7c09302e81522eeaffe1`；AAB 25,471,282 bytes，SHA-256 `8b5d916025fdcc3278379c335b80cdaf675f420ccfd408109167333761c51c00`。两者均有 7 个 arm64 原生库，不含 NodeProbe、NodeBridge、`libnode.so` 或 npm `node_modules`。
- **静态检查：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，`dump config` 报告 `PAGE_ALIGNMENT_16K`。NDK 28.2.13676358 `llvm-readelf` 检查 APK 与 AAB 各 7 个库的全部 21 个 `PT_LOAD`，均为至少 16 KB 且文件偏移/虚拟地址对齐余数相符；`libapp.so` 与 `libflutter.so` 为 64 KB，其余库为 16 KB。
- **签名与设备：**Gradle 明确只为 `.integration` 配置 Debug test signer，产品 Release 在提供正式签名配置前保持 unsigned；本次 `apksigner verify` 失败并报告缺少签名，符合预期。ADB 设备列表为空，未安装或运行本次产物。正式签名、16 KB 物理设备运行及 production Host/音乐链路仍未验收。本次只验证构建和静态产物，不把 16 KB 静态对齐表述为 16 KB 系统运行通过。
- **代码范围：**Android/Dart 源码相对本任务此前 `1515583` 基线没有变化；完整 Flutter suite 328 项通过/analyze 无问题的证据仍按此前验收记录引用，本次没有重跑测试。


## 2026-11-20 当前主线 Debug 与 4 KB 真机复验

- **基线与构建：**`HEAD=dedcdaba191898ec3a00b42d21a7593307a2f22f`。在 `app/` 运行 `flutter build apk --debug --no-pub --target-platform android-arm64`，构建成功。APK SHA-256 `aa26411163d708633f200825b8f2a72e267a2b28d43f09fb09f1f5c136a66cfd`，大小 99,843,319 bytes。`aapt` 显示 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、targetSdk 36、arm64；APK 使用本机 Android Debug signer（SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`）。构建使用 `--no-pub`，没有重新解析依赖。
- **静态检查：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。NDK 28.2.13676358 `llvm-readelf` 检查包内 7 个 arm64 `.so` 的 21 个 `PT_LOAD`，全部满足 `p_align >= 0x4000` 且文件偏移/虚拟地址的 16 KB 余数相符；APK 不含 `libnode.so` 或 NodeProbe 资产。
- **代码验证：**`flutter test --no-pub test/android_host_pairing_client_test.dart test/android_host_settings_panel_test.dart` 的 13 项全部通过；`flutter analyze --no-pub` 无问题。未运行全量测试。
- **4 KB 真机：**LGE AN10 / Android 15 / API 35 / arm64，`PAGE_SIZE=4096`。在保留应用数据的情况下 `adb install -r` 成功；`am start -W` 返回 `Status: ok`、`LaunchState: COLD`、`Complete`，用时 3,016 ms；进程存活且 `MainActivity` 为 top-resumed。该进程最近 500 行 logcat 未见 `FATAL EXCEPTION`、`Fatal signal` 或 tombstone 标记。验收后发送 HOME，系统启动器恢复为前台，普通 Aggregate 包仍安装；没有启动 NodeProbe/testnode。
- **范围：**本节证明当前 Debug APK 在这台 4 KB 设备的安装/冷启动，以及包内原生库的 16 KB 静态对齐。没有运行产品 Release，也没有正式签名或 16 KB 系统设备；静态对齐不表示 16 KB 系统实机兼容。production Host 业务和音乐闭环仍未验收；TalkBack 专项测试不在当前验收范围。`pubspec.lock` 的工作区修改未暂存；构建未执行 pub 解析。ADB reverse 为空，Host 47321/47322 无监听。


## 2026-11-20 基线 02855aa Release APK/AAB 干净工作树复建

- **源码与依赖输入：**从 `02855aa49e0546eee8ae9ecbe6ae352e3e8b0f01` 创建独立 detached worktree；为满足该提交当前 pubspec 的约束，将主工作区未提交的 `pubspec.lock` 复制到临时 worktree，并以 `flutter pub get --enforce-lockfile` 校验成功。当前未提交的 Dart UI 文件未进入这次构建。
- **产物：**`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK 为 27,713,920 bytes，SHA-256 `f5afb195e9e866e36b65e11aa8f3a13f62cf4e6777bdfb69a31c35af31f0af8e`；AAB 为 25,478,659 bytes，SHA-256 `8681295f929f5e272f4a4ce35d18c02a505e6599be725b3060ce86511d9eeb86`。包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36、arm64。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过且 `uncompressNativeLibraries.alignment=PAGE_ALIGNMENT_16K`。APK/AAB 各含 7 个 arm64 原生库，全部 21 个 `PT_LOAD` 均满足至少 16 KB 对齐与文件偏移/虚拟地址同余。没有 NodeProbe、NodeBridge、`libnode.so` 或 npm 载荷。
- **签名与验收边界：**APK `apksigner verify` 报缺少 `META-INF/MANIFEST.MF`，APK/AAB 均无签名条目，符合当前产品 Release 尚未配置正式签名的状态。此次只做干净源码树的 Release 构建和静态检查，没有安装/启动该 unsigned 产物；不代表 16 KB Android 系统实机运行验收。16 KB 真机、正式签名、生产 Host/音乐闭环仍是 A8 发布门槛。


## 2026-11-20 fbe9fce 主线 Release APK/AAB 静态复验

- **源码与依赖输入：**在 `fbe9fce`（`按 v3.5 对齐工作台与连接首页`）创建独立 detached worktree；将主工作区未提交的 `pubspec.lock` 复制到临时 worktree，`flutter pub get --enforce-lockfile` 通过。此构建包含该提交中的 UI 调整，不包含临时工作区改动。
- **产物：**arm64 Release APK/AAB 构建成功。APK 27,713,920 bytes，SHA-256 `2fbed8a69c2069d1f6bdf075c95fc6964e1ba500785c555648966eac0f9b9422`；AAB 25,482,492 bytes，SHA-256 `3860d32a33a3b9379449dac4768da22a9dfe26fdf415ac9583101ff816809b1a`。包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36、arm64。
- **静态门禁：**Build Tools 36.0.0 APK `zipalign -c -P 16 4` 通过；官方 Bundletool 1.18.3（SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`）`validate` 通过，AAB 配置为 `PAGE_ALIGNMENT_16K`。APK 与 AAB 各含 7 个 arm64 原生库，21 个 `PT_LOAD` 全部满足至少 16 KB 对齐及 offset/virtual-address 余数相符；无 NodeProbe、NodeBridge、`libnode.so` 或 npm 载荷。
- **签名与验收边界：**APK/AAB 没有签名条目，APK `apksigner verify` 因缺少 `META-INF/MANIFEST.MF` 而失败，符合当前未配置产品 Release 正式签名的状态。产物未安装或运行，不表示 16 KB 系统实机兼容。正式签名、16 KB 真机和 production Host/音乐闭环仍是 A8 发布门槛。


## 2026-11-20 fbe9fce test-signed Release 4 KB cold-start recheck

- **构建输入：**在 `fbe9fce` 干净 detached worktree 构建 `aggregateIsolatedIntegration=true` arm64 Release APK；临时工作树使用主工作区未提交的 `pubspec.lock` 副本并通过 `flutter pub get --enforce-lockfile`。APK package 为 `io.github.guog962464.aggregate.integration`、versionCode 8、versionName 0.3.7，大小 27,722,124 bytes，SHA-256 `29b58f0d253b8feb6541f8a95dae5d096482f3f9a6c3a32a45ff4aefaa5e5c79`；使用 Android Debug test signer，证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。
- **设备验收：**LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`。首次官方 cold-start runner 返回 `Status: ok`、`LaunchState: COLD`，但 3 秒时 `MainActivity` 未 resumed；进程仍存在，crash buffer 没有该包匹配记录。按项目清理器已卸载 `.integration`。之后一次受控复核在 0.5/1.5/3 秒都观察到 `MainActivity` resumed、同一 PID 存活且无匹配 crash；随后官方 runner 连续 3 次通过，PIDs `1667`/`2893`/`4252`，`am start -W` 分别等待 1,334/2,103/1,156 ms。每次均自动 force-stop 并卸载 `.integration`，普通 Aggregate 保持安装。
- **结论范围：**记录一次未复现的瞬时 Activity-resume 检查失败和后续四次可复核成功；未定位首次异常根因，也未修改应用代码。当前结论仅为该 test-signed Release 在这台 4 KB 设备的冷启动复核；不能替代正式签名、16 KB 系统实机或 production Host/音乐验收。复核后无障碍设置仍为 `null/0`，ADB reverse 为空。


## 2026-11-20 `6507c92` 当前提交 Release APK/AAB 静态复建

- **基线与依赖：**从 `6507c92ee0b7b0f71393e0b45d4a2b476271f1d1` 创建 detached worktree。该提交中的 lock 与 pubspec 约束不一致；复制主工作区未提交的 `pubspec.lock` 后 `flutter pub get --enforce-lockfile` 通过。构建使用该提交的 Dart 源码，不含主工作区未提交 UI 修改。
- **验证：**`flutter analyze --no-pub` 无问题。Release APK/AAB 构建均成功；本轮只做构建与静态产物检查，没有运行 Flutter 测试、安装或启动 Release 包，也没有执行无障碍测试。
- **产物：**APK 27,779,456 bytes，SHA-256 `1b50fbd9e595b55c3ff5435f64345541ba0208ceab592dcb29239818f48e9c46`；AAB 25,502,275 bytes，SHA-256 `8fe2340230e3635d6342ea4d59b1a2befd1296e5dc22c46a0d737954dfb9bf4d`。`aapt dump badging` 显示包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36，arm64-v8a only。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，`dump config` 报告 `PAGE_ALIGNMENT_16K`。APK/AAB 各有 7 个 arm64 原生库、21 个 `PT_LOAD`，全部满足至少 16 KB 对齐和 offset/virtual-address 同余。两种压缩包均无 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules` 载荷。
- **签名与范围：**APK/AAB 没有签名条目，保持 unsigned；未在 4 KB 或 16 KB 设备安装/运行。本项证明当前提交的产品 Release 可构建并通过 16 KB 静态检查，不代表正式签名、16 KB 系统运行或 production Host/音乐验收。16 KB 实机、正式签名及生产 Host/音乐闭环仍开放。


## 2026-11-20 `df0ddfd` 当前提交 test-signed Release 4 KB 冷启动

- **构建输入：**在 `df0ddfd1e7dc739e6f6e956597ce09db1312bc15` 的 detached worktree 构建 arm64 `.integration` Release APK。复制主工作区 `pubspec.lock`（SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`）到 workspace 根目录后，`flutter pub get --enforce-lockfile` 通过；当前未提交 Dart UI 改动未进入构建。构建使用 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter build apk --release --target-platform android-arm64 --no-pub --build-name=0.3.7 --build-number=8`。
- **产物：**APK package `io.github.guog962464.aggregate.integration`、versionCode 8、versionName 0.3.7，大小 27,787,660 bytes，SHA-256 `a7721d97010f56b93d63bde25e16ec03a1a1aaa8db8e83dd9772dbfd3736b8b8`。由本机 Android Debug test signer 签名，证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`；Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。
- **设备验收：**LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`。官方隔离冷启动 runner 返回 `Status: ok`、`LaunchState: COLD`，`MainActivity` resumed 且进程存活（PID 22864，`am start -W` WaitTime 1,539 ms）；没有匹配该包的新 crash-buffer 记录。脚本 force-stop 并卸载仅属于本次的 `.integration` 包；普通 Aggregate 仍安装，启动前台的 `hg.zp.mengnews/.MainActivity` 在验收后保持前台，ADB reverse 为空，Mac Host 端口 47321/47322 无 listener。
- **结论范围：**当前提交的 test-signed Release 在这台 4 KB 真机冷启动通过；不代表产品正式签名或 16 KB 系统运行通过。未启动 NodeProbe/testnode，也未执行无障碍/TalkBack 测试（按用户决定不在验收范围）。正式签名、16 KB 真机及 production Host/音乐闭环仍开放。


## 2026-11-20 当前 UI 提交后的 Release 复建与 4 KB 冷启动检查

- **源码与依赖：**从当前 HEAD `86aab891ff30e37166e9b4783369c8b2a48d426b` 的工作树构建；应用代码包含 `3dc5dac` 的连接/活动 UI 更新。工作树保留用户未提交的 `pubspec.lock` 修改（`objective_c` 9.6.4；`.dart_tool/package_config.json` 也指向 9.6.4），命令使用 `--no-pub`，没有改写该锁文件。
- **自动化检查：**`flutter test --no-pub test/action_editor_test.dart --plain-name 'macOS action editor follows the v4 preview geometry'` 几何测试 1 项通过；随后用测试名正则运行 Host CLI 不显示本地动作编辑器、动作新增并保存、取消丢弃草稿 3 项功能测试，全部通过。`activity_page_test.dart` 7 项与 `connections_page_lazy_test.dart` 4 项也全部通过，覆盖活动重开/取消、连接长列表懒构建等交互。`flutter analyze --no-pub` 无问题。没有运行全量 Flutter suite，也没有运行无障碍/TalkBack 专项测试。
- **产品 Release 工件：**arm64 APK 27,779,456 bytes，SHA-256 `f1825817fe713db275ffbb9b62c55ace1c0b70e0c49387b7b19869d2a91de3e9`；AAB 25,519,983 bytes，SHA-256 `35fd983eab178a2f93dfc27cd9d8dbd0177d225a837304766df3586ea691b3fc`。Package `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、minSdk 24、targetSdk 36、arm64-v8a only。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，AAB config 为 `PAGE_ALIGNMENT_16K`。APK 与 AAB 各 7 个 arm64 DSO，全部 21 个 `PT_LOAD` 均 `p_align >= 0x4000` 且文件偏移/虚拟地址模 16 KB 相同。APK/AAB 均无签名条目；APK `apksigner verify` 按预期报告缺少 `META-INF/MANIFEST.MF`。两个工件都不含 NodeProbe、NodeBridge、`libnode.so` 或 npm 载荷。
- **隔离真机包：**同一源码用 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true` 构建 test-signed `.integration` Release；APK SHA-256 `1446065084150c1e03be2fcc4f4eba7fbfbcb821ba24c356cb9ddeb5cb23bd66`，v2 test signer 证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。`zipalign -c -P 16 4` 通过，包内有 7 个 arm64 DSO，未发现 Node/npm 载荷。
- **4 KB 冷启动结果：**LGE AN10 / Android 15 / API 35 / `PAGE_SIZE=4096`。最初两次 runner 均得到 `Status: ok`，但 3 秒检查未观察到 `MainActivity` resumed；第一次检查后设备为 asleep，第二次检查时 Keyguard 仍显示，原因未证实。随后设备处于唤醒、解锁状态时，使用同一 APK 重跑，`LaunchState: COLD`，`MainActivity` resumed、进程存活，详见下方补验。两次早期 runner 及成功补验均只操作隔离 `.integration` 包；普通包未被 runner 操作。没有启动 NodeProbe/testnode；较早 `df0ddfd` 的结论不用于替代当前 UI 源码验收。
- **范围结论：**当前代码的 Release 构建、16 KB 静态检查及本机 4 KB test-signed 冷启动均通过；产品包仍 unsigned。4 KB 结果不改变正式签名、16 KB 真机和 production Host/音乐业务门槛。

## 2026-11-20 当前 UI 提交后的 4 KB Release 冷启动补验

- **设备状态与产物：**LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`。测试前只读状态为 `mWakefulness=Awake`、Keyguard `showing=false`，未发送唤醒或解锁指令。使用上节同一隔离 `.integration` Release APK，SHA-256 `1446065084150c1e03be2fcc4f4eba7fbfbcb821ba24c356cb9ddeb5cb23bd66`。
- **结果：**`app/tool/run_android_release_cold_start.py --device AEMN022427001360 --apk app/build/app/outputs/apk/release/app-release.apk` 返回成功；Android 报 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1184 ms`，`MainActivity` resumed，PID 2680，进程保持存活，无匹配的新 crash-buffer 记录。冷启动项在该 4 KB 设备验收通过。
- **清理：**runner force-stop 并卸载本次隔离 `.integration` 包。测试后普通 Aggregate 与隔离包均未安装，ADB reverse 为空；屏幕仍唤醒且未锁定，前台恢复为 `hg.zp.mengnews/...NewsDetailH5Activity`。没有启动 NodeProbe/testnode，也没有运行无障碍/TalkBack 测试。

## 2026-11-20 当前 UI 提交后的 HTTPS MCP 集成复验

- **源码与命令：**应用代码基线 `86aab891ff30e37166e9b4783369c8b2a48d426b`（本次当前 HEAD `4c760115042bc4f78630ff8f1a4b5af9b86c65a7` 只增加验收文档）；在 `app/` 运行 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter test --no-pub --no-uninstall --reporter expanded integration_test/android_http_mcp_test.dart -d AEMN022427001360 --dart-define=A2_EXTERNAL_MCP_URL=https://bommel.bot/api/mcp`。
- **结果：**LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机整份集成文件 5 项全部通过，包括外部 HTTPS 测试；它验证 HTTPS setup、保存配置、发现 `get_site_info` 并成功调用。其余四项本地 HTTP/安全存储/响应上限/401 与超时测试也通过。
- **测试服务与边界：**使用 [Bommel Bot Agent Gateway](https://bommel.bot/agents) 公布的 `https://bommel.bot/api/mcp`。服务方将该入口说明为公开只读、无需账号或 API key；本测试没有 Token，只调用 `get_site_info`，并在测试 finally 中删除临时连接。该结果验证公开 HTTPS MCP endpoint 的当前客户端路径，不代表任何用户生产 endpoint 或业务数据。
- **清理与未覆盖：**测试使用隔离 `.integration` Debug 包；测试前后普通 `io.github.guog962464.aggregate` 包均未安装且没有被 runner 操作，测试后的 `.integration` 包已卸载，ADB reverse 为空。测试未设置 `A2_WIFI_SWITCH_TEST`，所以没有切换 Wi-Fi；不把测试名中的 network recovery 外推为本轮网络切换验收。没有运行 NodeProbe/testnode，也没有运行无障碍/TalkBack 测试。

## 2026-11-20 Host operation ledger 容量保护单测

- **实现范围：**只在 `app/test/host_rpc_protocol_test.dart` 增加临时文件回归，未更改 ledger 运行时代码。使用 `maxEntries: 1` 写入第一项后，验证第二项被 `operationLedgerFull` 拒绝且 `operations.json` 字节内容未变；重新打开后旧 `started` 记录转为 `outcomeUnknown`，被拒绝的 operation 不存在。
- **验证：**`flutter test --no-pub test/host_rpc_protocol_test.dart --plain-name 'rejects new operations without changing a full ledger'` 通过；整份 `host_rpc_protocol_test.dart` 22 项通过；`dart format test/host_rpc_protocol_test.dart` 检查 0 变更。没有启动生产 Host、读取/更改真实账本或执行无障碍测试。
- **范围限制：**确认本地账本容量拒绝与进程重启语义；文档中的真实 Host 管理员恢复流程仍未在生产 Host 演练，也未执行设备撤权/配对密钥轮换。

## 2026-11-23 当前 HEAD Release APK/AAB 静态复验与 4 KB 冷启动

- **源码与依赖：**从当前 HEAD `be41aaae36e1118dac705d0097c3a0fb172a7584` 的共享工作树构建；Android 源码无未提交修改。工作区 `pubspec.lock` 有用户未提交修改，SHA-256 为 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`；命令使用 `--no-pub`，未解析或改写依赖。
- **产品 Release 工件：**`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK SHA-256 `2605b195f317a9c1bfc0d723006fa1070f629a185e241e44a335dbb0c427e587`、27,845,236 bytes；AAB SHA-256 `803b97a6227165504b15221ac103f4dc0bd43ed3fcd87d0cb3bf2d77c7384040`、25,571,035 bytes。包名 `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、minSdk 24、targetSdk 36，arm64 only；产品 APK/AAB 保持未签名。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。APK/AAB 各含相同的 7 个 arm64 原生库、21 个 `PT_LOAD`，全部 `p_align >= 0x4000` 且文件偏移与虚拟地址的 16 KB 余数相同；archive CRC 检查通过，未包含 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules`。从 [Google Bundletool 1.18.3 release](https://github.com/google/bundletool/releases/tag/1.18.3) 下载的官方 jar SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29` 与 GitHub release API asset digest 一致；`validate` 通过，AAB 配置报告 `PAGE_ALIGNMENT_16K`。
- **隔离 Release 冷启动：**同一源码构建 test-signed `io.github.guog962464.aggregate.integration` APK，SHA-256 `50b4a36d8bbc4d0f889ee9a8f992cb1cf3e99fcb46eb096061da5c82b23a4dfd`，使用 Android Debug test signer（证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`）；zipalign 检查通过。LGE AN10 / Android 15 / API 35 / 4 KB 真机冷启动 runner 返回 `Status: ok`、`LaunchState: COLD`、`MainActivity` resumed 且进程存活（PID 504，WaitTime 1,528 ms）。runner 随后卸载本轮隔离包。
- **清理与范围：**普通 Aggregate 包未被操作；ADB reverse 为空，Mac Host 端口 `47321/47322` 无 listener，手机返回 HONOR Launcher。此项是当前源码的 unsigned 产品 Release 静态检查与 test-signed Release 4 KB 冷启动，不代表正式签名或 16 KB 系统运行。没有启动 NodeProbe/testnode，也没有运行无障碍/TalkBack 专项测试；production Host/音乐闭环仍未验收。

## 2026-11-23 当前 HEAD 普通包名 Release 冷启动与静态复验

- **源码与构建：**基线为 `226c5b28b8975303a453e3cd7fba0915ff22d100`。`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过；`--no-pub` 未解析或改写工作区的用户 lockfile 修改。
- **产品工件：**arm64 APK SHA-256 `57085584c575dca996fe2d7b943f0203d367aa61e434a665b9222e7716c08781`（27,845,236 bytes）；AAB SHA-256 `11793d510080345edef6435bcbe1b23c78e86c1d0cf935b87732448351121f5b`（25,572,344 bytes）。`aapt` 报告包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7。产品 APK/AAB 均未签名。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。经 SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29` 核验的官方 Bundletool 1.18.3 `validate` 通过，AAB 报告 `PAGE_ALIGNMENT_16K`。APK 与 AAB 各含 7 个 arm64 原生库；全部 42 个 ELF `PT_LOAD` 均满足 `p_align >= 0x4000` 且 file offset/virtual address 对 16 KB 同余。两种工件均无 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules` 载荷，且没有产品签名条目。
- **普通 applicationId 冷启动：**使用短期 RSA 测试证书签名的同一 Release APK 安装为普通包名 `io.github.guog962464.aggregate`，`apksigner verify` 和 16 KB ZIP 对齐检查通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上，`am start -W` 返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1,442 ms`；`MainActivity` 是前台 resumed Activity，进程存活且无新增 crash-buffer 条目。随后 CAMERA“仅使用期间允许”路径通过：Package Manager 为 granted，appops 为 foreground allow，扫码预览正常；未扫描邀请或配对。另以 Package Manager `user-fixed` denied 状态确认普通包拒绝回退显示 `permissionDenied` 与粘贴邀请提示；没有在该包的系统弹窗中点选“禁止”。详细步骤和限制见 [A5.4 普通包名 Release 验收](android-a5-android-client.md#2026-11-23-普通包名测试签名-release-主界面与-camera-允许路径)。
- **清理与边界：**普通包已卸载，前台回到 HONOR Launcher；临时证书和 APK 已删除。此项通过当前产品源码的 arm64 Release 构建、静态 16 KB 门禁和普通包名 test-signed 4 KB 冷启动，不代表正式签名、正式签名升级/权限矩阵或 16 KB 系统运行。普通包的 CAMERA 拒绝回退状态由 Package Manager 构造并通过；弹窗点选“禁止”的路径仍只由此前隔离 `.integration` Release 验证。没有启动 NodeProbe/testnode 或运行无障碍/TalkBack 测试。

## 2026-11-23 当前 HEAD Release 工件同一性复验

- **基线与依赖：**从当前 HEAD `7e7add1956c7129dc60870c8828f89f69a5aeb20` 重建主 App arm64 Release APK/AAB。构建使用 `--no-pub`；用户未提交的 `pubspec.lock` SHA-256 前后均为 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，未被构建改写。
- **工件：**`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK SHA-256 `57085584c575dca996fe2d7b943f0203d367aa61e434a665b9222e7716c08781`、27,845,236 bytes；AAB SHA-256 `11793d510080345edef6435bcbe1b23c78e86c1d0cf935b87732448351121f5b`、25,572,344 bytes。`aapt` 确认 package `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、arm64 only。
- **静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；APK/AAB 各有 7 个 arm64 ELF、21 个 `PT_LOAD`，全部 `p_align >= 0x4000` 且 offset/virtual-address 对 16 KB 同余，ZIP CRC 检查通过。官方 Bundletool 1.18.3 JAR SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`；`validate` 通过，AAB `dump config` 报告 `PAGE_ALIGNMENT_16K`。APK/AAB 均无签名条目，也不含 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm 载荷。
- **同一性与边界：**两种工件的 SHA-256 与本文件前述 `226c5b2` 当前提交 Release 工件完全一致；该 APK 已有 test-signed 4 KB 真机冷启动记录，本次不重复安装。此复验确认当前 HEAD 仍生成相同静态工件，不增加新的设备运行证据；产品仍未正式签名，LGE AN10 只有 4 KB 页，16 KB 系统运行仍未验收。

## 2026-11-23 当前 HEAD 49c2e7a Release 复建与 4 KB 隔离冷启动

- **基线与构建：**当前 `main` HEAD `49c2e7a329b428e653d0ea950d83f7ee06d4503c`；主 App arm64 Release APK/AAB 均以 `--no-pub` 重建通过。`pubspec.lock` SHA-256 保持 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，没有触发依赖解析或改写。
- **主 App 工件：**APK SHA-256 `57085584c575dca996fe2d7b943f0203d367aa61e434a665b9222e7716c08781`（27,845,236 bytes），AAB SHA-256 `11793d510080345edef6435bcbe1b23c78e86c1d0cf935b87732448351121f5b`（25,572,344 bytes）。包名 `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、minSdk 24、targetSdk 36、arm64 only。两个产品工件均未签名；SHA-256 与上一条已验收工件完全一致。
- **静态 16 KB 门禁：**APK `zipalign -c -P 16 4` 通过；APK/AAB CRC 均通过，各含 7 个 arm64 ELF、21 个 `PT_LOAD`，NDK r28.2.13676358 `llvm-readelf` 检查的全部段 `p_align >= 0x4000` 且 file offset/virtual address 对 16 KB 同余。Bundletool 1.18.3（JAR SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`）`validate` 通过，AAB 配置为 `PAGE_ALIGNMENT_16K`。未包含 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules`。
- **4 KB 真机冷启动：**以 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true` 构建 `.integration` Release APK，SHA-256 `6dad15ca06c149adea50e9d39389baa3659ccdf672a889585558cd42e42779c8`，由 Android Debug test signer 证书 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832` 签名；v2 验签和 APK 16 KB zipalign 通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上冷启动返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1,454 ms`；`MainActivity` 成为 top-resumed，等待 2 秒后 PID `28712` 仍存活。
- **清理与范围：**`.integration` Release 包已卸载，普通 `io.github.guog962464.aggregate` 包仍安装，手机回到 HONOR Launcher；ADB reverse 为空，Mac Host `47321/47322` 无 listener。没有运行无障碍/TalkBack 或启动 NodeProbe/testnode。此项是当前 APK/AAB 静态门禁和 4 KB 测试签名 Release 冷启动，不代表正式签名、签名升级、16 KB 系统运行或生产 CLI/账号业务通过。

## 2026-11-23 isolated test-signed Release version 8-to-9 upgrade on 4 KB device

- **Artifacts:** Built isolated Debug APK with `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter build apk --debug --no-pub` and isolated Release APK with the same Gradle property plus `--build-number=9`. Both use applicationId `io.github.guog962464.aggregate.integration`, versionName `0.3.7`; Debug is versionCode 8 and Release is versionCode 9. Debug APK SHA-256 `be7a4a3f9e50268d869c2fb25e38674e3c2d1068526a51a5ab379a9613e51981`; Release APK SHA-256 `aa504e06ddb15ec60f3ad19a7bf7a1be2e2a1a5aaa337766e491d06dfd2b01ef`. `apksigner verify --print-certs` returned the same test certificate SHA-256 for both: `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`.
- **Upgrade and launch:** On LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`, `adb install` of Debug returned `Success`; Package Manager recorded `firstInstallTime=2026-11-23 22:35:43`, versionCode 8. `adb install -r` of the higher-version Release returned `Success`; the same `firstInstallTime` remained and Package Manager reported versionCode 9. Release cold start returned `Status: ok`, `LaunchState: COLD`; `MainActivity` became top-resumed and AndroidRuntime had no matching crash log.
- **Cleanup and scope:** Force-stopped and uninstalled only `.integration`; ordinary `io.github.guog962464.aggregate` remained installed, ADB reverse was empty, and the phone returned to HONOR Launcher. This proves a real-device version 8→9 update with the Android Debug test certificate. It does not verify an official product signing key, update from a previously published production certificate, 16 KB device execution, or persisted user-data sentinel behavior. Formal signing and production upgrade remain release gates.

## 2026-11-23 Android formal signing configuration recheck

- At current `main` (`3b5e0f0` plus documentation-only commits), `app/android/app/build.gradle.kts` assigns the Android Debug test signer only when `aggregateIsolatedIntegration=true`; the product Release build remains unsigned until a separately managed production signing configuration is supplied.
- Read-only inspection found no `key.properties`, JKS, or keystore file under `app/android`. No release key was created, opened, copied, or added to the repository. Thus an official product-signed artifact and upgrade from its production certificate cannot be verified in this environment; prior test-signed v8→v9 evidence remains limited to the isolated package.


## 2026-11-24 当前 HEAD 952d87e Release 重建与 4 KB 隔离冷启动

- **基线与构建：**源代码基线为 main HEAD 952d87e56adc1193495aea4eca713d4fc4c4279e。主 App arm64 Release APK 与 AAB 使用 Flutter --no-pub 构建，均成功；pubspec.lock SHA-256 保持 9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500。aapt 确认包名 io.github.guog962464.aggregate、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36、arm64 only。
- **产品工件：**APK 为 27,845,236 bytes，SHA-256 ff6e681c9c5bd554b26434ceaa6e2d6ea2d5960107f26030b0eaab2748706e20；AAB 为 25,570,163 bytes，SHA-256 e2f080c0b33c07021e248b93bcc0a992ed1feb7e9936411e9fa2c0aa83ce443b。APK 与 AAB 均有 7 个 arm64 原生库，不含 NodeProbe、NodeBridge、libnode.so、nodejs-mobile 或 npm node_modules。产品 APK/AAB 未签名，apksigner 对产品 APK 的缺签名结果符合当前配置。
- **静态 16 KB 检查：**Build Tools 36.0.0 zipalign -c -P 16 4 通过；APK/AAB ZIP CRC 均通过。NDK 28.2.13676358 llvm-readelf 检查两个工件各自的 7 个库，共 21 个 PT_LOAD，所有段满足 p_align 至少 0x4000 且文件偏移与虚拟地址对 16 KB 同余，异常数为 0。Bundletool 1.18.3 JAR SHA-256 为 a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29；validate 通过，AAB 配置为 PAGE_ALIGNMENT_16K。
- **4 KB 真机启动：**隔离 applicationId io.github.guog962464.aggregate.integration 的 Release APK SHA-256 为 d81ee6c95148cf8c3ad1dc51bb2cc30f4695e3ba4f4aced332b9339ad47789c7，使用 Android Debug test signer（证书 SHA-256 55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832），验签及 16 KB zipalign 通过。LGE AN10 / Android 15 / API 35 / arm64 / PAGE_SIZE=4096 上，冷启动返回 Status: ok、LaunchState: COLD；MainActivity resumed，进程 PID 30095 在约 3,078 ms 后仍存活。隔离包随后已卸载；普通 Aggregate 包保留安装，ADB reverse 为空。
- **范围：**本项更新当前 HEAD 的 Release 静态工件证据并补充 4 KB 测试签名隔离包冷启动。它不表示正式签名/签名升级、16 KB 系统实机、production Host、CLI 或真实账号音乐链路通过；无障碍/TalkBack 测试按用户决定不纳入。此次未启动 NodeProbe/testnode。

## 2026-11-24 当前 HEAD 36d0bff Release 重建与 4 KB 隔离冷启动

- **基线与依赖：**在 detached worktree `/private/tmp/aggregate-a8-head-build` 对提交 `36d0bffff56b7d6b52cc7946fb35259391d18546` 执行验收。依赖通过 `flutter pub get --offline` 按当前工作区锁定版本恢复，隔离 worktree 的 `pubspec.lock` 与当前工作区文件逐字比较一致；后续 build 使用 `--no-pub`。该提交包含 A5 Mac Host Dart 代码变更，当前构建产物哈希与 952d87e 记录不同；此项对当前 HEAD 重建并复验，不将 hash 差异单独归因于代码或构建非确定性。
- **产品 Release 工件：**`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK SHA-256 `d8f72bf165ea21997e7694d50fc73c62321558958f0d2ca32d5cf0a2690c06c2`、27,845,236 bytes；AAB SHA-256 `796e46b28ea56ca37a0780fef4d8da80f512e6fde9f94c8fc17d4e2aaa188593`、25,570,168 bytes。包名 `io.github.guog962464.aggregate`，versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36，仅 arm64-v8a。
- **静态发布门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；APK/AAB ZIP CRC 均通过。每个工件含 7 个 arm64 原生库，各自 21 个 `PT_LOAD` 全部满足 `p_align >= 0x4000`，file offset 与 virtual address 对 16 KB 同余。官方 Bundletool 1.18.3 JAR SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`，`validate` 通过，AAB 配置为 `PAGE_ALIGNMENT_16K`。两件产品工件均未签名；APK `apksigner verify` 不通过且 AAB 无签名条目。没有 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm 载荷。
- **当前 HEAD 4 KB 真机冷启动：**同一提交以 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter build apk --release --no-pub --target-platform android-arm64 --build-number=9` 生成隔离 test-signed APK；SHA-256 `15bccba58f8548c17473e03f6205cf28d89d4f53bb715adc60f3d9e14f165bb2`、27,853,440 bytes，包名 `io.github.guog962464.aggregate.integration`，versionCode 9，证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。zipalign 与 `apksigner` v2 验证通过。在 LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上冷启动 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1686 ms`；2 秒后 PID 11356 仍存活，`MainActivity` 为 top-resumed，按 PID 过滤的 logcat 没有 Flutter error/fatal exception。隔离包卸载后，普通 `io.github.guog962464.aggregate` 仍安装，PID 11980 与其 `MainActivity` 恢复为 top-resumed，ADB reverse 为空。
- **未关闭的发布条件：**没有 16 KB 真机，也没有正式 Android 签名身份；静态 16 KB 结构和 4 KB 真机冷启动不证明 16 KB 系统运行兼容。A3.6 许可/来源闭包、法律审查及 A5 production Host Keychain/RPC/音乐业务也仍开放。未运行 NodeProbe/testnode 或无障碍测试。

## 2026-11-24 b8cdfea A8 产品源码与锁文件延续核对

- **核对范围：**核对时 HEAD `b8cdfea57ee115978ac89bff82d6d0e438a6df59` 与已完成 Release/4 KB 冷启动验证的提交 `36d0bffff56b7d6b52cc7946fb35259391d18546` 之间，提交差异只有文档。两个提交的 `app/` tree SHA-1 均为 `98813a338ce3267e412e88696b49ece9cc756a26`；根 `pubspec.lock` blob SHA-1 均为 `abf71868c5c521aae60eb060a422506034c6bf27`。
- **结论修订：**提交树中的 `app/` 与锁文件相同，只能证明提交内容相同。36d0bff 构建记录称临时工作树经离线恢复后锁文件匹配共享工作区锁；这没有独立证明构建使用的是提交树里的锁文件。下方 2026-11-24 A8 复核显示，严格使用当前提交锁文件会失败，因此旧工件证据仅按相同 app 源码延续，不能据此声称已按提交锁文件复现。
- **边界：**这只确认提交间产品源码/锁文件未变化，不增加 16 KB 真机、正式签名/签名升级、生产 Host 或真实 CLI/网易云业务证据。未运行 NodeProbe/testnode 或无障碍测试。

## 2026-11-24 当前 HEAD fac0ef7 Release 重建与 4 KB 隔离冷启动

- **基线与依赖锁：**从 `a497300e866cd4284db818cee6815faec998176b` 的 detached worktree 构建；当前 HEAD `fac0ef704c2a128e7d857b5f6a05e3510e1ddf84` 到该提交只有文档差异，`app/` tree 均为 `98813a338ce3267e412e88696b49ece9cc756a26`。提交根锁文件 SHA-1 为 `abf71868c5c521aae60eb060a422506034c6bf27`、SHA-256 为 `99cd95094ec9627f44758881fc1bd4853982acdce7efd6dc6980bda78f5333c8`。在临时 worktree 对它运行 `flutter pub get --offline --enforce-lockfile` 失败（退出码 65），pub 报告有 106 个依赖需要变化。普通 `flutter pub get --offline` 成功并生成 SHA-256 `71a41ca6d88b667886ebf2055a1d03ad8e4759ab3528adae426d1fa744c6a52a` 的临时根锁文件；例如 `cli_util` 0.6.0→0.6.1、`coverage` 1.16.0→1.16.1、`jni` 1.1.2→1.2.1、`jni_flutter` 1.0.4+1→1.1.0。产品和隔离测试构建随后使用该解析图并带 `--no-pub`。主工作区用户修改的根 `pubspec.lock`（SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`）未被改写或暂存。
- **产品 Release 工件：**arm64 APK/AAB Release 构建成功。APK SHA-256 `493b309a21a2a5ee66796f053df3e5004ec228c91cb6aed7b891c29339b6a877`，27,845,236 bytes；AAB SHA-256 `7b0127c17ac575e8dfd19c42a4b01bbceef3ab7d7a84925c653a967794f71e1b`，25,570,227 bytes。APK 包名 `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、minSdk 24、targetSdk 36、arm64 only。
- **静态发布门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 对产品 APK 通过，APK/AAB ZIP CRC 通过。每个产品工件含 7 个 arm64 原生库；NDK r28.2.13676358 检查的每个工件 21 个 `PT_LOAD` 全部满足 `p_align >= 0x4000` 且 file offset 与 virtual address 对 16 KB 同余。Bundletool 1.18.3（JAR SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`）`validate` 通过，AAB 为 `PAGE_ALIGNMENT_16K`。产品 APK/AAB 均未签名；没有 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm 载荷。
- **4 KB 真机冷启动：**临时修改隔离构建变体后生成包名 `io.github.guog962464.aggregate.integration.a8check`、versionCode 10 的 test-signed arm64 Release APK，SHA-256 `e1e2ec27d0739a25149829fd7d7536dc88a2c4ae96522379e8fa58c4d2319fac`。Build Tools 36.0.0 `zipalign -c -P 16 4` 与 `apksigner verify` v2 均通过；测试证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上，冷启动返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 794 ms`；等待约 2 秒后 PID `18955` 仍存活且 `MainActivity` 为 top-resumed，按 PID 筛查的 500 条 logcat 未发现 `E/flutter`、fatal exception 或 native fatal signal。
- **清理与范围：**只卸载本次创建的 `.integration.a8check`；普通 `io.github.guog962464.aggregate` 仍安装并恢复前台（PID `11980`），ADB reverse 为空。当前产品 app 源码的 Release 构建、16 KB 静态布局和 4 KB 测试签名冷启动已覆盖；严格按已提交锁文件复现仍未通过，需有明确归属的锁更新后再重跑。没有 16 KB 真机、正式签名、A3.6 来源/许可证闭包、production Host/RPC 或真实 CLI/音乐流程证据；未运行无障碍测试或 NodeProbe/testnode。
- **后续状态：**本节记录第一次离线解析工件。锁文件严格复现的当前结论、五项任务归属锁更新及其重建工件见下方 [标准 pub.dev 锁更新与 Release 最终复验](#2026-11-24-a8-标准-pubdev-锁更新与-release-最终复验)；后者取代本节“严格按已提交锁文件复现仍未通过”的当前状态。

## 2026-11-24 A8 标准 pub.dev 锁更新与 Release 最终复验

- **锁文件更新：**以原提交锁 SHA-1 `abf71868c5c521aae60eb060a422506034c6bf27` 为基线，保留 `https://pub.dev` source URL，仅更新 `objective_c` 9.6.3→9.6.4、`cli_util` 0.6.0→0.6.1、`coverage` 1.16.0→1.16.1、`jni` 1.1.2→1.2.1、`jni_flutter` 1.0.4+1→1.1.0。最终锁 SHA-256 为 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`；`PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 在隔离 worktree 成功，锁内容保持原哈希。当前主工作区用户修改的锁（SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`）原样保留且不进入本次暂存。
- **最终产品工件：**在 app tree `98813a338ce3267e412e88696b49ece9cc756a26` 上用上述锁执行 `flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 成功。APK 27,845,236 bytes，SHA-256 `ba4a855d3f7d6a7d8dfd99637290ab4f4aba2d2a4ba883c070456f0eca0109fa`；AAB 25,570,228 bytes，SHA-256 `a235860aaafcccc093137df7ef944a006c9ee5dd24c57fbde7bd3eab2dfcd03a`。包名 `io.github.guog962464.aggregate`，versionCode 8/versionName 0.3.7、minSdk 24、targetSdk 36、arm64 only；两件产品工件未签名。
- **最终静态检查：**APK `zipalign -c -P 16 4` 与 APK/AAB ZIP CRC 检查通过。两个工件各 7 个 arm64 原生库、21 个 `PT_LOAD`；NDK r28.2.13676358 `llvm-readobj` 检查的 42 段全部满足 `p_align >= 0x4000`，file offset 与 virtual address 对 16 KB 同余。Bundletool 1.18.3 `validate` 通过，AAB 配置为 `PAGE_ALIGNMENT_16K`。两件工件均无 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules` 载荷。
- **最终 4 KB 真机冷启动：**使用同一锁构建独立 `.integration.a8check` test-signed Release APK，versionCode 10，大小 27,853,444 bytes，SHA-256 `6bdf809500967787cc6381600fe284e0b640247eca0a79a48d65e385e16dbcef`；`zipalign -c -P 16 4` 与 `apksigner verify` v2 通过，测试证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 冷启动 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1,417 ms`；等待约 2 秒后 PID `22416` 存活且 Activity top-resumed，PID 日志筛查无 Flutter error 或 fatal signal。临时包随后卸载，普通 Aggregate 包 PID `11980` 恢复前台，ADB reverse 为空。
- **当前结论与发布门槛：**依赖锁已按当前解析结果更新并严格验证；产品 Release 构建、16 KB 静态布局和 4 KB test-signed 真机冷启动均通过。没有 16 KB 物理设备和正式签名身份；A3.6 来源/许可证闭包与法律审查、A5 production Host/只读 RPC、CLI/网易云真实业务仍开放。未运行无障碍测试或 NodeProbe/testnode。

## 2026-11-24 当前 HEAD 7c1fa64 Release 重建与 4 KB 隔离冷启动

- **基线与依赖：**从提交 `7c1fa64407218fb41cc0c7fda112f586c9328e8c` 的 detached worktree `/private/tmp/aggregate-a8-refresh-7c1fa64` 验收；当前 `app/` tree 为 `ca68074cdccb56bb1c0750233af43a5f725257d3`，提交内 `pubspec.lock` SHA-1 `2e26f7d400ccc288b9f6b1e82a3969963af1383f`、SHA-256 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`。`PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 通过，之后以 `--no-pub` 构建。主工作区未提交的 `pubspec.lock` 修改不属于该构建。
- **产品 Release 工件：**arm64 APK/AAB Release 构建通过。APK 27,845,300 bytes，SHA-256 `58af83fdf965fb48fa89d0a96119a21b2b5a3b462d4bab28d7470ce7fca27ecb`；AAB 25,581,824 bytes，SHA-256 `355e853f37e26fc238f0ff0060cfed14f91e5891e934d45be7eca251f5297ee1`。APK 包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36，仅 `arm64-v8a`。Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；APK/AAB ZIP CRC 通过；两个工件各含 7 个 arm64 DSO、21 个 `PT_LOAD`，全部满足 `p_align >= 0x4000` 且 file offset/virtual address 对 16 KB 同余。Bundletool 1.18.3 `validate` 通过，AAB 配置为 `PAGE_ALIGNMENT_16K`。产品 APK `apksigner verify` 未通过签名验证（Release 保持未签名），AAB 没有签名条目；两个工件均不包含 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm `node_modules` 载荷。
- **隔离 4 KB 真机冷启动：**只为验收临时将隔离 applicationId 后缀设为 `.integration.a8check`，没有修改提交源码。test-signed Release APK 为 27,853,508 bytes，SHA-256 `7452eca282d443a85a95c4be2746c4a0a2be888dc25b61233549bc1256274f96`，versionCode 10；签名证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。`apksigner verify` 与 16 KB zipalign 检查通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上，`am start -W` 返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1,629 ms`；约 2 秒后 PID `21680` 仍存活，`MainActivity` top-resumed，按进程过滤的日志没有 `FATAL EXCEPTION`、`Fatal signal`、`UnsatisfiedLinkError`、`FlutterError` 或 `AndroidRuntime` 错误。临时包已卸载，原前台 `hg.zp.mengnews/com.zjonline.xsb_main.MainActivity` 已恢复，ADB reverse 为空；未进入 testnode 或运行无障碍测试。
- **范围与门槛：**当前提交的 Flutter UI 源码已重新完成 Release 构建和 4 KB 真机冷启动；静态 16 KB 布局通过，但没有 16 KB 真机，不能宣称 16 KB 系统运行通过。正式签名/生产证书升级、A3.6 运行时来源与许可闭包/法律审查、A4 Node/npm/CLI 生产集成、A5 production Host/配对/RPC 与真实音乐业务仍未关闭；Release 产品工件不含 Node/npm 运行时。

## 2026-11-24 当前 HEAD 1d1f66c Flutter 静态分析与 UI 回归

- **源码与依赖：**在提交 `1d1f66c26e5cbea5d8855221af4b9a270cfab3dd` 的干净 detached worktree `/private/tmp/aggregate-a8-tests-1d1f66c` 执行；`app/` tree `ca68074cdccb56bb1c0750233af43a5f725257d3` 与上节 A8 Release/设备验收相同。严格 `PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 成功，隔离锁 SHA-256 保持 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`。
- **静态分析与测试：**`flutter analyze --no-pub` 返回 `No issues found`。`flutter test --no-pub test/glass_motion_test.dart test/android_theme_transition_test.dart test/android_mobile_navigation_test.dart --reporter expanded` 三个文件共 21 项全部通过，覆盖共享玻璃动效/主题过渡与 Android 手机导航回归；未运行无障碍/TalkBack 测试，也没有操作手机前台。
- **工作区隔离：**主工作区 `pubspec.lock` 仍为用户未提交的 SHA-256 `9cb893d677146b21667d4137117378b0db159e67927bf87942656d49b3658500`，本项未暂存。一次最初从主工作区执行的严格锁解析因该用户锁内容而拒绝解析；随后改在 detached worktree 按提交锁成功，主锁哈希复核未变。该结果不把用户锁或主工作区 `.dart_tool` 状态纳入验收。
- **范围：**这补充当前共享 Flutter UI 的静态分析和定向回归证据；不替代全量 Flutter suite、16 KB 真机、正式签名或 A3.6/A4/A5 的开放验收门槛。

## 2026-11-24 当前 HEAD 086c7aa A8 输入身份复核（11:43 Asia/Shanghai）

- **已提交产品输入：**当前 `HEAD:app` tree 为 `ca68074cdccb56bb1c0750233af43a5f725257d3`，与已完成 Flutter UI 检查及 Release/4 KB 验收的 `1d1f66c:app` tree 完全一致。当前 `HEAD:pubspec.lock` SHA-256 为 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`，与 A8 Release/严格锁验证记录相同。
- **范围：**这只确认 A8 已提交源码和依赖锁身份未变化，因此既有 Release 静态检查与 4 KB 真机冷启动结果仍对应当前 HEAD；本次没有重建、重新安装或运行真机。主工作区未提交的测试文件与 `pubspec.lock` 修改不属于该产品输入，也未纳入本项结论。正式签名和 16 KB 真机门槛继续开放。

## 2026-11-24 app/test 非无障碍全量验收与 A5 Host 面板测试定位（11:44–11:51 Asia/Shanghai）

- **隔离与依赖：**在 detached worktree `/private/tmp/aggregate-a8-full-suite-20261124`（基线提交 `094c6a531a038013681186d2617928cf653e8b0a`）运行；`PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 成功，使用提交锁。
- **A5 Host 面板测试：**全量首轮发现三个测试把语义标签当作可见文本查找、另有一个停机状态文案已变更。测试只改为查找 UI 实际显示的“连接向导”“轮换身份”“已停止”；产品代码和语义属性未改。`flutter test --no-pub test/mac_host_settings_panel_test.dart --reporter expanded` 5 项全部通过。
- **非无障碍全量结果：**第一次未过滤的 `flutter test` 自动发现了用户已排除的 `accessibility_test.dart` 并执行其中一项；这是本轮误纳入的越界测试，后续没有重跑。随后显式排除该文件运行 app 测试集；A5 面板修正前为 365 通过、8 失败，修正后为 **368 通过、5 失败**（退出码 1）。剩余 5 项全部为 `TargetPlatform.macOS` 的玻璃文本对比（2 项）、减弱动态效果下玻璃开关文字（1 项）和宽屏布局断言（2 项）；本次全量执行中没有 Android 目标测试失败。
- **范围与剩余项：**这不是全量 suite 通过。主工作区未提交的 `widget_test.dart`、玻璃对比测试与设计文件没有带入隔离 worktree；剩余 5 项未在本 Android 任务中改写。后续测试命令继续排除 `accessibility_test.dart`。本轮没有重建 APK/AAB、安装或操作手机；正式签名与 16 KB 真机门槛仍开放。

## 2026-11-24 当前 HEAD 9a7e50c A8 产品输入身份复核（11:55 Asia/Shanghai）

- **产品输入对照：**当前 `HEAD` 为 `9a7e50c0f07d37c009c95b16801acfad84eb18d3`。`app/lib`（tree `d0ebe510a651cd3d0e01c4465abfa98e0efe655b`）、`app/android`（tree `299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`）、`app/pubspec.yaml`（blob `7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7`）和根 `pubspec.lock`（SHA-256 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`）均与 A8 Release/4 KB 验收基线 `094c6a5` 一致；根 `pubspec.yaml` 也未变。`094c6a5..HEAD` 在 `app/` 下唯一差异是 `app/test/mac_host_settings_panel_test.dart` 的测试查找修正，不影响 Android Release 构建输入。工作区未提交的 `pubspec.lock` 修改不属于已提交输入。
- **范围：**这仅确认已验收 Android 产品构建输入没有变化；本轮没有重新构建、运行测试、安装或操作手机。既有 Release 静态检查与 4 KB test-signed 冷启动证据可沿用到当前已提交产品输入。全量非无障碍 suite 仍有 5 个 macOS 目标失败；正式签名、16 KB 真机、A3.6 许可/来源闭包及 A5 production Host/配对/RPC 仍开放。

## 2026-11-24 当前 UI 测试输入的非无障碍全量复验（13:26 Asia/Shanghai）

- **隔离与输入：**在 detached worktree `/private/tmp/aggregate-a8-full-suite-20261124` 的提交 `094c6a531a038013681186d2617928cf653e8b0a` 复验，按已提交锁严格恢复依赖。`widget_test.dart` 和 `macos_dynamic_backdrop_text_contrast_test.dart` 从主工作区当前未提交版本复制到隔离 worktree；没有改写或暂存主工作区文件。为覆盖当前连续式设置页，对隔离副本中的旧 `Mac Host` 标签、旧 helper text、懒构建滚动及单视口逐标签 shader 截图定位作测试适配；`macos_reduce_motion_test.dart` 也仅在隔离 worktree 更新到当前 helper text。没有修改产品代码。
- **套件结果：**显式排除 `test/accessibility_test.dart` 后运行 66 个测试文件，**372 项通过、1 项失败**。A5 Host 面板测试及当前工作区改过的宽屏几何/标题断言通过；Android 目标用例没有失败。`macos_reduce_motion_test.dart` 的 live-switch 文案回归通过；玻璃按钮标签全尺寸/主题矩阵通过。
- **剩余失败：**仅 `macos_dynamic_backdrop_text_contrast_test.dart` 的 midpoint text halo 用例失败：macOS 800×600、暗色初始外观、shader phase `0.545` 的 appearance description 实测对比度 `4.428822014656451`，低于该用例 `4.5` 断言。保留阈值与实测失败，不将其改成通过。该项是 macOS 玻璃文本像素对比检查，不是 Android 目标失败；此次未运行 `accessibility_test.dart` 或 TalkBack 专项。
- **范围：**结果只覆盖当前用户测试文件的隔离副本、上述临时测试适配及提交产品代码；临时适配没有合入仓库。没有重新构建 APK/AAB、安装手机、启动 NodeProbe/testnode 或操作手机前台。A8 测试集仍有 1 个 macOS 目标失败；正式签名、16 KB 真机、A3.6 闭包和 A5 production Host/配对/RPC 仍开放。

## 2026-11-24 当前 HEAD a03e849 arm64 Release 重建与 16 KB 静态复核

- **源码和依赖：**在 detached worktree `aggregate-a8-current-a03e849` 的当前 HEAD `a03e8497eb8c237520c3b6cd6a86dbfd5ebf00c5` 运行 `PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile`，成功。提交内 `app/lib` tree `d0ebe510a651cd3d0e01c4465abfa98e0efe655b`、`app/android` tree `299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`、`app/pubspec.yaml` blob `7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7`、根 `pubspec.lock` SHA-256 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87` 与 4 KB 冷启动基线 `7c1fa64` 的产品构建输入相同；当前提交相对基线的差异不落在上述产品输入路径。
- **Release 工件：**`flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 均通过。APK 27,845,300 bytes，SHA-256 `417a51807a78093a79f091ce1f708d9a6e9b7ef036817c9dfc396675edaa6b88`；AAB 25,581,615 bytes，SHA-256 `d1a5996a56a563b4d9def156f65f4a3a8f80d93efae917372dcae04ae7c1bae8`。`aapt` 报包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、minSdk 24、targetSdk 36，仅 `arm64-v8a`。
- **静态门禁：**APK ZIP CRC 与 Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，`dump config` 报 `PAGE_ALIGNMENT_16K`。APK/AAB 各含同样的 7 个 arm64 DSO；NDK r28.2.13676358 `llvm-readobj` 检查每件工件 21 个 `PT_LOAD`，共 42 段均有 `p_align >= 0x4000` 且 file offset/virtual address 对 16 KB 同余，最小对齐为 16 KB。两个 ZIP CRC 均通过，原生库 SHA-256 在 APK/AAB 间一致；没有 NodeProbe、NodeBridge、`libnode.so`、nodejs-mobile 或 npm 载荷。
- **发布与设备边界：**APK 的 `apksigner verify` 因缺失签名 manifest 而失败，AAB 没有签名块；两件产品工件均未签名。本轮未安装或操作手机。因为已验收的 `app/lib`、Android Gradle、包清单及锁文件与 `7c1fa64` 的 4 KB 冷启动输入一致，可沿用该次 4 KB 真机证据作为相同产品输入的验收记录；这不是本轮的新设备运行。没有 16 KB 真机，不声明 16 KB 系统实机通过。
- **范围：**此次只做隔离依赖恢复、arm64 Release 构建和静态工件检查；未运行测试、安装手机包、正式签名或 Node/npm 产品验证。隔离工件/worktree 在记录前清理；主工作区用户测试、设计及锁文件改动未带入。

## 2026-11-26 当前 main 1658785 A8 产品输入延续复核

- **输入身份：**当前已提交 HEAD `1658785466a575bea811ea2f15b6ca71ec9c4351` 与 A8 Release/静态基线 `a03e8497eb8c237520c3b6cd6a86dbfd5ebf00c5` 的 `app/lib` tree（`d0ebe510a651cd3d0e01c4465abfa98e0efe655b`）、`app/android` tree（`299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`）、`app/pubspec.yaml` blob（`7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7`）及提交内 `pubspec.lock` blob 完全一致，锁 SHA-256 仍为 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`。
- **适用证据：**因此 `a03e849` 的 arm64 APK/AAB 构建、zipalign/Bundletool/42 个 PT_LOAD 静态 16 KB 检查及 `7c1fa64` 同一产品输入的 4 KB 冷启动记录仍适用于当前已提交产品输入。本轮只做 tree/blob 身份比较，没有重建 Release 工件、重跑静态工具或安装手机。
- **工作区与发布边界：**当前工作树未提交的 `pubspec.lock`、UI 测试和设计文件不属于该结论。APK/AAB 仍未正式签名；没有 16 KB 实体设备，故仍无 16 KB 系统实机运行证据。该条只更新已提交产品输入的延续关系。

## 2026-11-26 当前 HEAD `fca0102` A8 Release 与 4 KB 真机复验（18:21 Asia/Shanghai）

- **输入身份与隔离：**在 detached worktree `/private/tmp/aggregate-a8-head-2b288c3` 对提交 `2b288c36b8468219251b6f3e023945b385e0b9b2` 执行构建和设备验收。当前 HEAD `fca0102` 相对该提交只增加 macOS UI 验收文档；`app/lib` tree `6d5333503d4b7a0c2c9acfa8ac07d40c9321b4f4`、`app/android` tree `299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`、`app/pubspec.yaml` blob `7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7` 与提交锁 blob `2e26f7d400ccc288b9f6b1e82a3969963af1383f` 均对应本次构建输入。使用 `PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 成功，隔离 worktree 锁文件未变化。主工作区未提交的 lock、测试与设计文件未纳入，也未修改。
- **静态检查与定向回归：**`flutter analyze --no-pub` 通过，输出 `No issues found`；`flutter test --no-pub test/action_editor_test.dart` 的 5 项全部通过。本轮没有运行无障碍/TalkBack 测试。
- **Release 工件：**arm64 产品 APK/AAB Release 构建通过。未签名 APK SHA-256 `ee9c08d1f8f83724c14ff20673433d1349c9a6fe0f89c1e385de5154d06e4dba`；未签名 AAB SHA-256 `e5d6c06c3c0d7f9e0193201190a85ad0c0fe2b1c0a9ca9f453696738209db7fd`。APK `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过且报告 `PAGE_ALIGNMENT_16K`。APK/AAB 的 7 个 arm64 原生库逐一相同，21 个 `PT_LOAD` 均满足 16 KB 对齐与地址同余要求。产品工件保持未签名，不能视作可发布签名包。
- **4 KB 真机冷启动：**仅为集成验收构建本地 debug key 签名的 `.integration` Release 包（证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`），安装到 LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 真机。启动后进程 PID `10203` 存活，`MainActivity` 为 top-resumed，日志未见 `FATAL EXCEPTION` 或 `AndroidRuntime` 崩溃。验收后已卸载隔离包、确认 ADB reverse 为空，并恢复原新闻 App 前台；未进入 testnode/NodeProbe，也未操作无障碍功能。
- **范围与发布门槛：**这是 arm64 Release 构建、16 KB 二进制静态布局检查和 4 KB 设备冷启动证据；没有 16 KB 真机，不能宣称 16 KB 系统运行通过。正式签名、A3.6 受维护运行时的来源/许可闭包、A4 Node/npm/CLI 生产集成，以及 A5 production Host 完整业务闭环仍未完成。

## 2026-11-26 当前 HEAD `64e6a0d` 非无障碍 app/test 全量回归（18:35 Asia/Shanghai）

- **输入与范围：**在隔离 worktree `/private/tmp/aggregate-a8-head-2b288c3` 的 `2b288c3` 源码上运行；当前 `64e6a0d` 相对该基线的应用代码、测试、Android 工程、pubspec 与提交锁均未变化。测试针对 `app/test` 下 67 个文件排除 `accessibility_test.dart` 后的 66 个文件；主工作区未提交测试和锁文件没有纳入，也没有修改。
- **结果：**`find test -type f -name '*_test.dart' ! -name accessibility_test.dart -print0 | xargs -0 flutter test --no-pub --reporter expanded` 结束为 **370 项通过、5 项失败**。5 项均为 `TargetPlatform.macOS`：玻璃按钮标签对比度、玻璃文本 halo 对比度、减弱动态效果下切换玻璃开关后的文本检查（`StateError: No element`）、v3.5 macOS 工作区几何、宽屏主页面布局。其他用例通过；本轮未运行无障碍/TalkBack 测试，也未操作手机或生产 Host。
- **验收范围：**这补充了当前已提交 Flutter 测试集的完整非无障碍结果，不能称为全套测试通过。失败均来自 macOS 目标；Android 适配的 Release/4 KB 证据见上一节。用户工作区里的 UI 测试更改仍未提交，不能混入本次结论。正式签名、16 KB 真机、A3.6/A4/A5 发布与业务门槛继续开放。

## 2026-11-26 当前 HEAD `5eba508` A8 输入连续性复核

- **输入身份：**当前 HEAD `5eba508b48278dd4dd1299abd510380417dfe69b` 与测试/构建基线 `2b288c3` 的 `app/lib` tree `6d5333503d4b7a0c2c9acfa8ac07d40c9321b4f4`、`app/android` tree `299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`、`app/pubspec.yaml` blob `7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7`、`app/test` 及 `pubspec.lock` blob `2e26f7d400ccc288b9f6b1e82a3969963af1383f` 完全一致。`2b288c3..HEAD` 的这些路径无差异，期间新增提交只涉及文档。
- **证据沿用范围：**因此前两节 arm64 Release/16 KB 静态检查、LGE AN10 4 KB 冷启动与非无障碍 app/test 结果对应当前已提交应用输入。本次只做路径/tree/blob 身份比较，没有重建或重跑测试。主工作区未提交的 macOS 测试和 lock 更改不包括在内。

## 2026-11-26 当前 HEAD `452ffb0` A8 输入延续与非无障碍套件复验

- **产品输入身份：**当前 HEAD `452ffb0dfd1dddfcb8fd8c52ba8f750efd38fa76` 的 `app/lib` tree `cd9b68db3cc4ce08a6cc0d49158c20c73a82ebde`、`app/android` tree `299e8a57fc45f8119dd0caa1b15b4fb3cc0a05f2`、`app/pubspec.yaml` blob `7a73244f5ce3c08e570eb9b92ced96a1bb3e69c7` 与根 `pubspec.lock` blob `2e26f7d400ccc288b9f6b1e82a3969963af1383f` 均与 Release/4 KB 验收基线 `25b405e` 相同；`25b405e..452ffb0` 没有 Android 产品代码、Gradle、manifest、pubspec 或锁文件变化。故 `25b405e` 的产品 APK/AAB（SHA-256 分别为 `3ab47d6ba74c9f7a8507f92cc6660e55a7567a46a7be684205d19ba6c5ca3d0c`、`f4c5fe7c1cad25c4e2fa6eedc3df83ac04356a07d7f721b2fdb605e4fe57b71d`）、16 KB ELF/ZIP 静态检查与 `.integration` 4 KB 真机冷启动证据仍适用于当前已提交 Android 产品输入；本节没有重新构建或安装手机包。
- **当前非无障碍测试：**在提交 `452ffb0` 的隔离 worktree 排除 `test/accessibility_test.dart` 后运行 `app/test` 全集，**373 项通过、4 项失败**。失败包括一项玻璃 halo 对比阈值断言、`macos_reduce_motion_test.dart` 中 live glass switch 文案 `StateError: No element`、`widget_test.dart` 中 macOS 工作区期望宽度 299 实测 280，以及宽屏主页面断言。后三项明确使用 macOS 目标；halo 阈值项是共享 GlassSceneFrame 检查。结果不标记为全绿，也没有将 macOS 用户测试改动带入。
- **边界：**本轮不运行 accessibility/TalkBack 测试，不操作手机或 NodeProbe/testnode。产品 APK/AAB 仍未正式签名；没有 16 KB 真机，不能声明 16 KB 系统运行通过。A3.6 来源/许可闭包与 A5 production Host/配对/RPC 继续开放。工作区未提交的 UI 测试、设计文件及 `pubspec.lock` 改动均不属于本记录。

## 2026-11-26 当前 HEAD `9b7c310` A8 Release 与 4 KB 真机复验

- **输入与隔离：**当前 HEAD `9b7c310c3f7675c96b1d3a8ff6bc6dd20a3e4ceb` 相对 `fca0102` 已有共享 Dart/UI 文件更新，因此在 detached worktree `/tmp/aggregate-a8-current-9b7c310` 按当前提交重新构建。`flutter pub get --enforce-lockfile` 成功，根锁 SHA-256 保持 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`；主工作区未提交的 UI 测试、设计文件与 lock 修改没有纳入。
- **产品工件：**arm64 APK/AAB Release 构建成功，包名 `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、compileSdk 36。APK SHA-256 `fd44e474251543d3ca1bbd81b8f8da05e8a8bb6be2fee79625fa56be250b84ba`；AAB SHA-256 `54d21264ff2d2e693d9ff1dc69d4c5325386ea9e83e15bc049a58e1698920c71`。产品 APK 未签名（`apksigner verify` 返回 `DOES NOT VERIFY`），不视作可发布签名包。
- **16 KB 静态门禁：**Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，`dump config` 报告 `PAGE_ALIGNMENT_16K`。APK/AAB 各有 7 个 arm64 `.so`，各自全部 21 个 `PT_LOAD` 最小 `p_align=16384`，文件偏移与虚拟地址对 16 KB 同余；ZIP CRC 检查通过。产品工件不含 NodeProbe、NodeBridge、`libnode.so` 或 npm 载荷。
- **4 KB 冷启动：**从同一源码构建 `.integration` test-signed Release APK，APK SHA-256 `809389cdf0e953358b12829afa259a4c50c6b79aaa05ba1eaee51fe1d13bde5b`，测试签名证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`；`run_android_release_cold_start.py` 报 `Status: ok`、`LaunchState: COLD`，`MainActivity` 为 resumed，PID `16333` 存活，`WaitTime=1636 ms`。验收脚本已 force-stop 并卸载仅供本轮使用的 `.integration` 包；普通 Aggregate 包安装状态未改变。完成后设备回到系统 Launcher，ADB reverse 为空；未启动 NodeProbe/testnode。
- **代码检查与边界：**`flutter test --no-pub test/connection_setup_target_test.dart` 6/6 通过，`flutter analyze --no-pub` 无问题。无障碍/TalkBack 测试按用户要求排除。没有 16 KB 真机，不能由静态布局推断 16 KB 系统运行通过；产品正式签名、A3.6/A4 运行时发布资格、A5 production Host 和 A6 真实账号/播放闭环仍是发布门槛。

## 2026-11-26 当前 Android Host WSS 安全复扫与单帧修复

- **范围：**Codex Security Standard 只读扫描 `app/`，基线提交 `dcdb1968c043fab9b784cf68bb6aee2189bc792e`，扫描 ID `825e1492-7867-4870-be4e-8052a43d22a5`。当前主线 `4449092994ecd3a3441efa3481472a3fd5e9918f` 相对该基线只修改了 `docs/macos-glass-ui/` 文件，`app/` 输入未改变，因此该发现仍适用于当前 App 源码。扫描没有执行 App、设备、攻击流量或外部服务。
- **发现：低严重度 / 高置信度 CWE-400。**`app/lib/platform/android/android_host_pairing_client.dart:287-292` 的 Android `WebSocket.connect` 没设置 `maxPayloadLength`；当前 Dart 默认上限接近 `int` 最大值。用户扫描攻击者控制的邀请并开始配对后，固定私有 IPv4 WSS 端点可发送超大帧，在 JSON 解码前消耗 App 进程内存并导致崩溃。Mac Host 的 1 MiB 入站上限约束服务端收到的数据，不会限制恶意服务端发给 Android 客户端的出站帧。
- **修复：**共享 WSS 协议新增 `hostWssMaxFrameBytes=1 MiB`；Mac Host 继续使用该同一值限制入站帧，Android `WebSocket.connect` 也设置 `maxPayloadLength`。超限时不把消息交付给上层，既有 TLS pin、子协议、超时及合法 RPC 路径保持不变。
- **验证：**先在未修代码上运行回归用例，合法小帧通过，1 MiB+1 的文本和二进制帧均被交付，测试按预期失败；修复后 `flutter test --no-pub test/android_host_socket_connector_test.dart test/android_host_pairing_client_test.dart` 15/15、`flutter test --no-pub test/host_wss_transport_test.dart test/host_rpc_protocol_test.dart test/android_host_setup_wss_e2e_test.dart` 28/28 通过。覆盖小帧、恰好 1 MiB、超限文本及超限二进制。四个修改/新增 Dart 文件的 `dart analyze` 通过。全量 `flutter analyze --no-pub` 报两个 `avoid_print` info，均位于用户未跟踪文件 `app/lib/preview/ui53_keyboard_probe_main.dart`，没有修改该文件。
- **当时剩余边界：**该次单帧修复没有限制分片消息的总长度。后续处理见“WSS 分片边界闭合”小节。尚无 16 KB 实机，正式签名、生产 Host 与真实音乐链路仍开放。
- **报告：**原始只读扫描报告保留于 `/Users/guo/.codex/state/plugins/codex-security/scans/aggregate-security-dcdb1968/unversioned_20261126T142508Z_tqynfyj3/report.md`。该扫描没有运行 App、设备、攻击流量或外部服务。

## 2026-11-26 WSS 分片边界闭合

- **SDK 行为：**Dart 3.13.7 的 `maxPayloadLength` 检查逐帧执行；非最终数据帧会累积到 `BytesBuilder`，解码器没有跨帧消息总量限制。控制帧与分片消息共用该 builder，因此任意分片还可能影响同一消息的内容。只设置 `maxPayloadLength` 不足以限制总分配。
- **实现策略：**新增共享 `HostWssFrameGuardSocket`，在 Dart WebSocket 解码器读取前解析帧头，要求 FIN、无 RSV 扩展位、正确的 client/server mask、合法控制帧，并对每个数据帧应用 1 MiB 上限。Host WSS 业务消息现在要求单一未压缩数据帧；分片文本和二进制消息会在载荷转交前关闭连接。Android 侧保留证书 pin、TLS 有效期/目标校验、HTTP 101/`Sec-WebSocket-Accept`/子协议校验、禁用重定向与压缩；Mac Host 继续先校验原有 Upgrade/路径/Origin/子协议/连接配额，再进行受限升级。`WebSocket.fromUpgradedSocket` 的 `maxPayloadLength` 仍作为第二层检查。
- **兼容约束：**RFC 6455 允许把一条消息拆成多个帧；本项目 Host WSS 现在明确收紧为每条文本/二进制消息一个完整帧。当前 Dart 客户端和 Host 服务都按 `WebSocket.add` 逐条发送完整 RPC 消息，互通回归通过。未来若加入会主动分片的第三方 WSS 对端，必须先实现有界的分片重组器再放宽策略。
- **验证：**`flutter test --no-pub test/android_host_socket_connector_test.dart test/android_host_pairing_client_test.dart test/host_wss_transport_test.dart test/host_rpc_protocol_test.dart test/android_host_setup_wss_e2e_test.dart` 49/49 通过；覆盖小帧、1 MiB 边界、超限文本/二进制、错误 `Sec-WebSocket-Accept`、错误子协议、TLS pin 不匹配、Android 收到分片、Mac Host 收到分片、配对与只读/设置 RPC。六个修改 Dart 文件的格式检查和定向 `dart analyze` 通过；`flutter analyze --no-pub` 无问题；`flutter build apk --debug --no-pub` 成功。
- **实机边界：**本次 WSS 原始帧回归在本机 loopback TLS 上运行，未安装或操作手机。4 KB 真机已有此前的冷启动/运行时证据，本次没有重新测真机 WSS；没有 16 KB 页设备，不能据此声称 16 KB 系统运行通过。A5 production Host/配对、正式签名与真实音乐链路仍开放。

## 2026-11-26 当前 HEAD `d8c82b0` Release 静态与 4 KB 真机复验

- **输入与隔离：**在 detached worktree `/tmp/aggregate-a8-current-d8c82b0` 验证提交 `d8c82b03ba7315266cba81a47856d56679d39854`，主工作区 UI 测试、设计文件、`pubspec.lock` 和失败工件均未进入构建。默认 Pub mirror 下 `flutter pub get --enforce-lockfile` 试图重解析并拒绝已提交锁；显式 `PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 成功，锁 SHA-256 为 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`。
- **产品 Release 工件：**arm64 APK/AAB 分别由 `flutter build apk --release --no-pub --target-platform android-arm64` 与 `flutter build appbundle --release --no-pub --target-platform android-arm64` 构建成功。APK 27,845,300 bytes、SHA-256 `337448549b75a4cc3ddd3a8cd68ac85cec5ab7840604d6568cdfe72c991c969b`；AAB 25,578,143 bytes、SHA-256 `e6649b6b7b9d2518296161ac469a383502fe7f4a310c1b74b678eb7912f7ff84`。aapt 报告 `io.github.guog962464.aggregate`、versionCode 8/versionName 0.3.7、minSdk 24、target/compileSdk 36、arm64-v8a。
- **静态 16 KB 门禁：**Build Tools 36.0.0 对 APK 执行 `zipalign -c -P 16 4` 通过。APK/AAB ZIP CRC 通过，各含 7 个 arm64 `.so` 和 21 个 `PT_LOAD`；NDK r28.2.13676358 检查的段最小 `p_align=16384`，file offset 与 virtual address 对 16 KB 同余。官方 Bundletool 1.18.3（SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`）`validate` 通过，AAB `dump config` 为 `PAGE_ALIGNMENT_16K`。两个产品包均不含 NodeProbe、NodeBridge、`libnode.so` 或 npm `node_modules`；产品 APK 的 `apksigner verify` 为 `DOES NOT VERIFY`，AAB 无签名条目，不能作为正式签名发布包。
- **4 KB 真机冷启动：**以 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter build apk --release --no-pub --target-platform android-arm64 --build-number=10` 构建隔离包 `io.github.guog962464.aggregate.integration`，versionCode 10，大小 27,853,504 bytes、SHA-256 `7c4222356a10096ec66950b63f01528652dbf92a7dd89f7f0184fb5e66232a44`；测试证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`，APK v2 签名与 16 KB zipalign 检查通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上 runner 返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 1216 ms`；3 秒检查时进程 PID `29289` 存活且 `MainActivity` resumed。runner 仅卸载本轮 `.integration` 包；之后手机回到 HONOR Launcher，ADB reverse 列表为空。运行后普通 `io.github.guog962464.aggregate` 未安装；运行前未检查其安装状态，因此不推断其此前状态。
- **源码验收与边界：**以提交锁在同一 worktree 重新运行 WSS connector、pairing、Host transport、RPC 与 WSS e2e 5 组测试，49/49 通过；`flutter analyze --no-pub` 无问题。此次真机只验证 4 KB 页冷启动，不验证 WSS 局域网、生产 Host、正式签名升级、音乐账号/播放或 16 KB 页运行。16 KB 实机与正式签名身份仍是 A8 发布门槛；A3.6/A4 产品运行时资格、A5 当前 production Host/配对/RPC、A6 音乐闭环仍开放。

## 2026-11-27 当前 HEAD `7b0ea25` A8 Release 静态与 4 KB 真机复验

- **输入与隔离：**在 detached worktree `/private/tmp/aggregate-a8-current-7b0ea25` 验证提交 `7b0ea256a6e14f94c815ed1d354d84ef1bd7ae62`，未包含主工作区未提交的 macOS UI、测试、设计文件和 `pubspec.lock`。该提交相对 `d8c82b0` 的 Android 构建输入没有变化；共享 Flutter 代码唯一变化是 `settings_page.dart` 中只供 macOS `_buildMacSettings` 使用的外观开关标定，Android 仍走 `_buildStandardSettings`。`PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` 成功，提交锁 SHA-256 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87` 且未改变。
- **源码回归：**`flutter analyze --no-pub` 无问题；当前提交重跑 WSS connector、pairing、Host transport、RPC 与 WSS e2e 五组定向测试，49/49 通过。
- **产品 Release：**arm64 APK/AAB 构建成功，分别为 20,578,499 bytes / SHA-256 `0da1424ea7df75ad9ca4dfbe82f65ff39fd248a1f758dc568107a03524b0aa09` 与 20,091,474 bytes / SHA-256 `eb34bd583a22b0b3274198fa8321b05823281e9e4187eba985807dda5341659a`。包名 `io.github.guog962464.aggregate`，versionCode 8/versionName 0.3.7，minSdk 24、target/compileSdk 36。两包 ZIP CRC 通过；APK `zipalign -c -P 16 4` 通过；NDK r28.2.13676358 `llvm-readelf` 对 APK 与 AAB 的 3 个 arm64 `.so`、共 9 个 `PT_LOAD` 分别核验通过，最小 `p_align=16384` 且 offset 与 virtual address 对 16 KB 同余。Bundletool 1.18.3 `validate` 通过，AAB `dump config` 为 `PAGE_ALIGNMENT_16K`。两包均不含 NodeProbe、NodeBridge、`libnode.so`、npm CLI 或 `node_modules`。产品 APK `apksigner verify` 报 `DOES NOT VERIFY`，AAB 没有签名条目；二者都不是正式签名发布包。
- **4 KB 真机冷启动：**隔离 test-signed `.integration` Release APK SHA-256 `229776a326fab8817f1e9348a962cfbf59935bd85449966ab11008f9eaabf869`，versionCode 10，Android Debug test signer 证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`；v2 验签及 16 KB zipalign 通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上，`run_android_release_cold_start.py` 返回 `Status: ok`、`LaunchState: COLD`、`WaitTime: 727 ms`；3 秒后 PID `11799` 存活且 `MainActivity` resumed。runner 验收后卸载仅属本轮的 `.integration` 包；回读确认手机在 HONOR Launcher、验收包/普通 Aggregate 包均未安装、ADB reverse 为空，没有 NodeProbe/testnode 进程。
- **边界：**本轮证明当前提交的 Release 构建、16 KB 静态对齐与 4 KB 真机冷启动，不证明 16 KB 页系统执行。16 KB 实体设备不可用；正式签名仍缺发布密钥。A3.6/A4 运行时来源与产品能力、A5 production Host/直连/NSD/配对/RPC、A6 真实音乐账号与播放继续开放。TalkBack/accessibility 按用户决定排除。

## 2026-11-27 当前 HEAD `85863f3` A8 Release 静态与 4 KB 真机复验

- **输入与隔离：**在 detached worktree `/tmp/aggregate-a8-current-85863f3` 验收提交 `85863f39adac450eeb834f5625dcbd017b1073af`。与上一 A8 基线相比，当前共享 Flutter UI 与 Android Host pairing client 已有源码变化，因此从当前精确提交重新构建；未带入主工作区未提交的 UI 测试、设计稿和 `pubspec.lock` 修改。`PUB_HOSTED_URL=https://pub.dev flutter pub get --enforce-lockfile` 成功，根锁 SHA-256 保持 `7f704955c1899793bc2f3bc5a5a71c6d27b8756e19b62e61f650a43e0bf05e87`；`flutter analyze --no-pub` 报 `No issues found!`。
- **非无障碍测试：**显式排除 accessibility 测试后，app/test 套件结果为 **386 项通过、4 项失败**。四项都是 macOS UI 断言：玻璃主题动画、v3.5 工作区几何、宽屏设置页和宽屏主页面。结果不记为全绿；本轮没有运行 accessibility/TalkBack 测试。
- **产品 Release 工件：**arm64 APK/AAB 构建成功。APK 27,847,624 bytes，SHA-256 `df5e551c4fccb1b6e1091b0d1e78664776de003d5928a6db55a7b4a61860c436`；AAB 25,576,371 bytes，SHA-256 `c8963c1715452ea9a6045ca59f127a85bdd056e92466c367b4aa701bc761a532`。包名 `io.github.guog962464.aggregate`，versionCode 8/versionName 0.3.7、minSdk 24、target/compileSdk 36。APK/AAB ZIP CRC 与 Build Tools 36.0.0 `zipalign -c -P 16 4` 检查通过；Bundletool 1.18.3 `validate` 通过且 `dump config` 为 `PAGE_ALIGNMENT_16K`。两种工件都包含相同的 7 个 arm64 DSO；NDK r28.2.13676358 `llvm-readelf` 检查的所有 `PT_LOAD` 均满足 `p_align >= 0x4000` 且文件偏移/虚拟地址对 16 KB 同余。APK `apksigner verify` 显示缺少 `META-INF/MANIFEST.MF`，AAB `jarsigner` 显示未签名；两者均不是正式签名发布包。
- **4 KB 真机冷启动：**用同一源码构建隔离 `.integration` Release APK，versionCode 10、27,855,828 bytes、SHA-256 `a7aa774c67a8fbdf5ecc1cbea3b9237ee362675f5b61cfdbb9002bb29b367a06`；Android Debug 测试证书 SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`，v2 验签与 16 KB zipalign 检查通过。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 上，`run_android_release_cold_start.py` 报 `Status: ok`、`LaunchState: COLD`、`TotalTime: 1658 ms`，PID `16729` 存活且 `MainActivity` resumed。脚本卸载了仅供本轮使用的 `.integration` 包；原版 Aggregate versionCode 8 仍安装，手机回到 Launcher，ADB reverse 为空，无 NodeProbe/testnode 进程。
- **边界：**这是当前提交的 Release 构建、静态 16 KB 检查和 4 KB 真机冷启动证据，不证明 16 KB 系统实机运行，也不覆盖 npm/CLI、生产 Host、音乐账号播放等流程。当前没有 16 KB 真机或正式签名密钥；A3.6 来源/许可闭包、A4 产品运行时、A5 production Host 配对/RPC、A6 真实账号/播放及 A8 正式签名/16 KB 实机仍开放。无障碍/TalkBack 按用户决定排除。

## 2026-11-27 A8 current Flutter shared UI Release rebuild (HEAD `22d23ff`)

- **Source and dependency scope:** Built the current product tree at HEAD `22d23ff7531a2165e0a05613c6d569be5fdeb4fe`. The current committed shared `PageFrame`/Settings changes are included. There were no uncommitted `app/lib` or Android source changes; the root `pubspec.lock` was user-modified and left untouched. Both Flutter commands used `--no-pub`, so package resolution was not rerun and the existing package configuration was used.
- **Analyze and build:** `flutter analyze --no-pub lib` reported no issues. `flutter build apk --release --no-pub --target-platform android-arm64` and the matching `flutter build appbundle --release --no-pub --target-platform android-arm64` both succeeded. `aapt` reports `io.github.guog962464.aggregate`, versionCode 8, versionName 0.3.7, minSdk 24, target/compileSdk 36; both artifacts contain arm64-v8a only.
- **Artifacts:** APK `app/build/app/outputs/flutter-apk/app-release.apk`, 27,847,624 bytes, SHA-256 `00baf783215d9ff1424fd92d8dbab7d564045264d496a4cef2b6888de69052d6`. AAB `app/build/app/outputs/bundle/release/app-release.aab`, 25,581,209 bytes, SHA-256 `79d5c07c3a93786436e1b66d7a01f044b5032cb1fd2fcb11023b0a135042b07b`.
- **Static 16 KB gates:** ZIP CRC checks passed. Build Tools 36.0.0 `zipalign -c -P 16 4` passed for the APK. Each archive contains the same 7 arm64 shared libraries with 21 `PT_LOAD` segments; all satisfy `p_align >= 0x4000` and file-offset/virtual-address congruence modulo 16 KB. `libapp.so` and `libflutter.so` use 64 KB alignment; the other five libraries use 16 KB. Official Bundletool 1.18.3 JAR SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29` passed `validate`; `dump config` reports `PAGE_ALIGNMENT_16K`.
- **Payload and signing:** Neither artifact contains NodeProbe, NodeBridge, `libnode.so`, nodejs-mobile or npm `node_modules`. APK and AAB have no product signing entries; `apksigner` does not verify the APK and `jarsigner` reports the AAB is unsigned. These are unsigned product Release artifacts, not distribution-ready signed packages.
- **Device boundary at initial rebuild:** ADB was disconnected during the static build, so the product artifacts were not launched at that point. The later 4 KB isolated Release cold-start recheck against the same HEAD is recorded below and supersedes the earlier “not rerun” status. No 16 KB physical device is available; 16 KB system runtime and production signing remain open.

## 2026-11-27 A8 current `22d23ff` isolated Release 4 KB cold-start recheck

- **Artifact:** Built the isolated `.integration` Release APK from the same source using `flutter build apk --release --no-pub --target-platform android-arm64 --android-project-arg=aggregateIsolatedIntegration=true`. Package `io.github.guog962464.aggregate.integration`, versionCode 8/versionName 0.3.7, minSdk 24, targetSdk 36, arm64-v8a; 27,855,828 bytes, SHA-256 `8b0261a3e1e61bc5e930d98361b9ae984b0042b62f007c81bf09a0b32c54c07d`. Android Debug test certificate SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`; `apksigner verify` and Build Tools 36.0.0 `zipalign -c -P 16 4` passed.
- **Device:** On LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`, `run_android_release_cold_start.py` returned `Status: ok`, `LaunchState: COLD`, `TotalTime: 1400 ms`; PID `12838` remained alive and `MainActivity` resumed. The runner uninstalled only the `.integration` package. Afterwards `pm path` found no integration package, `adb reverse --list` was empty, no NodeProbe/testnode/Aggregate process remained, and the prior `hg.zp.mengnews/...SubmitCommunityVideoActivity` foreground resumed.
- **Product artifact restoration:** Rebuilt the unsigned product APK after the isolated run. Its SHA-256 returned to `00baf783215d9ff1424fd92d8dbab7d564045264d496a4cef2b6888de69052d6`; the product AAB remained `79d5c07c3a93786436e1b66d7a01f044b5032cb1fd2fcb11023b0a135042b07b`. Product APK package name and arm64 ABI were rechecked; APK 16 KB zipalign passed.
- **Acceptance boundary:** This is one isolated test-signed 4 KB startup check, not production signing or 16 KB hardware validation. No 16 KB device is available. The run checked startup/process survival only, not visual screen-state behavior or Node/npm/CLI, production Host, account, or playback workflows. A8 remains open for formal signing and 16 KB physical runtime.

## 2026-11-27 A8 production signing configuration availability

- **Configuration check:** At repository HEAD `1ec46fc9c2fe1dd3b752df03b2cf274acadbc053`, `app/android/app/build.gradle.kts` explicitly leaves the product Release unsigned until a separately managed production signing configuration is supplied. Only the isolated `.integration` variant selects the local Android debug key.
- **Local files:** A filename-only search under `app/android` found no `key.properties`, `.jks`, `.keystore`, or `.p12` signing material. No secret values or keystore contents were read.
- **Result and boundary:** A formal product signature cannot be produced from the current repository configuration. No new signing key was generated and no test key was substituted. Product APK/AAB remain unsigned; this is an observed configuration prerequisite, not an Android build failure. A8 formal signing and 16 KB physical-device execution remain open.
