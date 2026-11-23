# A5.4 Android 配对客户端与真机验收

记录日期：2026-11-13；2026-11-14 与 2026-11-19 补充直接 LAN 真机验收。USB ADB 反向转发与直连 LAN 的结果分别记录，覆盖范围不同；2026-11-19 结果仅覆盖普通 Android 包首次配对、`host.hello` 和只读 `connection.list`。

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

## 2026-11-17 当前网络环境下的只读 Host 复验

- 设备仍为 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机。当前手机与 Mac Host 处于不可互通的 Wi-Fi 网段，直接连接 Host 端口超时；这与 2026-11-14 在另一可互通网络完成的 LAN/NSD 验收是不同环境，不互相替代。
- 为按已批准的只读范围继续验收，使用隔离 `.integration` App/Keystore 身份，把测试邀请 endpoint 临时改为 `wss://127.0.0.1:47322/host`，由 Mac loopback TCP 代理转发至生产 Host 的 `47321`，并用 `adb reverse` 接通；原 Host ID、证书 SHA-256 pin 和 WSS 协议保持不变。Mac UI 的验证码与 Android 请求匹配，人工只批准“读取连接”。
- 配对后及 App 重启重连后，`host.hello` 成功；随后只读 `connection.list` 返回 1 项。为避免 `ConnectionsPage` 初始化时额外调用 `capability.search`，此项使用临时 Android 诊断入口直接调用。诊断代码随后从源码撤回；没有调用 setup、能力搜索、CLI/TUI/MCP、账号、终端或任何写入型 RPC。
- 清理：隔离 `.integration` 包已卸载，ADB reverse 与本机临时代理已移除，Mac Host 已停止且 `47321` 无监听。Mac 设置 UI 同时显示两条相同“这台手机 · 读取连接”grant 且不显示可区分 ID；为避免撤销原有授权，本次没有盲目删除，测试创建的只读 grant 仍留在 Host 上。
- 限制：本轮未验证 direct LAN/Bonjour NSD；2026-11-14 的直连 LAN 结果仍保留其原有范围。没有 16 KB 页实体设备；本轮没有进行 16 KB 系统运行验收。

## 2026-11-17 隔离 Android→Host setup WSS 集成验收

- 新增 `app/test/android_host_setup_wss_e2e_test.dart`，使用真实 Dart `AndroidHostPairingClient`、证书 SHA-256 pin、`HostWssTransport`、配对授权和 setup RPC dispatcher，在 loopback 上完成邀请解析、配对申请、最小 `connectionSetup` grant、认证、`setup.adapters`、`setup.detectExecutable`、`setup.test` 与 `setup.save`。
- 验收夹具仅使用临时目录、临时 operation ledger、固定测试 TLS 证书、测试签名 verifier 和内存 `ConnectionSetupPort`；测试私钥身份由 fake 提供，setup 的 save 仅写内存。测试确认 Host 显示程序位置为 `Mac 主机 · ncm-cli`，不返回 Mac 绝对路径；测试响应不包含夹具 secret 或路径，而 Host runtime 收到独立 secret field。没有启动 production Host，也没有调用任何用户连接或账号。
- 验证：`flutter test --no-pub test/android_host_setup_wss_e2e_test.dart --reporter expanded` 2 项通过；全量 `flutter test --no-pub --reporter expanded` 291 项通过；当时 `flutter analyze --no-pub` 与 `git diff --check` 无问题。两条 loopback 集成加强了 Android 配对客户端、`AndroidRuntimePort` 与 Host WSS/setup 实现间的联调证据，但不覆盖 Android Keystore 原生实现、Android 真机、Mac 生产 runtime、网易云账号/CLI 登录或其他 CLI/TUI/MCP 调用。该段记录之后的实机补验见下节。

## 2026-11-17 Android 真机 → 隔离 MacRuntime setup WSS 验收

- 复跑入口：`python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360`。协调脚本拒绝模拟器与预先安装的隔离包；Mac integration test 仅绑定 IPv4 loopback，脚本校验邀请为 `wss://127.0.0.1:<动态端口>/host` 后才添加对应 ADB reverse。Android 使用独立 `.integration` 包和真实 Android Keystore 身份、签名及证书 SHA-256 pin；Mac 侧使用 `HostWssTransport`、实际 `MacHostDeviceSignatureVerifier`（CryptoKit）、`HostPairingAuthority`、`HostRuntimeRpcDispatcher`、`HostSetupRpcDispatcher`、`FileHostOperationLedger` 和 `HostSetupCoordinator`。夹具仅自动批准 `connectionSetup` 与 `readConnections`。
- Host 的 setup `ConnectionSetupPort` 使用真实 `MacRuntime`，数据目录及 `HOME` 都在脚本临时目录。PATH 前置测试用 Node/npm/mpv 和 `@music163/ncm-cli` 合成 npm 包；其 `login --check` 固定返回未登录，不访问真实账号或网络。Android→Host 完成适配器读取、检测 Mac 可执行文件、发送合成 PEM、Netease `setup.test` 与 `setup.save`；真实 `MacRuntime` 在临时 connector profile 保存配置，随后写入临时 `connections.json`。
- 同一隔离 WSS 随后由 Host `HostRuntimeRpcDispatcher` 响应 Android `AndroidRuntimePort.listConnections` 与 `searchCapabilities`；在 `readConnections` 授权下，手机重新读取刚保存的 Host 连接并发现对应能力。该项只覆盖列表/搜索读路径，不运行 CLI action。
- 验收断言：Android 收到 `ready` 连接，UI 来源映射为 `Mac Host`；Host 不回传绝对可执行路径，检查详情不含路径或 PEM；PEM 不进入 Mac `connections.json`、Android `hosts.json` 或 Host/Android 测试日志，且只出现在临时 Mac profile 的私钥文件中；测试私钥文件权限为 `0600`，profile 目录为 `0700`，中间 `.setup-private-key.pem` 已删除。脚本退出码 0；integration tests 的定向 `flutter analyze` 无问题，`git diff --check` 通过。
- 清理后 `getconf PAGE_SIZE` 为 `4096`；ADB reverse 列表为空，`.integration` 与 `.integration.test` 均已卸载，普通 `io.github.guog962464.aggregate` 包仍安装。未启动生产 Mac Host、未写用户连接或 Keychain，测试目录（含邀请、合成密钥和日志）由脚本删除，未使用模拟器。
- **阶段判定：**A5.3 的实机配对、加密 setup 传输、MacRuntime 测试与保存、私钥隔离/脱敏验收通过；AndroidRuntimePort 另经同一 WSS Host 验证连接列表和能力搜索。该流程是 loopback 测试证书与假 CLI 的可复现集成验收，不等于真实网易云账号登录或生产 Host 写入。A5.5 的 CLI action、TUI、stdio MCP/HTTP MCP 业务调用仍未完成；日常 App 身份轮换、Release 权限及 16 KB 实机也仍未验收。

## 2026-11-17 隔离 Android 真机业务链路验收（A5.5）

