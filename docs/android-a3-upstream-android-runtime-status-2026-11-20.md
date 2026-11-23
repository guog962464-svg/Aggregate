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

## Termux Android 包候选（2026-11-20）

Termux stable APT 当前索引记录了 Node.js `24.22.3` 的 `aarch64`、`arm`、`i686` 和 `x86_64` 包。它补充了当前安全版本的 Android 二进制分发候选，但不是 `nodejs-mobile` 上游发行，也没有证明可直接嵌入 Aggregate。Termux 的构建配方把 Node 安装到 `$TERMUX_PREFIX`，显式使用 `--without-npm` 并单独推荐 `npm` 包；没有声明 Flutter/JNI `libnode.so` SDK。包哈希、来源与限制见 [Termux 运行时调查](android-a3-maintained-runtime-survey-2026-11-20.md)。本次未安装或运行这些 `.deb`，也未验证仓库签名、16 KB 对齐或完整 SBOM/许可闭包。

## 2026-11-20 发行新鲜度与制品溯源补充

- **Node.js 安全版本：**官方 Node 24 最新安全版本为 **24.22.3**（2026-11-11）。[官方发行页](https://nodejs.org/en/blog/release/v24.22.3/)发布带 PGP 签名的 SHASUMS 清单；其发行文件没有 Android 目标包。
- **官方 nodejs-mobile：**[官方 Releases](https://github.com/nodejs-mobile/nodejs-mobile/releases)最新标记仍为 `v18.20.4`（Node `18.20.4`、mobile `18.17.3`），Android 包支持 `armeabi-v7a`、`arm64-v8a`、`x86_64`。[release 页面](https://github.com/nodejs-mobile/nodejs-mobile/releases/tag/v18.20.4)显示 tag commit 经 GitHub 验证签名；资产只有 Android/iOS ZIP，[Release API](https://api.github.com/repos/nodejs-mobile/nodejs-mobile/releases/tags/v18.20.4)没有资产 digest，未发布单独的二进制签名、校验和文件、attestation 或 SBOM。
- **独立维护 fork：**[fogtape Releases](https://github.com/fogtape/nodejs-mobile/releases)最新整体发行是 Node `26.12.1-0` 预发布；Node 24 线最新为 [`v24.22.1-0`](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)，基于官方 Node `v24.22.1`，不是当前 `24.22.3`。该预发布提供 [Android full ZIP](https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-android-24.22.1-0.zip) 和 [lite ZIP](https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/nodejs-mobile-android-lite-24.22.1-0.zip)，ABI 均为 `arm64-v8a`、`armeabi-v7a`、`x86_64`。因此，在这两个已检查发布项目中**未发现匹配 Node `24.22.3` 的 Android 包**；`v24.22.1-0` 是 fork 发行，不是官方 nodejs-mobile 上游包。
- **fork 制品证据：**[发布的 `SHA256SUMS`](https://github.com/fogtape/nodejs-mobile/releases/download/v24.22.1-0/SHA256SUMS)列出 full 包 SHA-256 `d6fd9f610fe5d81fede8f0d400c5a62723247725a19831835f15abf4f0604250`、lite 包 `87ac319660b9dbff1c3a878d5dec2e15560a42f04d7660c8ddaf87c24627ac82`；GitHub [Release API](https://api.github.com/repos/fogtape/nodejs-mobile/releases/tags/v24.22.1-0)也暴露相同 asset digest。其 [README](https://github.com/fogtape/nodejs-mobile/blob/recipe/README.md)和 [Build workflow](https://github.com/fogtape/nodejs-mobile/blob/recipe/.github/workflows/build.yml)记录官方上游 pin、recipe commit、三 ABI 打包检查和 checksum 生成；workflow 使用未签名 annotated tag，未见二进制签名、校验清单签名、attestation 或 SBOM 发布步骤。校验和可核验传输内容，但不单独证明构建来源。
- **范围判断：**本次通过 Releases/API 枚举了 `nodejs-mobile/nodejs-mobile` 与 `fogtape/nodejs-mobile` 的公开发行和相应发布配方；这补足先前 fogtape 资产与溯源资料未展开的部分，但不代表穷尽所有第三方维护者。Node `24.22.3` 本地源码重建仍是 source-build 候选，不是已有匹配维护方 Android 发行。

## 2026-11-23 维护方发行复核

- [nodejs-mobile 官方 Releases](https://github.com/nodejs-mobile/nodejs-mobile/releases)的 Latest 仍为 `v18.20.4`，列出 Android `arm64-v8a` 等 ABI，Node 版本为 `18.20.4`；[Node.js 官方发行周期](https://nodejs.org/en/about/previous-releases)将 Node 18 标为 EOL（2025-03-27）。Node 18 的 EOL 状态本身不证明该移动发行包有无独立补丁。
- [Node.js 24.22.3 官方发行说明](https://nodejs.org/en/blog/release/v24.22.3/)确认其为 **2026-11-11** 的安全发行；不能由此推断移动端 fork 已合入或发布同等修复。
- [fogtape Releases](https://github.com/fogtape/nodejs-mobile/releases)当前列出的 Node 24 和 Node 26 最新预发布分别为 [`v24.22.1-0`](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0) 和 [`v26.12.1-0`](https://github.com/fogtape/nodejs-mobile/releases/tag/v26.12.1-0)。前者说明基于 Node `24.22.1`，并称源码升级本身不会自动发布；后者明确指出其 `danmu-api-android` 集成需要另行准备 runtime archive、更新 checksum 和进行设备验证，且属于独立审核步骤。这些陈述的直接适用对象是该 fork 的发布及其消费项目，不能作为 Aggregate 设备验证结果。
- 本次扩展检查 [JaneaSystems Releases](https://github.com/janeasystems/nodejs-mobile/releases) 与其 [changelog](https://github.com/janeasystems/nodejs-mobile/blob/mobile-master/doc_mobile/CHANGELOG.md)：`v0.3.3` 仍标记为 Latest，changelog 日期为 2021-08-16，版本为 Node `12.19.0` / mobile `0.3.3`，Android 使用 NDK r22b；该多 ABI 历史包不匹配当前 Node 24 安全线。加上官方 nodejs-mobile 和 fogtape，本次覆盖三个公开发行来源；仍未穷尽所有第三方或分发渠道。页面资产列表未正常加载，本次没有下载制品、核验散列、构建或运行设备测试；匹配维护方发行、来源、完整构建输入、安全维护、许可/SBOM 和 16 KB 真机验收仍需单独证据，A3.6 维护方发行门槛保持开放。
