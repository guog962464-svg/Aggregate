# A5.4 Android 配对客户端与真机验收

记录日期：2026-11-13；2026-11-14 补充直接 LAN/NSD 真机验收。USB ADB 反向转发下的首次配对/批准与同网段下已授权设备的直连验收分别记录，覆盖范围不同。

## 实现

- Flutter 设置页新增 Android 专属 Host 面板：按需打开后置相机扫描邀请二维码，也可粘贴邀请；显示 Mac Host、短期确认码和配对状态；保存多个 Mac、连接/断开或移除本地记录。摄像头只在用户点扫描时请求，手动粘贴可作为权限拒绝时的替代入口。Android UI 仍由 Flutter 构建。
- `AndroidHostPairingClient` 严格校验二维码 schema、有效期、Host/service 标识和地址；拒绝明文 WS、非私有/loopback IPv4、意外 path、用户信息、query/fragment、重复地址和超大 payload。WSS 只接受匹配邀请内 SHA-256 DER 指纹的证书，并检查证书有效期、主机名和端口。
- 配对申请、challenge 认证及每条 RPC 都使用 Android Keystore P-256 私钥签名。私钥不会返回 Dart；TLS pin、Mac Host ID 和 `host.hello` 身份会在连接后再次校验。协议错误、审批等待、撤销和 pin 错误映射为可见状态，连接关闭时清除 session。
- `AndroidHostManager` 将 Host 公钥身份元数据、证书 pin、私有端点和连接时间保存在 app-private `hosts.json`；不保存签名私钥或运行 session。损坏索引采用安全恢复策略。删除只清本地记录，Mac 端授权仍由 Mac 设置撤销。
- 生产 Host 使用固定 WSS 端口 `47321`，Bonjour DNS-SD TXT 带完整稳定 Host ID。Android Kotlin NSD bridge 根据该 ID resolve 服务并刷新私有 IPv4 地址；Dart 侧校验发现结果，发现不可用时保留二维码端点作为回退。
- NSD 地址 resolve 串行执行；4.5 秒总超时会确定返回已发现的地址，并通过 generation token 忽略停止发现后的迟到 callback，避免单个 NSD 回调永久挂起配对设置流程。

## 验收结果