- 入口：`python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360`。在 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机上，`.integration` 包使用真实 Android Keystore 身份、签名与 WSS pin；Mac 使用实际 `MacRuntime`、Host RPC dispatchers、CryptoKit 设备签名校验和临时 operation ledger。Mac listener 仅绑定 `127.0.0.1`，经测试邀请和 ADB reverse 通信；Host 数据目录、HOME、证书及所有连接均为临时夹具。
- Android→Host 向导以合成 Node/npm/mpv/`ncm-cli` 测试包完成 Netease 可执行文件检测、setup.test、setup.save；同一草稿二次保存在客户端被拒绝且只生成一条连接；再次测试后的草稿通过 setup.discard 清理，丢弃后保存请求被拒绝。Host 私钥 profile 与 setup 脱敏沿用前一节的临时存储断言。
- 通过 RemoteRuntime 执行只读 `music.state`，读取假账号的 signed-out 状态并走完受控 login terminal；另用 Python `fixture-tui` 检查 stdin/stdout TTY、raw-mode 字符输入、ANSI 定位/清屏输出与 PTY resize（96×32）回读，关闭后也验证 Host 终止进程。该 TUI 是终端协议夹具，不代表真实 Netease TUI 或任意 TUI 兼容。
- 预置的普通 CLI 动作固定调用 `/usr/bin/printf`，参数以 argv 传入、不经过 shell。首个隔离配对无该连接的 `externalWrite` grant，即使客户端确认也由 Host 拒绝；第二个独立 Keystore 身份获逐连接 `read`/`externalWrite` grant 后，Android 显式确认并调用成功。HTTP MCP 与 stdio MCP 各提供只读 resource/prompt 和一个 echo tool；两类 resource/prompt 均可读取，工具在未确认时本地拒绝，确认后经 Host grant 成功。
- 首个隔离身份在 `fixture-terminal-held` PTY 仍运行时关闭 Android Host session；Mac fixture 读取 fake CLI 写入的 PID，并用 `kill -0` 轮询确认终端进程退出。第二身份完成调用后也显式 disconnect，远端连接呈 unavailable；用已保存 Host 记录重连后连接恢复 ready。这证明正常 WSS 会话关闭会清理 PTY，不代表 Wi-Fi/进程骤停等意外 socket 中断后的自动恢复或 LAN/NSD；生产 Host 本轮仍只允许此前批准的只读 RPC，未执行生产 setup、CLI、MCP、账号或终端动作。
- 验证：隔离 loopback 真机 runner 通过并清理 `.integration`/`.integration.test`、ADB reverse 和临时目录；普通 `io.github.guog962464.aggregate` 包仍安装，反向映射为空，设备 `PAGE_SIZE=4096`。全量 `flutter test --no-pub --reporter expanded` 294 项通过；`flutter analyze --no-pub`、Android arm64 Debug APK 和 macOS Debug app 构建通过；APK `zipalign -c -P 16 4` 与包内 7 个 arm64 `.so` 的 `PT_LOAD p_align >= 0x4000` 静态检查通过，仍不替代 16 KB 系统实机运行。
- **阶段判定：**A5.5 的普通 CLI 动作、raw-mode/ANSI/窗口尺寸 TUI 协议夹具、HTTP/stdio MCP、隔离 Netease setup/account，以及拒绝/授权/重复保存/丢弃/活跃 PTY 时显式断开并清理进程/显式重连已有真实 Android→MacRuntime WSS 证据。仍未验证真实 Netease 账号或播放、真实产品 TUI、意外网络掉线恢复、production Host 写入业务、Release/signed 权限、日常 App 身份轮换和 16 KB 真机；A5.5、A5.4 与 A8 不因此关闭。

## 2026-11-17 Android Host session stream 结束后的手动重连单元测试

- 在 `app/test/android_host_pairing_client_test.dart` 新增 AndroidHostManager 状态回归用例。模拟已认证 `AndroidHostAuthenticatedSession` 的 fake socket message stream 自行结束，而不是调用 `manager.disconnect()`；断言状态通知转为 offline、`isConnected` 为 false，再通过保存的 Host 元数据显式 `manager.connect()`，确认第二次认证发送 `host.hello` 且状态回到 online。
- `flutter test --no-pub --reporter expanded test/android_host_pairing_client_test.dart`：9 项通过；全量 `flutter test --no-pub --reporter compact`：295 项通过；定向与全量 `flutter analyze --no-pub` 均无问题；`dart format`：无改动。
- 范围：这是 fake connector 的本地 Flutter 单元测试，不包含 TCP/TLS/WSS 服务端、Android 系统、Wi-Fi/路由断开、实际 NSD 地址更新或自动重试；只补强“会话流结束后标离线并可手动重连”的状态机证据，不能表述为意外网络掉线的实机验收。A5.5 保持开放。

## 2026-11-17 loopback WSS Host stop/start 手动重连集成测试

- 在 `android_host_setup_wss_e2e_test.dart` 增加 AndroidHostManager→真实 Dart WSS transport 集成场景：通过临时测试证书、证书 SHA-256 pin 与配对流程建立 loopback TLS/WSS 会话；调用 Host transport stop 后确认 Android 会话流结束、Manager 状态变 offline；在相同 loopback 端口与证书重启 Host fixture，再用已保存 endpoint 显式 `manager.connect()`，重新认证 `host.hello` 并恢复 online。
- Host 配对 store、setup runtime 和操作账本均为隔离测试夹具；没有连接 production Host 或执行真实用户写操作。`flutter test --no-pub --reporter expanded test/android_host_setup_wss_e2e_test.dart`：3 项通过；其后全量 Flutter suite 296 项通过；全量 `flutter analyze --no-pub` 无问题；`dart format` 无改动。
- 范围：这是同进程的 loopback WSS transport 停止/重启，不是 TCP RST、Wi-Fi/路由切断、Android 系统/NSD 或 16 KB 实机；重连由测试显式调用，不证明自动重试。A5.5 意外网络掉线实机验收仍开放。

## 2026-11-17 loopback WSS 突然断流与手动重连集成测试

- 在 `android_host_setup_wss_e2e_test.dart` 新增只绑定 loopback 的 TCP 透传夹具：它转发客户端与隔离 Host 之间的 TLS/WSS 字节，不终止 TLS；配对后同时销毁代理两端 TCP socket，不发送 WebSocket close frame。断言 AndroidHostManager 将会话标为 offline、释放在线 session，再通过保存的代理 endpoint 显式连接、重新认证并恢复 online。
- `flutter test --no-pub --reporter expanded test/android_host_setup_wss_e2e_test.dart`：4 项通过；全量 `flutter test --no-pub --reporter compact`：297 项通过；全量 `flutter analyze --no-pub` 无问题；`dart format` 无改动。
- 范围：这验证 loopback 下没有 WebSocket close frame 的传输断流和手动重连；不保证底层关闭一定表现为 TCP RST，也不覆盖 Wi-Fi/路由切换、Android OS/NSD、自动重连、production Host 或 16 KB 设备。A5.5 的意外网络中断实机验收仍开放。

## 2026-11-18 A5.5 4 KB 实机证据新鲜度复核

- 对比 `aecbd0c..c2bb4b0`：`app/android` 与 `app/lib/platform/android` 没有变化；共享 Flutter App shell、主题、玻璃控件和页面框架有改动，Android Host WSS 测试及 `run_android_host_setup_e2e.py` runner 也有更新。
- 当前 `flutter test --no-pub --reporter compact` 316 项通过、`flutter analyze --no-pub` 无问题，arm64 Release APK/AAB 重建和静态对齐检查通过。此为本机自动化/构建证据，不是当前代码在手机上的业务验收。
- `adb devices -l` 为空，无法在本轮重跑 LGE AN10 4 KB 真机 setup/CLI/MCP/TUI/Host 断连场景。2026-11-17 真机结果继续按当时的代码版本保留；当前 UI 与 E2E runner 的 4 KB 覆盖待设备恢复后补验。此前通过的是隔离 MacRuntime 和合成账号/CLI/MCP/TUI，不是 production Host 或真实音乐账号；A5.5 保持开放。

## 2026-11-18 Android Release 权限静态核验

- 检查当前 arm64 Release APK `app/build/app/outputs/flutter-apk/app-release.apk`（SHA-256 `7ec10656e50f27869dcbd5f384015aa4296d16cd0cea9db7631a3e82b7193273`）和 AAB（SHA-256 `3b8769328aac58e3563c45fac2d852885f1219b4a098fddaa8952668cc712aae`）。Build Tools 36.0.0 `aapt dump permissions` 与 Release manifest-merger blame 一致：`INTERNET` 来自主清单；`CAMERA` 来自 `mobile_scanner 7.5.0`，摄像头硬件 feature 标记为 optional；`ACCESS_NETWORK_STATE` 来自 `transport-backend-cct 2.3.3`。包中另有 AndroidX 定义的 signature 级动态接收器权限，不是运行时危险权限。
- 主清单网络安全配置禁止通用明文流量，只对 `localhost` 和 `127.0.0.1` 配置例外。Release APK/AAB 均未签名：`apksigner verify` 报缺少签名，`jarsigner -verify` 确认为 unsigned；因此本项只核对生成工件的权限声明与依赖来源，不代表签名后包的安装、运行时权限提示或 Play 分发行为。
- `flutter test --no-pub test/android_host_pairing_client_test.dart test/android_host_settings_panel_test.dart`：11 项通过，包含身份轮换授权流程的 fake/Widget 覆盖；没有 Android 设备，未对日常 App 的 AndroidKeyStore 身份执行轮换。`adb devices -l` 为空。
- **范围结论：**Release 权限声明静态审阅已补齐。A5.4 仍开放日常 App 身份轮换实测、签名 Release 的设备权限行为以及 16 KB 设备加载/运行；不把隔离 `.integration` 包的 Keystore 轮换结果外推到日常包。

