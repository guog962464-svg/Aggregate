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
| Android ↔ Mac Host 直接 LAN / Bonjour NSD（2026-11-14） | 同一可互通局域网，未改写 Mac 生成的原始短时邀请。使用已获“读取连接”授权的这台手机，在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机上运行隔离 Integration Test：Android 原生 NSD 发现 1 个端点且与邀请中的 Mac 地址匹配；WSS challenge 认证及 `host.hello` 成功；随后只调用 `connection.list`，返回 1 项“网易云音乐”。全程未调用其他 Host RPC。此轮复用已有只读授权，未覆盖新设备首次审批的直接 LAN 流程。 |
| 配对清理 | 从 Mac 撤销只读授权、从 Android 移除本机记录；确认待批准/已配对列表清空。停止本轮启动的 Mac Host，删除 ADB reverse 和临时 TCP 代理；CAMERA 权限恢复为 denied。 |
| 直接 LAN 验收清理 | 测试用 RuntimeStore 位于系统临时目录并在 finally 中删除；Mac Host 已停止，`47321` 不再监听；未产生新的待批准设备。保留验收前已有的只读 grant；未请求相机权限。普通 Android Debug APK 已重新安装到手机。 |

## 尚未关闭的验收

- 2026-11-14 已在直连 LAN 上通过原始邀请、NSD 地址发现、WSS pin/auth、`host.hello` 与只读 `connection.list`。本轮复用既有授权，尚未在直连 LAN 上验证新设备的 Mac 人工审批、网络切换后的重连以及撤销后请求拒绝；这不影响 11-13 USB 隧道下的首次批准/撤销结果，但两种网络路径不能相互替代。
- 没有可用的 16 KB 页实体设备。当前 APK native library 的 ELF 和 ZIP 对齐均通过静态检查，但 16 KB 设备的安装、加载、运行以及 JNI/相机/NSD smoke 仍是外部验收门槛。
- Android 全局设备身份轮换确认 UI 和 Keystore 别名切换已实现并由 fake/Widget 测试覆盖；真实 Keystore 轮换未在当前手机触发。2026-11-14 已实现 Mac TLS 身份轮换 UX：Mac 用户确认后先撤销全部配对授权、停止 Host，再更换 Host ID/证书；Keychain 通过候选密钥和证书校验后切换活动身份记录。Widget 测试验证取消、授权撤销失败保护与成功时序，macOS Debug 构建通过；未对当前用户 Keychain 执行真实身份切换，以免现有手机 pin 失效。Release/signed App 的 macOS 本地网络权限及 Android Release 包、Host 完整 RPC handler、A5.5 普通 CLI/TUI/MCP/网易云流程仍未完成。

## 复验

后续如需扩大验收，使用独立的新设备身份在直连 LAN 上完成一次性邀请和 Mac 只读审批，再覆盖网络切换、撤销及撤销后请求拒绝；不能轮换当前手机身份或撤销现有 grant 而不先保存恢复方案。另在 16 KB 实体设备独立安装并采集 page-size、启动、native load 和 scanner/NSD 日志。
