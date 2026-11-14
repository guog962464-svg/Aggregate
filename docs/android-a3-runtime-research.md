# A3.6：Android Node 运行时与 16 KB 页状态

核对日期：2026-11-14。范围包括仓库固定的 fogtape `nodejs-mobile` Node 24.22.1-0 探针、官方 Node/nodejs-mobile 状态，以及基于 Node 24.22.3 的临时 Linux 重建。未启动模拟器；没有可用的 16 KB 实体设备。

## 结论

- **Node 24.22.3 临时候选通过 4 KB 真机探针及 240 项 curated Node 测试：**从 fogtape 20 个移动补丁重放到官方 Node `v24.22.3` 后的源码树，在 Linux 容器用 NDK r27d 构建 arm64 `libnode.so`。隔离 Debug APK 仅含 3 个 arm64 `.so`，`PT_LOAD` 均为 `0x4000`；`zipalign -c -P 16 4` 与 APK v2 签名检查通过。LGE AN10 / Android 15 / API 35 / 4 KB 真机通过运行时生命周期探针，并通过 fork 的 240 项 curated Node 测试、包含 6 项新增移动行为测试。源码树 hash 是针对旧 Node 24.22.1 recipe 的预期值，24.22.3 候选尚无已审阅的新预期值；补丁语义与发行许可仍未完全审查，Android `parallel sequential` 之外的 Node 测试类别也未覆盖。产物仅在 `/tmp`，不属于产品候选。详细摘要见本文末尾。
- **真机 16 KB 加载仍未知：**Aggregate 当前只有 LGE AN10 4 KB 页设备。静态 ELF/ZIP 检查不能代替 16 KB Android 内核下启动、JNI 加载、内存分配及 Node 行为验收。fogtape 项目的文档声称其发布流程会在 Pixel 9 16 KB 实体设备上执行启动和 N-API addon smoke；这属于其 release CI 的证据主张，不能表述成 Aggregate APK 已经完成 16 KB 实机验证。
- **运行时仍不可作为发布基线：**官方 `nodejs-mobile` Release 仍停在基于 Node 18.20.4 的版本；Node 18 已 EOL。fogtape 已发布的 Node 24 Android 包 `v24.22.1-0` 仍为 prerelease；本次 `v24.22.3` 是自行重建的实验产物，不是维护方发布或审阅过的 Android binary，也没有验证安全补丁对 mobile fork 的完整适用性。
- **A3.6 继续保持开放：**Node 24.22.3 的 20 个移动补丁可无冲突应用，4 KB 真机 curated 集及配置的 Android mobile test suite 已通过（详见下文）；但它仍是未经维护方发布的临时候选，未覆盖 16 KB 实体机运行。隔离 NodeProbe Release APK/AAB 单 arm64 静态检查已通过但未签名，Aggregate 产品 Release 签名/成品检查仍未完成。Node `v24.22.3` 源 LICENSE 已确认为官方该 tag 的 44 项 LICENSE 加上移动 polywasm MIT 条目；fogtape recipe 顶层 LICENSE 是另一份 39 项清单，不是候选二进制的许可文件。主要 Android 构建依赖和 NDK notices 已完成静态分类，但不等于完整二进制 SBOM 或法律复核。NDK r27d cpufeatures 源码被静态编入 Node 库；NodeProbe 准备脚本现校验并打包 NDK 根 NOTICE，临时候选 APK/AAB 已重打包且静态容器检查通过（见下文）。产品端继续不开放 Node/npm/CLI。

## 官方支持与维护现状

| 来源/候选 | 截至核对日期的证据 | 对本项目的判断 |
| --- | --- | --- |
| Node.js core | 官方 `BUILDING.md` 明确将 Android 列为“不支持平台”，且当前 CI 不在 Android 上测试。 | 上游 Node 版本号本身不能代表官方支持 Android。若基于 Node core 自建 Android 库，Aggregate 要承担移动补丁、构建、测试和安全回移责任。 |
| `nodejs-mobile` 官方仓库 | 官方 Releases 页面列出的最新库为 Node 18.20.4；Node 18 于 2025-03-27 EOL。 | 不适合作为新的产品运行时基线；16 KB 与维护分支要求也不能由更新 AGP/NDK 解决。 |
| fogtape `recipe` 分支 Node 24 | 官方 Releases 页面把 `v24.22.1-0` 标为 prerelease，日期为 2026-10-22，基于 Node `v24.22.1`。Node.js 官方 `v24.22.3` 于 2026-11-11 发布为 LTS 安全版本，包含多项安全修复。 | 项目当前固定包与 Node 官方最新安全补丁落后两个 patch 版本。需要检查每项公告对 mobile build 的适用性，并取得重新构建、摘要和测试绑定到同一新标签的 Android 库。不要将当前预发布二进制标作当前安全基线。 |
| fogtape `recipe-v26` | fogtape 发布页另有 Node 26.12.1-0 prerelease；Node 官方 26.13.1 于 2026-11-11 发布为 LTS。 | 它是独立移动构建线，不会自动修复 Node 24 线。它同样需要随上游安全版本更新，并单独验证应用/依赖兼容性。 |

fogtape README 描述了可复建的 source recipe：固定 Node 上游 tag/commit、标注移动补丁、检查生成树 hash，并由 CI 构建。其测试文档说明发布链要求 full device suite 和 Android arm64 Pixel 9 16 KB 实体机启动/N-API addon smoke；这些是比单纯 `readelf` 更强的上游证据。Aggregate 尚未取得与本地 asset SHA 一一绑定的那次 BrowserStack run 明细，因此将其记录为上游项目声明，不替代本项目门槛。

### 许可范围

当前 `prepare.sh` 固定核对 Node archive、同标签 `LICENSE` 和锁定 NDK LLVM `NOTICE` 的 SHA-256，并将两份声明打入 Debug 探针；fogtape README 将 Node 与其 mobile patch/tooling 标为 MIT。此检查证明下载与文件固定，不构成完整发布许可审计。发布前仍需把具体 archive 的第三方依赖、OpenSSL/ICU 等随包组件、NDK `libc++_shared.so` 和版权声明核实为与二进制完全对应的清单，并提供目标产品可用的 notices。

## Aggregate 当前静态检查

复核仓库：[A3 探针记录](android-a3-probe.md)、[`prepare.sh`](../app/android/nodeprobe/prepare.sh)、[`nodebridge/build.gradle.kts`](../app/android/nodebridge/build.gradle.kts)、[`CMakeLists.txt`](../app/android/nodebridge/src/main/cpp/CMakeLists.txt)。