## 2026-11-18 production Mac Host 只读可达性复核

- 使用干净 detached worktree（提交 `519d99a20964307b79777ca2a09949f6f94ad3cd`）构建并启动 macOS Release Host，避免包含主工作区未提交的 UI 文件。`flutter build macos --no-pub` 成功；Host 设置页显示“运行中”，进程监听 `192.168.8.4:47321`。构建依赖解析只改动了临时 worktree 的 `pubspec.lock`，随后恢复；未更改主工作区文件。
- LGE AN10 / Android 15 / API 35 / arm64 真机恢复 USB ADB 后，实测 `PAGE_SIZE=4096`、`wlan0=192.168.31.135/24`，路由表只有本地 `/24` 路由，没有默认网关；Mac Host 位于 `192.168.8.4/24`。手机到 Host 的 ICMP 探测失败，两个网段之间无可用 LAN 路径。本次没有建立 ADB reverse 或代理。
- 日常包 `io.github.guog962464.aggregate` 已安装，但 app-private `files/` 中没有 `hosts.json`。Mac Host 页面列出两条不可区分的“这台手机 · 读取连接”既有授权，且没有待批准设备。为避免误用或撤销现存授权，没有轮换 Android 身份、修改/撤销授权或尝试用身份不明的 grant 认证；没有完成配对，也没有调用 `host.hello` / `connection.list`。新邀请按钮未产生可确认的二维码/复制控件。
- 清理：没有创建或删除配对授权；关闭本次验证启动的 Host 进程后，`47321` 不再监听。未触碰真实账号、连接、CLI、终端或播放。
- **阶段判定：**本轮确认当前主线版本的 macOS Host 可构建、可启动并绑定预期私有网卡；Android→Host 只读 RPC 因手机与 Mac 网段隔离、日常包缺少已保存 Host 元数据而未验收。A5.4 / A5.5 保持开放；此前隔离身份的 USB loopback 只读验收和 2026-11-14 direct LAN 结果仍按各自环境与代码版本记录，不作本轮替代。

## 2026-11-18 production Mac Host 经 USB ADB 反向转发完成只读 RPC 验收

- 在干净 detached worktree `519d99a20964307b79777ca2a09949f6f94ad3cd` 构建并启动 production macOS Release Host。验证走真实 `LocalRuntimePort`、`MacHostModule`、生产 WSS 和 Host runtime dispatcher；Host 监听 `192.168.8.4:47321`。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机仍处于 `192.168.31.0/24`，与 Mac 所在网段不通。本轮通过 USB `adb reverse` 将本机回环 WSS 桥接到 Host；仅把邀请 endpoint 改为 `wss://127.0.0.1:50433/host`，邀请中的 Host ID、证书 SHA-256 pin、nonce 和有效期保持不变。
- 使用临时 `.integration` Android 包及独立 Keystore 身份。配对审批由临时验收钩子自动执行，且只接受指定测试设备名、`android` 平台和精确的 `readConnections` scope；没有任何逐连接权限。独立回环控制通道核对 Android 回传确认码与 Host pending code 一致后才继续认证。Android `AndroidHostPairingClient.authenticate()` 完成 challenge 认证并验证 `host.hello`，随后只调用只读 `connection.list`，返回 1 项。未调用连接向导、能力搜索、CLI/TUI/MCP、账号、终端或写操作。
- 临时集成测试通过：`A5_LIVE_READONLY_RPC hostHello=passed connectionListCount=1`；Flutter analyze 无问题，integration test 全部通过。该测试 harness 和入口只存在于临时 worktree，验收后已清除。
- 清理确认：Mac grant 已撤销、Host 已停止、临时 `.integration` 包已卸载、ADB reverse 已移除，端口 `47321` 无监听；日常 Android 包、其 Keystore 身份和既有授权均未触碰。临时邀请、审批码、截图和包含邀请信息的构建产物已删除。
- **阶段判定：**这补足了 production Host 上真实 Keystore→CryptoKit 配对、`host.hello` 和只读连接列表 RPC。此前无法直连 LAN 的结论仍成立；USB 隧道不等于 NSD/LAN 直连。日常包身份轮换、签名 Release 权限、16 KB 实机以及 production Host 上的向导和真实业务仍未验收，A5.4 / A5.5 保持开放。

## 2026-11-18 隔离 test-signed Android Release 相机权限补验

- 从 detached worktree `897c2268d6325a4f9b615cc3bd60c80f7e70cc7f` 构建 arm64 Release APK，`versionCode=8`、`targetSdk=36`。因仓库只给 Debug 配置 `.integration` 后缀，验收期间仅在临时 worktree 的 Release variant 增加相同隔离后缀；使用一次性 RSA-2048 测试证书签名。`apksigner verify` 确认 APK v2/v3 签名有效，测试签名不代表正式签名或发布资格；APK SHA-256 为 `fa8579fc3b41df9fa4d33f12d8754e5035ae5817577da88cb7badd4b48b2feaa`。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机安装包名 `io.github.guog962464.aggregate.integration`。首次点“扫描二维码”触发 Android 系统相机权限弹窗；选“仅使用期间允许”后 `CAMERA` 变为 granted、app-op 为 foreground，扫码页面正常显示，最近 logcat 未见 `SecurityException`、`CameraAccessException` 或崩溃。
- 为验证拒绝路径，通过 ADB 撤销临时包权限并重启后再次打开扫码页；Android 系统重新显示权限弹窗，选择“禁止后不再提示”后，应用显示“无法打开相机。请允许相机访问，或返回后粘贴二维码内容。”及 `permissionDenied` 状态，没有崩溃。Package Manager 显示 `CAMERA granted=false` 且拒绝标志为 `USER_FIXED`。
- 清理：临时 `.integration` Release 包已卸载，一次性测试密钥和 APK 已删除；普通 `io.github.guog962464.aggregate` 包仍安装，ADB reverse 为空，Host 端口无监听。未请求真实连接、账号或网络数据。
- **范围判定：**这证明当前 Android 15 上 test-signed、targetSdk 36 隔离 Release 包的相机运行时允许/永久拒绝与恢复提示路径可用。正式签名 Release、日常包身份及权限、16 KB 系统加载/运行仍未验证；Release 只读 Host RPC 结果也不等于普通配对界面验收。A5.4 保持开放。

## 2026-11-18 A5.5 当前 checkout 隔离业务链路实机复验

