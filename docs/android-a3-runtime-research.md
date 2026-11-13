# A3.6：Android Node 运行时与 16 KB 页状态

核对日期：2026-11-13。范围是仓库已固定的 fogtape `nodejs-mobile` Node 24.22.1-0 候选、官方 Node/nodejs-mobile 状态，以及 Android 16 KB 静态要求。未启动模拟器；没有可用的 16 KB 实体设备。

## 结论

- **静态 16 KB 部分通过（当前 arm64 Debug 探针）：**检查 `nodeprobe-debug.apk` 和 AAB 中的 `libaggregate_node_probe.so`、`libc++_shared.so`、`libnode.so`，每个 `PT_LOAD` 的 `p_align` 均为 `0x4000`，且 `p_offset`/`p_vaddr` 对齐余数一致；三个库的 GNU_RELRO 均符合 Android 指南条件。APK 的 `zipalign -c -P 16 4` 检查通过，AAB 由 bundletool 1.18.3 验证且配置为 `PAGE_ALIGNMENT_16K`。普通 Flutter Debug APK 的 zipalign 检查也通过。此结果限于 Debug 产物和 arm64 ABI。
- **真机 16 KB 加载仍未知：**Aggregate 当前只有 LGE AN10 4 KB 页设备。静态 ELF/ZIP 检查不能代替 16 KB Android 内核下启动、JNI 加载、内存分配及 Node 行为验收。fogtape 项目的文档声称其发布流程会在 Pixel 9 16 KB 实体设备上执行启动和 N-API addon smoke；这属于其 release CI 的证据主张，不能表述成 Aggregate APK 已经完成 16 KB 实机验证。
- **当前运行时不可作为发布基线：**官方 `nodejs-mobile` Release 仍停在基于 Node 18.20.4 的版本；Node 18 已 EOL。fogtape 有独立、可重建的 Node 24/26 mobile recipe 和发布自动化，但当前 Node 24 二进制 `v24.22.1-0` 仍标为 prerelease、发布时间为 2026-10-22；Node 官方在 2026-11-11 已发布 24.22.3 安全更新。该 Android 二进制未基于最新 Node 24 安全更新，A3.6 的维护/安全门槛未过。
- **A3.6 继续保持开放：**arm64 Debug APK/AAB 静态核验通过，但维护版 Android runtime、完整许可清单、与当前安全版本同步、Release APK/AAB 成品检查及 16 KB 实机运行仍需完成。产品端继续不开放 Node/npm/CLI。

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
| 运行时与来源固定 | Node `v24.22.1-0`；`prepare.sh` 固定 archive SHA-256 `d6fd9f610fe5d81fede8f0d400c5a62723247725a19831835f15abf4f0604250`、同标签 LICENSE SHA-256 `c373dabed995013e091b1908996a69a1647ef19d400e6c1fd4b7fb06d8bc0f66`，并校验 NDK LLVM NOTICE SHA-256 `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e`。两份 notice 均打入当前探针 APK/AAB。 | 支持当前实验包来源复核；不代表完整第三方依赖清单，也不证明 Node 版本目前仍是最新安全版本。 |
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
