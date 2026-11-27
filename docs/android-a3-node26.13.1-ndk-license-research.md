# Node 26.13.1 / NDK 30 隐式运行库许可来源复核

> **范围与结论：**本记录只覆盖 Node 26.13.1 arm64-v8a 候选 `libnode.so` 链接时隐式纳入的 NDK `libunwind.a` 与 `libclang_rt.builtins-aarch64-android.a`。它补充来源和许可文本证据，不构成法务意见、合规批准或完整 `libnode.so` SBOM。两个组件的组件级许可说明与保留源文件的 SPDX 头部表达式并存，故不据此选择一个最终表达式；`libnode.so` 的项目许可候选继续保持 `unresolved`。

## 候选与 archive 对照

- Node `26.13.1`，Android `arm64-v8a` / API 24，NDK `30.0.16248370`；候选包中 `libnode.so` SHA-256 为 `84030ab41a5c6cdf4e413d41d81b3f8fe8e4c441a8fa0361ddfacd2911fe986a`。候选 APK SHA-256 为 `ebbc373ce6690e6aa646872c12dd56fb81804350d17c82d17f14b304855a77e1`。
- 既有 [link-map summary](android-a3-node26.13.1-link-map-summary.json) 标出 37 个显式静态归档与 2 个隐式 NDK 归档；[NDK runtime source map](android-a3-node26.13.1-ndk-runtime-source-map.json) 固定 Android LLVM 源码 revision `9f872551d3c681d06fd303b36f16ed5c274735eb`，记录归档成员与源文件映射。

| 隐式归档 | 归档 SHA-256 | archive 成员 | link map 中有保留输出段的成员标签 | 对应的唯一保留源文件 |
|---|---|---:|---:|---:|
| `libunwind.a` | `bfbe474acf75b59fd2f19f0b7210588aa662410d5d8d0996812fe50e9e0143ab` | 9 | 5 | 5 |
| `libclang_rt.builtins-aarch64-android.a` | `7e900bcdd0bb6f05824fd7e96c9309ee9c47c22751a1b3c98242d1f4902e4632` | 287 | 55 | 16 |

compiler-rt 的 40 个保留 `outline_atomic_*` 成员映射到同一个 `aarch64/lse.S` 源文件，变体来自固定 revision 的 CMake 生成规则。其余 archive 成员的来源按成员标签和该 revision 的 CMake 源选择规则对应；source map 不声称重建了 NDK 对象或所有编译参数。

本次从固定 revision 的官方 Android Gitiles 源码归档抽取保留源文件，并与 source map 中记录的 SHA-256 对照：`libunwind` 5/5、compiler-rt 16/16 哈希匹配。21 个唯一保留源文件的前 60 行均声明 `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception`。该逐文件证据与下面的组件级许可说明同时记录，不把二者擅自合并。

## NOTICE 与上游许可文本

