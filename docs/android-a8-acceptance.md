# Android A8 发布前检查与文档验收

> 检查日期：2026-11-14。A8.4 安全修复、Release 构建检查及 A8.5 内部指南已完成；Android 仍未达到分发验收：缺少正式签名身份、16 KB 页真机及生产 Host/音乐闭环。Android 仍是实验目标，仓库当前产品发布目标为 macOS。

## A8.4 安全、依赖与分发检查

### 检查范围与方法

此前 Codex Security Standard 扫描目标修订为 `a5dde7507e268c7079b1eea63058636bbe4ed665`，覆盖 Android/Flutter Runtime、配对 Mac Host、Node/npm 探针、密钥/日志、构建与分发配置。该工作台扫描 ID `be3aab55-1467-4e8c-b571-0a56f577389d` 最终标记为 failed，不能作为无漏洞结论。本轮工作树差异审查 ID `96cfdbea-0984-4bc6-8ea5-0e45608ad884` 已完成：审阅 92 项源文件 inventory，0 项可报告漏洞；覆盖状态为 partial。原报告保留外部 HTTPS 当前版本复验、MCP 并发/超时取消语义、Host 账本恢复三个后续问题。扫描快照之后，本轮增加了 Android 全局 POST 并发上限和协议级请求 deadline/HTTP abort 回归测试，并补充 Host 账本人工恢复流程；这些后续材料不属于原报告覆盖。扫描针对 base `bd8034286ac168c596def1f09ab3960ce01d4e0e` 的冻结工作树快照，不是全仓库审计，也不能替代 16 KB 设备或生产服务验收。没有正式签名的 Android Release，也没有 16 KB 页实体设备。

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
| A8SEC-2 | 中 | **攻击放大路径已修复，账本容量仍有限。** 已配对且获 `connectionSetup` 的设备对不存在/过期草稿执行 `setup.discard` 时直接返回幂等成功，不写持久 operation ledger；200 个不同 operation ID 回归测试确认不创建记录。真实授权 mutation 仍受全 Host 共享的 10,000 条/4 MiB 硬上限约束，达到上限后新 mutation 安全失败。下方定义了人工恢复步骤；操作流程尚未在生产 Host 演练，没有自动压缩或管理员恢复 UI。 |
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

旧 Codex Security 扫描 ID `be3aab55-1467-4e8c-b571-0a56f577389d` 最终为 failed，其 0 findings 不能作为无风险结论。本轮差异扫描 ID `96cfdbea-0984-4bc6-8ea5-0e45608ad884` 已正常完成并生成报告；报告路径见工作区外的 Codex Security scan artifacts。它没有验证 16 KB 设备行为或外部 HTTPS 本轮实机闭环。

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
- A7/A8.1–A8.3 已记录 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机的安装、运行、HTTP MCP、配对、UI/IME、生命周期及存储验证。本轮 Android HTTP MCP Integration Test 文件 4 项通过，外部 HTTPS 用例因未设置 `A2_EXTERNAL_MCP_URL` 跳过。没有 16 KB 真机、TalkBack 服务、生产 Host LAN/Bonjour、实际音乐账号或签名 Release；这些项目仍未验收。

## 本轮验证

- Flutter 全量测试：211 项通过，包含 HTTP 包装流错误后继续传递数据和 `onDone`、跨会话并发上限、timeout 后请求 abort 的回归用例。
- `flutter analyze --no-pub`：无问题。
- Dart format、公共层边界检查、15 项共享包测试：通过。
- Android arm64 Debug APK、Release APK/AAB 与 macOS Debug 构建：通过；macOS 构建有 `mobile_scanner` 使用 macOS 10.15 弃用 API 的既有编译警告。
- Bundletool 1.18.3 `validate`、APK `zipalign -P 16`、Release APK/AAB 内 7 个 arm64 原生库的 16 KB ELF `PT_LOAD` 检查：通过。Release 工件未签名；无正式签名身份。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机：HTTP MCP 集成文件 4 项通过、外部 HTTPS 用例因未设置环境变量跳过。测试后主包被移除，已重装 versionCode 12 Debug APK 并启动。第一次未隔离集成测试删除了旧 versionCode 11 App 数据及旧 Android Keystore 配对身份；隔离后缀也未能保证主包留存。重装后未重新建立 Host 配对；后续未再运行会安装/卸载 App 的真机集成命令。未使用模拟器。
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
- **范围：**本节证明当前 Debug APK 在这台 4 KB 设备的安装/冷启动，以及包内原生库的 16 KB 静态对齐。没有运行产品 Release，也没有正式签名或 16 KB 系统设备；静态对齐不表示 16 KB 系统实机兼容。TalkBack、production Host 业务和音乐闭环仍未验收。`pubspec.lock` 的工作区修改未暂存；构建未执行 pub 解析。ADB reverse 为空，Host 47321/47322 无监听。
