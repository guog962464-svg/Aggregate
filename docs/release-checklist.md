# macOS 阶段 3 预览验收与正式分发条件

更新：2026-11-10。当前只验收这台 Apple Silicon Mac 的预览体验，最新包为 0.3.7。Intel Mac、macOS 12 和独立系统用户矩阵暂缓，不计入本轮通过门槛。用户当前无法取得 Developer ID；现有 ZIP 使用 ad hoc 签名，未获 Apple 公证，不作为正式发布包。逐项证据见[阶段 2/3 本机验收](phase23-acceptance.md)。

| 项目 | 本机证据 / 后续验收 |
| --- | --- |
| 架构与系统 | Xcode 项目部署目标 12.0；Release 包检查 arm64、x86_64 切片及 `LC_BUILD_VERSION`。本机 macOS 27.2、arm64；Intel 实机和 macOS 12 实机仍需测试。 |
| 功能回归 | `sh tool/check.sh`；`dart run app/bin/stage2_smoke.dart`；`dart run app/bin/stage3_stability_smoke.dart`；原生 Keychain 跨进程测试。 |
| 网易云 | 用户已在当前 Mac 的 Aggregate App 内人工验收稳定播放、播控和实际出声。早先 `dart run app/bin/netease_smoke.dart` 及 Node 20/24 直连对照出现 daemon 超时或状态与队列不一致；自动探针仍需复现条件和回归修正。 |
| 界面 | `cd app && flutter test --update-goldens tool/ui_review_test.dart` 生成 800×600、1024×768、1440×900 的浅深色工作台、连接、设置、音乐页截图；主/次文字 WCAG AA 对比度测试通过。测试引擎缺少中文字体，需以原生窗口目视检查文字。 |
| 数据升级 | 当前 `connections.json` 和 `preferences.json` 为 schemaVersion 1；同目录重启恢复连接、排序、动作和偏好已测。损坏或未知版本的配置会保留 `.damaged-*` 备份并在工作台提示。正式升级需在真实旧版用户目录中演练。 |
| 预览打包 | 运行 `tool/package_macos_preview.sh <输出目录>`，脚本构建 Release、ad hoc 签名、压缩、解压并验证签名与 SHA-256。 |
| 安装与升级 | 当前 Mac 的隔离 HOME 已验证空配置首次启动、旧版后读取已有连接及最终包读取隔离配置；原生 Keychain 有跨进程集成测试。仍需独立 macOS 用户、Intel 实机与最低系统版本机器。未公证包若被 Gatekeeper 拦截，仅按 Apple 官方“隐私与安全性 → 仍要打开”流程，在确认来源可信后手动放行；不以此证明常规分发可行。 |

**本轮本机预览验收门槛：**当前 Mac 上通用功能、界面、隔离配置启动与恢复通过；搜索结果在开启 VoiceOver 的原生辅助功能树中可达并能激活，减少动态效果下的页面操作通过。网易云稳定播放、播控和实际听音已由用户通过 Aggregate App 人工验收；自动探针的历史失败另列回归风险。Intel Mac、macOS 12、独立系统用户和正式分发的验证另行安排。签名校验只能证明现有 ad hoc 包的完整性，不能证明开发者身份或 Apple 公证。

**未来正式分发条件：**取得 Developer ID Application 证书、签名权限、Team ID 和公证凭证；用正式签名构建并提交 `xcrun notarytool submit --wait`，对 App 执行 `xcrun stapler staple`，最后在干净 Mac 上验证 Gatekeeper。当前缺少证书，尚未执行这些步骤；不能用 ad hoc 签名替代。证书和公证要求见 [Apple 开发者文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
