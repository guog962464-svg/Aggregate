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
- 使用临时 `.integration` Android 包及独立 Keystore 身份。Mac 审批的 grant 精确限定为 `readConnections`，没有任何逐连接权限；Mac 侧匹配了 Android 返回的确认码。Android `AndroidHostPairingClient.authenticate()` 完成 challenge 认证并验证 `host.hello`，随后只调用只读 `connection.list`，返回 1 项。未调用连接向导、能力搜索、CLI/TUI/MCP、账号、终端或写操作。
- 临时集成测试通过：`A5_LIVE_READONLY_RPC hostHello=passed connectionListCount=1`；Flutter analyze 无问题，integration test 全部通过。该测试 harness 和入口只存在于临时 worktree，验收后已清除。
- 清理确认：Mac grant 已撤销、Host 已停止、临时 `.integration` 包已卸载、ADB reverse 已移除，端口 `47321` 无监听；日常 Android 包、其 Keystore 身份和既有授权均未触碰。临时邀请、审批码、截图和包含邀请信息的构建产物已删除。
- **阶段判定：**这补足了 production Host 上真实 Keystore→CryptoKit 配对、`host.hello` 和只读连接列表 RPC。此前无法直连 LAN 的结论仍成立；USB 隧道不等于 NSD/LAN 直连。日常包身份轮换、签名 Release 权限、16 KB 实机以及 production Host 上的向导和真实业务仍未验收，A5.4 / A5.5 保持开放。