- supersedes（仅当前证据新鲜度）：本文件“A5.5 4 KB 实机证据新鲜度复核”中“ADB 列表为空，当前 runner 无法复验”的当时状态；此前那次无设备观察仍然准确。
- 在当前工作区运行 `python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360`，runner 输出 Mac loopback Host fixture、Android physical Keystore + WSS setup flow 均 PASS，并确认清理完成。LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096`。
- 该 runner 用临时 loopback WSS Host、测试 TLS/Keystore、fake Node/npm/mpv/ncm-cli/MCP、临时 HOME 与 Host 数据；当前 `android_host_setup_e2e_test.dart` 对 setup 检测/测试/保存/丢弃、普通 CLI、TUI PTY 输入与 96×32 resize、HTTP/stdio MCP、权限边界及断连重连作断言。未连接 production Host 或真实网易云账号，不是产品 TUI/播放验收。Runner 不输出用例计数，且结束时删除日志；这里只记录其退出成功，不补写无法复核的数量。
- 版本范围：运行于 HEAD `ba7da5b10afcc3e14241873158a1adf6848168d0`，同时包含当前未提交的 Flutter UI/theme 修改和 `pubspec.lock` mirror 修改；Android host runner/test/bridge 文件没有未提交差异。该结果验证当前工作树整体通过这条隔离真机业务链路，不替代完整 Flutter 全量测试。
- 清理验证：`.integration` 与 `.integration.test` 均卸载，普通 `io.github.guog962464.aggregate` 仍安装；ADB reverse 列表为空，production 端口 `47321` 无监听。Runner 未针对普通包执行卸载或清数据。
- **阶段判定：**A5.5 更新后的隔离真机向导/CLI/TUI/MCP 路径有当前工作树证据。直接 LAN/NSD、production Host 业务、真实账号/播放和 16 KB 系统仍未验收，A5.5 保持开放。

## 2026-11-18 A5.5 current checkout runner recheck

- Command: `python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360`.
- Result: Mac loopback Host fixture and Android physical Keystore + WSS setup flow both reported PASS. Device: LGE AN10 / Android 15 / API 35 / arm64 / 4 KB page. Runner does not expose a case count, so no test count is inferred.
- Scope: temporary loopback WSS/TLS certificate, Android integration Keystore, isolated HOME/MacRuntime data, and fake Node/npm/mpv/CLI/MCP fixtures. Covers the current checkout's setup detect/test/save/discard and the existing CLI/TUI/MCP, permissions, and disconnect/reconnect path; it does not cover a real Netease account, production business RPCs, production TUI or unexpected network loss.
- Baseline: HEAD `90abf203e2770196fa50e00f59705451aded49b1`; the worktree also had unrelated uncommitted `glass_action_button.dart` and `pubspec.lock` changes. The Android host runner/test/bridge files were unchanged from the prior run.
- Cleanup readback: `.integration` and `.integration.test` are absent; ordinary `io.github.guog962464.aggregate` remains installed; ADB reverse is empty; production port 47321 has no listener. The runner used no production Host, account, or ordinary-app data.
- Stage status: this refreshes the isolated 4 KB runner evidence only. Direct LAN/NSD, production Host business, real account/playback, unexpected network recovery, signed Release permissions, and 16 KB hardware remain open; A5.5 is not closed.

## 2026-11-18 A5.5 physical abrupt TCP drop and reconnect

- Command: `python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360`.
- Result: the Mac loopback Host fixture and Android physical Keystore + WSS setup flow both reported PASS. Device: LGE AN10 / Android 15 / API 35 / arm64 / 4 KB page. The runner does not expose a case count.
- The fixture routes WSS through a loopback TCP tunnel and exposes a temporary loopback-only drop control on a separate port. The Android integration test pairs with a fresh isolated Keystore identity, establishes the WSS session, asks the fixture to destroy the active TCP sockets without a WebSocket close frame, observes `AndroidHostStatus.offline` and four Host connections as unavailable, then manually reconnects through the saved endpoint and observes the connections return to ready. No automatic retry is claimed.
- Scope: fake Node/npm/mpv/CLI/MCP, temporary TLS identity, isolated HOME/MacRuntime data and `.integration` package. No production Host, account, ordinary-app data or 16 KB device was used. This is a physical Android client over USB `adb reverse` to a loopback test Host; it does not simulate Wi-Fi/routing/Android OS loss or direct LAN/NSD.
- Cleanup readback: `.integration` was removed, ordinary `io.github.guog962464.aggregate` remains installed, ADB reverse is empty, device page size is 4096, and production port 47321 has no listener.
- Stage status: physical abrupt TCP loss and manual reconnect are now covered. Automatic retry, Wi-Fi/route/OS loss, direct LAN/NSD freshness, production business RPC, real Netease login/playback, production TUI, signed Release permissions and 16 KB hardware remain open; A5.5 remains open.

## 2026-11-18 A5.5 physical automatic reconnect

- supersedes the previous section's “No automatic retry is claimed” and “Automatic retry remains open” statements for this isolated abrupt-TCP-drop scenario; those statements correctly described the earlier manual-only implementation and evidence.
- `AndroidHostManager` now retries saved-endpoint session authentication with bounded delays of 1, 2, 4, 8 and 16 seconds. It retries only transient transport/availability failures, does not replay RPC calls, and cancels pending retries on explicit disconnect, removal, pairing replacement, identity rotation or disposal. A session stable for 30 seconds resets the retry count.
- Verification: the focused Flutter unit/WSS suite passed (14 tests), `flutter analyze --no-pub` found no issues, and `python3 app/tool/run_android_host_setup_e2e.py --device AEMN022427001360` reported both the Mac loopback Host fixture and Android physical Keystore + WSS setup flow PASS. The physical integration test destroys both TCP tunnel sockets without a WebSocket close frame, observes offline/unavailable state, waits for automatic reauthentication, then verifies the Host connections return to ready. A later explicit disconnect/manual reconnect assertion remains in the same runner.
- Device/scope: LGE AN10 / Android 15 / API 35 / arm64 / 4 KB pages; actual Android physical Keystore; isolated loopback WSS test Host via USB `adb reverse`; fake CLI/Node/npm/MCP and temporary HOME/Host data. This does not cover Wi-Fi or route changes, Android process death/background suspension, direct LAN/NSD, production business RPC, real account/playback, signed Release, other ABIs or 16 KB hardware.
- Cleanup readback: runner reported isolated package/reverse cleanup; `adb reverse --list` was empty, ordinary `io.github.guog962464.aggregate` remained installed, and port 47321 had no listener. `pubspec.lock` remains an unrelated user modification and is excluded from the task commit.
- Stage status: automatic reconnect after abrupt WSS/TCP loss is now verified on the connected 4 KB device. A5.5 remains open for direct LAN/NSD and remaining production/real-account acceptance; A5.4/A8 signed Release and 16 KB gates also remain open.

## 2026-11-18 Android-to-Mac LAN reachability preflight

- Read-only interface check found the Android device on `192.168.31.0/24` and the Mac on `192.168.10.0/24`; the Android route to the Mac address went through its `192.168.31.1` gateway. One ICMP probe received no reply.
- A temporary listener bound only to the Mac's private `en0` address on an ephemeral port received no Android TCP connection; `toybox nc` timed out. The listener was closed immediately. Production Host port 47321 had no listener; no production Host was started and no pairing/RPC was attempted.
- This records a failed reachability preflight at the observed network state. It does not prove all routed TCP is blocked, and it is not a direct WSS/NSD test. Direct LAN/NSD acceptance remains open until the device can reach the Mac on a shared or routed network.

## 2026-11-18 Current-worktree A5.5 physical rerun after fixture correction

- The first current-worktree run failed in the Mac fixture with `A SemanticsHandle was active at the end of the test`; the Android Keystore/WSS client itself reported PASS. The fixture is a headless service host and does not pump or inspect widgets, so `macos_android_host_setup_fixture_test.dart` now sets `semanticsEnabled: false` to disable the unused default semantics lifecycle.
- `dart format --set-exit-if-changed integration_test/macos_android_host_setup_fixture_test.dart` made no changes, and `flutter analyze --no-pub integration_test/macos_android_host_setup_fixture_test.dart` found no issues. Rerunning `python3 tool/run_android_host_setup_e2e.py --device AEMN022427001360` then reported both `Mac loopback Host fixture: PASS` and `Android physical Keystore + WSS setup flow: PASS`. The runner does not report a case count.
- Device: LGE AN10 / Android 15 / API 35 / arm64 / 4 KB (`getconf PAGESIZE=4096`). The runner uses test TLS/Keystore, fake Node/npm/mpv/CLI/MCP, temporary HOME and MacRuntime data. It does not connect to production Host or a real Netease account; the Debug integration APK was not the Release APK built in the separate A8 check.
- Cleanup readback: ordinary `io.github.guog962464.aggregate` remains installed; `.integration` and `.integration.test` and NodeProbe packages are absent; ADB reverse is empty; port 47321 has no listener; no runner temporary directory remains.
- At test time the worktree also contained unrelated uncommitted shared glass UI/golden and lockfile changes; they were not staged in the Android task. The shared UI/golden files were later committed as `d029ef3`; the root `pubspec.lock` change remains unstaged. This result refreshes the isolated 4 KB runner only; direct LAN/NSD, production business, real account/playback, automatic network recovery, signed Release runtime and 16 KB hardware remain open.

## 2026-11-18 当前主线隔离 test-signed Release 冷启动检查

- 基线为 `f559d7b642b51c2d08135c2ed42144189060b45c`。在 detached worktree 临时为 Release variant 加 `.integration` applicationId 后缀并使用 Android Debug 测试签名；锁文件从当前工作树复制后以 `flutter pub get --offline --enforce-lockfile` 生成 workspace 配置。主工作树和产品 Gradle 配置未改动。
- `flutter build apk --release --no-pub --target-platform android-arm64` 通过。Build Tools 36.0.0 `aapt dump badging` 确认 `io.github.guog962464.aggregate.integration`、versionCode 8、targetSdk 36、arm64-v8a；`apksigner verify` 的 APK v2 验证通过，签名证书为 Android Debug（SHA-256 `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`）。`zipalign -c -P 16 4` 通过。APK SHA-256：`aa28c7974d093dd1db268fab14529f498306670dd6ab911b98a434f1f2f0ce04`。
- LGE AN10 / Android 15 / API 35 / arm64 真机报告 `PAGE_SIZE=4096`。隔离 APK 安装成功；显式启动 MainActivity 返回 `Status: ok`、`Complete`，后续核对进程存活且 MainActivity 为 resumed。最近 400 条 logcat 未见 `FATAL EXCEPTION`；另有一条 Android `queued-work-loo` 的 ART profile 路径 SELinux read-denied 警告，未单独诊断。
- 清理：`.integration` 已卸载；普通 `io.github.guog962464.aggregate` 仍安装；ADB reverse 为空；Host 端口 `47321` 无监听；临时 detached worktree 与测试构建目录已删除。未启动 Host、未触碰日常包数据/身份或连接。
- **范围判定：**这补充当前主线代码在 4 KB Android 15 上的 test-signed Release 安装与冷启动证据。测试证书和隔离包名不代表正式签名/日常身份，也不覆盖 CAMERA 权限路径之外的交互、16 KB 系统或 A3.6 Node/npm 产品门槛；A5.4 与 A8 分发验收仍开放。

## 2026-11-19 当前工作树 Android 构建与 4 KB 真机启动复核

- 基线为当前主线 `030aab57e61149d032f89064fe5ca2193bb33d23`。在 `app/` 运行 `flutter test --no-pub`，328 项全部通过；`flutter analyze --no-pub` 无问题；`flutter build apk --debug --no-pub --target-platform android-arm64` 成功。构建日志有 Android SDK XML v4 与本机工具最高支持 v3 的兼容性提示，但未影响构建。
- APK 包名 `io.github.guog962464.aggregate`、versionCode 8、versionName 0.3.7、targetSdk 36，SHA-256 `869e9351a2cb2560d466cb844722a8a7af1a028435fcae2eec440c76ea538ca5`。Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；7 个 arm64 native library 的 21 个 `PT_LOAD` 全部 `p_align >= 0x4000` 且 offset/virtual-address 余数相符。这是 APK 的静态 16 KB 对齐结果。
- LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页实体机上，安装包更新前后 APK signer SHA-256 相同（Android Debug `55057a5288c78c7e42492db9141df637c17c606179b78cbb50972a822be89832`）；`adb install -r` 成功。启动后 Aggregate PID 存活，`MainActivity` 为 top-resumed。没有卸载普通包或清除应用数据。
- 当前真机 `wlan0=192.168.31.135/24`，Mac `en0=192.168.10.144`；端口 `47321` 当前无监听，`app-private files/` 下没有 `hosts.json`。本轮未建立新的 Host 配对或执行 production RPC。历史 Host UI 曾显示两条无法区分的只读授权；Android Keystore 轮换实现会删除旧别名，所以没有在日常包身份上执行轮换，避免使未知对应的授权失效。
- 当前 `app/android/app/build.gradle.kts` 未为产品 Release 配置签名，注释明确 Release 包在提供正式密钥前保持 unsigned；只为隔离 `.integration` Release 指定本机 Debug signer。因此本轮不能验证正式签名权限行为。16 KB 真机仍缺。
- **范围判定：**当前主线 Flutter 回归、静态分析、arm64 Debug 构建、APK 对齐和 4 KB 普通包启动通过；A5.4 仍待安全条件下的日常身份轮换、正式签名 Release 权限及 16 KB 实机加载/运行。A5.5 仍待 direct LAN/NSD 与适用范围内的 production Host 端到端业务验收；本轮未访问真实账号或执行业务写入。


## 2026-11-19 当前同网段 production Mac Host 直连只读验收

- **替代范围：**本节更新 [2026-11-18 LAN 可达性预检](#2026-11-18-android-to-mac-lan-reachability-preflight) 中“当前网络状态下不能 direct LAN”的结论；该结论在当时的异网段环境成立。此前 USB `adb reverse` 只读验收仍是独立历史证据，不由本节替代。
- **环境：**当前提交基线 `1515583baec78be5ab8407279dfbd670abe2d65b`。LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页真机 `wlan0=192.168.8.7/24`；Mac `en0=192.168.8.4/24`，两端同属 `192.168.8.0/24`。ICMP 和 Android `toybox nc` 到 `192.168.8.4:47321` 可达。Mac 运行当前主线 Aggregate Host；本次是普通包 `io.github.guog962464.aggregate` 与日常 Android Keystore 身份，没有使用 `.integration` 包、模拟器或 ADB reverse。
- **配对：**普通 Android 设置页提交新邀请后，Mac 展示的待批准设备名与 Android 相同，确认码匹配。用户已授权启动 Host 并只读配对；Mac 上选择“批准只读”。Android 配对页随后显示该 Host 在线，认证流程中的 `host.hello` 成功。
- **RPC：**临时集成验收入口以普通包现有 Host 记录连接同一个 `192.168.8.4:47321` endpoint；`AndroidRuntimePort` 只执行 `host.hello` 和 `connection.list`。返回 1 项，名称为“网易云音乐”。没有调用 `capability.search`、setup、CLI/TUI、HTTP/stdio MCP、账号、终端、播放或业务写入。测试命令：`flutter test --no-pub --no-uninstall --reporter expanded integration_test/a5_direct_lan_readonly_probe_test.dart -d AEMN022427001360`，结果通过。
- **结论边界：**证明当前同网段下普通 Android 包可与 Mac Host 直连 WSS、完成配对与最小只读 RPC；不单独宣称 NSD 发现链路通过，不代表 setup/CLI/TUI/MCP、真实账号或业务闭环通过。A5.5 继续开放；A5.4 仍待日常 Keystore 身份轮换、正式签名 Release 权限及 16 KB 实体设备验收。
- **清理：**已重新构建并安装普通 Debug APK（保留包与数据），从 Android 仅移除本轮新增的 Host 记录，并移除其空 `hosts.json`；`activity.json` 与 `preferences.json` 哈希保持不变。Mac 仅撤销本轮新建且唯一命名的只读 grant，原有两条“这台手机 · 读取连接”授权保留；Mac Host 停止、应用退出，端口 `47321` 无监听。临时测试文件、邀请二维码/载荷临时目录、预检脚本均清除，ADB reverse 为空。
- **前置条件与授权：**本机 Mac Keychain 在 Host 启动时请求访问现有 TLS 身份；按用户先前提供的授权处理，未把凭据写入记录。有效权限范围为启动 Host、批准本轮只读设备和调用以上两项只读方法；未扩大到其他 Host 操作。

## 2026-11-19 NSD 复验准备时网络状态变更

- 这是上一节 direct WSS 只读验收之后单独准备验证 NSD 的状态记录；没有把直连结果当作 NSD 证据。源码检查确认 `AndroidHostManager._connectHost()` 会先调用 `discovery.discover(hostId)`，仅在发现结果为空时才回退到已保存 endpoint；上一节配对与连接成功不足以证明实际发现到 NSD 服务。
- 重新打开当前主线 macOS Debug app 并启动 Host 后，listener 读回绑定 `192.168.10.144:47321`，与刚才 direct LAN 验收的 `192.168.8.4:47321` 不同。Android 最后一次可读地址是 `192.168.8.7/24`；随后 `adb devices -l` 为空，无法取得同一时刻的手机地址或运行 NSD 客户端探测。
- 未生成邀请、未配对、未调用任何 RPC。发现网络条件不匹配后立即从 Mac UI 停止 Host 并优雅退出 app；复核 `47321` 无 listener、无 Aggregate 进程。当前 Mac `en0=192.168.10.144`，Android IP 当前未知，NSD 发现待设备重新连接且两端网络条件一致时补验。

## 2026-11-19 NSD 用户反馈后实机复验

- **邀请：**Mac UI 曾生成一条短时邀请，未复制、未分享、未用于配对；界面显示于 2026-11-19 11:24:53 到期。没有产生待审批设备。
- **网络读回：**收到“IP 已一致”的反馈后重读网络，Mac `en0=192.168.8.4/24`，LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页手机 `wlan0=192.168.31.135/24`，手机连接 Wi-Fi `ws-5g`。两个地址仍不同子网；手机路由到 `192.168.8.4` 经 `192.168.31.1`，Android 临时 TCP 探针连接 Mac `192.168.8.4` 超时。测试期间 Mac 从 `192.168.10.144` 切换为 `192.168.8.4`，手机地址未同步变化。
- **Mac 广播：**启动当前主线 Debug Aggregate Host，监听 `192.168.8.4:47321`。macOS `dns-sd -B/-L` 找到并本机解析 `_aggregate-host._tcp.local` 服务，TXT 记录含格式有效的 Host ID，端口为 47321。
- **Android NSD：**以 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true` 构建隔离 `.integration` 包，在实际 LGE AN10 上运行临时集成测试，直接调用产品 `MethodChannelAndroidHostDiscovery.discover(hostId)`。4.5 秒发现窗口结束后返回 `[]`，预期的 `wss://192.168.8.4:47321/host` 未出现，测试失败。NSD 结果是空发现；结合不同子网和单播 TCP 超时，当前网络未通过 direct NSD/WSS 验收。
- **范围与清理：**本次只检查 Bonjour/NSD 与临时 TCP 可达性；未配对、未生成或审批新设备、未调用 `host.hello`、`connection.list` 或任何其他 RPC，未改动 Mac grants 和普通 Android 包数据。已通过 UI 停止 Host 并优雅退出 app；端口 `47321` 无监听；卸载隔离 `.integration` 包，普通 `io.github.guog962464.aggregate` 保留；临时测试文件已删除，ADB reverse 为空。A5.4/A5.5 的 NSD 与 direct LAN 门槛仍开放。

