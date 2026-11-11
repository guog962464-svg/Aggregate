# Android A1：执行目标与连接向导契约

> 2026-11-10。实现范围：共享契约与 Android Flutter 宿主。HTTP MCP、Host 配对、Node/npm/CLI 仍分别属于 A2、A5、A3/A4。

## 执行目标和旧数据

`ExecutionTarget.device` 表示连接由**保存它的运行端所在设备**执行；`ExecutionTarget.host(hostId)` 表示由配对 Host 执行，`hostId` 是稳定身份，不使用显示名、IP 或文件路径。旧版 `Connection` / `ConnectionSpec` JSON 没有 `executionTarget` 时读取为 `device`，本机目标继续按旧格式保存。macOS `MacRuntime` 拒绝保存 Host 目标；A6 的路由层才会负责跨设备连接。

| 数据或操作 | 执行目标规则 |
| --- | --- |
| 连接目录、能力、运行、活动、终端、账号 | 归属同一目标；Host 离线时保留目标身份，不转为手机本地。 |
| 连接 ID / 能力 ID | A6 合并目录时给 Host ID 加稳定 Host 前缀，路由时还原原 ID；手机本地旧 ID 不改。显示名不能用于去重。 |
| `RuntimeFeatures` | 描述一个运行端可执行的能力。A1 Android 壳声明空连接类型与无终端；A6 合并时需在连接级过滤，不能把 Host 终端能力套到所有连接。 |
| `profileId` | 只是运行端自有配置的标识。Mac 上的账号目录不复制到手机，也不作为 Android 路径解析。 |

## 适配器与文件来源

| 扩展接口 | Android 本地 | Host 路由 |
| --- | --- | --- |
| `connectionAdapters` | A1 空目录；A2 仅 HTTP，A4 追加已验证的本地包。 | A5 返回 Mac 已登记适配器，并标明 Host 身份。 |
| `detectExecutable` | A1 不可调用；A4 的本地包不使用 Mac 绝对路径。 | A5 在 Mac 上查找，返回 Mac 路径并在 UI 标注归属。 |
| `testConnectionSetup` | A2 使用临时 HTTP 会话；A4 才可测试本地包。 | A5 通过配对通道在 Mac 执行预检。 |
| `saveConnectionSetup`、`discardConnectionSetup` | A2 保存/清理手机草稿和凭证；A1 无草稿。 | A5 按设备身份保存/清理 Mac 草稿与独立 profile。 |
| `ConnectionAccountPort` 的 `readAccount`、`beginAccountLogin`、`waitAccountLogin`、`logoutAccount` | A1/A2 不实现；本地网易云须 A4 单独验证。 | A5/A6 透传 Mac 已验证的网易云账号流程，终端会话仍属于 Mac。 |
| `ConnectionSpec.profileId` | A1 不创建；A4 若有本地包，引用手机私有配置。 | 始终指向 Mac 运行端的独立配置，不作为手机路径。 |

`ConnectionAdapter.executionTarget` 随适配器确定草稿所属设备。macOS 原有适配器默认 `device`；未来 Host 目录在 Android 展示时必须附加 `hostId`。`ConnectionSetupDialog` 将目标写进 `ConnectionSpec`，Host 程序字段标为 Host 路径，不调用手机文件选择器。Android 也不提供本地可执行路径按钮；A4 若通过受控 JS 包，使用包入口标识而不是假造绝对路径。

| 输入 | A1 语义 | 后续实现 |
| --- | --- | --- |
| CLI 程序路径、工作目录、动作清单路径 | 属于执行设备；Host 路径可手填或由 Host 自动检测。 | A5 检测/校验，A6 路由。 |
| `SetupField.readFileContent` | 用户选取本设备文档后读取内容；值仅进入内存草稿。 | A5 的私钥内容经配对加密通道发往 Host，不发送手机路径。 |
| Android 文档 URI | 不等于可执行文件或 Mac 路径。 | A2 按内容或授权 URI 处理导入/导出，必要时复制至应用私有目录。 |
| Bearer Token、私钥 | 不写入草稿 JSON、活动、错误或日志。 | A2 本机安全存储；A5 Host 端安全处理。 |

## 草稿生命周期

1. `填写中 → 测试中`：输入和密文只在当前 Widget/运行端内存中。测试失败返回 `canSave=false`，不产生已保存连接。
2. `测试通过 → 可保存`：`draftId` 仅指向测试过的规范化配置。`actionRequired` 表示后续账号操作待完成，不等于测试失败；UI 显示每一项检查。
3. 输入、适配器或执行设备变化：旧报告立即失效并请求 `discardConnectionSetup`；异步旧测试结果到达时也丢弃。关闭弹层同理。
4. 保存：运行端须原子地写入连接与凭证；成功后草稿不可再保存。失败时可重试同一有效草稿或提示重新测试，不能留下孤立连接或秘密。
5. 运行端进程结束、Host 配对撤销、过期或断线：运行端清理未保存的草稿及临时 profile。A2/A5 定义 TTL、幂等和跨进程恢复策略；A1 不持久化敏感草稿。

## A1 Android 壳的诚实能力边界

`AndroidRuntimePort` 只提供空的连接/能力/活动列表及进程内偏好状态。连接、终端、文件、调用都返回明确的未支持错误；`RuntimeFeatures.connectionKinds` 为空，因此生产 UI 不显示可操作的添加入口。共享连接向导的手机布局在 Widget 测试中验证，A2 接入 HTTP 后才向用户开放它。该壳不作为 HTTP MCP、npm 或 CLI 可用的证据。