| 检查 | 观测 | 范围/限制 |
| --- | --- | --- |
| 运行时与来源固定 | Node `v24.22.1-0`；`prepare.sh` 固定 archive SHA-256 `d6fd9f610fe5d81fede8f0d400c5a62723247725a19831835f15abf4f0604250`、同标签 LICENSE SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`，并校验 NDK LLVM NOTICE SHA-256 `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1`。Node LICENSE 与 NDK LLVM NOTICE 均随 APK/AAB 打包。 | 支持当前实验包来源复核；不代表完整第三方依赖清单，也不证明 Node 版本目前仍是最新安全版本。 |
| arm64 16 KB ELF | NDK `28.2.13676358` 检查当前 Debug APK/AAB 中三个 arm64 `.so`：所有 `PT_LOAD` 的 `p_align=0x4000` 且 offset/virtual address 余数相符；GNU_RELRO 结束于其 writable LOAD 末尾，后续 writable LOAD 从向上取整的 16 KB 页边界之后开始。当前 APK SHA-256 `0b54798d1900c2402c19f035786f2a84a2233f40746043cc13ea0079538b6494`，AAB SHA-256 `f7eb31d114b15c124f5bbb78089e920655946a9a9221df1fbd1e61d991ac5843`。 | 仅当前 arm64 Debug APK/AAB；不表示签名 Release 或 16 KB 真机加载。 |
| APK ZIP 与 AAB | Build Tools `36.0.0 zipalign -c -P 16 4` 检查探针 APK、普通 Flutter Debug APK 均成功。Bundletool `1.18.3 validate` 成功，AAB 配置为 `PAGE_ALIGNMENT_16K`。 | ZIP/container 对齐检查不验证设备内核加载或运行行为。 |
| NDK/AGP | NDK r28.2.13676358、AGP 9.1.0。CMake bridge 另显式传 `-Wl,-z,max-page-size=16384`；Android 指南称 NDK r28 起默认生成 16 KB ELF 对齐。 | Prebuilt `libnode.so` 与 `libc++_shared.so` 仍要逐个检查；工具版本不自动更改外部预编译库。 |
| 三 ABI 实验 | 同日 `-Pa3ProbeAllAbis=true` Debug APK/AAB 的 Bundletool 校验、`PAGE_ALIGNMENT_16K` 配置和 universal APK ZIP 对齐通过；arm64/x86_64 的全部库及 armeabi-v7a 的 Node/JNI 库 `PT_LOAD` 为 `0x4000`。armeabi-v7a 的 NDK r28c `libc++_shared.so` `PT_LOAD` 仍为 `0x1000`。 | 默认包维持 arm64 only；不能把三 ABI 构建称为全部 ABI ELF 通过。x86_64、armeabi-v7a 真机加载未知。 |
| 真实 16 KB 设备 | 无 Aggregate 实测。 | 持续待验；不能用 4 KB AN10、模拟器禁令范围外的替代运行或静态检查关闭此项。 |

## 16 KB 要求与剩余门槛

Android 官方指南规定：NDK r28 及以上默认用 16 KB ELF 对齐，但所有预编译共享库也必须各自符合；AGP 8.5.1 及以上负责兼容的 APK 打包。指南检查既包括 `LOAD` 段，也包括 APK 中 native library ZIP alignment 和存在共享 writable `LOAD` 时 GNU_RELRO 的边界。对于 16 KB 设备，代码不能假定 `PAGE_SIZE == 4096`，应使用 `getpagesize()` / `sysconf(_SC_PAGESIZE)`，并检查按页对齐的 `mmap()` 调用。Google Play 页面目前写明：面向 API 35 及以上的 64-bit 应用从 2027-02-01 起，更新必须支持 16 KB 页。

接下来不需要在没有实体 16 KB 设备时反复重做相同的静态检查。可先完成：

1. 升级或等待维护方发布基于最新 Node LTS 安全 patch 的 Android archive；将 upstream tag、mobile recipe commit、release SHA256SUMS、设备 CI run ID 一并固定。
2. 为候选 Release 逐个 ABI 对成品 APK/AAB 库做 ELF `LOAD`/RELRO、ZIP packaging 与依赖闭包检查；32-bit 只有解决其 `libc++_shared.so` 对齐后才能加入。
3. 完成包括 Node、OpenSSL、ICU、NDK C++ 运行库的许可/组件清单及安全更新责任。
4. 当 16 KB 实体设备可用时，执行一次实际安装与 Node/JNI/addon smoke，并保留 Android page-size 和运行时日志。若继续无设备，标为明确外部验收门槛，不标通过。

## 官方一手来源

- [Android：Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes) — NDK/AGP 版本、ELF `LOAD`、ZIP 对齐、RELRO、运行时代码与 Google Play 时间要求。
- [Node.js 官方构建平台说明](https://github.com/nodejs/node/blob/main/BUILDING.md#android) — Android 当前非支持平台且不在 Node CI 测试。
- [Node.js 24.22.3 官方发布说明（2026-11-11）](https://nodejs.org/en/blog/release/v24.22.3) — 当前 Node 24 LTS 安全版本与修复列表。
- [Node.js release lines](https://nodejs.org/en/about/previous-releases) 与 [Node 18 EOL](https://nodejs.org/en/about/eol) — LTS/EOL 状态。
- [nodejs-mobile 官方 Releases](https://github.com/nodejs-mobile/nodejs-mobile/releases) — 官方 Android/iOS 预编译包状态。
- [fogtape Node 24 mobile Releases](https://github.com/fogtape/nodejs-mobile/releases) — `v24.22.1-0` 与独立 Node 26 线的版本/预发布标记。
- [fogtape README](https://github.com/fogtape/nodejs-mobile/blob/recipe/README.md)、[TESTING.md](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/TESTING.md)、[RELEASING.md](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/RELEASING.md) — recipe 可复建方式、移动测试覆盖与发布门槛。

## 2026-11-14 补核：安全版本、候选与 CI 证据

- **本次核对的官方 `nodejs-mobile`、fogtape 与 digidem 候选中，没有可直接采用的当前安全版成品。** fogtape `v24.22.1-0` 是基于官方 Node `v24.22.1` 安全版的移动预发布包；Node 官方已于 2026-11-11 发布 `v24.22.3` LTS 安全更新，包含后续 HTTP/2、TLS、权限及依赖修复。fogtape 的 Node 26 线也未追上官方 `v26.13.1` 安全更新：其最新 `v26.12.1-0` 同样是预发布包。Node 24/26 的 LTS 状态不代表 Node 上游支持 Android；上游构建文档仍写明 Android 不受支持且不纳入其 CI 测试。[Node 24.22.3](https://nodejs.org/en/blog/release/v24.22.3)、[Node 26.13.1](https://nodejs.org/en/blog/release/v26.13.1)、[Node Android 构建支持说明](https://github.com/nodejs/node/blob/v24.22.3/BUILDING.md#android)、[fogtape Releases](https://github.com/fogtape/nodejs-mobile/releases)、[v24.22.1-0 发布页](https://github.com/fogtape/nodejs-mobile/releases/tag/v24.22.1-0)。
- **存在源代码更新路径，尚无对应的已发布补丁包。** fogtape `recipe` 线固定 Node 上游 tag，以移动补丁、`mobile-src/` 和 `expected-tree.txt` 重建并校验产物树；其升级指南要求对新官方 tag 重放补丁、更新树摘要并重新构建/验证。该流程曾将 Node 24 线重基到官方 `v24.22.1`，但截至本日 Releases 尚无基于 `v24.22.3` 的 Android 包。因此它是可执行的维护路线，不是当前安全二进制的证明。[24.22 更新记录](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/UPSTREAM-24.22.md)、[升级指南](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/UPGRADING.md)、[发布流程](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/RELEASING.md)。
- **更正 2026-11-13 对 fogtape 16 KB CI 的描述。** [README](https://github.com/fogtape/nodejs-mobile/blob/recipe/README.md) 和 [TESTING.md](https://github.com/fogtape/nodejs-mobile/blob/recipe/docs/TESTING.md) 仍称发布会在 BrowserStack Pixel 9 16 KB 真机运行 smoke；但 fork 的 [`NOTICE.md`](https://github.com/fogtape/nodejs-mobile/blob/recipe/NOTICE.md) 记录由于没有 BrowserStack 凭据，已删除两个 real-device job，当前 [build workflow](https://github.com/fogtape/nodejs-mobile/blob/recipe/.github/workflows/build.yml) 保留的是 Android 模拟器 smoke、精选测试和完整测试。`v24.22.1-0` 的[实际发布 run](https://github.com/fogtape/nodejs-mobile/actions/runs/39740652002)列出这些 Android emulator jobs，未列出实体机任务；因此该发布没有可核实的上游 16 KB 真机运行证据。其余 CI 成绩属于 fork 自身证据，不是 Aggregate APK 的设备证据。Aggregate 仍没有 16 KB 实体设备；本仓库现有结果仍限 arm64 Debug ELF/RELRO/ZIP 静态检查。[Android 16 KB 官方指南](https://developer.android.com/guide/practices/page-sizes)。
- **其他已核对候选与许可边界。** 官方 `nodejs-mobile` 最新仍为 Node 18.20.4，Node 18 已 EOL；`digidem/nodejs-mobile` 的最新 Node 24 包仍是 2026-09-03 的 `v24.20.0-0`，也不是当前安全版。[官方 mobile Releases](https://github.com/nodejs-mobile/nodejs-mobile/releases)、[Node EOL](https://nodejs.org/en/about/eol)、[digidem 24.20.0-0](https://github.com/digidem/nodejs-mobile/releases/tag/v24.20.0-0)。fogtape README 将 Node 与 mobile patches/tooling 标为 MIT，标签 [`LICENSE`](https://github.com/fogtape/nodejs-mobile/blob/v24.22.1-0/LICENSE) 包含 Node 和第三方依赖许可文本；但其发布打包流程只把 `bin/`、`include/` 放进 ZIP，并单独附 SHA256SUMS，没有把 LICENSE/NOTICE 放入运行时 ZIP。Aggregate 探针脚本会另行下载、校验该标签 LICENSE 并放入探针 assets；正式分发仍须核对随包 NDK `libc++_shared.so` 等组件的 notices 和完整许可清单。[fogtape README](https://github.com/fogtape/nodejs-mobile/blob/recipe/README.md)、[发布打包步骤](https://github.com/fogtape/nodejs-mobile/blob/recipe/.github/workflows/build.yml#L1195-L1222)、[Aggregate `prepare.sh`](../app/android/nodeprobe/prepare.sh)。

**A3.6 判断：**继续开放。下一候选至少要有基于官方最新安全 patch 的可校验 Android archive、与所发二进制对应的许可/组件清单，以及逐 ABI Release APK/AAB 静态检查；仍需 Aggregate 在 16 KB 实体设备完成安装、Node/JNI/addon smoke。fork 文档中的真机表述或其模拟器 CI 均不能关闭这项缺口。

## 2026-11-14 补核：recipe 重建、补丁差异、许可清单与 curated 真机测试

- **recipe 固定基线可复现。**从 Node 官方 `v24.22.1` tag `ce7aaf1cee78b8cf0ce17364260535c418d3ed26` 重建并叠加 fogtape `recipe` 的 20 个补丁和 `mobile-src/` 后，树 hash 精确匹配 `expected-tree.txt`：`59a1f9b50b39080936dc0e78838b3945da83d8e0`。把上游切到 Node `v24.22.3` commit `e63cab040c09d43ceef8cb35508c40044614e906`，20 个补丁也全部干净应用；结果树为 `5b1a23adddf4b698abcfa45cc8d22de930c01b32`。后一个 hash 与固定值不同，是因为固定值对应 24.22.1 上游基线；没有更新 fork 的预期值，也没有把这次重建当成维护方审阅过的升级。
- **检查了新旧上游间被补丁拥有的文件。**Node `v24.22.1` 到 `v24.22.3` 有 90 个上游文件变化；与 `patches/files.map` 相交的只有 `common.gypi` 和 `src/crypto/crypto_context.cc`。物化后的 24.22.3 树保留 V8 embedder 标识 `-node.63`，以及上游新增的 TLS CA 状态重置和 session ID context 保存；同一 crypto 文件中移动补丁的 Apple trust-settings guard 仍存在。静态 test-edit audit 通过，没有移除上游测试的 `node:test`；它对 7 个超过 40 行的移动测试发出审查长度警告。补丁集源码审阅仍未覆盖完整构建矩阵；本次 Node Android mobile suite 也未覆盖 `parallel sequential` 之外的测试类别。
- **记录了两项需纳入后续复核的补丁行为。**`src/node_credentials.cc` 只在 `NODE_MOBILE` 下绕开 Android zygote 遗留的 `AT_SECURE` 判断，但仍比较真实 UID/GID；这使 embedder 设置的 `NODE_OPTIONS`、`NODE_PATH` 和 CA 环境变量可被 Node 读取，未来产品必须确保这些环境值不是用户或远端输入。`deps/v8/src/trap-handler/trap-handler.h` 将 `V8_TRAP_HANDLER_SUPPORTED` 无条件设为 `false`，不仅影响 Android，也改变 fork 的 iOS/host 构建；这是有意的安全/信号处理取舍，但性能与非 Android 影响没有在 Aggregate 中验证。
- **Node 许可文件来源已厘清到文件级。**官方 Node `v24.22.1` 与 `v24.22.3` 上游 `LICENSE` 相同：157,609 bytes、44 个第三方条目、SHA-256 `5888dbb9a1d2b18f2c3e6c5f6af1b39de658372b402a0577b002777f14c62ace`。物化源码再由移动 polywasm 补丁加入其 MIT 声明，成为 158,804 bytes、45 个条目、SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`；此前隔离 NodeProbe APK 中的 `assets/nodejs-mobile-LICENSE.txt` 与该文件哈希相同。此次 fork 测试 harness APK 是另一产物，只包含测试 fixture 的 license 文件。fogtape recipe 仓库根目录 LICENSE 则是 116,078 bytes、39 个条目、SHA-256 `66233b87054d6bca9b0c2f23b027bb2caf1ebd961a6f981616d098dade33af34`，不能用它代替物化源码/二进制对应的声明。NDK r27d LLVM `NOTICE` SHA-256 `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1` 与 NodeProbe 包内资产匹配；NDK 根目录另一个 522,923-byte `NOTICE`（SHA-256 `4d5224d1c0b54ffa88b0dc0088191638fdbb7227835095dfb98f7f66b416a323`）没有随包，具体对 `libc++_shared.so` 是否适用仍待确认。此项是文件映射，不是法律意见或完整二进制组件审计。
- **4 KB 实体机 curated 测试通过。**fork 的 `tools/mobile-test/curated-device-tests.txt` 选择集在 LGE AN10 / Android 15 / API 35 / arm64 / `getconf PAGE_SIZE=4096` 上由官方 Node `tools/test.py` 逐项运行：240 项执行全部通过、0 失败，含 `test-mobile-credentials`、`test-mobile-fetch`、`test-mobile-node-path`、`test-mobile-system-ca`、`test-mobile-unix-socket`、`test-mobile-worker-env-clone`。Node 24.22.3 未剥离 `libnode.so` SHA-256 `7a7fafdabfd3236acc9f77033d75faa2deb633cb07c3f9f1eb6644be4212a449`；测试 APK SHA-256 `710a0772a4897eeff36916ebd75129922af432347f215fccb359b10164edb402`，APK 内剥离库 SHA-256 `9d8addcb602701d2c414339bb9a8c248e4f9445b7e8f72e8ea664aaa351a9d67`。Node 库由 NDK r27d 构建，测试宿主 APK 使用本机 NDK r28.2；临时测试 APK 已从真机卸载，Aggregate 主 App 保持安装。日志留在 `/private/tmp/aggregate-a3-probe-24.22.3/curated-node-tests-4kb.log`。这些结果仍限 4 KB 页面、单 ABI 和 curated 子集，不代表签名产品 Release 或 16 KB 加载通过。

