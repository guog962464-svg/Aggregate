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
| B001 | `app/lib/app/app_shell.dart:317` | 应用外壳：顶部操作、全局导航 | 2026-11-18 暗色首页实窗图 `01-home-dark.png`；仅签收截图中可见实例，其他页面/主题/状态待核 |
| B002 | `app/lib/app/app_shell.dart:364` | 应用外壳：顶部操作、全局导航 | 2026-11-18 暗色首页实窗图 `01-home-dark.png`；仅签收截图中可见实例，其他页面/主题/状态待核 |
| B003 | `app/lib/app/app_shell.dart:399` | 应用外壳：顶部操作、全局导航 | 2026-11-18 暗色首页实窗图 `01-home-dark.png`；仅签收截图中可见实例，其他页面/主题/状态待核 |
| B004 | `app/lib/app/app_shell.dart:620` | 应用外壳：顶部操作、全局导航 | 2026-11-18 暗色首页实窗图 `01-home-dark.png`；仅签收截图中可见实例，其他页面/主题/状态待核 |
| B005 | `app/lib/features/activity/activity_page.dart:116` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B006 | `app/lib/features/activity/activity_page.dart:172` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B007 | `app/lib/features/activity/activity_page.dart:229` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B008 | `app/lib/features/activity/activity_page.dart:263` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B009 | `app/lib/features/activity/activity_page.dart:282` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B010 | `app/lib/features/activity/activity_page.dart:292` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B011 | `app/lib/features/activity/activity_page.dart:303` | 活动页：记录操作与列表状态 | 既有活动页截图；逐实例待核 |
| B012 | `app/lib/features/catalog/workspace_page.dart:183` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B013 | `app/lib/features/catalog/workspace_page.dart:239` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B014 | `app/lib/features/catalog/workspace_page.dart:246` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B015 | `app/lib/features/catalog/workspace_page.dart:253` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B016 | `app/lib/features/catalog/workspace_page.dart:265` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B017 | `app/lib/features/catalog/workspace_page.dart:344` | 工作台：功能行及收藏操作 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B018 | `app/lib/features/connections/action_editor_dialog.dart:255` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B019 | `app/lib/features/connections/action_editor_dialog.dart:260` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B020 | `app/lib/features/connections/action_editor_dialog.dart:266` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B021 | `app/lib/features/connections/action_editor_dialog.dart:336` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B022 | `app/lib/features/connections/action_editor_dialog.dart:366` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B023 | `app/lib/features/connections/action_editor_dialog.dart:372` | 连接管理：动作编辑对话框 | 无对应对话框截图 |
| B024 | `app/lib/features/connections/connection_setup_dialog.dart:477` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B025 | `app/lib/features/connections/connection_setup_dialog.dart:483` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B026 | `app/lib/features/connections/connection_setup_dialog.dart:757` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B027 | `app/lib/features/connections/connection_setup_dialog.dart:765` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B028 | `app/lib/features/connections/connection_setup_dialog.dart:785` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B029 | `app/lib/features/connections/connection_setup_dialog.dart:818` | 连接管理：创建/编辑连接对话框 | 无对应对话框截图 |
| B030 | `app/lib/features/connections/connection_setup_target_dialog.dart:50` | 连接管理：新增连接目标选择对话框 | 无对应对话框截图 |
| B031 | `app/lib/features/connections/connection_setup_target_dialog.dart:72` | 连接管理：新增连接目标选择对话框 | 无对应对话框截图 |
| B032 | `app/lib/features/connections/connection_setup_target_dialog.dart:87` | 连接管理：新增连接目标选择对话框 | 无对应对话框截图 |
| B033 | `app/lib/features/connections/connections_page.dart:173` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B034 | `app/lib/features/connections/connections_page.dart:179` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B035 | `app/lib/features/connections/connections_page.dart:236` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B036 | `app/lib/features/connections/connections_page.dart:332` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B037 | `app/lib/features/connections/connections_page.dart:366` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B038 | `app/lib/features/connections/connections_page.dart:425` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B039 | `app/lib/features/connections/connections_page.dart:431` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B040 | `app/lib/features/connections/connections_page.dart:440` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B041 | `app/lib/features/connections/connections_page.dart:445` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B042 | `app/lib/features/connections/connections_page.dart:450` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B043 | `app/lib/features/connections/connections_page.dart:500` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B044 | `app/lib/features/connections/connections_page.dart:724` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B045 | `app/lib/features/connections/connections_page.dart:747` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B046 | `app/lib/features/connections/connections_page.dart:768` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B047 | `app/lib/features/connections/connections_page.dart:774` | 连接管理：连接行、筛选与操作 | 既有连接管理页面截图；对话框/状态仍待核 |
| B048 | `app/lib/features/invocation/capability_run_page.dart:401` | 功能调用：运行表单与结果页 | 未捕获：PreviewRuntime 会跳过执行确认对话框；确认按钮实例仍待核 |
| B049 | `app/lib/features/invocation/capability_run_page.dart:407` | 功能调用：运行表单与结果页 | 未捕获：PreviewRuntime 会跳过执行确认对话框；确认按钮实例仍待核 |
| B050 | `app/lib/features/invocation/capability_run_page.dart:581` | 功能调用：运行表单与结果页 | 2026-11-18 暗色实窗表单图 `03-run-form-dark.png`；运行按钮位置可见，busy/disabled 与浅色待核 |
| B051 | `app/lib/features/invocation/capability_run_page.dart:590` | 功能调用：运行表单与结果页 | 未捕获：PreviewRuntime 隐藏终端按钮，真实终端路径未启用 |
| B052 | `app/lib/features/invocation/capability_run_page.dart:597` | 功能调用：运行表单与结果页 | 未捕获：演示调用未停留在活动运行态，取消按钮未呈现 |
| B053 | `app/lib/features/invocation/schema_form.dart:286` | 功能调用：动态参数表单字段 | 2026-11-18 暗色实窗表单图 `03c-run-form-after-keypress.png`、`03d-run-form-focus-path.png`；只见基础数字字段，复杂字段/浅色/校验状态待核 |
| B054 | `app/lib/features/invocation/schema_form.dart:335` | 功能调用：动态参数表单字段 | 暗色 JSON 表单图 `33-json-form-dark.png`、`34-json-form-expanded-dark.png`；展开后 AX 名称变为“收起 JSON 编辑器”，未修改内容 |
| B055 | `app/lib/features/invocation/terminal_page.dart:275` | 功能调用：终端输出与输入 | 无终端页截图 |
| B056 | `app/lib/features/invocation/terminal_page.dart:388` | 功能调用：终端输出与输入 | 无终端页截图 |
| B057 | `app/lib/features/invocation/terminal_page.dart:419` | 功能调用：终端输出与输入 | 无终端页截图 |
| B058 | `app/lib/features/invocation/terminal_page.dart:427` | 功能调用：终端输出与输入 | 无终端页截图 |
| B059 | `app/lib/features/invocation/terminal_page.dart:469` | 功能调用：终端输出与输入 | 无终端页截图 |
| B060 | `app/lib/features/music/music_account_control.dart:105` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B061 | `app/lib/features/music/music_account_control.dart:200` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B062 | `app/lib/features/music/music_account_control.dart:206` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B063 | `app/lib/features/music/music_account_control.dart:394` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B064 | `app/lib/features/music/music_account_control.dart:473` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B065 | `app/lib/features/music/music_account_control.dart:480` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B066 | `app/lib/features/music/music_account_control.dart:488` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B067 | `app/lib/features/music/music_account_control.dart:497` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B068 | `app/lib/features/music/music_account_control.dart:507` | 网易云音乐：账户/授权控制 | 无账户面板截图 |
| B069 | `app/lib/features/music/music_mini_player.dart:23` | 音乐控制确认（由全局迷你播放器触发） | 暗色暂停确认图 `27-mini-player-pause-confirm-dark.png`；取消按钮可见并取消，未执行播放控制 |
| B070 | `app/lib/features/music/music_mini_player.dart:29` | 音乐控制确认（由全局迷你播放器触发） | 暗色暂停确认图 `27-mini-player-pause-confirm-dark.png`；执行按钮可见，未点击 |
| B071 | `app/lib/features/music/music_mini_player.dart:68` | 全局迷你播放器 | 暗色图 `26-mini-player-dark.png` 显示样例播放态与控制按钮；点暂停后打开确认图 `27-mini-player-pause-confirm-dark.png` 并取消；样例状态不是实际播放 |
| B072 | `app/lib/features/music/music_mini_player.dart:407` | 全局迷你播放器：展开控制区 | 暗色迷你播放器图 `26-mini-player-dark.png`；上一首、暂停、下一首、停止和刷新等控制按钮可见；未触发控制 |
| B073 | `app/lib/features/music/music_player_page.dart:201` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；取消按钮可见，之后在内存预览中授权本次搜索 |
| B074 | `app/lib/features/music/music_player_page.dart:207` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；允许按钮可见并用于内存预览搜索，不访问外部服务 |
| B075 | `app/lib/features/music/music_player_page.dart:236` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；取消按钮可见并取消，未执行播放命令 |
| B076 | `app/lib/features/music/music_player_page.dart:242` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；执行按钮可见，未点击 |
| B077 | `app/lib/features/music/music_player_page.dart:512` | 网易云音乐：播放器与搜索入口 | 2026-11-18 暗色播放启动图 `06-music-starting-dark.png`；仅见 busy 状态的停止按钮，未测可用点击 |
| B078 | `app/lib/features/music/music_player_page.dart:603` | 网易云音乐：播放器与搜索入口 | 2026-11-18 暗色音乐主页图 `05-music-search-results-dark.png`、`06-music-starting-dark.png`；PreviewRuntime 未到稳定播放态 |
| B079 | `app/lib/features/music/music_search_results.dart:180` | 网易云音乐：搜索结果操作 | 2026-11-18 暗色非空搜索图 `05-music-search-results-dark.png`；可播放/不可播放行的操作差异已目视，点击动画/浅色待核 |
| B080 | `app/lib/features/settings/appearance_selector.dart:48` | 设置：明暗主题选择器 | 既有设置页及焦点截图；逐实例/动态状态待核 |
| B081 | `app/lib/features/settings/settings_page.dart:37` | 设置：通用操作与本机数据 | 既有设置页截图；逐实例待核 |
| B082 | `app/lib/features/settings/settings_page.dart:43` | 设置：通用操作与本机数据 | 既有设置页截图；逐实例待核 |
| B083 | `app/lib/features/settings/settings_page.dart:130` | 设置：通用操作与本机数据 | 既有设置页截图；逐实例待核 |
| B084 | `app/lib/platform/macos/mac_host_settings_panel.dart:267` | 设置：Mac Host 配对和权限操作 | 暗色撤销确认图 `32-host-revoke-confirm-dark.png`；取消按钮可见并取消，未撤销设备 |
| B085 | `app/lib/platform/macos/mac_host_settings_panel.dart:273` | 设置：Mac Host 配对和权限操作 | 暗色撤销确认图 `32-host-revoke-confirm-dark.png`；危险操作按钮可见，未点击 |
| B086 | `app/lib/platform/macos/mac_host_settings_panel.dart:307` | 设置：Mac Host 配对和权限操作 | 暗色身份轮换确认图 `28-host-rotate-confirm-dark.png`；取消按钮可见并取消，未轮换身份 |
| B087 | `app/lib/platform/macos/mac_host_settings_panel.dart:313` | 设置：Mac Host 配对和权限操作 | 暗色身份轮换确认图 `28-host-rotate-confirm-dark.png`；危险操作按钮可见，未点击 |
| B088 | `app/lib/platform/macos/mac_host_settings_panel.dart:463` | 设置：Mac Host 配对和权限操作 | 暗色 Host 停止/运行图 `17-settings-host-stopped-dark.png`、`18-settings-host-running-dark.png`；只核静态状态，按钮点击动效/浅色待核 |
| B089 | `app/lib/platform/macos/mac_host_settings_panel.dart:501` | 设置：Mac Host 配对和权限操作 | 暗色运行态图 `18-settings-host-running-dark.png`；轮换入口静态外观已目视，确认流程待核 |
| B090 | `app/lib/platform/macos/mac_host_settings_panel.dart:549` | 设置：Mac Host 配对和权限操作 | 暗色待处理/已配对图 `20-settings-host-pairing-dark.png`；新邀请入口静态外观已目视，弹窗待核 |
| B091 | `app/lib/platform/macos/mac_host_settings_panel.dart:583` | 设置：Mac Host 配对和权限操作 | 暗色假邀请详情图 `30-host-invitation-dark.png`；复制按钮可见，未点击；二维码和 loopback 地址均为内存 stub 数据 |
| B092 | `app/lib/platform/macos/mac_host_settings_panel.dart:616` | 设置：Mac Host 配对和权限操作 | 暗色待处理/已配对图 `20-settings-host-pairing-dark.png`；仅静态外观已目视 |
| B093 | `app/lib/platform/macos/mac_host_settings_panel.dart:662` | 设置：Mac Host 配对和权限操作 | 暗色待处理/已配对图 `20-settings-host-pairing-dark.png`；仅静态外观已目视 |
| B094 | `app/lib/platform/macos/mac_host_settings_panel.dart:669` | 设置：Mac Host 配对和权限操作 | 暗色图 `20-settings-host-pairing-dark.png` 可见按钮；点击后 `22-host-approved-dark.png` 显示待处理项消失、已配对数变为 2；操作为内存 stub |
| B095 | `app/lib/platform/macos/mac_host_settings_panel.dart:680` | 设置：Mac Host 配对和权限操作 | 暗色待处理/已配对图 `20-settings-host-pairing-dark.png`；仅静态外观已目视 |
| B096 | `app/lib/platform/macos/mac_host_settings_panel.dart:695` | 设置：Mac Host 配对和权限操作 | 暗色待处理图 `20-settings-host-pairing-dark.png`；打开后的自定义权限弹窗见 `21-host-custom-permissions-dark.png`，取消退出 |
| B097 | `app/lib/platform/macos/mac_host_settings_panel.dart:720` | 设置：Mac Host 配对和权限操作 | 暗色配对设备图 `20-settings-host-pairing-dark.png` 可见修改入口；设备权限弹窗见 `31-host-edit-permissions-dark.png`，只查看后取消 |
| B098 | `app/lib/platform/macos/mac_host_settings_panel.dart:726` | 设置：Mac Host 配对和权限操作 | 暗色配对设备图 `20-settings-host-pairing-dark.png` 可见撤销入口；确认弹窗见 `32-host-revoke-confirm-dark.png`，只查看后取消 |
| B099 | `app/lib/platform/macos/mac_host_settings_panel.dart:951` | 设置：Mac Host 配对和权限操作 | 暗色设备权限弹窗图 `31-host-edit-permissions-dark.png`；取消按钮可见并用于退出，未修改权限 |
| B100 | `app/lib/platform/macos/mac_host_settings_panel.dart:957` | 设置：Mac Host 配对和权限操作 | 暗色设备权限弹窗图 `31-host-edit-permissions-dark.png`；保存按钮可见，未点击 |
| B101 | `app/lib/platform/macos/mac_host_settings_panel.dart:982` | 设置：Mac Host 配对和权限操作 | 暗色设备权限弹窗图 `31-host-edit-permissions-dark.png`；逐连接权限选项可见，未更改 |
| B102 | `app/lib/widgets/capability_row.dart:35` | 工作台/搜索：功能行 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B103 | `app/lib/widgets/capability_row.dart:50` | 工作台/搜索：功能行 | 2026-11-18 暗色工作台实窗图 `02-workspace-dark.png`；截图中可见实例已目视，浅色/动态状态待核 |
| B104 | `app/lib/widgets/page_state.dart:47` | 通用页面：空态/错误态动作 | 无空态/错误态截图 |
| B105 | `app/lib/widgets/result_panel.dart:74` | 调用结果：复制、展开与结果操作 | 2026-11-18 暗色成功结果图 `04-run-result-dark.png`；仅复制按钮静态外观已目视，复制动作未验证 |
| B106 | `app/lib/widgets/result_panel.dart:238` | 调用结果：复制、展开与结果操作 | 暗色本地模拟失败结果图 `35-simulated-error-result-dark.png`、`36-simulated-error-result-scrolled-dark.png`、`37-simulated-error-detail-dark.png`；错误详情 AX 文本已核对；“检查活动状态”按钮只查看未点击 |
| B107 | `app/lib/widgets/result_panel.dart:288` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |
| B108 | `app/lib/widgets/result_panel.dart:364` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |
| B109 | `app/lib/widgets/result_panel.dart:376` | 调用结果：复制、展开与结果操作 | 无结果面板截图 |

## 当前结论

这张清单建立了调用点到页面的映射，不关闭 UI-6.7。现已为部分连接/动作对话框、终端、运行表单、音乐账户与搜索/播放确认、全局迷你播放器、Mac Host 邀请/权限/撤销/轮换确认、JSON 展开和本地模拟错误结果增加暗色隔离实窗证据。浅色对应页、逐个按钮的静置/点击动画，以及其余未覆盖的页面实例仍未签收；截图只证明画面中实际出现的实例与状态。