- 已安装 NDK 的 LLVM toolchain NOTICE 为 130,424 bytes、2,414 行，SHA-256 `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1`。NDK r30 官方 [`NOTICE.toolchain`](https://android.googlesource.com/toolchain/prebuilts/ndk/r30/+/refs/heads/androidx-main/NOTICE.toolchain) 是 777,125 bytes、SHA-256 `6b8633011d874b75629180e60de13ebfd546a10e56dc7d0380a35f6609f30617`；它与候选 APK 的聚合 notice 相同，并完整包含已安装 NDK 的 LLVM toolchain NOTICE。内嵌 NOTICE 第 520–525 行说明 compiler_rt 可在 University of Illinois/NCSA 与 MIT 中择一，文件另含 LLVM Apache 2.0 与 LLVM exception 文本。
- 候选 APK 的 `assets/a3-node-runtime/NOTICE-NDK-30-toolchain` 为 777,125 bytes、SHA-256 `6b8633011d874b75629180e60de13ebfd546a10e56dc7d0380a35f6609f30617`。它是包含多项许可文本的聚合文件，不等于 LLVM toolchain NOTICE；逐字节查找确认完整 toolchain NOTICE 从偏移 `95,918` 开始嵌入。另一个包内文件 `assets/a3-node-runtime/NOTICE-NDK-30` 与 NDK 根 `NOTICE` 精确匹配：493,924 bytes，SHA-256 `a3c12eee897f63991da71464b690433a15d0d74a508ce0e275436279bdcaff58`。
- 固定 Android LLVM revision 的 [`libunwind/LICENSE.TXT`](https://android.googlesource.com/toolchain/llvm-project/+/9f872551d3c681d06fd303b36f16ed5c274735eb/libunwind/LICENSE.TXT) 为 16,706 bytes、311 行，SHA-256 `b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d`。其第 240–245 行也说明 libunwind 可在 University of Illinois/NCSA 与 MIT 中择一；相同文件开头还含 LLVM Apache 2.0 与 exception 文本。此 per-library `LICENSE.TXT` 不在已安装 NDK 包或候选 APK 的同名许可资产中；虽在源映射归档中有哈希记录，不能把“源映射含文件”当成“APK 已携带文件”。
- 官方 Android [NDK r30 源目录](https://android.googlesource.com/toolchain/prebuilts/ndk/r30/) 与 [NDK LLVM 版本表](https://android.googlesource.com/platform/ndk/+/mirror-goog-main-ndk/docs/LLVM.md)用于定位 NDK r30。固定源码仓库为 [Android LLVM project](https://android.googlesource.com/toolchain/llvm-project/)；compiler-rt 的 source-selection 依据是该 revision 的 [`compiler-rt/lib/builtins/CMakeLists.txt`](https://android.googlesource.com/toolchain/llvm-project/+/9f872551d3c681d06fd303b36f16ed5c274735eb/compiler-rt/lib/builtins/CMakeLists.txt)。

### 许可判断边界

目前有三类可核验证据：NDK toolchain NOTICE 的 compiler_rt 组件级 dual-license 说明、libunwind 的固定 revision `LICENSE.TXT` dual-license 说明，以及 21 个保留源文件各自的 Apache/LLVM-exception SPDX 标头。它们的适用范围和二进制分发时所需的表达方式需由法务确认；本记录不宣称某一个表达式已经覆盖全部保留对象。compiler-rt 的 dual-license 文本已在候选 NOTICE 中；libunwind 专属 `LICENSE.TXT` 未打入候选资产，须在后续发布许可包核对中单独处理。

另外，`libnode.so` 由 37 个显式 archive 与上述两个 NDK archive 组成。这里仅推进两个隐式 NDK 输入的映射和许可证据；Node/V8/OpenSSL 等显式依赖、桥接库、静态运行库、完整 BOM 文本关联及法律审查仍未闭合。`docs/android-a3-binary-license-inventory-node-26.13.1.json` 中 `libnode.so` 状态保持 `unresolved`，A3.6 不因此关闭。

## 核验记录

- 对照本机 NDK `toolchains/llvm/prebuilt/darwin-x86_64/NOTICE`、NDK 根 `NOTICE` 与候选 APK 中两份 NDK notice 资产的长度、SHA-256 和字节包含关系；核对的官方 r30 notice 文件为 [`NOTICE.toolchain`](https://android.googlesource.com/toolchain/prebuilts/ndk/r30/+/refs/heads/androidx-main/NOTICE.toolchain) 与 [`NOTICE`](https://android.googlesource.com/toolchain/prebuilts/ndk/r30/+/refs/heads/androidx-main/NOTICE)。
- 使用 `python3 tool/android/generate_ndk_runtime_source_map.py --ndk-root /Users/guo/Library/Android/sdk/ndk/30.0.16248370 --static-inventory docs/android-a3-node26.13.1-static-link-inventory.json --output /tmp/android-a3-node26-ndk-runtime-source-map.json` 可重建 NDK archive source map；本记录另外独立抽取固定 revision 的两份源码归档，只比对有保留输出段的唯一 source SHA 与 SPDX 头部。
- 本轮没有改动 NDK、Node source、候选 APK/AAB、Android 产品集成或当前 Aggregate identity；没有执行法务审查或 16 KB 真机测试。该候选仍是隔离 NodeProbe 输入，不是已签名 Aggregate 产品发行包。
