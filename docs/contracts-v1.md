# Aggregate 契约 v1（阶段 0）

> 2026-11-09。阶段 0 冻结语义，阶段 1 已在 `packages/aggregate_contracts/lib/` 实现模型与 JSON 序列化。持久化仍属于阶段 2。

## 1. 标识与来源

- `connectionId`：安装内生成的 UUID，连接重命名后不变。`kind` 为 `cli | mcpStdio | mcpHttp`；连接保留显示名、执行位置、配置引用、状态和版本。
- `capabilityId`：`connectionId + capabilityKind + sourceName` 的结构化组合，不拼接成可解析性不明的字符串。`capabilityKind` 为 `cliCommand | cliAction | mcpTool | mcpResource | mcpPrompt`。重名能力保留各自来源。
- `runId`：每次调用独立 UUID；重试必须生成新 ID 并关联前次 ID，防止重复写入被当作同一次成功。
- URI、可执行文件路径和 HTTP URL 只属于对应连接/能力，不进入 ID。

## 2. RuntimePort 与 McpClientPort

`RuntimePort` 是 UI 的唯一运行入口：列连接、搜索能力、调用、订阅事件、取消、读资源、取提示、开终端。`McpClientPort` 隔离具体 SDK 的连接、工具、资源与提示操作。两者不含 `dart:io` 或 macOS 类型。阶段 0 仅定义接口，不提供假运行结果。

调用返回 `RunHandle`，其后通过 `watchRun(runId)` 接收带时间戳的状态与内容块。事件必须按单个 run 排序；UI 不凭按钮点击推断成功。断线后如无法确认远端写入效果，用 `outcomeUnknown`，不自动重放。

## 3. 运行状态、错误和权限

状态：`created → validating → awaitingPermission → running → succeeded | failed | cancelled | timedOut | outcomeUnknown`。终态不可逆。超时代表本地停止等待；远端是否已执行需单独判断。

错误码：`invalidArguments`、`executableMissing`、`connectionFailed`、`authenticationRequired`、`permissionDenied`、`protocolError`、`timedOut`、`cancelled`、`outputLimitExceeded`、`outcomeUnknown`、`internal`。错误事件保留安全的用户文案、诊断阶段、可选原始错误类别；日志不得写明文密钥。

权限级别：`read`、`localControl`、`externalWrite`、`unknown`。连接器声明只是提示，未知 MCP 工具默认 `unknown`，需要用户确认后执行。能力来源、执行位置与目标对象在授权界面显示。

结果保留 MCP 原始内容块和结构化内容；UI 再派生文本、JSON、文件、图片或终端视图。不能把内容块当 HTML 或脚本执行。

## 4. CLI 连接器清单 v1

清单是可选增强；任意 CLI 没有清单也可以用原生命令入口。示例：

```json
{
  "schemaVersion": 1,
  "id": "example.git",
  "displayName": "Git",
  "platforms": ["macos"],
  "executable": "/usr/bin/git",
  "actions": [
    {
      "id": "status",
      "title": "查看状态",
      "argv": ["status", "--short"],
      "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false},
      "output": "text",
      "permission": "read",
      "timeoutMs": 15000
    }
  ]
}
```

规范要求：`schemaVersion`、稳定连接器 ID、显示名、支持平台、可执行文件引用与动作列表；每个动作包含稳定 ID、标题、`argv` 数组、JSON Schema 输入、输出类型、权限与超时。占位符只替换数组元素中的值，不交给 shell 展开。配置中敏感值只保存凭证引用。清单校验器、版本迁移和签名信任属于阶段 1/2。

## 5. 版本与兼容

契约序列化采用显式 `schemaVersion`，未知字段可保留但未知枚举不得默默映射为已授权状态。MCP 协议版本属于连接握手元数据，与 Aggregate 契约版本分开。阶段 0 互操作实测见 [报告](phase0-report.md)。
