# Android A8 发布前检查与文档验收

> 检查日期：2026-11-14。A8.4 安全/发行审查及 A8.5 内部指南已完成；Android Release 验收未通过。Android 仍是实验目标，仓库当前产品发布目标为 macOS。

## A8.4 安全、依赖与分发检查

### 检查范围与方法

Codex Security Standard 扫描目标修订为 `a5dde7507e268c7079b1eea63058636bbe4ed665`，覆盖 Android/Flutter Runtime、配对 Mac Host、Node/npm 探针、密钥/日志、构建与分发配置。重点安全路径及调用关系经过源代码审查；跟踪库存为 363 个文件，图像等非可执行资产不作为源代码检查。扫描结论不声称对全部 363 个文件逐行人工审计。没有生产 Android Release 工件，也没有 16 KB 页实体设备。扫描工作台 ID：`be3aab55-1467-4e8c-b571-0a56f577389d`；扫描最终标记为 failed，未保存这三项审查发现到工作台。

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
| 主 App Debug APK：`app/build/app/outputs/flutter-apk/app-debug.apk` | 99,506,706 bytes | `apksigner` 验证通过，使用 Android Debug 证书；仅内部测试 |
| 独立 NodeProbe Debug APK：`app/build/nodeprobe/outputs/apk/debug/nodeprobe-debug.apk` | 290,622,972 bytes | Android Debug 证书；包含实验运行时，不是主 App 产品包 |
| 独立 NodeProbe Debug AAB：`app/build/nodeprobe/outputs/bundle/debug/nodeprobe-debug.aab` | 39,012,187 bytes | Debug 探针 Bundle，不是发布 AAB |

主 App 没有可供验收的 Release APK/AAB。当前 `app/android/app/build.gradle.kts` 显式将 Release signingConfig 指向 Debug 签名。`flutter build apk --release --no-pub` 在 `:app:compileReleaseJavaWithJavac` 失败：生成的 `GeneratedPluginRegistrant.java` 引用了 Release compile classpath 不包含的 `integration_test`。`flutter pub get --offline --enforce-lockfile` 后重试仍失败，且用户现有 `pubspec.lock` 字节未改变。不能把 Debug 签名或未生成的 Release 文件称作发布签名验收通过。Android 官方说明 Debug 证书不适于多数商店发布。[Android app signing](https://developer.android.com/studio/publish/app-signing)

A8.2 的普通 arm64 APK 与固定 Node Debug 探针原生库通过 ELF 16 KB 对齐检查和 `zipalign -P 16`；手头 LGE AN10 实机仍为 4 KB 页。未有 16 KB 页设备，不能声明 16 KB 系统运行通过。Android 官方指南列出面向 API 35+ 应用的 Play 适配时限为 2027-02-01；正式发行前应复核最新日期并在 16 KB 环境做运行验收。[Android 16 KB page-size guidance](https://developer.android.com/guide/practices/page-sizes)

### 仍需处理的安全发现

以下发现来自源代码审查，本轮只记录和分级，未修改运行时行为：

| ID | 严重性 | 影响与条件 | 发行前处理 |
| --- | --- | --- | --- |
| A8SEC-1 | 中 | Android 接受非回环 HTTP MCP；只有新建连接中带临时 Bearer Token 时才拒绝远程 HTTP。选择此类地址后，请求和返回数据可被同网段观察或篡改。用户需主动配置该端点；回环 HTTP 有本机服务用途。 | 对非回环明文 HTTP 默认拒绝，或在 UI 显示明确风险并要求确认；保存凭证后的重载连接也使用同一 TLS 校验。 |
| A8SEC-2 | 中 | 已批准且含 `connectionSetup` scope 的配对设备可发出大量不同 `setup.discard` operation ID；即使草稿不存在，也会经共享 Host operation ledger 写入持久记录。账本达到 10,000 条或 4 MiB 后，Host 新 mutation 返回 `operationLedgerFull`，影响所有配对设备。需要有效配对和授权，非未认证远程攻击。 | 加每设备/方法配额；在保留重放/结果未知语义的前提下实现安全压缩/保留策略，并定义管理员恢复方式。 |
| A8SEC-3 | 低 | 已配置的恶意或被攻陷 MCP Server 可返回超大发现页/schema/工具结果。HTTP transport 会把完整响应流 join 后再 JSON decode；调用层的分页上限限制页数，没有限制响应字节、单页条数或总结果大小，预览截断发生在解析/序列化之后，可能耗尽内存或卡死 App。 | 在传输层限制响应字节；限制工具/资源/提示及 schema 数量/长度；在解码、图片转换、预览前限制 MCP 结果体积。 |

修复或完成经审查的风险例外后，才可撤销对应 Android 发行阻塞。其他经核对不作为本次漏洞报告：Host stdio 启动受用户明确授予的 `connectionSetup` 权限约束；Host 内容读取受配对和逐连接授权约束；npm audit 命中的是独立 Debug fixture；Debug 签名和 `integration_test` 构建错误属于当前发行阻塞。

Codex Security 工作台扫描 ID 为 `be3aab55-1467-4e8c-b571-0a56f577389d`；最终语义草稿因原有候选项未关联到报告发现/处置而被工作台拒绝，达到允许的纠正提交次数后，扫描被标记为 failed。工作台生成了一份失败状态报告，但该报告包含 0 项保留发现并明确说明不能由此得出无漏洞结论。**不要把该工作台扫描状态视为通过或已封存。**以上三项源代码审查发现及证据保存在本验收文档中；如后续需要有效的工作台扫描报告，应启动新扫描并按候选 ID 逐项关联发现/处置。

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
- A7/A8.1–A8.3 已记录 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机的安装、运行、HTTP MCP、配对、UI/IME、生命周期及存储验证。没有 16 KB 真机、TalkBack 服务、生产 Host LAN/Bonjour、实际音乐账号和真实 Android Release 包；这些项目仍未验收。

## 本轮验证

- Flutter 全量测试：200 项通过。
- `flutter analyze --no-pub`：无问题。
- `flutter pub get --offline --enforce-lockfile`：成功，未改动已有 `pubspec.lock`。
- 主 App Release APK：未通过；失败原因见上文 `integration_test` 注册表错误。无 Release AAB 可签名或测量。
- 本机 Android Debug APK 构建、签名与工件尺寸：已核对；Debug 签名不等同发布身份。
- A8.2 静态 16 KB ELF/ZIP 对齐：沿用已归档证据；没有可补做的 16 KB 实机运行验证。
- 未使用模拟器。
