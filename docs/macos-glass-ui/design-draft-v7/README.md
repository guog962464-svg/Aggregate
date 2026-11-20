# Aggregate 全功能设计稿 v7.0 · 画板目录

27 张页面与适配器画板统一为 **1360×900 logical pt**。外壳依据 macOS Profile 的 Accessibility bounds 建模：32 pt 原生标题栏 + 40 pt Flutter 工具栏，搜索按钮位于 x=976、y=32、360×40 pt；侧栏宽 240 pt，正文左缘 x=280。04/18 按当前 `ActivityPage` 与 `PageState.empty` 的真实约束修正；播放器和侧栏下沿依据隔离 Profile 的 AX bounds 校准。侧栏连接与导航沿用低亮玻璃操作面，当前项加强边缘光；点阵掩码和单元尺寸从 Flutter source 读取。05 外观画板保留生产主题切换控件截图作为材质锚点，主题开关行为保持冻结。

画板覆盖当前 macOS 用户路径：工作台、CLI/MCP/音乐连接、参数与结果、终端、执行授权、历史活动、设置、Host、连接向导、账号登录、播放器和危险确认。状态变体、窄窗规则与页面入口见[功能覆盖矩阵](feature-coverage.md)。所有样例只在安全预览 Runtime 中使用；MCP 首页仅展示当前合同支持的工具、资源和提示，不展示未接入的资源模板。

| 画板 | 页面 | 画板 | 页面 |
| --- | --- | --- | --- |
| [01](01-workspace.svg) | 工作台 / 参数 / 结果 | [13](13-action-editor.svg) | 动作 JSON 编辑 |
| [02](02-music.svg) | 音乐播放与搜索 | [14](14-music-account-login.svg) | 音乐账号 |
| [03](03-connections.svg) | 连接管理 | [15](15-settings-shortcuts.svg) | 快捷键 |
| [04](04-activity.svg) | 活动记录 | [16](16-result-success.svg) | 成功结果 |
| [05](05-settings-appearance.svg) | 外观与主题切换 | [17](17-connection-home.svg) | CLI 连接首页 |
| [06](06-settings-host.svg) | Mac Host | [18](18-mini-player.svg) | 活动空态 + 迷你播放器 |
| [07](07-connection-setup.svg) | 添加连接配置 | [19](19-target-selector.svg) | 执行目标选择 |
| [08](08-terminal-running.svg) | 交互终端 | [20](20-host-permissions.svg) | Host 权限 |
| [09](09-permission-confirmation.svg) | 执行授权 | [21](21-mcp-home.svg) | MCP 连接首页 |
| [10](10-states.svg) | 通用状态 | [22](22-settings-local-data.svg) | 本机数据 |
| [11](11-button-motion.svg) | 按钮静置/点击态 | [23](23-danger-confirmation.svg) | 危险操作确认 |
| [12](12-dark-reference.svg) | 深色工作台 | [24](24-result-unknown.svg) | 结果待确认 |
| [25](25-setup-stdio-mcp.svg) | stdio MCP 配置 | [26](26-setup-http-mcp.svg) | HTTP MCP 配置 |
| [27](27-setup-music-adapter.svg) | 网易云音乐适配器 |

重新生成画板：

```sh
python3 docs/macos-glass-ui/design-draft-v7/render_designs.py
```

完整设计说明见[设计稿 v7.0](../design-draft-v7.md)；代码模块、用户操作和状态覆盖见[功能覆盖矩阵](feature-coverage.md)。
