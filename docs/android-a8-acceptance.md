# Android A8 发布前检查与文档验收

> 检查日期：2026-11-14。A8.4 安全修复、Release 构建检查及 A8.5 内部指南已完成；Android 仍未达到分发验收：缺少正式签名身份、16 KB 页真机及生产 Host/音乐闭环。Android 仍是实验目标，仓库当前产品发布目标为 macOS。

## A8.4 安全、依赖与分发检查

### 检查范围与方法

此前 Codex Security Standard 扫描目标修订为 `a5dde7507e268c7079b1eea63058636bbe4ed665`，覆盖 Android/Flutter Runtime、配对 Mac Host、Node/npm 探针、密钥/日志、构建与分发配置。该工作台扫描 ID `be3aab55-1467-4e8c-b571-0a56f577389d` 最终标记为 failed，不能作为无漏洞结论。本轮工作树差异审查 ID `96cfdbea-0984-4bc6-8ea5-0e45608ad884` 已完成：审阅 92 项源文件 inventory，0 项可报告漏洞；覆盖状态为 partial，保留外部 HTTPS 当前版本复验、MCP 并发/超时取消语义、Host 账本恢复三个后续问题。审查针对 base `bd8034286ac168c596def1f09ab3960ce01d4e0e` 的冻结工作树快照，不是全仓库审计，也不能替代 16 KB 设备或生产服务验收。没有正式签名的 Android Release，也没有 16 KB 页实体设备。

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
| A8SEC-2 | 中 | **攻击放大路径已修复，账本容量仍有限。** 已配对且获 `connectionSetup` 的设备对不存在/过期草稿执行 `setup.discard` 时直接返回幂等成功，不写持久 operation ledger；200 个不同 operation ID 回归测试确认不创建记录。真实授权 mutation 仍受全 Host 共享的 10,000 条/4 MiB 硬上限约束，达到上限后新 mutation 安全失败；没有自动压缩或专门管理员恢复 UI。该剩余容量限制应在上线前纳入 Host 管理与恢复设计。 |
| A8SEC-3 | 低 | **已缓解并覆盖边界测试。** Android MCP HTTP transport 在 JSON/SSE 解码前限制每个响应 8 MiB、取消超限流并拒绝重定向。发现层限制每类最多 20 页、总能力 1,000 个、目录总量 4 MiB、schema 256 KiB、字段 16 KiB、cursor 4 KiB、提示参数 64 个。自动化测试覆盖 1,001 个工具目录拒绝；LGE AN10 真机返回 8 MiB+1 响应时在解码前被拒绝。 |

A8SEC-1 与 A8SEC-3 的对应风险路径已封闭到上述范围；A8SEC-2 的不存在草稿放大方式已移除，Host 全局账本仍保留有限容量。其它经核对不作为本次漏洞报告：Host stdio 启动受已授权 `connectionSetup` 权限约束；Host 内容读取受配对和逐连接授权约束；npm audit 命中的是独立 Debug fixture；Release 签名身份、16 KB 实机及真实服务闭环仍未完成。

差异审查对 HTTP 响应包装流中的错误完成行为曾记录一个候选：如果下游收到错误但继续监听，原实现不会发出结束事件。逐条检查 `mcp_dart` JSON/SSE 消费路径后确认产品当前消费者会在错误后终止或取消订阅，因此该候选不构成可达安全漏洞。审查快照之后，仍修正了包装层的通用 Stream 语义，并新增回归用例验证错误、后续数据和 `onDone` 均按源流顺序传递；这项修正由后续本地测试验收，不属于上述冻结快照。

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

- Flutter 全量测试：208 项通过，包含 HTTP 包装流错误后继续传递数据和 `onDone` 的回归用例。
- `flutter analyze --no-pub`：无问题。
- Dart format、公共层边界检查、15 项共享包测试：通过。
- Android arm64 Debug APK、Release APK/AAB 与 macOS Debug 构建：通过；macOS 构建有 `mobile_scanner` 使用 macOS 10.15 弃用 API 的既有编译警告。
- Bundletool 1.18.3 `validate`、APK `zipalign -P 16`、Release APK/AAB 内 7 个 arm64 原生库的 16 KB ELF `PT_LOAD` 检查：通过。Release 工件未签名；无正式签名身份。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机：HTTP MCP 集成文件 4 项通过、外部 HTTPS 用例因未设置环境变量跳过。测试后主包被移除，已重装 versionCode 12 Debug APK 并启动。第一次未隔离集成测试删除了旧 versionCode 11 App 数据及旧 Android Keystore 配对身份；隔离后缀也未能保证主包留存。重装后未重新建立 Host 配对；后续未再运行会安装/卸载 App 的真机集成命令。未使用模拟器。
- HTTP 包装流修正发生在差异扫描快照封存之后；本地测试覆盖了修正，但扫描报告不包含该后续变更。
- 用户已有 root `pubspec.lock` 镜像 URL 改动保持未暂存；任务只提交 MCP path override 对应 lock hunk。