## 2026-11-19 用户反馈后网络地址再次读回

- 再次读取系统网络接口：Mac `en0=192.168.8.4/24`；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页手机 `wlan0=192.168.31.135/24`，仍不是同一子网。手机连接 `ws-5g`，其到 Mac 的路由经 `192.168.31.1`；Mac 到手机按默认路由经 `192.168.8.1`。
- 一次 Mac 到手机的 ICMP 探测无响应。该轮没有启动 Mac Host 或运行 NSD/WSS；既有 Host listener 已停止，没有配对或 RPC。用户反馈后的这一读回仍不能证明两端地址已一致或 LAN 可达，NSD/direct WSS 验收保持开放。

## 2026-11-19 14:33 网络地址与 Host listener 复读

- **接口与路由：**Mac `en0=192.168.8.4/24`；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页设备 `wlan0=192.168.31.135/24`。两端仍不在同一子网；Android 到 Mac 经 `192.168.31.1`，Mac 到 Android 经默认网关 `192.168.8.1`。Android 对 Mac 执行一次 ICMP 探测，1 包发送、0 包收到。
- **服务与清理：**Mac `47321` 无 TCP listener，未启动 Host；没有配对、NSD、WSS 或 RPC。本轮读取时 NodeProbe 未安装/运行，设备临时 Node 目录已清理。
- **结论：**这次用户反馈后的实际读回仍未证明 IP 同网段或 LAN 可达，A5.4/A5.5 当前 NSD/direct LAN 验收保持开放。既有同网段 direct WSS 只读验收仍作为原时刻的历史结果，不被这次网络状态追溯性否定。

