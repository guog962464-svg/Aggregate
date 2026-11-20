# Aggregate 全功能设计稿 v6.6 · 画板目录

27 张页面与适配器画板统一为 **1360×900 logical pt**，窗口边缘、40pt 顶栏、240pt 侧栏和底部播放器按 macOS Profile 逻辑窗口取样。侧栏连接与导航以低亮玻璃操作面呈现，当前项单独加强；点阵掩码和圆角单元尺寸从 Flutter 生产 glyph/token 读取，运行、刷新、搜索使用本版重新设计的 9×9 掩码。05 外观画板仍包含生产主题切换控件截图，作为不可修改的材质参照。样例数据仅用于设计检查。能力分类以当前 Runtime 合同为准：MCP 首页含工具、资源和提示，不展示尚未接入的资源模板。工作台和成功结果目录遵循 Runtime 标题排序；16 号画板显示滚动到 Git 结果后的真实可见窗口。播放器可见时，侧栏设置和状态位置按底部播放器占用区收起；连接名称、能力数量、弹窗入口背景与可见音乐会话都绑定到文档列出的预览 Runtime 和状态步骤。

| 画板 | 页面 | 画板 | 页面 |
| --- | --- | --- | --- |
| [01](01-workspace.svg) | 工作台 / 参数 / 结果 | [13](13-action-editor.svg) | 动作 JSON 编辑 |
| [02](02-music.svg) | 音乐播放与搜索 | [14](14-music-account-login.svg) | 音乐账号 |
| [03](03-connections.svg) | 连接管理 | [15](15-settings-shortcuts.svg) | 快捷键 |
| [04](04-activity.svg) | 活动记录 | [16](16-result-success.svg) | 成功结果 |
| [05](05-settings-appearance.svg) | 外观与主题切换 | [17](17-connection-home.svg) | CLI 连接首页 |
| [06](06-settings-host.svg) | Mac Host | [18](18-mini-player.svg) | 迷你播放器 |
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
python3 docs/macos-glass-ui/design-draft-v6/render_designs.py
```

完整设计说明、尺寸、状态和功能映射见[设计稿 v6.6](../design-draft-v6.md)。