本节记录时，fork 完整设备套件尚未运行。之后的完整配置 Android mobile test suite 结果见下节；其运行也没有关闭 A3.6：Node 24.22.3 仍是本地重建，不是已发布/审阅 Android archive；未完成对全部补丁与链接/打包依赖的语义及许可闭包审查；没有 16 KB 实体机，产品 Release 仍未签名。下一步应继续完成可在 4 KB 设备/本地环境验证的源代码和许可审阅，并把 16 KB 真机与正式签名成品保留为外部验收项。


## 2026-11-14 本机 Node 24.22.3 源码重建尝试

- 在 `/tmp/aggregate-nodejs-mobile-rebase-24.22.3` 克隆 fogtape `recipe`（HEAD `d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5`），将上游基线切换为官方 Node `v24.22.3`，解析至提交 `e63cab040c09d43ceef8cb35508c40044614e906`。`scripts/prepare.sh` 成功重放全部 20 个移动补丁，没有内容冲突；源码树校验却得到 `5b1a23adddf4b698abcfa45cc8d22de930c01b32`，与 recipe 中旧基线固定值 `59a1f9b50b39080936dc0e78838b3945da83d8e0` 不同。未更新 expected-tree 或提交这个未经审阅的 recipe。
- 在生成的 `/tmp/aggregate-nodejs-mobile-out-24.22.3` 上尝试 arm64 Android Release build，使用 Aggregate 的 NDK `28.2.13676358` 与 `-Wl,-z,max-page-size=16384`。macOS 默认 `ar` 不支持 fork Makefile 的 GNU response-file 归档调用；切到 NDK `llvm-ar` 后仍出现宿主工具链接差异。用仅在临时目录的 wrapper 适配宿主链接参数后，构建进一步暴露 macOS host `libuv.a` 缺少 `uv__fs_event`、`uv__kqueue_init` 等符号；没有生成可用 `libnode.so`。
- 此结果只证明补丁能应用到新 Node 源码，不证明新基线能被完整构建或通过 Node/mobile 测试。fogtape 的发布 workflow 在 Linux runner 上执行 Android 构建；当前 Mac 没有运行中的 Docker daemon，故本次未替换成 Linux 容器构建。[fogtape Android build workflow](https://github.com/fogtape/nodejs-mobile/blob/recipe/.github/workflows/build.yml)、[Node 上游的 Android 支持说明](https://github.com/nodejs/node/blob/v24.22.3/BUILDING.md#android)。
- 当次源码重放、wrapper 和构建产物均留在 `/tmp`；没有修改 Aggregate 中被忽略的现有 24.22.1 `.so`、头文件、assets，也没有安装或清除主 App 的数据。当时 Docker daemon 不可用，所以只记录 Mac host 构建失败；后续 Linux 重建与真机验证见下一节。

## 2026-11-14 Linux 临时重建与 4 KB 真机验证

- **源码与构建：**fogtape `recipe` HEAD `d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5` 重放 Node `v24.22.3` 的 20 个移动补丁，基线提交 `e63cab040c09d43ceef8cb35508c40044614e906`。移动源码树 hash 为 `5b1a23adddf4b698abcfa45cc8d22de930c01b32`，与 `expected-tree.txt` 的 `59a1f9b50b39080936dc0e78838b3945da83d8e0` 不同；没有更新基线或宣称补丁复核完成。Ubuntu 24.04 x86_64 Docker、Android NDK r27d `27.3.13750724`、Android API 24、arm64、full flavor；target 链接使用 `-Wl,-z,max-page-size=16384`。host `mksnapshot` 需通过 `LINK.host=/usr/bin/g++` 链接，整次 `make -j4` 成功。
- **未剥离库：**`libnode.so` 为 AArch64 ELF，117,347,080 bytes，SHA-256 `7a7fafdabfd3236acc9f77033d75faa2deb633cb07c3f9f1eb6644be4212a449`；4 个 `PT_LOAD` 的 `p_align` 均为 `0x4000`，offset 与 virtual address 对齐余数相符。DT_NEEDED 为 `libm.so`、`libdl.so`、`liblog.so`、`libc++_shared.so` 和 `libc.so`。
- **隔离 APK：**使用临时 `/tmp/aggregate-a3-probe-24.22.3` 工程构建，APK SHA-256 `aa15bc0e215e2a1614f618eb16fe9c64881dbf240539dba2f2b24c71bc0131bd`。AGP 剥离后的 APK 内 `libnode.so` 为 94,860,408 bytes，SHA-256 `9d8addcb602701d2c414339bb9a8c248e4f9445b7e8f72e8ea664aaa351a9d67`。包内只含 `libaggregate_node_probe.so`、`libc++_shared.so`、`libnode.so` 三个 arm64 native libraries；三者所有 `PT_LOAD` 均为 `0x4000`，`zipalign -c -P 16 4` 与 APK v2 签名校验通过。签名为临时 Debug 签名，不代表 Release 签名。
- **4 KB 实机结果：**LGE AN10、Android 15/API 35、arm64、`getconf PAGE_SIZE=4096`。隔离包验证了 Node 不同 Service generation 启动、文件写入/读取、loopback 网络、Node 进程强杀后的恢复、整 App force-stop 后重启、APK 重装和后台 `am kill` 后重启；主进程在 Node 子进程崩溃时存活。验证器结束时卸载的仅是隔离包 `io.github.guog962464.aggregate.nodeprobe`；主 Aggregate 未覆盖、未清数据。未启动模拟器。
- **限制：**以上只证明这份临时 arm64 Debug APK 在 4 KB 设备上的行为及 ELF/ZIP 静态性质。没有 16 KB 实体机，不能证明 16 KB 内核加载；当时尚未运行 fogtape 移动测试套件，后续结果见紧接的套件验收小节。后续许可文件核对见下节；完整组件与发行许可审查仍未完成。所有构建与 APK 均留在 `/tmp`，没有替换仓库内 Node 24.22.1 资产。

## 2026-11-14 Node 24.22.3 Android mobile test suite 真机验收

- **运行范围：**在 LGE AN10 / Android 15 / API 35 / arm64 / `PAGE_SIZE=4096` 真机上，使用临时 Node 24.22.3 Linux 重建候选及隔离包 `nodejsmobile.test.testnode`。候选来自 Node `v24.22.3` 上游基线 `e63cab040c09d43ceef8cb35508c40044614e906`，叠加 fogtape `recipe` `d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5` 的 20 个移动补丁，树 hash `5b1a23adddf4b698abcfa45cc8d22de930c01b32`。执行测试树 HEAD 为 `335255ec039036e696209dcaf65d5289db5c7de1`。
- **命令与覆盖：**对 Android 架构的 `parallel sequential` 测试集按交错规则分为 4 组，每组各执行一次：`./tools/test.py -j 1 --flaky-tests=skip --timeout=300 --arch android --run=<0|1|2|3>,4 parallel sequential`。runner 设置 `--flaky-tests=skip`，本次没有重试；“完整”仅指该脚本配置的 Android parallel/sequential 集，不包含其它 Node 测试类别，也不包含被配置跳过的 flaky 测试。
- **结果：**分组 0/4、1/4、2/4、3/4 分别完成 948、948、947、947 项，累计 3,790 项通过、0 失败。四个进程均退出码 0，日志均包含 `All tests passed.`。外层日志分别为 `/tmp/aggregate-a3-probe-24.22.3/full-suite-0-of-4.log` 至 `full-suite-3-of-4.log`；SHA-256 依次为 `57b84c8b5fc9c9e65cb5e3c3f37191cd57fe46cdc43e9dd23f599f8367bc934f`、`422d90d5be73427568b177a338e18d735d9516ffae85c9e0ac39d4436e3fbc79`、`32729877cecfe64084f8cadad39b1ab79ab6020047cffc163fd1d0102426e2cc`、`aee0bd5e0b5dcd19eacb30176b38ed31f5e4b8888c2761d7c333ff8497542953`。
- **清理与影响：**停止并卸载本轮安装的 `nodejsmobile.test.testnode`；之后 `pm list packages --user 0` 和 `pm path` 未显示测试包，普通 `io.github.guog962464.aggregate` 仍能解析到已安装 APK。runner 按自身脚本清除了 Android logcat。它的 macOS 主机侧可选资源诊断输出 `free: command not found`、BSD `ps` 不支持 `--sort`，但设备 `/proc/meminfo`、文件系统采样可读，且各分片测试 verdict 均成功。
- **未覆盖与结论：**结果只覆盖上述候选、arm64、4 KB 真机和配置中的 Android parallel/sequential 集；没有 16 KB 设备，不能推断其加载或运行；也不是维护方发布的 Android binary、补丁完整审计、许可闭包审查或 Aggregate 签名产品 Release 证明。A3.6 继续开放，Node/npm/CLI 产品入口仍关闭。

### 许可文件哈希与清单差异（2026-11-14）

- Node 24.22.3 构建源码中的 `LICENSE` 为 158,804 bytes，SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`，与探针资产 `nodejs-mobile-LICENSE.txt` 完全相同。其 Node `tools/license-builder.sh` 生成清单列出 45 个依赖/工具组件，含 ICU、OpenSSL、libuv、V8、npm、zlib、brotli、zstd、simdjson、nghttp2、ngtcp2 等。
- NDK r27d 内 `toolchains/llvm/prebuilt/linux-x86_64/NOTICE` 为 130,424 bytes，SHA-256 `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1`，与探针资产 `android-ndk-llvm-NOTICE.txt` 完全相同；本次 APK 使用的 notice 与构建所用 NDK 文件一致。
- **发行许可仍不能判为完整。**当前 fogtape `recipe` HEAD 的根 `LICENSE` SHA-256 为 `66233b87054d6bca9b0c2f23b027bb2caf1ebd961a6f981616d098dade33af34`，清单有 39 项，与 Node 24.22.3 build `LICENSE` 的 45 项清单不一致：recipe 清单另有 `cjs-module-lexer`、`ESLint`、`highlight.js`、`base64` 等项目；build 清单另列 `amaro/swc`、LIEF、simdjson、zstd、polywasm 等。由于 recipe 分支与该重基树的依赖内容、Android 实际编入/随包文件尚未逐项对应，不能以任一文件单独证明第三方许可闭包。NDK r27d 根目录 `NOTICE` 为 522,923 bytes、SHA-256 `4d5224d1c0b54ffa88b0dc0088191638fdbb7227835095dfb98f7f66b416a323`；静态构建图显示 `tools/v8_gypfiles/v8.gyp` 从 NDK `sources/android/cpufeatures/cpu-features.c` 构建 `ndk_cpufeatures`，作为 `v8_zlib` 的静态依赖，候选 `libnode.so` 中定义了 `android_getCpuFeatures`。NDK 根 NOTICE 包含该源文件的 BSD 许可文本及 cpufeatures NOTICE。原候选缺少根 NOTICE；后续隔离 APK/AAB 已重打包并纳入它。LLVM NOTICE 本身列明 libc++/libc++abi 的许可，因此根 NOTICE 的已确认用途是静态 cpufeatures 依赖，而非 libc++_shared.so。此为文件/链接范围核对，不是完整 SBOM 或法律意见。
- 结论只到**文件级 hash 对照通过、许可清单级差异未解决**。发布前需以最终重建源码、实际链接/打包组件和对应 NDK 版本逐项核实，并把所需 notices 随正式产物提供；本次 Debug APK 不构成法律审查或分发许可结论。

## 2026-11-14 隔离 NodeProbe Release 静态验收

- 在临时工程 `/tmp/aggregate-a3-probe-24.22.3` 构建 `:nodeprobe:assembleRelease` 和 `:nodeprobe:bundleRelease` 均成功。APK `nodeprobe-release-unsigned.apk` SHA-256 `588eca99d7db9f58d8eddeda51d4702bac21b9388ce04fbe1c9760730ca17b28`；AAB `nodeprobe-release.aab` SHA-256 `4764f119a4213c165a278a9a14601b80c3b93d4bae3110955d444ebbf5b4a18c`。APK 与 AAB 均未签名。
- Build Tools 36.0.0 `zipalign -c -P 16 4` 检查 Release APK 通过；Bundletool `1.18.3 validate` 成功，`dump config` 报告 `uncompressNativeLibraries.enabled=true`、`alignment=PAGE_ALIGNMENT_16K`。
- APK 和 AAB 都只包含 `libaggregate_node_probe.so`、`libc++_shared.so`、`libnode.so` 三个 arm64 库。对两种容器内的 ELF 直接检查，全部 `PT_LOAD` 的 `p_align=0x4000` 且 offset/vaddr 余数相同；Release JNI bridge 1,040,104 bytes、SHA-256 `8452785332232c5b2c1695ff34b966f05968f811303a05fc791c2a6ff6705321`；`libc++_shared.so` 1,292,904 bytes，AGP strip 后 `libnode.so` 94,860,408 bytes。Release APK/AAB 的 `libc++_shared.so` 与 `libnode.so` SHA-256 与前述 Debug APK 相同；JNI bridge 因 Release 编译优化而不同。
- **范围限制：**该结果是单 ABI 的隔离 NodeProbe 未签名 Release 预检查，不是 Aggregate Flutter 产品 Release，也未安装运行这两个未签名包；不代表正式签名、完整多 ABI、商店交付或 16 KB 真机验收。对应的正式产品成品 gate 仍开放。

## 2026-11-14 NDK 根 NOTICE 补齐与 Release 重打包

- **准备脚本：**`app/android/nodeprobe/prepare.sh` 增加 NDK 根目录 `NOTICE` 的 SHA-256 allowlist：NDK r27d 为 `4d5224d1c0b54ffa88b0dc0088191638fdbb7227835095dfb98f7f66b416a323`，NDK r28.2 为 `faf0dc52cf6ce9ab09a04b0c074a378dd2565ee1ed9bc1179d83793bcdba012e`；生成探针时会把它复制为 `assets/android-ndk-NOTICE.txt`。`bash -n` 与 `git diff --check` 通过；两套本机 NDK 的根 NOTICE 和 LLVM NOTICE hash 均与脚本值匹配。
- **候选重打包：**向临时 Node 24.22.3 NodeProbe 工程加入 NDK r27d 根 NOTICE 后，`nodeprobe:assembleRelease` 与 `nodeprobe:bundleRelease` 成功。APK SHA-256 `41c390474ff22bd2dc5be17d65565266acdde09d10d3f4ba8e9fbd37c3b46447`；AAB SHA-256 `f5d928a06f1edce543f7304875949ad9343967c85d1275c443bf3cdb5c494cc8`；均留在 `/tmp` 且未签名。
- **成品检查：**APK 与 AAB 均包含 Node LICENSE（158,804 bytes，hash `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`）、LLVM NOTICE（130,424 bytes，hash `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1`）和 NDK 根 NOTICE（522,923 bytes，hash `4d5224d1c0b54ffa88b0dc0088191638fdbb7227835095dfb98f7f66b416a323`）。Build Tools 36.0.0 `zipalign -c -P 16 4` 通过；Bundletool 1.18.3 `validate` 通过，`dump config` 仍报告 `PAGE_ALIGNMENT_16K`。包内 `libnode.so` hash 仍为 `9d8addcb602701d2c414339bb9a8c248e4f9445b7e8f72e8ea664aaa351a9d67`，JNI bridge hash 仍为 `8452785332232c5b2c1695ff34b966f05968f811303a05fc791c2a6ff6705321`。
- **边界：**重打包补齐了已识别的 NDK cpufeatures notice，不代表 Node 45 项源码清单与移动 recipe 39 项清单已映射，也不代表正式产品包或完整许可审核；16 KB 仍只有静态检查，没有真实设备运行。

## 2026-11-14 移动补丁静态补核

- **版本标识漂移：**物化源码的 `src/node_version.h` 报告上游 Node `24.22.3`，而 `src/node_mobile_version.h` 仍把 `NODE_MOBILE_PATCH_VERSION` 固定为 `1`、revision 固定为 `0`。`src/node_metadata.cc` 据此分别设置 `process.versions.node = "24.22.3"` 和 `process.versions.mobile = "24.22.1-0"`。这不改变核心 Node 版本字段，但会让移动构建身份落后于实际基线；发布前应由维护方更新版本元数据、重建并绑定新的源码树 hash 与二进制摘要。本轮候选没有因此重建，既有 3,790 项结果不验证修正后的身份值。
- **环境变量信任边界：**`NODE_MOBILE` 下的 `SafeGetenv()` 不再用 Android zygote 遗留的 `AT_SECURE` 阻断读取，但 UID/GID 不相等检查仍保留。候选因此会读取 embedder 提供的 `NODE_OPTIONS`、`NODE_PATH`、`NODE_EXTRA_CA_CERTS`、`OPENSSL_CONF` 等值；Aggregate 产品若启用此运行时，必须由受信任代码生成这些环境项，不能把用户输入、远端配置或 npm 包内容直接放入进程环境。
- **V8 trap handler：**移动补丁把 `V8_TRAP_HANDLER_SUPPORTED` 无条件定义为 `false`，影响 Android、iOS 和 host 构建，而不只 Android。需要维护方确认这一跨平台取舍并量化 WebAssembly 相关性能/内存行为；当前 Android full flavor 测试通过不能替代该专项测量或 iOS 回归。
- **WebAssembly polyfill 与许可：**Android 运行时在 `globalThis.WebAssembly` 已存在时直接返回，因此候选的 Android full flavor 不加载 polywasm；该 polyfill 为 iOS jitless 运行时的后备实现。polywasm 0.2.0 的 MIT 声明存在于 `deps/polywasm/LICENSE.md`，README 记录 tarball 与源文件摘要，Node 根 `LICENSE` 也列明该组件。该单项有明确来源记录，但不关闭其余依赖/NDK 组件许可闭包。
- **测试排除规模：**fork 的 Android `parallel.status` 与 `sequential.status` 新增 590 条 `SKIP` 模式规则（这是模式数，不是被跳过的测试总量），涵盖广泛的 child-process、CLI、cluster、debugger、REPL、process 等测试；四个分片命令还显式使用 `--flaky-tests=skip`。因此 3,790 项通过只代表该 fork 配置并可在移动设备运行的子集。除 `parallel` / `sequential` 外的 Node 测试目录、flaky 项和被这些模式排除的行为仍需单独覆盖或保持明确不支持。
- **其余检查边界：**本轮还检查了 Android 构建目标、JNI/mobile 宏、libuv、V8、OpenSSL/CAres/zlib GYP 变更，以及 test harness 如何将 `--arch android` 映射到 Android status。它们没有替代完整的逐补丁审阅、各 flavor/ABI 构建和实机回归；尤其是可选 ICU lite profile 不是本次 full flavor 候选的验收对象。
- **16 KB ELF 构建参数不完整：**fogtape 的 release workflow 使用 NDK r27d，在 Build 步骤把 `ANDROID_LDFLAGS=-Wl,-z,max-page-size=16384` 映射为 `LDFLAGS` 后调用标准 `tools/android_build.sh`；因此 CI 确实传入了 max-page 参数。workflow、移动 smoke/addon 脚本和当前候选链接配置均未设置 `-Wl,-z,common-page-size=16384`。Android 官方指南对 NDK r27 及更早版本列出 max 与 common 两项链接参数，r28 起才默认 16 KB ELF 对齐（[官方 16 KB 页面指南](https://developer.android.com/guide/practices/page-sizes)）。本地临时候选库和 addon 的 LOAD 段已通过静态 `p_align=0x4000` 检查；这证明被检查的二进制段对齐，但不能代替对漏掉 common-page 参数的构建链修订与重建。下一步应由维护方补齐该参数，或固定 NDK r28+，再检查各 ABI 的真实 release 库。此项是构建配置与指南不完整，不是已观察到候选二进制失配。
- **NDK 组件许可映射：**候选构建树中的 `ndk_cpufeatures` 从 NDK r27d 的 `sources/android/cpufeatures/cpu-features.c` 生成静态对象，并被 V8 `v8_zlib` 依赖；对象和最终 `libnode.so` 都定义 `android_getCpuFeatures`。NDK r27d 根 `NOTICE` 含该源的 BSD 许可文本；`toolchains/llvm/prebuilt/linux-x86_64/NOTICE` 则列明 libc++ 与 libc++abi 许可。原临时 NodeProbe APK/AAB 只带后者，后续重打包已增加根 NOTICE 并通过 APK/AAB 静态检查，详见上一节。

**结论：**静态补核发现需先修正/解释的移动版本标识漂移，并保留环境变量来源、全局 trap-handler 取舍、广泛测试排除、许可闭包、未审阅变体、可复建 16 KB 链接配置和 16 KB 真机作为未关闭项。Node/npm/CLI 产品入口继续关闭；A3.6 不通过本次补核关闭。

## 2026-11-14 4 KB N-API addon 与 message 类补验

- **候选和设备：**继续使用官方 Node `v24.22.3` 基线、fogtape recipe 20 个移动补丁的本机候选，源码树 hash `5b1a23adddf4b698abcfa45cc8d22de930c01b32`；测试宿主为隔离 `nodejsmobile.test.testnode` APK，SHA-256 `c1fa99c16dc4d9e3b88cefc1739ef0092ba4b33389139ab7a4e711f1a3116f84`，其中剥离 `libnode.so` hash `9d8addcb602701d2c414339bb9a8c248e4f9445b7e8f72e8ea664aaa351a9d67`。APK 中本次运行的 9 个 `test/message` JS 文件均与测试树源文件逐个 SHA-256 一致。设备为 LGE AN10 / Android 15 / API 35 / arm64 / `getconf PAGE_SIZE=4096`。
- **N-API 真实 addon：**使用 NDK r27d `27.3.13750724` 和该候选的 `src/node_api.h`、`out/Release/libnode.so`，执行 `tools/mobile-test/addon/build-android-addon.sh` 构建 `crc-native`。产物 `/tmp/aggregate-a3-crcnative.node` SHA-256 `06db76e99914b7ec0e951aef91685ab752e07cd77408c18060c0b78500f7e3fe`，含 `napi_register_module_v1`、`crc_u32_napi`，所有 ELF `PT_LOAD` 的 `p_align=0x4000`，依赖当前 `libnode.so`。按 recipe 的 `run-android-addon.sh` 将 addon 和测试 JS 放到隔离 App 私有目录后，实机结果为 `NAPI_ADDON_OK crc=0xd4a1185 android arm64`、`Android NAPI-addon: PASS`，退出码 0。该用例覆盖 `dlopen`/N-API 注册、Buffer 读写、与 Node zlib CRC32 对照及无效参数错误路径。
- **message 类测试：**命令为 `DEVICE_ID=AEMN022427001360 python3 tools/test.py --mode release --arch android --shell out/android.release/node --timeout 300 --flaky-tests=skip -j 1 --skip-tests=node_run message`。目录 11 项中显式排除 `node_run_list`、`node_run_non_existent` 两个 `spawnSync` 用例；实际运行 9 项，4 通过（`console_assert`、`max_tick_depth`、`util-inspect-error-cause`、`util_inspect_error`），5 未通过测试输出基线（`assert_throws_stack`、`internal_assert`、`internal_assert_fail`、`nexttick_throw`、`test-testpy-env-var-via-comment`）。前四个错误输出样例中的四条用例在 Node 返回后还观察到 `FORTIFY: pthread_mutex_lock called on a destroyed mutex` 行；`assert_throws_stack` 另有 `Comparison {}` 与上游期望差异。环境变量样例的 `A_SET_ENV_VAR` 未设置，显示宿主 `test.py` 的注释环境未被 Android proxy 传入 app 进程。以上是当前候选/测试代理观察，尚未区分 Node 运行时行为、Android 日志噪声和 runner 输出传输差异，不将它们归因成已确认的 Node 缺陷或通过结果。
- **日志与清理：**message 运行日志 `/tmp/aggregate-a3-message-tests.log` SHA-256 `ffc888573f55a16c3c90290f68af7af772b67c1510d5c6e5c450afe532bbef31`；addon 日志 `/tmp/aggregate-a3-napi-addon-4kb.log` SHA-256 `5435b20d1265cffb535225ed2e7112a466c8ccb38b958a9b8ab8de401e237011`。测试前 runner 清理了设备 logcat；结束后只卸载隔离测试包、移除本次推送到 `/data/local/tmp` 的 addon/JS，重新打开普通 Aggregate App。确认普通包仍安装且处于 resumed，测试包已卸载，设备页大小仍为 4096。未启动模拟器、Mac Host 或生产 WSS/RPC。
- **结论和限制：**N-API addon 在 4 KB 真机成功加载/执行，为候选 native-addon ABI 链路提供了实机证据；16 KB 页设备没有运行，16 KB 仅是 addon ELF 静态对齐参数。message 类覆盖只留下 4/9 通过、5/9 输出不匹配，不能计入 3,790 项全通过结果；另两条 subprocess 用例未执行。A3.6 仍开放：版本 metadata 漂移、维护方发行候选、逐补丁/依赖许可审查、其他 Node 测试类别、Android 错误退出输出与代理环境变量行为、签名 Aggregate Release、16 KB 真机仍待处理。产品 Node/npm/CLI 入口继续关闭。
- **verified_scope：**候选 `v24.22.3` 单 ABI arm64、LGE AN10 Android 15/API 35/4 KB 实机上的隔离 testnode N-API addon 实际加载/调用，以及 Android `message` 类 9 项测试运行结果；APK 的 9 个测试文件与源一致。不是 16 KB 实际加载、发布签名、Aggregate 产品包、任意 native npm 模块、完整测试套件或对 FORTIFY 原因的定位。
- **supersedes：**仅细化同文件前文“其他 Node 测试类别尚未单独运行”的表述：`message` 类现在有 9 项运行记录（4 通过、5 未通过），另 2 项 child-process 测试明确未运行；其他类别与全部移动行为的覆盖缺口仍成立。
- **retrieval_feedback：**检索 `A3.6 4 KB Node addon`、`test/message`、`node-android-proxy envs`、`FORTIFY destroyed mutex`；采用本文件此前的 Node 24.22.3 候选 hash、测试排除和 16 KB/Release 边界，以及同 thread 日志中的 `parallel/sequential` 设备结果。核对临时 Node test harness 的 `run-android-addon.sh`、`build-android-addon.sh`、Android `MainActivity`/JNI 环境入口、测试源与 APK 资产 hash，并以当前 LGE AN10 实机结果区分“addon 加载通过”与“message 输出比较失败”。

## 2026-11-14 Node LICENSE 与移动候选组件清单差异核对

- **官方源文件锚点：**`git show e63cab040c09d43ceef8cb35508c40044614e906:LICENSE` 的 SHA-256 为 `5888dbb9a1d2b18f2c3e6c5f6af1b39de658372b402a0577b002777f14c62ace`，包含 44 个第三方条目。候选工作树根 `LICENSE` 为 158,804 bytes、45 个条目、SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`；与该官方 Node 24.22.3 tag 的文件 diff 仅在尾部新增 `deps/polywasm` MIT 条目。因而候选源 LICENSE 的主要来源不是 recipe 根 LICENSE。
- **recipe 清单差异：**fogtape `recipe` HEAD 的根 LICENSE 为 116,078 bytes、39 项、SHA-256 `66233b87054d6bca9b0c2f23b027bb2caf1ebd961a6f981616d098dade33af34`。按顶层条目名对比，recipe 独有 `ESLint`、`base64`、`cjs-module-lexer`、`highlight.js`；候选独有 `LIEF`、`amaro`、`merve`、`gypi_to_gn.py`、`on-exit-leak-free`、`polywasm`、`simdjson`、`sonic-boom`、`swc`、`zstd`。两个同名路径有源码布局变动：`inspector_protocol` 从 `deps/` 到 `tools/`，`simdutf` 从顶层 `deps/` 到 `deps/v8/third_party/`。这解释了清单不是一对一条目映射；recipe 清单不能替代候选源 LICENSE。
- **Android full flavor 编译/运行证据：**候选 `config.gypi` 中 `node_use_amaro=true` 并列入 `deps/amaro/dist/index.js`；`node_cjs_lexer.cc` 引用 Merve，输出 `libnode.so` 有 `merve_*` 符号；构建生成静态 `libsimdjson.a`、`libmerve.a`、`libzstd.a`，`libnode.so` 中有 simdjson 与 ZSTD 符号。`lib/fs.js` 会加载 `internal/streams/fast-utf8-stream`；Node bootstrap 引用 `internal/process/finalization.js`（该文件标注由 on-exit-leak-free 改写）。这些源码/构建痕迹支持候选 LICENSE 对主要静态库和内置 JS 的覆盖。
- **非运行时或条件依赖：**候选 `deps/LIEF` 与 `tools/gypi_to_gn.py` 属于源树/构建工具清单；本次 `libnode.so` 的 `DT_NEEDED` 没有 LIEF，Android `obj.target` 也没有 LIEF 库产物。Android full flavor 的 WebAssembly 全局存在，polywasm 分支不会被加载；它保留在候选源和 LICENSE 中作为 iOS jitless 后备。recipe 独有的 ESLint 与 highlight.js 路径分别来自工具/文档资产，`deps/base64` 与 `deps/cjs-module-lexer` 均不在该候选树；Node Buffer 使用 simdutf，CommonJS export lexer 改用 Merve。分类依据是临时候选源码与构建树，不表示所有 upstream Node API 或用户包依赖都已作法律审查。
- **运行时动态依赖与声明：**候选 `libnode.so` 的 `DT_NEEDED` 为 `libm.so`、`libdl.so`、`liblog.so`、`libc++_shared.so`、`libc.so`；Android cpufeatures 是静态依赖。隔离 NodeProbe APK/AAB 已包含源 LICENSE、NDK LLVM NOTICE 和 NDK 根 NOTICE，相关 SHA-256 与上文记录一致。
- **结论与边界：**本次核对将“recipe 39 项 vs 候选 45 项”的来源差异及候选中主要 Android 编译依赖分类补齐；先前“这两份清单还未逐项对应”的当前结论由此细化。它没有生成经发行维护方确认的完整 SBOM，也不是法律意见；其他工具链、AAB 分包后的实际分发映射、所有许可义务与产品最终二进制仍需正式复核。A3.6 继续开放。
- **verified_scope：**Node upstream commit `e63cab040c09d43ceef8cb35508c40044614e906`、fogtape recipe `d4aedf536d035bf4eeab7a7a6e18b73d154d0ea5`、候选源码树 `5b1a23adddf4b698abcfa45cc8d22de930c01b32` 和单 ABI arm64 `libnode.so` 静态构建证据；不代表 Release 签名、Google Play split 投递、其它 ABI 或法律结论。
- **supersedes：**只替代本文件此前把“recipe 根 39 项与候选源 45 项差异尚未分类”作为未解析项的表述；候选 LICENSE 与官方 v24.22.3 tag、recipe 独有项和候选主要 Android 依赖现已得到静态分类。完整 SBOM/法律复核、正式产品 Release、16 KB 实机与移动补丁语义审查仍未关闭。
- **retrieval_feedback：**检索 `Node LICENSE 39 vs 45`、`Node 24.22.3 LICENSE polywasm`、`libnode DT_NEEDED`、`merve simdjson zstd`；采用本文件已有的 Node source hash、NDK 根/LLVM NOTICE 与候选 APK/AAB 摘要。对比官方上游 LICENSE、recipe 根 LICENSE、候选 `tools/license-builder.sh`/依赖源码、Android `config.gypi`、`.a` archive file list、ELF symbols/DT_NEEDED 和已打包 notices；没有调用网络，也没有把 source inventory 等同于最终法律意见。