## 2026-11-19 19:05 网络状态与后台 runner 清理复核

- **网络：**Mac `en0=192.168.8.4/24`；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页手机 `wlan0=192.168.31.135/24`。当时未指定路由表的 `ip route` 输出只列出 `192.168.31.0/24` 直连路由，尚未检查 Wi-Fi 策略路由表；后续策略表复核及更正见下一节。Mac 到手机按默认路由经 `192.168.8.1`，一次 ICMP 无响应。production Host `47321` 无监听。本轮未启动 Host、未尝试 NSD、配对、WSS 或 RPC。
- **设备占用：**Node `pummel` 扩展诊断通过低优先级 `NodeTestService` 后台执行，没有打开 testnode Activity、没有清空共享 logcat。suite 后已 force-stop 并从当前 Android 用户卸载 `nodejsmobile.test.testnode`；`pm path` 与进程复核为空。前台 Activity 始终是 `hg.zp.mengnews/com.zjonline.xsb.loginregister.activity.LoginPasswordActivity`，普通 `io.github.guog962464.aggregate` 包仍安装。
- **结论：**当时的未指定策略表输出未包含默认路由；不能据此判断 Wi-Fi 网络没有默认网关，后续策略表更正见下一节。两端仍非同一子网，ICMP 无响应；此前同网段的 production `host.hello`/只读 `connection.list` 作为其原时刻验收记录保留。

## 2026-11-19 Android 默认路由策略表复核与更正

- **路由更正：**19:05 记录中的 `adb shell ip route` 是未指定策略表的输出，只列出 `192.168.31.0/24` 直连路由；不能据此认定 Android 没有默认路由。复核 `ip rule` 后发现 Wi-Fi 使用 table `1026`；`ip route show table 1026` 明确列出 `default via 192.168.31.1 dev wlan0`，`ip route get 192.168.8.4 mark 0x103c8` 也确认到 Mac 的包会经 `192.168.31.1` 发出。ConnectivityManager 的 Wi-Fi `LinkProperties` 同样包含该默认路由。更正先前“手机没有默认路由”的表述。
- **当前可达性：**LGE AN10 `wlan0=192.168.31.135/24`、Mac `en0=192.168.8.4/24` 仍属不同子网。当前 Mac 到手机及手机到 Mac 的 ICMP 各一次均无响应；Mac `47321` 没有 listener。本轮未启动 Host，未连接/切换网络，也未尝试 NSD、配对、WSS 或 RPC。此前 Android 到 `192.168.8.4:47321` 的 TCP 探针超时及 NSD 空发现仍是直接 LAN 的最近端到端结果。
- **范围：**本项只修正路由表解释；默认网关存在并不证明跨子网策略允许直连。A5.4/A5.5 的 NSD/direct LAN 仍未通过本次网络状态下的复验，已完成的历史同网段只读配对继续按其原环境记录。

## 2026-11-19 19:54 Mac Host 启动钥匙串授权复核

- **启动：**从当前工作树启动 Debug Aggregate，在“设置 → Mac Host”点击“启动 Host”后，macOS 弹出 `io.github.guog962464.aggregate.host.tls.v1` 登录钥匙串授权框。按用户先前提供的凭据输入后，授权框仍未关闭；随后取消该次请求，设置页恢复“启动 Host”，没有批准或改变现存 Host 身份。
- **网络与服务：**Mac `en0=192.168.8.4/24`，LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 手机 `wlan0=192.168.31.135/24`，仍属不同子网。Host `47321` 无 listener；本轮未配对、未运行 NSD/WSS、未调用任何 RPC。
- **清理：**已优雅退出本轮 Debug Aggregate，未安装或启动 testnode，手机原测试项目仍在前台；未改动 Android 配对记录、Mac TLS 身份或网络设置。该次启动未能完成钥匙串授权，不能作为 Host 启动或 LAN 验收通过。

## 2026-11-19 21:22 正式入口 Host 启动前台复核

- **入口确认：**用户允许使用前台后，检查发现当时桌面 Aggregate 窗口是 Profile `preview_main.dart`，Mac Host 页没有真实 Host 控件。以正式 `main.dart` 运行 `flutter run --no-pub -d macos` 后构建成功，并在“设置 → Mac Host”看到“启动 Host”。
- **钥匙串结果：**启动触发 macOS 登录钥匙串对 Host TLS 私钥的导出授权请求。按用户此前提供的密码输入并选择“始终允许”后，SecurityAgent 提示仍未关闭；在确认安全输入及前台交互后仍无进展，Flutter Debug 进程丢失连接并退出。请求遗留提示随后被清理；没有更改钥匙串项目或身份。不能据此判断密码错误，也不将该次尝试计作 Host 启动成功。
- **服务与网络：**Mac `en0=192.168.8.4/24`，LGE AN10 手机 `wlan0=192.168.31.135/24`，仍属不同子网。Mac `47321` 无 listener；没有配对、NSD、WSS 或 RPC。手机前台仍为原 LoginPasswordActivity，没有启动 testnode。
- **运行环境与清理：**发现另一个仍运行的 Profile 预览 Flutter 会话；切换时预览窗口曾自动恢复，之后没有再关闭该会话。Debug Host 请求结束后没有 Aggregate Host listener。当前共享工作区中的 UI 文件及 `pubspec.lock` 修改均未由本轮编辑或暂存。
- **结论：**A5.4/A5.5 仍开放。阻塞因素是 macOS Host TLS Keychain 授权未完成及当前异网段；本轮没有获得新的配对/RPC 证据。前台权限已用于本次入口检查，不需要再启动 testnode。

## 2026-11-19 22:15 签名 Debug Host 钥匙串复核

