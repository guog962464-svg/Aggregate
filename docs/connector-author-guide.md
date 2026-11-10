# CLI/MCP 连接器作者指南

Aggregate 的功能入口由 `RuntimePort` 统一调用。首版运行端为 macOS；公共 Dart 契约不依赖 macOS API。新增普通 CLI 或 MCP 无需修改平台核心。特殊视图是可选的，网易云使用 `presentation` 标识接入播放器。

## CLI 清单

清单格式见 [JSON Schema](../connectors/manifest.schema.json)，可从 [Git 示例](../connectors/examples/git-status.json)复制。顶层必填 `schemaVersion: 1`、`id`、`displayName`、`platforms`、`executable`、`actions`。首版发布目标填 `platforms: ["macos"]`；未来端可扩展字段，但当前不会在那些端运行。

每个动作必填唯一 `id`、`title`、`argv`、`inputSchema`、`output`、`permission`、`timeoutMs`。`argv` 是字符串数组，程序路径放在顶层 `executable`。`inputSchema` 使用对象形态的 JSON Schema，平台据此生成表单并验证输入。`output` 可选 `text`、`json`、`file`、`terminal`；`permission` 可选 `read`、`localControl`、`externalWrite`、`unknown`。写入或控制动作应标为相应权限，使用户看到执行确认。超时范围为 100–3,600,000 毫秒。

先在连接详情“编辑动作”中填样本输入，查看展开后的完整参数数组，再保存和运行。不要把密钥硬编码在清单或命令参数中。清单版本不兼容会被拒绝，不能静默降级。

## MCP Server

支持 stdio 和 Streamable HTTP，发现 tools、resources、prompts。stdio Server 应把协议消息写入 stdout，将普通日志写入 stderr；HTTP Server 应使用正确的 MCP 端点、状态码和 Content-Type。客户端会分页发现能力、在断线后刷新目录，并对非幂等调用的未知结果停止自动重放。当前 HTTP 认证为静态 Bearer Token，用户在添加连接时输入，App 保存到 macOS 钥匙串。

建议用工具同时验证正常响应、非法参数、超时、断线重连和认证失败。仓库的 `dart run app/bin/stage2_smoke.dart` 使用独立 Python MCP fixture 覆盖 stdio/HTTP 与工具、资源、提示；`dart run app/bin/stage3_stability_smoke.dart` 覆盖断线恢复。发布连接器时说明可执行文件来源、需要的权限、输出格式和适用平台。
