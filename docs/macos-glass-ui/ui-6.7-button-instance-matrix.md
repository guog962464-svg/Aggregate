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
| B001 | `app/lib/app/app_shell.dart:676` | 应用外壳：顶部操作、全局导航 | 2026-11-19 暗色 Profile：全局搜索入口 AX 192×40，点击后进入“所有功能”并显示搜索字段；同日浅色 Profile 重新核对 192×40，实鼠标按住/释放样本和路由回读见验收记录。补采暗色按下样本：截图请求在 MouseDown 后 86.7ms，调用完成于 179.3ms；释放后切页，后续样本不再包含搜索图案。时序受截图调用延迟限制；其他页面/状态待核 |
| B002 | `app/lib/app/app_shell.dart:395` | 应用外壳：侧栏连接导航项 | 2026-11-19 macOS Profile，540×700pt 隔离夹具：浅/深主题分别从抽屉点击“UI 检查 · Git CLI”，均进入 Git CLI 页面并显示 3 条样例动作。2026-11-21 在独立 800×632pt Profile 副本复核 selected：浅/深均选中“示例 Git CLI”，AX 页面标题读回且显示 3 项样例动作；指针移到空白区域后选中底板仍可见。新截图和 SHA 见验收记录。只签收双主题静置 selected 外观与路由；动画关键帧、display-present/FPS 仍待核 |
| B003 | `app/lib/app/app_shell.dart:435` | 应用外壳：分区导航项（活动） | 2026-11-19 macOS Profile，540×700pt 隔离夹具：浅/深主题分别点击侧栏“活动”，均进入活动页并显示筛选区。浅色图 `aggregate-ui6-7-sidebar-profile/03-activity-light.png`；深色图 `07-activity-dark.png`；深色打开侧栏后的当前项见 `08-activity-navigation-dark.png`。2026-11-21 在独立 800×632pt Profile 副本补核 selected：浅/深各点击“活动”进入活动页，将指针移至内容空白处后选中底板仍可见，截图及 SHA 见验收记录。只签收双主题静置选中外观与路由；动画关键帧、display-present/FPS、其他生产调用点仍待核 |
| B004 | `app/lib/app/app_shell.dart:703` | 应用外壳：顶部操作、全局导航 | 当前此调用点位于 `if (macOS) ... else AggregateIconButton` 的非 macOS 搜索回退分支，与 B001 共用 `searchAll` 逻辑，不是第二个 macOS 搜索实例；macOS 正式分支由 B001 的 `AggregateActionButton` 呈现。此非 macOS 回退不属于当前发行目标，尚未验收其静置/点击视觉。 |
| B005 | `app/lib/features/activity/activity_page.dart:116` | 活动页：记录操作与列表状态 | 2026-11-19 两主题实鼠标按住/释放后仍留活动页；按钮 AX 46×46。2026-11-21 隔离 Profile 用 ScreenCaptureKit `SCStreamUpdateFrameDisplayTime` 采集双主题释放后 0–650ms 指定时点；96 个 WindowServer 回调，深色目标序列漏 133.3ms，浅色无缺点。指针释放后移至空白侧沟；刷新只重设 `listRecentRuns()` future，未调用真实服务。证据 SHA、有限采样和非面板 FPS 限制见验收记录；UI-6.7 仍部分验收 |
| B006 | `app/lib/features/activity/activity_page.dart:172` | 活动页：记录操作与列表状态 | 深色活动图可见成功/失败/取消行；浅色失败行 `59c-activity-failed-list-light.png` 被选中并打开详情；全量列表含本地样例记录 |
| B007 | `app/lib/features/activity/activity_page.dart:229` | 活动页：记录操作与列表状态 | 深/浅 Profile（800×720pt、DPR 2）对“全部、成功、失败、取消、超时、运行中、结果待确认”七项各实鼠标点击一次，共 14 组。各项 +200ms WindowServer 窗口帧均采到；指针移出后对应筛选仍呈选中底板，成功/失败/取消显示匹配的 fixture 行，其余无匹配状态显示空态。深色目标漏：运行中 550ms、结果待确认 0ms；浅色目标漏：全部 100ms、成功 33.3ms、取消 0ms、超时 0ms、运行中 0/650ms、结果待确认 66.7ms。完整 timing JSON 哈希与截图见验收记录。只验本地 fixture 和当前 7 个筛选实例，不代表其他 108 个调用点；FrameTiming、连续动画和物理面板 FPS 仍未验 |
| B008 | `app/lib/features/activity/activity_page.dart:427` | 活动页：记录操作与列表状态 | 浅深主题 800×720pt Profile 中从失败详情实鼠标点击“返回记录”，均回到活动列表；AX 确认详情消失、失败记录恢复且失败筛选保持选中。AX target 115×40；WindowServer 0–650ms 15 个指定目标两主题全采到，98/99 个回调。源码只 `setState(selected=null)`。截图和 timing JSON SHA 见验收记录；只核 B008 本地 fixture 点击/路由，不代表连续动画曲线或面板 FPS |
| B009 | `app/lib/features/activity/activity_page.dart:282` | 活动页：记录操作与列表状态 | 深浅失败详情 `58a-activity-failed-detail-dark-scrolled.png`、`59b-activity-failed-detail-light-scrolled.png` 可见“重新打开功能”。旧浅色路径与 Profile 截图见下方验收记录；2026-11-21 在 800×720pt 深/浅 Profile 先 `scroll-to` 保证按钮完整可见（AX 141×40），再实鼠标点击：两主题均进入“两整数相加”参数页，AX 状态保持“尚未运行”。源码回调只检索能力并调用 `widget.onOpen`，未执行操作。ScreenCaptureKit 释放后样本：深色 15 个目标齐全；浅色漏 66.7ms，其余时点齐全。完整截图、timing JSON 哈希和隔离 fixture 边界见验收记录；此证据仅签收 B009 路由/安全结果及所采动态片段，不代表连续帧、FPS或其余调用点已验 |
| B010 | `app/lib/features/activity/activity_page.dart:368` | 活动页：记录操作与列表状态 | 深/浅主题在相同 800×720pt、DPR 2 Profile 中从运行中样例打开详情，`scroll-to` 后对 macOS `_macDetail` 的“取消运行”实鼠标点击；AX target 均 115×40。两主题都显示“已取消”并移除取消操作。WindowServer 目标采样各 14/15：深色漏 0ms，浅色漏 50ms；截图/timing SHA 见验收记录。只核隔离内存 fixture，真实服务响应仍待核 |
| B011 | `app/lib/features/activity/activity_page.dart:303` | 活动页：记录操作与列表状态 | 深浅失败详情图可见“复制诊断”。新增 macOS Widget 回归通过测试通道拦截 `Clipboard.setData`，验证单次复制的脱敏运行 ID/状态/时间内容和成功提示，系统剪贴板未读写；`flutter test --no-pub test/activity_page_test.dart` 通过。Profile 原生点击与动效仍待验 |
| B012 | `app/lib/features/catalog/workspace_page.dart:183` | 工作台：搜索框清除按钮 | 浅色 Profile 实窗键盘输入 Git 后显示 3 项、清除恢复 17 项；深色 PreviewRuntime 输入 Git 后显示 1 项、清除恢复 12 项并展示“清除搜索”悬停提示。2026-11-19 补浅/深物理按下/释放窗口帧：按住约 714 ms，浅色采样 +12/+162/+696 ms、释放 +64 ms；深色采样 +6/+139/+405/+656 ms、释放 +25/+259 ms。签收此实例双主题功能和可见按压/释放变化；完整曲线与物理面板 FPS 仍待核。截图与 SHA 见验收记录 |
| B013 | `app/lib/features/catalog/workspace_page.dart:665` | 工作台：空连接态添加 CLI（macOS 宽窗目录） | 2026-11-21 在 800×720pt、DPR 2 的浅/深 Profile 对此生产实例实鼠标点击：两主题均进入目标选择器，选本机预览目标后进入 CLI 配置，取消返回空连接管理页；未测试、保存或运行 CLI。WindowServer 显示帧样本两主题各 14/15（深色漏 200ms、浅色漏 0ms），逐帧截图/SHA 与范围见验收记录。连续动画、FrameTiming 和物理面板 FPS 仍待核 |
| B014 | `app/lib/features/catalog/workspace_page.dart:672` | 工作台：空连接态添加 stdio MCP（macOS 宽窗目录） | 2026-11-21 在 800×720pt、DPR 2 的浅/深 Profile 对此生产实例实鼠标点击：两主题均进入目标选择器，选本机预览目标后进入 stdio MCP 配置，取消返回空连接管理页；未测试、保存或连接服务。WindowServer 显示帧样本两主题各 14/15（深色漏 0ms、浅色漏 33.3ms），逐帧截图/SHA 与范围见验收记录。连续动画、FrameTiming 和物理面板 FPS 仍待核 |
| B015 | `app/lib/features/catalog/workspace_page.dart:253` | 工作台：空连接态添加 HTTP MCP | HTTP-only 浅色空态进入本机 Mac（预览）HTTP MCP 配置并取消；深色 HTTP-only Profile 同样打开“预览 MCP HTTP”表单后取消。URL/token 未输入，未测试或保存；截图与 SHA 见验收记录，动效待核 |
| B016 | `app/lib/features/catalog/workspace_page.dart:265` | 工作台：无匹配结果清除筛选 | 浅色 Profile 实窗在资源筛选下输入无匹配文本，点击清除恢复 17 项；深色 UI 检查 Profile 同样在资源筛选下输入无匹配文本，空态 AX 有“清除筛选”，点击后搜索清空、筛选复位并恢复 17 项，截图与 SHA 见验收记录。仅签收深色功能和静态悬停外观，点击动效待核 |
| B017 | `app/lib/features/catalog/workspace_page.dart:344` | 工作台：类型筛选分段按钮 | 浅色 Profile 实窗逐项选择工具、资源、提示、CLI；AX 结果数依次为 3、1、1、12；恢复“全部”后为 17。深色 UI 检查 Profile 复现同样计数；截图与 SHA-256 见验收记录。仅签收筛选结果与静态外观，动效逐帧待核 |
| B018 | `app/lib/features/connections/action_editor_dialog.dart:255` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗新增 `action1`，取消重开后恢复原有单项；深色 Profile 重复验证，AX 清单动作 ID 仅 `version`。截图与 SHA 见验收记录；点击动效仍待核 |
| B019 | `app/lib/features/connections/action_editor_dialog.dart:260` | 连接管理：动作编辑对话框 | 浅色与深色 Profile 均打开系统文件面板后取消；未选择或读取文件。深色入口/状态见验收记录；面板按钮动效未测 |
| B020 | `app/lib/features/connections/action_editor_dialog.dart:266` | 连接管理：动作编辑对话框 | 浅色与深色 Profile 均打开系统保存面板后取消；未选路径或写文件。深色入口/状态见验收记录；面板按钮动效未测 |
| B021 | `app/lib/features/connections/action_editor_dialog.dart:336` | 连接管理：动作编辑对话框 | 浅色 Profile 返回 `["仅内存预览", "--help"]`；深色 Profile 对临时 `action1` 输入 `{}` 显示相同数组，页面提示只展开参数、不运行程序。截图与 SHA 见验收记录 |
| B022 | `app/lib/features/connections/action_editor_dialog.dart:366` | 连接管理：动作编辑对话框 | 浅色 Profile 实窗点击取消后关闭；重开清单确认新增草稿已丢弃。深色 Profile 取消新增后重开 AX 清单仅含 `version`，见验收记录与 `reopened-clean.png`。`action_editor_test.dart` 回归覆盖取消后重开且未调用保存 |
| B023 | `app/lib/features/connections/action_editor_dialog.dart:372` | 连接管理：动作编辑对话框 | 浅色 Profile 保存后重开，AX 下拉项含原动作与 `action1`；深色 Profile 保存后重开，聚焦 JSON AX value 含两个动作，实窗下拉菜单可见 `查看版本 · version` 与 `新动作 · action1`。仅写入进程内 `Ui6InspectionRuntime`，退出即丢弃；截图与 SHA 见验收记录。Widget 回归覆盖新增、参数预览和保存 |
| B024 | `app/lib/features/connections/connection_setup_dialog.dart:477` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 配对 Mac 样例输入 `git` 后 Host stub 返回未找到；深色 Profile 同样显示未找到提示，没有运行命令或连接设备。截图与 SHA 见验收记录 |
| B025 | `app/lib/features/connections/connection_setup_dialog.dart:483` | 连接管理：创建/编辑连接对话框 | 浅色和深色 Profile 本机 Mac 预览表单都打开原生文件面板后取消；未选文件或读取文件。深色表单图见验收记录，面板只做 AX 打开/取消核验，没有截取含文件列表的系统面板 |
| B026 | `app/lib/features/connections/connection_setup_dialog.dart:757` | 连接管理：创建/编辑连接对话框 | 浅色和深色 Profile 输入虚构路径 `/tmp/ui6-preview-cli` 后运行内存安全 stub；均显示检查通过，没有访问本机命令、网络或凭据。深色截图与 SHA 见验收记录 |
| B027 | `app/lib/features/connections/connection_setup_dialog.dart:765` | 连接管理：创建/编辑连接对话框 | 浅色与深色 Profile 的安全 stub 检查通过后 AX 均显示“保存连接”已启用；没有点击保存或新增连接。深色截图与 SHA 见验收记录 |
| B028 | `app/lib/features/connections/connection_setup_dialog.dart:785` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 540×700pt 与深色 Profile 请求紧凑尺寸后均显示“关闭添加连接”全屏布局；点击后表单收起且草稿未保存。深色截图见验收记录；小屏 Widget 回归也覆盖关闭与丢弃草稿 |
| B029 | `app/lib/features/connections/connection_setup_dialog.dart:818` | 连接管理：创建/编辑连接对话框 | 浅色 Profile 表单取消退出，没有保存连接；深色本机 CLI、stdio MCP 和 HTTP MCP 表单也均取消返回，证据见 B013–B015 深色记录 |
| B030 | `app/lib/features/connections/connection_setup_target_dialog.dart:50` | 连接管理：新增连接目标选择对话框 | 浅色与深色 Profile 都显示本机 Mac 与虚构配对 Mac 两个选项；深色目标选择器截图与 SHA 见验收记录。选择本机 Mac 后进入隔离配置表单 |
| B031 | `app/lib/features/connections/connection_setup_target_dialog.dart:72` | 连接管理：新增连接目标选择对话框 | 浅色 Profile 选择虚构配对 Mac（样例）进入内存 stub 配置表单；深色 Profile 同样读回目标“配对 Mac（样例）”，再完成 Host 查找未命中。没有连接设备；截图见验收记录 |
| B032 | `app/lib/features/connections/connection_setup_target_dialog.dart:87` | 连接管理：新增连接目标选择对话框 | 浅色 Profile 目标选择器取消后关闭；深色 Profile Escape 取消后 AX 确认 picker 消失，管理连接页仍只有 3 个预置样例，没有新增连接。深色返回截图与 SHA 见验收记录 |
| B033 | `app/lib/features/connections/connections_page.dart:173` | 连接管理：连接行、筛选与操作 | 浅色紧凑删除确认见 `105-delete-confirm-light-compact.png`；暗色紧凑 Git CLI 删除确认见 `aggregate-ui6-7-connection-rows-dark-profile/git-delete-confirm.png`，点击取消后详情恢复，连接仍在 `git-delete-after-cancel.png`。删除未确认 |
| B034 | `app/lib/features/connections/connections_page.dart:179` | 连接管理：连接行、筛选与操作 | 浅色及暗色确认框均能看到危险删除按钮；暗色按钮未点击，取消后 3 个内存样例仍保留。暗色图 `git-delete-confirm.png` 与 `git-delete-after-cancel.png` 见验收记录 |
| B035 | `app/lib/features/connections/connections_page.dart:236` | 连接管理：连接行、筛选与操作 | 浅色紧凑连接页见 `101-connection-target-compact-light.png`；暗色紧凑添加入口打开目标选择器见 `aggregate-ui6-7-connection-setup-dark-profile/target-picker.png`。只进入内存预览表单，没有创建连接 |
| B036 | `app/lib/features/connections/connections_page.dart:332` | 连接管理：连接行、筛选与操作 | 浅色紧凑 Git CLI 详情见 `103-connection-detail-compact-light.png`；暗色详情点击“返回连接”后列表恢复，顺序为 Git CLI、MCP、音乐，见 `aggregate-ui6-7-connection-rows-dark-profile/connections-restored.png` |
| B037 | `app/lib/features/connections/connections_page.dart:366` | 连接管理：连接行、筛选与操作 | macOS 不适用：`app_shell.dart` 仅在 `_mobilePlatform` 下传入 `onOpenConnection`，此按钮只供移动端连接工作区使用，macOS 页面按设计不呈现 |
| B038 | `app/lib/features/connections/connections_page.dart:425` | 连接管理：连接行、筛选与操作 | 浅色紧凑首行上移为禁用态；暗色详情动作图 `aggregate-ui6-7-connection-rows-dark-profile/git-detail-actions.png` 中首行上移也呈灰暗态。当前 agent-desktop AX `states` 为空，未据此签收 disabled 语义 |
| B039 | `app/lib/features/connections/connections_page.dart:431` | 连接管理：连接行、筛选与操作 | 浅色证据见 `104-connection-actions-first-item-compact-light.png`。暗色点击 Git CLI 下移后 AX 顺序为 MCP、Git CLI、音乐，截图 `aggregate-ui6-7-connection-rows-dark-profile/connections-after-move.png`；再上移后 AX 与截图恢复 Git CLI、MCP、音乐。只改动进程内样例顺序并已复原 |
| B040 | `app/lib/features/connections/connections_page.dart:440` | 连接管理：连接行、筛选与操作 | 浅色紧凑 Git CLI 详情取消见 `106-action-editor-from-detail-compact-light.png`；暗色从详情打开后 AX 显示原动作 `version`，点击取消返回同一详情，未保存；深色动作编辑器静态证据见验收记录 B018–B023 |
| B041 | `app/lib/features/connections/connections_page.dart:445` | 连接管理：连接行、筛选与操作 | 浅色 MCP、Git 样例测试见既有实窗记录。暗色 MCP 点击测试后详情与 5 项能力仍在；`Ui6InspectionRuntime.refreshConnection` 只返回本地样例，没有外部服务或网络请求 |
| B042 | `app/lib/features/connections/connections_page.dart:450` | 连接管理：连接行、筛选与操作 | 浅色紧凑详情取消见 `105-delete-confirm-light-compact.png`；暗色详情删除打开确认框后点击取消，返回 Git CLI 详情且未删除，见 `git-delete-confirm.png` 与 `git-delete-after-cancel.png` |
| B043 | `app/lib/features/connections/connections_page.dart:500` | 连接管理：连接行、筛选与操作 | 浅色紧凑详情与返回见 `103-connection-detail-compact-light.png`；暗色 Git CLI 详情动作见 `aggregate-ui6-7-connection-rows-dark-profile/git-detail-actions.png`，返回后 AX 与 `connections-restored.png` 确认列表恢复。重排已复原 |
| B044 | `app/lib/features/connections/connections_page.dart:724` | 连接管理：通用创建连接对话框 | macOS 不适用：`LocalRuntimePort` 实现 `ConnectionSetupPort`，macOS 新建流程使用 `ConnectionSetupDialog`，其文件选择已由 B025 覆盖；通用 `AddConnectionDialog` 不在 macOS 路由中 |
| B045 | `app/lib/features/connections/connections_page.dart:747` | 连接管理：通用创建连接对话框 | macOS 不适用：动作清单选择属于通用 `AddConnectionDialog`；macOS 正式运行端走 `ConnectionSetupDialog`，不呈现此控件 |
| B046 | `app/lib/features/connections/connections_page.dart:768` | 连接管理：通用创建连接对话框 | macOS 不适用：通用 `AddConnectionDialog` 不在 macOS 正式运行端路由中；macOS 配置表单取消已由 B029 覆盖 |
| B047 | `app/lib/features/connections/connections_page.dart:774` | 连接管理：通用创建连接对话框 | macOS 不适用：通用 `AddConnectionDialog` 不在 macOS 正式运行端路由中；不以 PreviewRuntime 绕过“不能添加真实连接”保护来触发此按钮 |
| B048 | `app/lib/features/invocation/capability_run_page.dart:402` | 功能调用：运行确认框取消按钮 | 浅色隔离 Profile 点击取消后确认框关闭、运行状态保持“尚未运行”；暗色同样通过。浅/深证据分别见 `108-write-confirm-light.png` 与 `pause-confirm-dark.png`。仅验证本地预览夹具；真实外部写入未执行 |
| B049 | `app/lib/features/invocation/capability_run_page.dart:408` | 功能调用：运行确认框执行按钮 | 暗色确认框实际点击“执行”后 AX 显示“运行成功 / 预览结果：暂停播放”；结果由 `PreviewRuntime` 在内存生成，没有控制播放器或外部服务。确认框与结果见 `pause-confirm-dark.png`、`pause-result-dark.png`。不代表真实外部写入 |
| B050 | `app/lib/features/invocation/capability_run_page.dart:582` | 功能调用：运行表单与结果页 | 2026-11-19 暗色 Profile：暂停播放表单的“运行”按钮 AX 87×40；浅色 Profile 再核 87×40，实鼠标点击打开权限确认后取消，AX 状态仍“尚未运行”。补采暗色按下样本请求在按下后 85.0ms、完成于 174.9ms；释放后约 +55ms 截图仍显示表单，约 +189ms 样本已显示权限确认。点击“取消”后 AX 仍为“尚未运行”，没有执行预览或真实操作；忙碌/禁用状态待核。截图与时序限制见验收记录。既有浅色表单图 `107-write-capability-form-light.png`、`108-write-confirm-light.png` 另见 |
| B051 | `app/lib/features/invocation/capability_run_page.dart:599` | 功能调用：运行表单打开终端按钮 | 浅色隔离 Profile 点击“在终端运行”并进入 UI 检查全内存终端 stub；界面明确说明不会运行外部命令。见 `111-terminal-action-form-light.png`、`112-terminal-stub-light.png` |
| B052 | `app/lib/features/invocation/capability_run_page.dart:606` | 功能调用：运行中取消按钮 | 使用 `UI6_SEED_ACTIVITY_RUNNING=true` 呈现内存 fixture 的运行态；点击取消后 AX 确认“运行状态：已取消”。取消前截图 `116-running-cancel-light.png`；不代表真实服务终态 |
| B053 | `app/lib/features/invocation/schema_form.dart:342` | 功能调用：动态参数表单字段的 JSON 格式化图标 | 浅色 JSON 表单点击“格式化 JSON 参数”，有效默认 `{}` 未报错但没有可见格式变化；非空 JSON 格式化、字段校验与输入动画未验证。见 `109-json-form-format-light.png` |
| B054 | `app/lib/features/invocation/schema_form.dart:397` | 功能调用：动态参数表单字段的 JSON 编辑器展开按钮 | 暗色图 `33-json-form-dark.png`、`34-json-form-expanded-dark.png`；浅色 Profile 验证展开/收起，AX 名称在“展开 JSON 编辑器”与“收起 JSON 编辑器”间切换。见 `110-json-editor-expanded-light.png` |
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
| B070 | `app/lib/features/music/music_mini_player.dart:29` | 音乐控制确认（由全局迷你播放器触发） | macOS 隔离 Profile 原生确认框静态图 [`B070-pause-confirmation-window.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-music-confirmation/B070-pause-confirmation-window.png>)；AX 读到“取消”“执行”各 87×41 pt，取消后确认框消失。未点“执行”；深色对应态、按钮点击动效与真实播放仍未验收 |
| B071 | `app/lib/features/music/music_mini_player.dart:68` | 全局迷你播放器 | macOS 隔离 Profile 浅色静态图 [`B071-mini-player-idle.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-music-confirmation/B071-mini-player-idle.png>)；AX 为“暂停”46×46 pt，播放样例中点按进入 B070 确认框后取消。无按下相位/点阵动画采样，未触发真实播放 |
| B072 | `app/lib/features/music/music_mini_player.dart:407` | 音乐能力运行页：`MusicRunPanel` 动作行（暂停/继续、上一首、下一首、停止、刷新） | 浅色 macOS 隔离 Profile 静态图 [`B072-music-run-panel-idle.png`](</Users/guo/.codex/visualizations/2026/11/19/aggregate-ui6-7-music-confirmation/B072-music-run-panel-idle.png>)；播放中样例页 AX 读到暂停 87×40 pt、停止/刷新各 113×40 pt。只打开能力页，未点动作或“运行”；点击动效与深色态仍未验收。`music_mini_player_test.dart` 不覆盖此 `MusicRunPanel` 调用点 |
| B073 | `app/lib/features/music/music_player_page.dart:201` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；2026-11-19 `music_search_permission_test.dart` 通过，验证取消不授权；本轮/Profile 真实画面未重验 |
| B074 | `app/lib/features/music/music_player_page.dart:207` | 网易云音乐：搜索授权确认 | 暗色授权图 `23-music-search-confirm-dark.png`；2026-11-19 `music_search_permission_test.dart` 通过，验证允许后仅由 PreviewRuntime 返回样例结果；本轮/Profile 真实画面未重验 |
| B075 | `app/lib/features/music/music_player_page.dart:236` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；取消按钮可见并取消，未执行播放命令 |
| B076 | `app/lib/features/music/music_player_page.dart:242` | 网易云音乐：歌曲播放确认 | 暗色歌曲确认图 `25-music-play-confirm-dark.png`；执行按钮可见，未点击 |
| B077 | `app/lib/features/music/music_player_page.dart:512` | 网易云音乐：播放器与搜索入口 | 2026-11-18 暗色播放启动图 `06-music-starting-dark.png`；仅见 busy 状态的停止按钮，未测可用点击 |
| B078 | `app/lib/features/music/music_player_page.dart:603` | 网易云音乐：播放器与搜索入口 | 暗色音乐图 `05-music-search-results-dark.png`、`06-music-starting-dark.png`；浅色 `49-music-light.png`；`connection_experience_test.dart` 覆盖 PreviewRuntime 搜索样例并从结果播放，非真实服务 |
| B079 | `app/lib/features/music/music_search_results.dart:180` | 网易云音乐：搜索结果操作 | 暗色非空搜索图 `05-music-search-results-dark.png`；`music_search_results_lazy_test.dart` 与 `music_queue_controls_test.dart` 覆盖列表播放/加入下一首的 Widget 回调；玻璃动态与浅色原生状态待核 |
| B080 | `app/lib/features/settings/appearance_selector.dart:44` | 设置：明暗主题选择器 | 浅色 `38-settings-light.png` 可见主题控件；`glass_theme_switch_test.dart` 回归覆盖拖动满 450 ms 后仅在释放时提交、取消/隐藏拖动及减少动态效果；原生连续画面仍待核 |
| B081 | `app/lib/features/settings/settings_page.dart:39` | 设置：清空活动确认框取消按钮 | 2026-11-18 深色清理确认图 `clear-dialog-dark-confirm.png`；实际取消后预置的成功/失败/已取消三条内存活动仍存在；浅深确认框见验收记录；按下动画关键帧待核 |
| B082 | `app/lib/features/settings/settings_page.dart:45` | 设置：清空活动确认框危险按钮 | 2026-11-18 浅色清理确认图 `clear-dialog-light.png`；确认后隔离 `PreviewRuntime` 活动列表为空，见 `activity-empty-after-confirm-light.png`；不触碰持久数据；按下动画关键帧待核 |
| B083 | `app/lib/features/settings/settings_page.dart:279` | 设置：本机数据清空活动按钮 | 2026-11-18 设置页清空按钮在浅/深主题均可见并打开确认弹窗；截图 `local-data-light-before.png`、`local-data-dark-before.png`；只测试内存预览回调 |
| B084 | `app/lib/platform/macos/mac_host_settings_panel.dart:267` | 设置：Mac Host 配对和权限操作 | 暗色撤销确认图 `32-host-revoke-confirm-dark.png`；取消按钮可见并取消，未撤销设备 |
| B085 | `app/lib/platform/macos/mac_host_settings_panel.dart:273` | 设置：Mac Host 配对和权限操作 | 2026-11-18 暗色 Profile 假 Host 实际确认撤销；AX 中已配对卡片消失、待处理样例保留。确认图 `revoke-confirm-profile-dark.png`；只改进程内 fake，不访问真实 Host |
| B086 | `app/lib/platform/macos/mac_host_settings_panel.dart:307` | 设置：Mac Host 配对和权限操作 | 暗色身份轮换图 `28-host-rotate-confirm-dark.png`；`mac_host_settings_panel_test.dart` 验证取消后不撤销、不停止 Host、不轮换 |
| B087 | `app/lib/platform/macos/mac_host_settings_panel.dart:313` | 设置：Mac Host 配对和权限操作 | 2026-11-18 暗色 Profile 对假 Host 确认身份轮换；AX 提示成功、Host 关闭且设备列表清空，44321 无 listener。图 `identity-rotation-confirm-profile-dark.png`、`host-rotated-profile-dark.png`；无真实设备/Keychain/TLS 操作 |
| B088 | `app/lib/platform/macos/mac_host_settings_panel.dart:463` | 设置：Mac Host 配对和权限操作 | 2026-11-18 Profile 浅/深主题均点击启动与停止；`host-running-light.png`、`host-running-dark.png`、`host-stopped-after-click-light.png`、`host-stopped-after-click-dark.png`。假 Host 仅改进程内状态；确认无 44321 监听，Profile VM service loopback 仍在；按下动画关键帧待核 |
| B089 | `app/lib/platform/macos/mac_host_settings_panel.dart:501` | 设置：Mac Host 配对和权限操作 | 2026-11-18 浅色 Profile 打开身份轮换确认并取消；`host-identity-confirm-light.png`；AX 复核运行状态、假配对设备和邀请仍保留。确认轮换路径由 fake Widget 回归覆盖，本次未在实窗确认；按下动画待核 |
| B090 | `app/lib/platform/macos/mac_host_settings_panel.dart:549` | 设置：Mac Host 配对和权限操作 | 2026-11-18 浅色 Profile 首屏曾裁切二维码；暗色 Profile 滚至邀请详情后，实窗截图显示完整二维码、过期时间、本机地址数量及复制按钮，见 `host-invitation-generated-dark-scrolled.png`。Flutter Debug 本地 Semantics 矩形高 40 px；同状态 live AX bounds 为 `{x:602,y:749,width:139,height:1}`，两者存在几何差异，责任层未定位。假 Host、无网络配对，按下动画与 AX 几何待核 |
| B091 | `app/lib/platform/macos/mac_host_settings_panel.dart:583` | 设置：Mac Host 配对和权限操作 | 2026-11-18 macOS Widget 测试：启动假 Host 并生成假邀请后点击复制；内存截获的单次 Clipboard payload 与二维码 payload 完全一致，成功提示出现。未写系统剪贴板；邀请及 loopback 地址均为内存 stub |
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
| B102 | `app/lib/widgets/capability_row.dart:40` | 工作台/搜索：功能行 | 2026-11-18 暗色 Profile 点击“两个整数相加”行后打开参数页，结果状态仍为“尚未运行”；`feature-open-form-dark.png`。没有点运行，未调用 Runtime。 |
| B103 | `app/lib/widgets/capability_row.dart:57` | 工作台/搜索：功能行 | 2026-11-18 暗色 Profile 点击“收藏 两个整数相加”，出现收藏分组和“取消收藏”按钮；随后取消并确认空收藏恢复。收藏仅改动 `PreviewRuntime` 内存偏好；截图 `workspace-actions-dark.png`、`workspace-favorite-added-dark.png`。 |
| B104 | `app/lib/widgets/page_state.dart:47` | 通用页面：空态/错误态动作 | 2026-11-18 临时暗色 Profile 夹具呈现生产 `PageState.error`，点击“重试”后 AX 计数由 0 变为 1；截图 `page-state-error-dark.png`。回调仅递增夹具计数，不代表真实数据重试；无按下关键帧、浅色图或帧率数据 |
| B105 | `app/lib/widgets/result_panel.dart:88` | 调用结果：复制、展开与结果操作 | 暗色原生成功结果图 `04-run-result-dark.png`。新增 macOS Widget 回归：点击“复制结果”后测试 messenger 仅在内存截获一次 `Clipboard.setData`，文本/JSON 拼接格式正确并显示“已复制结果”；未读写系统剪贴板。原生 Profile 的系统剪贴板动作仍未验收 |
| B106 | `app/lib/widgets/result_panel.dart:348` | 调用结果：复制、展开与结果操作 | 2026-11-18 暗色 Profile 新图 `failure-recovery-scrolled-dark.png` 显示“检查活动状态”和错误详情入口完整位于 MiniPlayer 上方。点击后状态不变：本地模拟 `inspection-error` 在返回 `RunHandle` 前抛错，`_checkActivityStatus` 因 handle 为空直接返回；不证明真实 Runtime 活动查询。先前浅色滚动验收与错误详情图见本表前文；无按下帧或 FrameTiming |
| B107 | `app/lib/widgets/result_panel.dart:398` | 调用结果：复制、展开与结果操作 | 2026-11-18 暗色隔离 Profile 恢复内存中的 `outcomeUnknown` 活动；点“检查活动状态”后 AX 状态仍“结果待确认”，提示先在执行端确认且不要直接重跑。图 `unknown-outcome-recovery-dark.png`；fake 查询只读进程内状态，无真实执行端、按下帧或 FrameTiming |
| B108 | `app/lib/widgets/result_panel.dart:474` | 调用结果：复制、展开与结果操作 | 2026-11-18 临时暗色 Profile 呈现生产 ResultPanel 文件结果；点“预览文件”后 AX 显示 fake PreviewRuntime 返回的 `预览文件：/tmp/aggregate-preview-report.txt`。图 `local-file-preview-dark.png`；未读取真实文件，无按下帧/FrameTiming |
| B109 | `app/lib/widgets/result_panel.dart:486` | 调用结果：复制、展开与结果操作 | 2026-11-18 同一夹具点“在访达中显示”；fake `revealLocalFile` 为空实现，AX 无错误/状态变化且 Finder 前后均无窗口。只验到控件触发，不覆盖生产揭示行为；图 `local-file-preview-dark.png` |

## 当前结论

这张清单建立了调用点到页面的映射，不关闭 UI-6.7。现有证据覆盖部分连接/动作对话框、终端、运行表单、音乐搜索/播放确认、全局迷你播放器、Mac Host 邀请/权限/撤销/轮换确认、JSON 展开和本地模拟错误结果；少量音乐账号与播放器行为另有 Widget 回归，但不能代替原生页面验收。浅色对应页、逐个按钮的静置/点击动画，以及其余未覆盖的页面实例仍未签收；截图只证明画面中实际出现的实例与状态。

2026-11-18 组件级补证：隔离 96 dp Profile fixture 使用共享 `GlassActionButton` 实际呈现运行、刷新、搜索的浅深静置态和点击反馈；运行三角再整体右移两格完成视觉居中。详细帧与哈希见[点击反馈验收](acceptance-record.md#2026-11-18-ui-67-三枚主图标点击反馈增强与-profile-复核)及[居中复核](acceptance-record.md#2026-11-18-ui-67-运行刷新搜索图案居中微调)。该 fixture 验证共享组件的三种动作 profile，不映射或签收表中任何特定生产调用点；109 个调用点仍需逐实例跟进。