- **构建与签名：**`flutter build macos --no-pub --debug` 构建正式 `main.dart` 入口成功；默认 Debug app 为 ad-hoc 签名。Xcode 以 Apple Development/Manual 设置重建时，Runner 与 Flutter 插件目标要求本机没有的 `Mac Development` 证书。为避免修改工程签名配置，将 Debug app 复制到临时目录，以本机 Apple Development 身份直接签名；`codesign --verify --deep --strict` 通过，bundle identifier 与 `DebugProfile.entitlements` 均符合预期。该临时副本不属于 Release 产物。
- **钥匙串授权：**独立打开签名副本并启动 Host 后，SecurityAgent 再次请求 `io.github.guog962464.aggregate.host.tls.v1` 登录钥匙串访问。用用户已提供的凭据填写安全字段并尝试“始终允许”，提示仍未关闭；桌面物理点击被一个 `警告` 对话框遮挡而未投递。`securityd` 日志记录该服务项的 `ObjectAcl REJECTS access using ACL`。现有证据能确认 ACL 拒绝了该次访问，不能据此判断密码错误或证明授权已更新。
- **调用路径复核：**`HostTlsIdentityChannel` 将 `loadOrCreate`/`rotate` 放在专用 `identityQueue` 执行；本次失败不足以支持“Keychain 调用阻塞 Flutter 主线程”的判断。未观察到 Host 身份轮换或条目删除。
- **退出与范围：**Debug 进程退出后确认没有存活的 Debug Host 请求者，再取消遗留的 SecurityAgent 请求；Mac `47321` 无 listener，没有配对、NSD、WSS 或 RPC。原 Profile 预览进程保持运行并恢复到前台；手机仍在原项目，未启动 testnode。Mac `192.168.8.4/24` 与 Android `192.168.31.135/24` 仍不同子网。A5.4/A5.5 继续开放。

## 2026-11-20 10:02 同网段直连复核与邻居解析失败

- **网络与 Host：**LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机 `wlan0=192.168.10.195/24`，Mac `en0=192.168.10.144/24`，地址位于同一 `/24`。正式 `main.dart` Debug app 启动 Host 后，`lsof` 确认 `192.168.10.144:47321` 正在监听。Android 路由查询选择 `wlan0`，但邻居表对 Mac 地址为 `INCOMPLETE`；`toybox nc` 返回 `No route to host`。Mac 到手机两次 ICMP 均无响应，ARP 无条目。
- **配对结果：**普通 `io.github.guog962464.aggregate` 的邀请 payload 在设备字段中校验为完整匹配后发起一次配对；Android 显示“找不到 Mac Host”，Mac 未出现新待批准设备，现存只读 grant 未更改。没有建立配对、没有调用 `host.hello`/`connection.list` 或其他 Host RPC。结论只覆盖该 Wi-Fi 下的终端间路径不可达；同网段地址本身不代表二层可互访，也不推翻 2026-11-19 在另一网络中已通过的 direct WSS 记录。
- **备用通道与清理：**仅绑定 `127.0.0.1` 的临时 TCP 桥接和 `adb reverse tcp:47321 tcp:47322` 的 loopback TCP 探针通过；没有用 loopback 邀请发起配对或 RPC。过程中手机前台离开 Aggregate 后未再切换，普通 Aggregate 包仍安装；NodeProbe/testnode 未安装或启动。ADB reverse 已移除、桥接已停止、Mac Host 已停止、47321/47322 均无 listener、临时 Debug PID 已退出。A5.4/A5.5 仍开放。

## 2026-11-20 前台 Host 启动与 ADB reverse TCP 预检

- **Host 启动：**`flutter build macos --no-pub --debug` 成功，打开正式 `main.dart` Debug app 并从“设置 → Mac Host”启动服务。Keychain 安全授权窗口出现；在安全字段输入前窗口已关闭，输入动作返回失效目标（未送达）。随后 Mac UI 显示“停止 Host”，`lsof` 确认 `192.168.8.4:47321` 正在监听。可确认本次 Host listener 启动成功；授权窗口关闭原因未知，本轮未新输入凭据，也未轮换 Host 身份或修改现有 grant。
- **网络与反向通道：**Mac `en0=192.168.8.4/24`，LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机 `wlan0=192.168.31.135/24`，当前仍为不同子网。仅绑定 `127.0.0.1:47322` 的临时 TCP 桥转发至 Mac Host listener；配置 `adb reverse tcp:47321 tcp:47322` 后，Android `toybox nc -z -w 4 127.0.0.1 47321` 成功。此结果只覆盖 USB reverse 的 TCP 连通，不含 TLS/WSS、邀请校验、配对或 RPC。
- **手机界面与配对边界：**打开普通 `io.github.guog962464.aggregate`（versionCode 8）后开始进入设置；设备 UI 自动化随后读到用户项目 `hg.zp.mengnews` 的更新界面节点，目标应用前台状态不再确定，故停止触屏操作，没有生成邀请、提交配对或调用 `host.hello`、`connection.list`。Mac 页面原有两条只读 grant 未改动；没有访问网易云账号/播放，也未清理 Android 应用数据。
- **清理：**在 Mac UI 停止 Host 后确认 `47321/47322` 无 listener；ADB reverse 已移除，临时 TCP 桥和本轮 Debug PID 已停止，原 Profile 预览进程保留。Android 前台恢复为用户项目 `hg.zp.mengnews/com.zjonline.xsb_main.MainActivity`；普通 Aggregate 保留安装，NodeProbe/testnode 未安装或启动。
- **结论与范围：**本轮刷新了 Mac Debug Host 启动及 USB reverse TCP 预检证据，但没有通过 production WSS/配对/RPC 验收，不能替代直接 LAN 或 NSD。A5.4/A5.5 继续开放；16 KB 实体设备仍缺失。

## 2026-11-20 普通 Android 包 USB 邀请扫描复验

- **Host 与 USB 通道：**在 Debug Aggregate 正式入口启动 Host，PID 42745 监听 `192.168.8.4:47321`。Mac `en0=192.168.8.4/24` 与 LGE AN10 `wlan0=192.168.31.135/24` 仍属不同子网。建立仅绑定 Mac 回环地址 `127.0.0.1:47322` 的临时 TCP 桥，配置 `adb reverse tcp:47321 tcp:47322`；手机对 `127.0.0.1:47321` 的 TCP 探针通过。此探针只证明 TCP 转发，不证明 TLS/WSS。
- **邀请扫描与边界：**Mac 新建短时邀请后，只将 JSON 中 endpoint 主机改为 `127.0.0.1`，Host ID、证书指纹、nonce 与有效期保持不变；手机普通包 `io.github.guog962464.aggregate`（versionName 0.3.7）扫描后把内容填入 Mac Host 邀请框。没有确认表单解析、没有可读的待审批请求，也没有建立 WSS socket；Host 刷新后仍只有两条原有“读取连接”授权。未批准、撤销或轮换任何 grant，未调用 `host.hello`、`connection.list` 或其他 RPC。手机相机确实在扫描时连接并断开，但不能据此推断配对请求已发送。
- **清理与结论：**停止 Host 并确认 `47321/47322` 无 listener；移除 ADB reverse，停止临时桥，关闭本轮 Debug 窗口并保留 Profile 进程；恢复原为空的 Mac 剪贴板并删除临时邀请二维码、脚本、截图与日志。Android 普通包仍安装，未清数据；手机随后回到用户的 `hg.zp.mengnews` 项目，普通 Aggregate 进程已停止。NodeProbe/testnode 未安装或启动。本次只补充 scanner 到邀请输入框和 USB TCP 预检证据，A5.4/A5.5 的 direct LAN、NSD、生产 WSS 配对、`host.hello`/`connection.list` 仍未验收；16 KB 实体设备仍缺失。

## 2026-11-20 USB loopback 邀请解析回归测试

- 对 `AndroidHostInvitation.fromQrPayload` 增加 `wss://127.0.0.1:47321/host` 用例；配对设置页 Widget 流程改用 loopback 邀请，检查模拟扫码、提交、完成配对后保存的 Host endpoint 仍为 `127.0.0.1:47321`。
- `cd app && flutter test --no-pub test/android_host_pairing_client_test.dart test/android_host_settings_panel_test.dart`：13 项通过。设置页使用注入的 scanner 和 fake HostManager，验证邀请解析及 UI 状态流，不建立 socket，也不覆盖相机或 Mac Host 网络行为。
- **结论边界：**USB reverse endpoint 在产品解析器和设置页状态流程中有自动化覆盖；真实手机这次只确认扫描回填，尚无表单提交、TLS/WSS、Mac 审批或 RPC 证据。A5.4/A5.5 继续开放。


