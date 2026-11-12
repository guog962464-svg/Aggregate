# Android APK 内置 Node 包入口契约

状态：A4.3 设计建议；保存、丢弃、删除和清除应用数据的设备验收尚未完成。此文档用于隔离 Debug 实验，不开放 Android 产品连接器。

## 设计决定

- Android 内置包仍是 `ConnectionKind.cli`，但它不是文件系统里的可执行文件。`ConnectionSpec.executable` 继续表示绝对文件路径；Node 包连接将其留空，不写入 `bundled://...` 一类伪路径。
- 不在公共 Dart 合同里新增 `npmPackage`、Node 版本或 APK 资源路径字段。`ConnectionSetupDraft.adapterId` 用来选择固定适配器；`ConnectionSpec.profileId` 只引用 Android Runtime 自己生成的私有配置目录。
- A4 JSON5 探针的候选固定身份为 adapter `android-bundled-json5`、包 `json5@2.2.3`、入口 ID `json5.bin`。`json5.bin` 映射到 APK 已打包资源中的 `lib/cli.js`。包名、版本、摘要和入口映射来自构建时清单；不能从连接配置或调用参数指定 JS 文件路径。
- 每个保存的连接使用随机、严格校验的 `profileId`，例如 `node-profile-<opaque-id>`。私有 profile 元数据记录 adapter/package/version/entrypoint ID；JSON5 用户配置与缓存分别放在 Android 应用私有目录。`connections.json` 只保存 profile 引用，不保存密钥、源码或可执行路径。
- 不增加新的通用端口或安装接口。当前只有一个 APK 内置包样本，没有证据表明存在需要跨适配器变化的行为；包清单解析、资源映射和 profile 生命周期由 Android Runtime 内部实现。设备端 npm 安装不属于此契约。

## 保存与清理

1. **测试草稿**：只创建临时草稿，不提交长期 profile；检查 APK 内固定包身份和已知入口能启动。失败或超时清理临时文件。
2. **保存**：Runtime 生成 profile ID，在应用私有目录准备临时 profile；写入不含秘密的固定包元数据与用户配置；先将 profile 目录原子改名，再原子写入连接记录。任一步失败时回滚；若进程恰好在两次提交之间退出，启动时识别并清理未被连接引用的 profile。
3. **丢弃**：取消或过期草稿时删除临时 profile 和下载缓存，不产生 `ConnectionSpec`。
4. **启动/升级**：从 profile ID 读取配置，并将包名、版本、摘要和入口 ID 与当前 APK 的静态清单比对。只从静态映射解析实际入口；应用升级可刷新包资源，但要保留用户配置。
5. **删除连接**：先持久化移除连接引用，再删除该连接拥有的 profile 与缓存。清理失败时记为待重试 orphan；下次启动仅在连接清单完整通过解析和校验时清理没有引用的 profile，清单损坏时备份并保留现有 profile，避免误删用户数据。
6. **清除数据/卸载**：所有数据均处于应用私有沙箱，不写共享存储。Android 清除数据或卸载后，profile、配置和缓存应一并消失。

任何从磁盘读出的 ID 或 profile 元数据都不可信。ID 必须匹配受限字符集和长度，包和入口必须命中 APK 静态清单；禁止把 profile 内容拼接成路径或直接传给 `require()`。

## A4.3 验收矩阵

| 操作 | 通过条件 |
| --- | --- |
| 测试后丢弃草稿 | 无永久连接、profile、配置或包缓存 |
| 测试后保存并重启 | 连接引用唯一 profile；配置在应用私有目录；连接 JSON 不含凭证或可执行路径 |
| APK 原位升级 | 静态包版本刷新，用户配置和有效 profile 引用保留，陈旧包文件消失 |
| 删除连接 | 连接记录、profile 和专属缓存消失；其他连接数据不变 |
| 中途终止保存 | 连接和 profile 都回滚，或由启动清理器识别并收回 orphan |
| 伪造 profile/package/entrypoint | 运行前拒绝；不访问 profile 外路径，不执行任意 JS |
| 清除数据/卸载 | app 私有数据全部由 Android 清除；无共享目录残留 |

## 当前边界

`ConnectionAdapter` 已有静态 adapter ID，`ConnectionSetupDraft` 已带临时 adapter ID，`ConnectionSpec.profileId` 已定义为 Runtime 拥有的 profile 引用。Android `AndroidRuntimePort` 当前只公布 HTTP MCP，并拒绝 CLI/profile 字段；本设计尚未改动这些行为。当前项目发布范围仍为 macOS，未来 Android Runtime 可以先在独立实验或明确的后续版本中实现此契约，通过 A4.3 与 A4.7 门槛后再决定是否向用户展示。
