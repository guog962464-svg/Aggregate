# A3 Android Node.js 上游发行状态（2026-11-20）

## 结论

截至 2026-11-20，已核对的 Node.js 和 nodejs-mobile 官方发布证据**未发现**与 Node 24.22.3 安全版本匹配的 nodejs-mobile 上游 Android 发行包。nodejs-mobile 官方最新标记为 Latest 的发行是 `v18.20.4`，含 Android arm64-v8a，但不满足 A3.6 的 Node 24 安全版本要求。其他维护方是否存在符合要求的可审计 Android 发行仍未查全，不能据此断言任何地方都不存在；A3.6 的维护方发行门槛保持开放。

此次核对的固定候选为 **Node 24.22.3 / `process.versions.mobile` 24.22.3-0、NDK r28c、arm64**。项目已有记录中的本地重建和真机实验是社区源码构建的证据，不是 nodejs-mobile 上游维护方发行该组合的证据，也不能单凭版本字符串证明二进制来源、全部安全补丁或持续维护。详见 [A3 运行时研究](android-a3-runtime-research.md) 和 [适配计划](android-adaptation-plan.md)。

## 官方证据

- Node.js 官方于 **2026-11-11** 发布 [Node.js 24.22.3 LTS 安全版本](https://nodejs.org/en/blog/release/v24.22.3/)，[安全公告](https://nodejs.org/en/blog/vulnerability/november-2026-security-releases)列出 24.22.3。官方[发行周期](https://nodejs.org/en/about/previous-releases)将 Node 24 列为 LTS，将 Node 18 列为 2025-03-27 EOL。Node 24 的维护状态不自动转移到任何移动端 fork 或二进制。
- [nodejs-mobile 官方发行页](https://github.com/nodejs-mobile/nodejs-mobile/releases/tag/v18.20.4)标记 `v18.20.4` 为 Latest，2024-10-07 发布，列出 Android `armeabi-v7a`、`arm64-v8a`、`x86_64` 和头文件；其版本记录为 Node `18.20.4`、mobile `18.17.3`。这证明官方曾发行 Android arm64 包，并不证明存在 Node 24 的包或该旧包获得后续安全维护。[官方仓库](https://github.com/nodejs-mobile/nodejs-mobile)将 Android/iOS 二进制指向其 GitHub Releases。
- 检查 [官方 Releases 列表](https://github.com/nodejs-mobile/nodejs-mobile/releases)及 `git ls-remote --tags` 的官方远端 tag，未看到 `v24` 或 `nodejs-mobile-v24` 前缀的 tag；该搜索范围不排除未使用这些名称的 tag、其他分发位置或未公开发行。GitHub API 请求因速率限制返回 403，未能使用 API 独立枚举所有资产和发行元数据。
- [官方 Android 构建说明](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/BUILDING.md)提供 NDK r24 和 `tools/android_build.sh` 的源码构建步骤，输出 `libnode.so`；这是一条构建路径，不是 Node 24.22.3、NDK r28c 的维护方发行或持续更新承诺。[Node.js 官方构建说明](https://github.com/nodejs/node/blob/main/BUILDING.md#android)将 Android 列为不受支持的平台且不在其现有 CI 中测试，因此 Node 官方 Linux arm64 发行不能当作 Android 嵌入式 `libnode.so`。
- [fogtape 的发行页](https://github.com/fogtape/nodejs-mobile/releases)列出 Node 24 的 `v24.22.1-0` 预发布；它是独立 fork 的发行，不是 `nodejs-mobile/nodejs-mobile` 上游发行，也早于 Node 24.22.3 安全更新。fork 发布、源码 recipe、本地修改和本地构建各自需要独立核验，不能互相替代。

## 尚需证据

要关闭维护方发行门槛，需要找到维护方明确发布的匹配 Android arm64 构建，核实资产、来源和完整构建输入（包括 Node/mobile 版本与 NDK）、安全更新维护承诺和可审计性；不能以本地候选的版本标识代替。许可/SBOM 审查、正式签名及 16 KB 真机验收仍按 A3.6 分别完成。本次仅核对公开资料，没有重新构建、验证资产散列或运行设备测试。
