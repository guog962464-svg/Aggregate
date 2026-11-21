# Aggregate 全功能设计稿 v9.0.3 · 画板目录

27 张页面与适配器画板统一为 **1360×900 logical pt**。它们先定义要实现的版式、按钮表面、点阵剪影、光效和功能状态；实现阶段再用同一 Runtime fixture 启动 Flutter Profile 实窗，逐屏并排验收。外壳沿用既有窗口边界：32 pt 原生标题栏 + 40 pt Flutter 工具栏；侧栏宽 240 pt，正文左缘 x=280。主题开关原始截图是雾银背景、乳白玻璃、石墨点阵与琥珀弧光的唯一材质参照；主题开关逻辑保持冻结。

v9.0 全新设计了导航和按钮层级：普通连接及内容行回到背景平面，只有当前导航使用浅玻璃落面；操作按钮保留柔软体积和上缘光，不再把每一项都画成同款凸起胶囊。运行、刷新和搜索的 9×9 点阵重新校正方向、比例与剪影。05/06/15/22 是同一条连续设置页的四个滚动位置。v9.0.1 将 17/21 的连接状态标签校准为 Profile 安全 Runtime 实际提供的连接名与执行目标；v9.0.2 将 02/14 的音乐账号入口固定在播放器信息区，避免画板遗漏可发现的入口；v9.0.3 补齐 13 的参数检查交互，并使连接配置、配对设备和 Host 权限样例与安全内存 Runtime 一致。每张画板的样例状态和入口见主稿第 9 节；样例只存在于内存 Runtime。

画板覆盖当前 macOS 用户路径：工作台、CLI/MCP/音乐连接、参数与结果、终端、执行授权、历史活动、设置、Host、连接向导、账号登录、播放器和危险确认。状态变体、窄窗规则与页面入口见[功能覆盖矩阵](feature-coverage.md)。所有样例只在安全预览 Runtime 中使用；MCP 首页仅展示当前合同支持的工具、资源和提示，不展示未接入的资源模板。

| 画板 | 页面 | 画板 | 页面 |
| --- | --- | --- | --- |
| [01](01-workspace.svg) | 工作台 / 参数 / 结果 | [13](13-action-editor.svg) | 动作 JSON 编辑 |
| [02](02-music.svg) | 音乐播放与搜索 | [14](14-music-account-login.svg) | 音乐账号 |
| [03](03-connections.svg) | 连接管理 | [15](15-settings-shortcuts.svg) | 设置页滚动至快捷键 |
| [04](04-activity.svg) | 活动记录 | [16](16-result-success.svg) | 成功结果 |
| [05](05-settings-appearance.svg) | 设置页顶部 / 外观 | [17](17-connection-home.svg) | CLI 连接首页 |
| [06](06-settings-host.svg) | 设置页滚动至 Mac Host | [18](18-mini-player.svg) | 活动空态 + 迷你播放器 |
| [07](07-connection-setup.svg) | 添加连接配置 | [19](19-target-selector.svg) | 执行目标选择 |
| [08](08-terminal-running.svg) | 交互终端 | [20](20-host-permissions.svg) | Host 权限 |
| [09](09-permission-confirmation.svg) | 执行授权 | [21](21-mcp-home.svg) | MCP 连接首页 |
| [10](10-states.svg) | 通用状态 | [22](22-settings-local-data.svg) | 设置页滚动至本机数据 |
| [11](11-button-motion.svg) | 按钮静置/点击态 | [23](23-danger-confirmation.svg) | 危险操作确认 |
| [12](12-dark-reference.svg) | 深色工作台 | [24](24-result-unknown.svg) | 结果待确认 |
| [25](25-setup-stdio-mcp.svg) | stdio MCP 配置 | [26](26-setup-http-mcp.svg) | HTTP MCP 配置 |
| [27](27-setup-music-adapter.svg) | 网易云音乐适配器 |

重新生成 27 张画板：

```sh
python3 docs/macos-glass-ui/design-draft-v9/render_designs.py
```

完整设计说明见[设计稿 v9.0.3](../design-draft-v9.md)；代码模块、用户操作和状态覆盖见[功能覆盖矩阵](feature-coverage.md)。设计阶段锁定前不开始对应的生产页面改造。