| 项目 | 结果与范围 |
| --- | --- |
| Flutter 自动化 | `flutter test --no-pub --reporter expanded`：134 项通过。覆盖邀请输入、签名/auth/RPC 流程（fake transport 与 identity）、Host 持久化、发现结果校验及设置 UI。 |
| 静态分析 | `flutter analyze --no-pub`：无问题。`git diff --check`：通过。 |
| Debug 构建 | `flutter build apk --debug --no-pub --target-platform android-arm64` 与 `flutter build macos --debug --no-pub`：通过。 |
| APK 原生库 | Build Tools 36.0.0 `zipalign -c -P 16 4` 通过。包内 7 个 `.so` 均属于 `arm64-v8a`，逐个 `PT_LOAD p_align` 最小值不低于 `0x4000`。这是 Debug APK 静态检查，不是 16 KB 内核运行结果。 |
| Android 真机 | LGE AN10、Android 15/API 35、arm64、4 KB 页：安装更新后的 APK 并启动 `MainActivity` 成功；先前相机扫描 UI 打开验收已通过。本轮结束后已撤销 CAMERA 运行权限，恢复为未授权状态。未使用模拟器。 |
| Android ↔ Mac Host 真机配对 | 通过 USB ADB 反向转发完成。为适配手机与 Mac 的 LAN/VPN 隔离，测试邀请只把端点改为 `wss://127.0.0.1:47321/host`；Host ID、证书 SHA-256 pin、nonce 和有效期保持原值。Mac Host 收到 Android Keystore 签名请求，验证码与两端一致；Mac UI 以“批准只读”授权后，Android 完成 challenge 认证和 `host.hello`，保存 Host 并显示已连接。断开后通过保存记录重连成功。此路径真实使用 Android Keystore 与 Mac CryptoKit，但经 USB 隧道，不覆盖直接 LAN 或 DNS-SD。 |
| Android ↔ Mac Host 直接 LAN / Bonjour NSD（2026-11-14） | 同一可互通局域网，使用 Mac 原样生成的短时邀请，在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机上先后验证已授权手机和隔离的新 Android App 身份。新身份通过独立 `.integration` 包名及 Android Keystore 创建：Android 原生 NSD 发现 1 个与邀请匹配的端点；直连 WSS 提交配对申请，Mac 用户只批准“读取连接”；challenge 认证及 `host.hello` 成功，随后只调用 `connection.list` 并返回 1 项“网易云音乐”。撤销该临时 grant 后再次认证被 Mac 以 unauthorized 拒绝，Android 映射为 `approvalRequired`。另在隔离包验证真实 Android Keystore 别名轮换；随后短暂关闭并恢复 Android Wi-Fi，NSD 重新发现 1 个 Host endpoint，WSS 重新认证和只读 `connection.list` 成功。没有调用其他 Host RPC；没有轮换日常 App 身份。 |
| Android Keystore 身份隔离复验（2026-11-14） | LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页。先用 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true` 构建，再以 `aapt dump badging` 确认 APK 包名为 `io.github.guog962464.aggregate.integration`；原普通包当时仍安装。执行 `flutter test --no-pub --no-uninstall --reporter expanded integration_test/android_host_identity_test.dart -d AEMN022427001360`，覆盖 Keystore 身份稳定读取、签名、删除后重新生成不同身份；测试通过。`--no-uninstall` 保留 runner 所用包，随后只手动卸载 `.integration`；卸载后普通 `io.github.guog962464.aggregate` 仍在设备上。此复验不启动 Host、不联网、不调用 Host RPC，也不覆盖普通 App 身份。 |
| 配对清理 | 从 Mac 撤销只读授权、从 Android 移除本机记录；确认待批准/已配对列表清空。停止本轮启动的 Mac Host，删除 ADB reverse 和临时 TCP 代理；CAMERA 权限恢复为 denied。 |
| 直接 LAN 验收清理 | 临时新设备 grant 已撤销，待批准列表为空；Mac Host 已停止，`47321` 不再监听；`.integration` 包已卸载，普通 `io.github.guog962464.aggregate` Debug APK 已重建、重装并启动，Wi-Fi 恢复开启，CAMERA app-op 为 ignore。Flutter integration runner 的清理也移除了普通包；重装后 app-private `app_flutter` 中没有 `hosts.json`，无法确认测试前是否有本地记录，Mac 原有“这台手机 · 读取连接”grant 保留但重装后的 App 可能需要重新配对。剪贴板已恢复，邀请/define/临时测试文件已删除。 |

## 尚未关闭的验收

- 2026-11-14 已在直连 LAN 上通过原始邀请、NSD 地址发现、新设备 Mac 人工只读审批、WSS pin/auth、`host.hello`、只读 `connection.list`、授权撤销及撤销后请求拒绝；拒绝响应的 JSON-RPC request ID 也已修复并有 WSS 回归测试。实际 Android Keystore 别名轮换仅在可卸载的隔离 `.integration` 包验证，未轮换日常 App 身份。Mac TLS 身份轮换已在唯一且默认的临时 macOS Keychain 中真实运行集成测试，通过身份/证书指纹变化与回读稳定性断言；退出后登录 Keychain 默认项和搜索列表恢复原值，临时 Keychain 删除，当前用户身份及 grant 未动。短暂关闭/恢复 Wi-Fi 后的 NSD/WSS 重连已通过隔离包验收。16 KB 实体设备运行及 Release/signed 权限仍待验收；integration runner 移除普通包后已重装，但重装后的本地 Host 列表为空，既有 Mac grant 保留，后续使用可能需要重新配对。
- 2026-11-14 隔离 Android KeyStore 测试随后以 `.integration` 包再次通过；先核验 APK applicationId，再使用 Flutter `--no-uninstall`，测试结束后只卸载该隔离包，普通 `io.github.guog962464.aggregate` 安装状态保留。此前直接 LAN/Wi-Fi 验收中 integration runner 曾移除普通包的观察仍成立；只有本次明确核验包名并使用 `--no-uninstall` 的本地身份测试证明未卸载普通包。此前重装后的普通包本地 Host 列表仍为空，原 Mac grant 保留。
- 没有可用的 16 KB 页实体设备。当前 APK native library 的 ELF 和 ZIP 对齐均通过静态检查，但 16 KB 设备的安装、加载、运行以及 JNI/相机/NSD smoke 仍是外部验收门槛。
- Android 全局设备身份轮换确认 UI 和 Keystore 别名切换已实现并由 fake/Widget 测试覆盖；实际 Keystore 别名轮换仅在隔离 `.integration` 包验证，没有触碰日常 App 身份。2026-11-14 已实现 Mac TLS 身份轮换 UX：Mac 用户确认后先撤销全部配对授权、停止 Host，再更换 Host ID/证书；Keychain 通过候选密钥和证书校验后切换活动身份记录。Widget 测试验证取消、授权撤销失败保护与成功时序；另在独立临时 Keychain 中执行真实轮换集成测试。当前用户 Keychain 未轮换，以免现有手机 pin 失效。Release/signed App 的 macOS 本地网络权限及 Android Release 包仍未完成；A5.5 的 Android RemoteRuntime 与生产 Host 普通 CLI/TUI/MCP/网易云业务工作流尚未端到端验收。

## 复验

Mac Keychain TLS 身份轮换已在隔离临时 Keychain 完成真实集成验证，当前用户身份保持不变；后续扩大验收集中在日常 Android 身份轮换、Release/signed App 本地网络权限与 16 KB 实体设备安装/运行，并采集 page-size、启动、native load、scanner/NSD 日志。direct LAN 首次审批、只读调用、撤销、撤销后拒绝及 Wi-Fi 中断恢复已由隔离身份验证；测试期间普通包被 integration runner 移除后已重装，当前本地 Host 列表为空，原 Mac grant 保留。
