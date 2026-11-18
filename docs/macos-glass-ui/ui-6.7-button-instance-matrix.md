# UI-6.7 生产按钮实例核对表

> 源码基准：`d6968a8bc388ec6e45f7acfb46ccedefd31cc680`。扫描 `app/lib` 得到 109 个生产按钮调用点，分布于 20 个文件。此表是源码定位清单；动态列表会由一个调用点生成多个运行时实例，因此 109 个调用点不等于 109 个最终实例。

## 核验规则

- 每个调用点都要在对应的 Profile 页面、弹窗或状态中定位，检查实际尺寸、对齐、相邻控件、文字长度及适用的 selected、busy、disabled 状态。
- 有浅深主题差异时两种主题都检查；动态按钮另观察静置与点击收尾，不用共享组件测试替代目视核验。
- “既有截图”仅表示该页面曾留有截图，截图拍摄时间晚于本表源码基准时仍需核对当前版本；这不代表调用点已签收。
- 现有 PreviewRuntime 不含 Mac Host 实际服务；该面板须用隔离的 stub fixture 或继续标记未验证，不得改用用户真实配对数据。

## 逐调用点清单

| 编号 | 当前源码位置 | 页面/控件上下文 | 当前证据状态 |
| --- | --- | --- | --- |
| B001 | `app/lib/app/app_shell.dart:317` | 应用外壳：顶部操作、全局导航 | 暗色首页 `01-home-dark.png`；浅色设置页 `38-settings-light.png` 可见全局搜索入口及侧栏；仅截图中可见实例，动态状态待核 |
| B002 | `app/lib/app/app_shell.dart:364` | 应用外壳：顶部操作、全局导航 | 暗色首页 `01-home-dark.png`；浅色设置页 `38-settings-light.png` 可见全局搜索入口及侧栏；仅截图中可见实例，动态状态待核 |
| B003 | `app/lib/app/app_shell.dart:399` | 应用外壳：顶部操作、全局导航 | 暗色首页 `01-home-dark.png`；浅色设置页 `38-settings-light.png` 可见全局搜索入口及侧栏；仅截图中可见实例，动态状态待核 |
| B004 | `app/lib/app/app_shell.dart:620` | 应用外壳：顶部操作、全局导航 | 暗色首页 `01-home-dark.png`；浅色设置页 `38-settings-light.png` 可见全局搜索入口及侧栏；仅截图中可见实例，动态状态待核 |
| B005 | `app/lib/features/activity/activity_page.dart:116` | 活动页：记录操作与列表状态 | 深色 `57-activity-dark.png`、浅色 `60b-activity-all-light-current.png` 可见刷新按钮；浅色失败筛选后触发刷新，样例仍在；局部实例已目视 |
| B006 | `app/lib/features/activity/activity_page.dart:172` | 活动页：记录操作与列表状态 | 深色活动图可见成功/失败/取消行；浅色失败行 `59c-activity-failed-list-light.png` 被选中并打开详情；全量列表含本地样例记录 |
| B007 | `app/lib/features/activity/activity_page.dart:229` | 活动页：记录操作与列表状态 | 深/浅截图可见七个筛选；浅色 Profile 实窗逐个选择成功、失败、取消、超时、运行中、结果待确认，列表各仅显示对应状态；点“全部”后恢复六类样例。仅本地 fixture，动态动效逐项和真实服务记录仍待核 |
| B008 | `app/lib/features/activity/activity_page.dart:263` | 活动页：记录操作与列表状态 | 浅深紧凑详情可见返回记录；浅色 `59c-activity-failed-list-light.png` 为点击后回到失败列表的状态 |
| B009 | `app/lib/features/activity/activity_page.dart:282` | 活动页：记录操作与列表状态 | 深浅失败详情 `58a-activity-failed-detail-dark-scrolled.png`、`59b-activity-failed-detail-light-scrolled.png` 可见“重新打开功能”；未打开功能。现有 widget 测试另覆盖运行中“查看运行”按钮 |
| B010 | `app/lib/features/activity/activity_page.dart:292` | 活动页：记录操作与列表状态 | 深/浅 Profile 的运行中列表及详情均已截图；两种主题滚至操作区后“取消运行”语义点击成功，AX 状态变为“已取消”。浅色按钮与 MiniPlayer 暂停控件 AX 矩形相隔 11 个逻辑像素。仅验证隔离内存 fixture，真实服务响应仍待核 |
| B011 | `app/lib/features/activity/activity_page.dart:303` | 活动页：记录操作与列表状态 | 深浅失败详情图可见“复制诊断”；未点击，系统剪贴板未改动 |
| B012 | `app/lib/features/catalog/workspace_page.dart:183` | 工作台：搜索框清除按钮 | 浅色 Profile 实窗用键盘输入 Git 后显示 3 项，点击清除恢复 17 项；见截图 82/84。深色与点击动效待核 |
| B013 | `app/lib/features/catalog/workspace_page.dart:239` | 工作台：空连接态添加 CLI | 浅色空态实窗点击后进入本机 Mac（预览）的 CLI 配置，并取消退出；截图 85/86。没有测试或保存，深色与动效待核 |
| B014 | `app/lib/features/catalog/workspace_page.dart:246` | 工作台：空连接态添加 MCP | 浅色空态实窗点击后进入本机 Mac（预览）的 stdio MCP 配置，并取消退出；截图 85/87。没有测试或保存，深色与动效待核 |
| B015 | `app/lib/features/catalog/workspace_page.dart:253` | 工作台：空连接态添加 HTTP MCP | HTTP-only 浅色实窗点击后进入本机 Mac（预览）的 HTTP MCP 配置，并取消退出；截图 88/89。未输入凭据、测试或保存，深色与动效待核 |
| B016 | `app/lib/features/catalog/workspace_page.dart:265` | 工作台：无匹配结果清除筛选 | 浅色 Profile 实窗在资源筛选下输入无匹配文本，点击清除恢复搜索、筛选及 17 项；见截图 83/84。深色与点击动效待核 |
| B017 | `app/lib/features/catalog/workspace_page.dart:344` | 工作台：类型筛选分段按钮 | 浅色 Profile 实窗逐项选择工具、资源、提示、CLI；AX 结果数依次为 3、1、1、12；恢复“全部”后为 17。截图及 SHA-256 见验收记录。仅签收筛选结果与静态外观，动效逐帧待核 |
| B018 | `app/lib/features/connections/action_editor_dialog.dart:255` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗点击新增后 AX 清单出现 `action1`；取消再打开恢复原有单项。截图 `90-action-editor-added.png`；深色仅有静态截图，动效仍待核 |
| B019 | `app/lib/features/connections/action_editor_dialog.dart:260` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗打开原生文件面板，因未选择文件而禁用“打开”；点击“取消”返回编辑器，未读文件。深色仅有静态截图 |
| B020 | `app/lib/features/connections/action_editor_dialog.dart:266` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗打开原生保存面板后点击“取消”；未选保存路径、未写文件。深色仅有静态截图 |
| B021 | `app/lib/features/connections/action_editor_dialog.dart:336` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗点击参数预览；AX 结果为 `["仅内存预览", "--help"]`，提示清单有效且不会运行程序。没有执行外部命令；深色仅有静态截图 |
| B022 | `app/lib/features/connections/action_editor_dialog.dart:366` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗点击取消后关闭；重开清单确认新增草稿已丢弃。`action_editor_test.dart` 回归覆盖取消后重开且未调用保存；截图 `94-action-editor-cancel-check.png` 为取消后的连接详情 |
| B023 | `app/lib/features/connections/action_editor_dialog.dart:372` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗保存后重开，AX 下拉项包含原动作与 `action1`；仅写入进程内 `Ui6InspectionRuntime`，退出即丢弃，不触碰磁盘或外部服务。Widget 回归覆盖新增、参数预览和保存；深色动态状态仍待核 |
| B024 | `app/lib/features/connections/connection_setup_dialog.dart:477` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 的配对 Mac 样例表单输入 `git` 并点击 Host 查找；内存 stub 返回未找到提示，没有运行命令或连接设备。截图 `100-connection-setup-host-detect-miss-light.png`；深色和动态状态待核 |
| B025 | `app/lib/features/connections/connection_setup_dialog.dart:483` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 本机 Mac 预览表单打开原生文件面板后取消；未选文件或读取文件。配置静态图 `52-connection-setup-light.png`、`52-connection-setup-dark.png` 另见；深色交互待核 |
| B026 | `app/lib/features/connections/connection_setup_dialog.dart:757` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 输入虚构路径后点击测试；隔离 stub 显示安全检查通过，未访问本机命令、网络或凭据。截图 `98-connection-setup-test-passed-light.png`；未使用真实连接 |
| B027 | `app/lib/features/connections/connection_setup_dialog.dart:765` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 的安全 stub 检查通过后 AX 显示保存按钮已启用；未点击，未新增连接。深色仍为静态配置图 |
| B028 | `app/lib/features/connections/connection_setup_dialog.dart:785` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 窗口以 540×700pt 进入紧凑分支；点击“关闭添加连接”后表单收起且草稿未保存，截图 `102-connection-setup-compact-light.png`。更正此前“实际宽度停在 768pt”的结论；小屏 Widget 回归也覆盖关闭与丢弃草稿 |
| B029 | `app/lib/features/connections/connection_setup_dialog.dart:818` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 表单点击取消后退出，没有保存连接；深色仅静态配置图 |
| B030 | `app/lib/features/connections/connection_setup_target_dialog.dart:50` | 连接管理：新增连接目标选择对话框 | 浅色 Profile 目标选择器见截图 `96-connection-target-light-current.png`；选择本机 Mac（预览）后进入隔离配置表单 `97-connection-setup-local-light-current.png`，没有连接真实设备 |
| B031 | `app/lib/features/connections/connection_setup_target_dialog.dart:72` | 连接管理：新增连接目标选择对话框 | 浅色 Profile 选择虚构的配对 Mac（样例），进入只连内存 stub 的配置表单 `99-connection-setup-paired-mac-light.png`；未连接设备 |
| B032 | `app/lib/features/connections/connection_setup_target_dialog.dart:87` | 连接管理：新增连接目标选择对话框 | 浅色 Profile 目标选择器的取消操作关闭弹窗；没有创建连接。截图 `96-connection-target-light-current.png`；深色取消交互待核 |
| B033 | `app/lib/features/connections/connections_page.dart:173` | 连接管理：连接行、筛选与操作 | 浅色紧凑删除确认弹窗见 `105-delete-confirm-light-compact.png`；点击取消后弹窗关闭，内存样例仍保留。深色图 `55-delete-confirm-dark.png` 另可见静态样式 |
| B034 | `app/lib/features/connections/connections_page.dart:179` | 连接管理：连接行、筛选与操作 | 浅色紧凑删除确认弹窗中危险删除按钮可见但未点击；删除操作未确认，内存样例未删除。深色图 `55-delete-confirm-dark.png` 另可见静态样式 |
| B035 | `app/lib/features/connections/connections_page.dart:236` | 连接管理：连接行、筛选与操作 | 浅色紧凑连接页点击“添加连接”打开目标选择器；见 `101-connection-target-compact-light.png`。仅后续进入内存预览表单，没有创建连接 |
| B036 | `app/lib/features/connections/connections_page.dart:332` | 连接管理：连接行、筛选与操作 | 浅色紧凑 Git CLI 详情页点击“返回连接”后返回列表；详情见 `103-connection-detail-compact-light.png` |
| B037 | `app/lib/features/connections/connections_page.dart:366` | 连接管理：连接行、筛选与操作 | macOS 不适用：`app_shell.dart` 仅在 `_mobilePlatform` 下传入 `onOpenConnection`，此按钮只供移动端连接工作区使用，macOS 页面按设计不呈现 |
| B038 | `app/lib/features/connections/connections_page.dart:425` | 连接管理：连接行、筛选与操作 | 浅色紧凑首行上移按钮呈禁用状态；点击 Git CLI 的“连接下移”后列表顺序更新，见 `104-connection-actions-first-item-compact-light.png`。动态视觉仅核对此实例 |
| B039 | `app/lib/features/connections/connections_page.dart:431` | 连接管理：连接行、筛选与操作 | 浅色紧凑列表点击“连接下移”后以 AX 重新读取并确认顺序变化；见 `104-connection-actions-first-item-compact-light.png`。其余行及深色状态待核 |
| B040 | `app/lib/features/connections/connections_page.dart:440` | 连接管理：连接行、筛选与操作 | 浅色紧凑 Git CLI 详情点击“编辑动作”打开编辑器，清单显示原动作 `version`；点击取消返回详情，未保存；见 `106-action-editor-from-detail-compact-light.png` |
| B041 | `app/lib/features/connections/connections_page.dart:445` | 连接管理：连接行、筛选与操作 | 浅色紧凑 MCP 与 Git 样例分别点击“测试连接”；隔离 `Ui6InspectionRuntime.refreshConnection` 只返回内存连接，未运行外部服务或网络请求 |
| B042 | `app/lib/features/connections/connections_page.dart:450` | 连接管理：连接行、筛选与操作 | 浅色紧凑详情点击删除后打开确认弹窗；点击取消后弹窗关闭，未删除样例；见 `105-delete-confirm-light-compact.png` |
| B043 | `app/lib/features/connections/connections_page.dart:500` | 连接管理：连接行、筛选与操作 | 浅色紧凑 Git CLI 样例详情及其操作按钮见 `103-connection-detail-compact-light.png`；点击返回后列表恢复。深色动态状态待核 |
| B044 | `app/lib/features/connections/connections_page.dart:724` | 连接管理：通用创建连接对话框 | macOS 不适用：`LocalRuntimePort` 实现 `ConnectionSetupPort`，macOS 新建流程使用 `ConnectionSetupDialog`，其文件选择已由 B025 覆盖；通用 `AddConnectionDialog` 不在 macOS 路由中 |
| B045 | `app/lib/features/connections/connections_page.dart:747` | 连接管理：通用创建连接对话框 | macOS 不适用：动作清单选择属于通用 `AddConnectionDialog`；macOS 正式运行端走 `ConnectionSetupDialog`，不呈现此控件 |
| B046 | `app/lib/features/connections/connections_page.dart:768` | 连接管理：通用创建连接对话框 | macOS 不适用：通用 `AddConnectionDialog` 不在 macOS 正式运行端路由中；macOS 配置表单取消已由 B029 覆盖 |
| B047 | `app/lib/features/connections/connections_page.dart:774` | 连接管理：通用创建连接对话框 | macOS 不适用：通用 `AddConnectionDialog` 不在 macOS 正式运行端路由中；不以 PreviewRuntime 绕过“不能添加真实连接”保护来触发此按钮 |
| B048 | `app/lib/features/invocation/capability_run_page.dart:401` | 功能调用：运行表单与结果页 | 浅色隔离 Profile 对无参外部写入动作“暂停播放”打开确认并点击取消，确认框关闭、未执行；见 `108-write-confirm-light.png`。暗色同类确认状态待核 |
| B049 | `app/lib/features/invocation/capability_run_page.dart:407` | 功能调用：运行表单与结果页 | 同一浅色确认框内可见“执行”按钮，未点击；未执行写入。见 `108-write-confirm-light.png`；暗色待核 |
| B050 | `app/lib/features/invocation/capability_run_page.dart:581` | 功能调用：运行表单与结果页 | 浅色隔离 Profile 点击“暂停播放”的“运行”打开权限确认；见 `107-write-capability-form-light.png`、`108-write-confirm-light.png`。busy/disabled 状态待核 |
| B051 | `app/lib/features/invocation/capability_run_page.dart:590` | 功能调用：运行表单与结果页 | 浅色隔离 Profile 点击“在终端运行”并进入 UI 检查全内存终端 stub；界面明确说明不会运行外部命令。见 `111-terminal-action-form-light.png`、`112-terminal-stub-light.png` |
| B052 | `app/lib/features/invocation/capability_run_page.dart:597` | 功能调用：运行表单与结果页 | 使用 `UI6_SEED_ACTIVITY_RUNNING=true` 呈现内存 fixture 的运行态；点击取消后 AX 确认“运行状态：已取消”。取消前截图 `116-running-cancel-light.png`；不代表真实服务终态 |
| B053 | `app/lib/features/invocation/schema_form.dart:286` | 功能调用：动态参数表单字段 | 浅色 JSON 表单点击“格式化 JSON 参数”，有效默认 `{}` 未报错但没有可见格式变化；非空 JSON 格式化、字段校验与输入动画未验证。见 `109-json-form-format-light.png` |
| B054 | `app/lib/features/invocation/schema_form.dart:335` | 功能调用：动态参数表单字段 | 暗色图 `33-json-form-dark.png`、`34-json-form-expanded-dark.png`；浅色 Profile 验证展开/收起，AX 名称在“展开 JSON 编辑器”与“收起 JSON 编辑器”间切换。见 `110-json-editor-expanded-light.png` |
| B055 | `app/lib/features/invocation/terminal_page.dart:275` | 功能调用：终端输出与输入 | 浅色全内存终端点击“中断程序”后显示 `^C`；见 `115-terminal-interrupt-light.png`。未中断真实进程 |
| B056 | `app/lib/features/invocation/terminal_page.dart:388` | 功能调用：终端输出与输入 | 浅色全内存终端点击 Ctrl 后状态提示“Ctrl 已按下”，再发送 Tab 后提示清除；见 `113-terminal-key-input-light.png`、`114-terminal-key-interaction-light.png` |
| B057 | `app/lib/features/invocation/terminal_page.dart:419` | 功能调用：终端输出与输入 | 全内存终端无文本选择时“复制”呈禁用外观；未点击或读取终端剪贴内容。见 `112-terminal-stub-light.png` |
| B058 | `app/lib/features/invocation/terminal_page.dart:427` | 功能调用：终端输出与输入 | 浅色全内存终端“粘贴”可见但未点击，避免读取系统剪贴板；仅有静态画面证据 `112-terminal-stub-light.png` |
| B059 | `app/lib/features/invocation/terminal_page.dart:469` | 功能调用：终端输出与输入 | 浅色全内存终端仅验证 Tab 与 ↑ 两个按键控件产生本地交互；未逐项检查其余按键。见 `114-terminal-key-interaction-light.png` |
| B060 | `app/lib/features/music/music_account_control.dart:105` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证管理账号按钮打开面板；Widget 状态回归通过，未验证原生玻璃外观或动效 |
| B061 | `app/lib/features/music/music_account_control.dart:200` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证退出确认取消后不调用退出；仅 Widget 行为证据 |
| B062 | `app/lib/features/music/music_account_control.dart:206` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证确认退出后进入未登录态；仅 Widget 行为证据 |
| B063 | `app/lib/features/music/music_account_control.dart:394` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B064 | `app/lib/features/music/music_account_control.dart:473` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证取消扫码后会话关闭；仅 Widget 行为证据 |
| B065 | `app/lib/features/music/music_account_control.dart:480` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B066 | `app/lib/features/music/music_account_control.dart:488` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证确认退出并清除音乐会话授权；仅 Widget 行为证据 |
| B067 | `app/lib/features/music/music_account_control.dart:497` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证切换账号先退出再开始扫码登录；仅 Widget 行为证据 |
| B068 | `app/lib/features/music/music_account_control.dart:507` | 网易云音乐：账户/授权控制 | `music_account_control_test.dart` 验证扫码登录、取消与完成登录；仅使用内存测试 runtime |
| B069 | `app/lib/features/music/music_mini_player.dart:23` | 音乐控制确认（由全局迷你播放器触发） | 暗色暂停确认图 `27-mini-player-pause-confirm-dark.png`；取消按钮可见并取消，未执行播放控制 |
| B070 | `app/lib/features/music/music_mini_player.dart:29` | 音乐控制确认（由全局迷你播放器触发） | 暗色暂停确认图 `27-mini-player-pause-confirm-dark.png`；`connection_experience_test.dart` 验证执行后获得会话授权，未验证原生按钮动效 |
| B071 | `app/lib/features/music/music_mini_player.dart:68` | 全局迷你播放器 | 暗色图 `26-mini-player-dark.png` 与浅色 `38-settings-light.png`、`49-music-light.png` 显示样例播放态；`music_mini_player_test.dart` 的 macOS 变体验证同一玻璃播放按钮在暂停/继续图案间切换；样例状态不是实际播放 |
| B072 | `app/lib/features/music/music_mini_player.dart:407` | 全局迷你播放器：展开控制区 | 暗色图 `26-mini-player-dark.png` 与浅色 `38-settings-light.png`、`49-music-light.png`；`music_mini_player_test.dart` 验证播放器控件与溢出区、桌面停止/刷新入口；未触发真实播放控制 |
| B073 | `app/lib/features/music/music_player_page.dart:201` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；`music_search_permission_test.dart` 验证取消不授权；当前/Profile 真实画面未重验 |
| B074 | `app/lib/features/music/music_player_page.dart:207` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；`music_search_permission_test.dart` 验证允许后仅用 PreviewRuntime 返回样例结果 |
| B075 | `app/lib/features/music/music_player_page.dart:236` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；取消按钮可见并取消，未执行播放命令 |
| B076 | `app/lib/features/music/music_player_page.dart:242` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；执行按钮可见，未点击 |
| B077 | `app/lib/features/music/music_player_page.dart:512` | 网易云音乐：播放器与搜索入口 | 2026-11-18 暗色播放启动图 `06-music-starting-dark.png`；仅见 busy 状态的停止按钮，未测可用点击 |
| B078 | `app/lib/features/music/music_player_page.dart:603` | 网易云音乐：播放器与搜索入口 | 暗色音乐图 `05-music-search-results-dark.png`、`06-music-starting-dark.png`；浅色 `49-music-light.png`；`connection_experience_test.dart` 覆盖 PreviewRuntime 搜索样例并从结果播放，非真实服务 |
| B079 | `app/lib/features/music/music_search_results.dart:180` | 网易云音乐：搜索结果操作 | 暗色非空搜索图 `05-music-search-results-dark.png`；`music_search_results_lazy_test.dart` 与 `music_queue_controls_test.dart` 覆盖列表播放/加入下一首的 Widget 回调；玻璃动态与浅色原生状态待核 |
| B080 | `app/lib/features/settings/appearance_selector.dart:48` | 设置：明暗主题选择器 | 浅色 `38-settings-light.png` 可见主题控件；`glass_theme_switch_test.dart` 回归覆盖拖动满 450 ms 后仅在释放时提交、取消/隐藏拖动及减少动态效果；原生连续画面仍待核 |
| B081 | `app/lib/features/settings/settings_page.dart:37` | 设置：通用操作与本机数据 | 2026-11-18 深色清理确认图 `clear-dialog-dark-confirm.png`；实际取消后预置的成功/失败/已取消三条内存活动仍存在；浅深确认框见验收记录；按下动画关键帧待核 |
| B082 | `app/lib/features/settings/settings_page.dart:43` | 设置：通用操作与本机数据 | 2026-11-18 浅色清理确认图 `clear-dialog-light.png`；确认后隔离 `PreviewRuntime` 活动列表为空，见 `activity-empty-after-confirm-light.png`；不触碰持久数据；按下动画关键帧待核 |
| B083 | `app/lib/features/settings/settings_page.dart:130` | 设置：通用操作与本机数据 | 2026-11-18 设置页清空按钮在浅/深主题均可见并打开确认弹窗；截图 `local-data-light-before.png`、`local-data-dark-before.png`；只测试内存预览回调 |
| B084 | `app/lib/platform/macos/mac_host_settings_panel.dart:267` | 设置：Mac Host 配对和权限操作 | 暗色撤销确认图 `32-host-revoke-confirm-dark.png`；取消按钮可见并取消，未撤销设备 |
| B085 | `app/lib/platform/macos/mac_host_settings_panel.dart:273` | 设置：Mac Host 配对和权限操作 | 暗色撤销确认图 `32-host-revoke-confirm-dark.png`；`mac_host_settings_panel_test.dart` 用 fake pairing control 验证确认后撤销设备，不访问真实 Host |
| B086 | `app/lib/platform/macos/mac_host_settings_panel.dart:307` | 设置：Mac Host 配对和权限操作 | 暗色身份轮换图 `28-host-rotate-confirm-dark.png`；`mac_host_settings_panel_test.dart` 验证取消后不撤销、不停止 Host、不轮换 |
| B087 | `app/lib/platform/macos/mac_host_settings_panel.dart:313` | 设置：Mac Host 配对和权限操作 | 暗色身份轮换图 `28-host-rotate-confirm-dark.png`；`mac_host_settings_panel_test.dart` 验证确认后撤销、停止并轮换 fake Host 身份 |
| B088 | `app/lib/platform/macos/mac_host_settings_panel.dart:463` | 设置：Mac Host 配对和权限操作 | 2026-11-18 Profile 浅/深主题均点击启动与停止；`host-running-light.png`、`host-running-dark.png`、`host-stopped-after-click-light.png`、`host-stopped-after-click-dark.png`。假 Host 仅改进程内状态；确认无 44321 监听，Profile VM service loopback 仍在；按下动画关键帧待核 |
| B089 | `app/lib/platform/macos/mac_host_settings_panel.dart:501` | 设置：Mac Host 配对和权限操作 | 2026-11-18 浅色 Profile 打开身份轮换确认并取消；`host-identity-confirm-light.png`；AX 复核运行状态、假配对设备和邀请仍保留。确认轮换路径由 fake Widget 回归覆盖，本次未在实窗确认；按下动画待核 |
| B090 | `app/lib/platform/macos/mac_host_settings_panel.dart:549` | 设置：Mac Host 配对和权限操作 | 2026-11-18 浅色 Profile 启动假 Host 后点击生成邀请；`host-invitation-generated-light.png`，AX 读到邀请过期信息与 1 个本机网络地址。二维码被当前窗口底部区域部分遮挡，故只部分验收；没有网络配对，按下动画待核 |
| B091 | `app/lib/platform/macos/mac_host_settings_panel.dart:583` | 设置：Mac Host 配对和权限操作 | 暗色假邀请详情图 `30-host-invitation-dark.png`；复制按钮可见，未点击；二维码和 loopback 地址均为内存 stub 数据 |
| B092 | `app/lib/platform/macos/mac_host_settings_panel.dart:616` | 设置：Mac Host 配对和权限操作 | 2026-11-18 暗色隔离 Profile 待处理设备卡片及拒绝/只读/向导按钮见 `pairing-controls-dark.png`；真实 Host 未启动，内容来自假设备 |
| B093 | `app/lib/platform/macos/mac_host_settings_panel.dart:662` | 设置：Mac Host 配对和权限操作 | 2026-11-18 暗色隔离 Profile 已配对设备卡片见 `paired-devices-dark.png`，另见撤销取消后的 `revoke-cancelled-paired-remains-dark.png`；设备均为进程内假数据 |
| B094 | `app/lib/platform/macos/mac_host_settings_panel.dart:669` | 设置：Mac Host 配对和权限操作 | 2026-11-18 在假 Host 中实际点击“批准只读”；待处理项消失，AX 读回一个已配对预览设备且仅“读取连接”范围；结果图 `readonly-approved-dark.png` |
| B095 | `app/lib/platform/macos/mac_host_settings_panel.dart:680` | 设置：Mac Host 配对和权限操作 | 2026-11-18 通过假 Host 停止/启动重新注入待处理样例后点击“允许连接向导”；待处理项消失，AX 读回“读取连接 · 连接向导”；操作没有网络请求，结果状态见 `revoke-cancelled-paired-remains-dark.png` |
| B096 | `app/lib/platform/macos/mac_host_settings_panel.dart:695` | 设置：Mac Host 配对和权限操作 | 2026-11-18 打开自定义权限弹窗 `custom-permission-dialog-dark.png`；对 Git CLI 假连接选本机控制（自动包含读取）及连接向导后批准，AX 确认假设备获得连接向导；`paired-devices-dark.png` |
| B097 | `app/lib/platform/macos/mac_host_settings_panel.dart:720` | 设置：Mac Host 配对和权限操作 | 2026-11-18 打开已配对设备修改弹窗 `edit-permission-dialog-dark.png`；回读此前本机控制选择，另选连接管理及 Git CLI 外部写入后保存；AX 确认范围更新，操作仅写入假 Host 内存 |
| B098 | `app/lib/platform/macos/mac_host_settings_panel.dart:726` | 设置：Mac Host 配对和权限操作 | 2026-11-18 暗色 Profile 打开 `revoke-confirm-dark.png` 后取消；AX 仍读到已配对预览设备。取消后的设备列表截图 `revoke-cancelled-paired-remains-dark.png`；未撤销任何真实设备 |
| B099 | `app/lib/platform/macos/mac_host_settings_panel.dart:951` | 设置：Mac Host 配对和权限操作 | 2026-11-18 在已配对设备的 Profile 权限弹窗中实际点击“取消”；弹窗关闭，原 grant 未改变。静置图 `edit-permission-dialog-dark.png`；无按下关键帧 |
| B100 | `app/lib/platform/macos/mac_host_settings_panel.dart:957` | 设置：Mac Host 配对和权限操作 | 2026-11-18 编辑假 grant 后实际点击“保存权限”；AX scope 更新为读取连接、连接向导、连接管理。动作及保存后 AX 证据见 UI-6.7 Host 配对/权限验收；写入仅在 fake control 内存中 |
| B101 | `app/lib/platform/macos/mac_host_settings_panel.dart:982` | 设置：Mac Host 配对和权限操作 | 2026-11-18 在自定义批准与已配对编辑弹窗中点选 Git CLI 的本机控制、外部写入；AX 读回对应选择及自动包含的读取权限。静态弹窗图 `custom-permission-dialog-dark.png`、`edit-permission-dialog-dark.png`；实际操作为 fake grant |
| B102 | `app/lib/widgets/capability_row.dart:35` | 工作台/搜索：功能行 | 2026-11-18 暗色 Profile 点击“两个整数相加”行后打开参数页，结果状态仍为“尚未运行”；`feature-open-form-dark.png`。没有点运行，未调用 Runtime。 |
| B103 | `app/lib/widgets/capability_row.dart:50` | 工作台/搜索：功能行 | 2026-11-18 暗色 Profile 点击“收藏 两个整数相加”，出现收藏分组和“取消收藏”按钮；随后取消并确认空收藏恢复。收藏仅改动 `PreviewRuntime` 内存偏好；截图 `workspace-actions-dark.png`、`workspace-favorite-added-dark.png`。 |
| B104 | `app/lib/widgets/page_state.dart:47` | 通用页面：空态/错误态动作 | 2026-11-18 临时暗色 Profile 夹具呈现生产 `PageState.error`，点击“重试”后 AX 计数由 0 变为 1；截图 `page-state-error-dark.png`。回调仅递增夹具计数，不代表真实数据重试；无按下关键帧、浅色图或帧率数据 |
| B105 | `app/lib/widgets/result_panel.dart:74` | 调用结果：复制、展开与结果操作 | 2026-11-18 暗色成功结果图 `04-run-result-dark.png`；仅复制按钮静态外观已目视，复制动作未验证 |
| B106 | `app/lib/widgets/result_panel.dart:238` | 调用结果：复制、展开与结果操作 | 暗色本地模拟失败结果图 `35-simulated-error-result-dark.png`、`36-simulated-error-result-scrolled-dark.png`、`37-simulated-error-detail-dark.png`；浅色中间滚动图 `48-error-result-light-scrolled.png` 本身不能证明最终位置；浅色原生 Profile 末尾图 `61-error-result-light-scroll-end.png` 显示恢复按钮及错误详情行完整位于 MiniPlayer 上方，再滚 12 个滚轮单位 AX 位置不变；`capability_run_page_test.dart` 同样验证最大滚动范围。“检查活动状态”按钮只查看未点击 |
| B107 | `app/lib/widgets/result_panel.dart:288` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |
| B108 | `app/lib/widgets/result_panel.dart:364` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |
| B109 | `app/lib/widgets/result_panel.dart:376` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |

## 当前结论

这张清单建立了调用点到页面的映射，不关闭 UI-6.7。现有证据覆盖部分连接/动作对话框、终端、运行表单、音乐搜索/播放确认、全局迷你播放器、Mac Host 邀请/权限/撤销/轮换确认、JSON 展开和本地模拟错误结果；少量音乐账号与播放器行为另有 Widget 回归，但不能代替原生页面验收。浅色对应页、逐个按钮的静置/点击动画，以及其余未覆盖的页面实例仍未签收；截图只证明画面中实际出现的实例与状态。

2026-11-18 组件级补证：隔离 96 dp Profile fixture 使用共享 `GlassActionButton` 实际呈现运行、刷新、搜索的浅深静置态和点击反馈，详细帧与哈希见[验收记录](acceptance-record.md#2026-11-18-ui-67-三枚主图标点击反馈增强与-profile-复核)。该 fixture 验证共享组件的三种动作 profile，不映射或签收表中任何特定生产调用点；109 个调用点仍需逐实例跟进。