## 2026-11-20 最新异网段复核与前台保护

- **网络状态：**Mac `en0=192.168.10.144/24`；LGE AN10 `wlan0=192.168.31.135/24`，不同子网。Android 仅有 `192.168.31.0/24` 的 wlan0 直连路由。
- **Host/USB：**Mac `47321` 与 `47322` 当前均无 TCP listener；`adb reverse --list` 为空。未启动 Host、未建立邀请、未提交配对、未调用 WSS/RPC。
- **前台保护：**复核时手机有其他应用位于前台，本轮没有切换应用或改动网络设置；没有启动 NodeProbe/testnode。A5.4/A5.5 不新增验收证据，待同网段可达且 Mac Host 可用时再继续。

## 2026-11-20 Mac Host 跨网段直连预检

- **Host 启动：**从 `5f940a30c8edfb5605f49f189200962d70fc3dd7` 的隔离工作树运行正式 `lib/main.dart`。该工作树原锁文件无法通过 `flutter pub get --enforce-lockfile`；复制主工作区当前未提交的 `pubspec.lock` 后解析通过，再以 `flutter run --no-pub -d macos` 构建并启动成功，未包含主工作区未提交 Dart UI 修改。设置页显示 Host 运行中，`lsof` 确认监听 `192.168.8.4:47321`。Keychain 授权提示曾出现，随后消失且 Host 开始监听；自动化未能确认提示由何种操作关闭，因此不将本轮记为密码输入或 ACL 授权验收，也未轮换 Host 身份。
- **网络：**Mac `en0=192.168.8.4/24`、默认网关 `192.168.8.1`；LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 真机 `wlan0=192.168.10.195/24`，地址不在同一子网。Android `toybox nc -z -w 4 192.168.8.4 47321` 超时；Mac ping 手机 2 次均无响应且 ARP 无条目。
- **配对边界：**没有生成邀请或提交配对请求；没有新增/审批设备，也未调用 `host.hello`、`connection.list` 或其他 RPC。Host 设置快照仍显示原有两条只读授权。没有更改网络设置，没有启动 NodeProbe/testnode，也没有执行无障碍测试。
- **清理：**通过 Host 设置停止服务，复核 `47321/47322` 均无监听，ADB reverse 为空；本轮 Debug app 和 Flutter runner 均已退出，临时工作树与截图已清理。手机未被切换应用，当前 Activity 读回为 HONOR 应用市场。曾观察到独立 Profile 预览进程，后续检查时该 PID 已不存在；本轮没有向其发送关闭信号，原因未知。
- **结论：**本轮仅证明 Mac Host 可启动并监听，当前手机到 Mac 的直接 TCP 路径不可达；不构成 LAN/NSD/WSS 配对验收，也不推翻 2026-11-19 已通过的只读直连历史记录。A5.4/A5.5 继续开放。

## 2026-11-20 同网段 Mac Host 直连与只读配对复验

- **环境与构建：**Mac `en0=192.168.8.4/24`，LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页真机 `wlan0=192.168.8.7/24`。从 `716144d` detached worktree 构建正式 Mac Debug app，并在临时 worktree 中通过 `aggregateIsolatedIntegration=true` 构建 `.integration` Android Debug 包；两边只复用主工作区当时的 `pubspec.lock`，用户的 UI/lock 改动未暂存或修改。没有使用模拟器。
- **直接 LAN / Bonjour / WSS：**Android 到 `192.168.8.4:47321` 的 TCP 探测成功，无 ADB reverse。使用 Mac 原生生成的短时邀请和 Android Keystore 临时身份；Mac UI 核对确认码后只批准“读取连接”。Android NSD 发现 1 个 endpoint，`AndroidHostManager.connect()` 通过发现结果连接；WSS Host 身份与证书 pin 校验、`host.hello` 通过，之后只读 `connection.list` 返回 1 条。没有调用 `capability.search`、setup、CLI/TUI/MCP、账号、终端或写入型 RPC。
- **清理：**只读测试 grant 已按测试设备名撤销，待批准列表为空，Mac 原有两条“这台手机 · 读取连接”grant 保留；Mac Host UI 显示已关闭且 `47321/47322` 无 listener。`.integration` 包已移除，`adb reverse --list` 为空，手机前台恢复为 `hg.zp.mengnews/com.zjonline.xsb_main.MainActivity`；临时 Debug app、worktree、邀请内容、截图和诊断文件均已清理。
- **结论边界：**本轮补齐了同网段下隔离 Android Debug 身份的直接 LAN、Bonjour NSD、只读配对与 WSS/RPC 证据，不代表普通签名 Release 的本地网络权限、16 KB Android 运行、日常 Android 身份轮换或 A5.5 真实业务/账号流程通过。没有进行无障碍/TalkBack 测试，也没有启动 NodeProbe/testnode。

## 2026-11-23 A5 本机协议与向导核心测试复验

- 在当前工作区运行 6 个本机 Flutter 测试文件：`android_runtime_port_test.dart`、`connection_setup_runtime_test.dart`、`host_runtime_rpc_dispatcher_test.dart`、`host_pairing_authority_test.dart`、`host_setup_rpc_dispatcher_test.dart`、`android_host_pairing_client_test.dart`；共 47 项通过，0 项失败。runner 中的 HTTP 401 日志来自预期的拒绝分支，测试进程最终报告 `All tests passed!`。
- 命令：`flutter test --no-pub --reporter expanded test/android_runtime_port_test.dart test/connection_setup_runtime_test.dart test/host_runtime_rpc_dispatcher_test.dart test/host_pairing_authority_test.dart test/host_setup_rpc_dispatcher_test.dart test/android_host_pairing_client_test.dart`（工作目录 `app/`）。
- 按用户要求，未运行包含语义断言/无障碍特征注入的 `connection_setup_dialog_test.dart` 和 `connection_setup_target_test.dart`；未运行任何 TalkBack、读屏或无障碍专项测试。
- 该结果来自本机 Flutter 测试 runner 与隔离测试依赖，没有启动 Android App、Mac Host 或 production WSS；不替代 Android 真机业务链路、LAN/NSD、真实账号/播放或 16 KB 系统验证。A5.4/A5.5 保持开放。

## 2026-11-23 Android 实体 Keystore 与隔离 Host setup E2E

- **命令与环境：**在 `app/` 运行 `python3 tool/run_android_host_setup_e2e.py --device AEMN022427001360`。设备为 LGE AN10 / Android 15 / API 35 / arm64 / 4 KB 页；Mac en0 为 `192.168.8.4/24`，手机 wlan0 为 `192.168.31.136/24`，仍处于不同子网。
- **结果：**`Mac loopback Host fixture: PASS`、`Android physical Keystore + WSS setup flow: PASS`。Android 使用实体设备 Keystore 和隔离 `.integration` 包，通过 USB ADB reverse 连接本机 loopback Host fixture；当前集成测试覆盖 setup 检测/测试/保存/丢弃、普通 CLI、TUI PTY 输入与 resize、HTTP/stdio MCP、权限拒绝与批准、断开及重连。fixture 使用隔离 HOME/MacRuntime 数据和假 Node/npm/mpv/ncm-cli/MCP 服务。
- **日常身份隔离轮换：**另运行 `ORG_GRADLE_PROJECT_aggregateIsolatedIntegration=true flutter test --no-pub --reporter expanded integration_test/android_host_identity_test.dart -d AEMN022427001360`，1 项通过。该项在隔离包真实 Android Keystore 验证身份创建/稳定读取、签名、删除和生成不同的新身份；日常 `io.github.guog962464.aggregate` 包及其身份未触碰。
- **清理：**runner/test 删除隔离测试包、ADB reverse 与临时 fixture；普通 Aggregate 包未被目标操作。测试后手机回到 HONOR Launcher，`.integration` 包路径不存在，reverse 列表为空，Mac `47321/47322` 无 listener。没有访问 Mac 生产 Host、生产钥匙串、真实账号或音乐服务。
- **验收边界：**本轮补齐隔离身份真实 Keystore 轮换与隔离 Host 业务路径证据；不代表 direct LAN/Bonjour/NSD、production WSS、日常身份轮换、正式 Release 权限、真实 CLI/账号/播放或 16 KB 系统通过。未启动 NodeProbe/testnode；按用户要求未运行无障碍/TalkBack 专项测试。A5.4/A5.5 仍保持开放。
