# V8 `libv8_libbase.a` Member and Notice Audit

Date: 2026-11-20
Scope: the A3.6 arm64 NodeProbe candidate only. This is a source and artifact evidence report, not legal approval.

## Pinned evidence boundary

- Node.js `24.22.3`, Node mobile `24.22.3-0`; Node source base commit [`e63cab040c09d43ceef8cb35508c40044614e906`](https://github.com/nodejs/node/commit/e63cab040c09d43ceef8cb35508c40044614e906).
- V8 `13.6.17`, vendored V8 tree `f291e09f79e4b197c356477fcdb800a22d24d038`, as recorded in the candidate inventory.
- Android NDK r28c (`28.2.13676358`).
- Candidate inventory: [`docs/android-a3-node-static-link-inventory-2026-11-19.json`](android-a3-node-static-link-inventory-2026-11-19.json), SHA-256 `01a6bcd4286a01a09302093c4242df52d288037690733249ff3122f4b4f8f4e0`.
- Linker map: `/private/tmp/aggregate-node24-darwin-2026-11-19/libnode.map`, SHA-256 `7ce78f56a23d5b827e8573f3c5990b0809ad948d6c69dcc5116369f731ac06dc`.
- Archive: `/private/tmp/aggregate-node24-darwin-2026-11-19/src/out/Release/obj.target/tools/v8_gypfiles/libv8_libbase.a`, SHA-256 `fe55af156c27c9fa58b291b040ef11beb4861e70be7ab8f893e1405ab3b6d6d2`.

The Node GitHub links in the member table identify source paths at the pinned base commit; they are not a byte-identity claim for every candidate file. Local source hashes were calculated under `/private/tmp/aggregate-node24-darwin-2026-11-19/src`; the path column is relative to that root.

## Method

1. Recomputed the supplied inventory, map, and archive SHA-256 values; all match.
2. Enumerated the thin archive directly with NDK r28c `llvm-ar -t`: 40 unique members. The system BSD `ar` did not read this GNU thin archive, so the NDK LLVM archiver was used.
3. Parsed object paths with retained sections from the exact linker map. It contains 39 distinct `libv8_libbase.a` object members. Set comparison leaves exactly `deps/v8/src/base/platform/memory-protection-key.o` without retained sections.
4. Mapped each archive object path to the same relative `.cc` source path under `deps/v8/src/base/`, confirmed that source exists locally, and hashed each file. The `v8_libbase` source list in the pinned V8 `BUILD.gn` corroborates these paths. Local `deps/v8/BUILD.gn` SHA-256 is `d41fadae65b0613bd16c8c4888a80575278be5d238e5ddcf2a761a4a0d1bf2d5` and matches the file at the pinned Node commit.
5. Reviewed all 40 mapped `.cc` source headers and the V8-root license texts relevant to this source group. Also read the V8 base source area for a local `LICENSE`, `NOTICE`, or `COPYING` file; none is present there.
6. Read the existing candidate license assets in the available debug-signed audit APK, SHA-256 `f16497c63370c0c191a76a507931e392464d252dc12d6cc112e8aeb20473093d`. This is a packaging sample, not the unsigned release artifact. No build, test, device, or accessibility work was performed.

## All 40 archive members

“Retained” means the exact linker map contains at least one retained section for that object. It does not mean all symbols from an object are reachable at runtime.

| # | Archive member (relative path) | Source path at Node base commit (URL identifies path) | Retained | Candidate local source SHA-256 |
|---:|---|---|:---:|---|
| 1 | `deps/v8/src/base/abort-mode.o` | [deps/v8/src/base/abort-mode.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/abort-mode.cc) | yes | `bfdb1cf3dccac62d5ec0023b4987f3eeb84d9ed4e89e4329fd3a9417e3050325` |
| 2 | `deps/v8/src/base/bits.o` | [deps/v8/src/base/bits.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/bits.cc) | yes | `ffdafc344aea2b124bd0d76b9299e9699b5c4359c515a27a7ab2ead32542e7bd` |
| 3 | `deps/v8/src/base/bounded-page-allocator.o` | [deps/v8/src/base/bounded-page-allocator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/bounded-page-allocator.cc) | yes | `abd4ccb83416792e9937de5ae5a2b230d46275d9557acd6147d1e87826e5c0a7` |
| 4 | `deps/v8/src/base/cpu.o` | [deps/v8/src/base/cpu.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/cpu.cc) | yes | `b31a50162f5aad6b1518f6884506a5b4f2fc7f19a0eb2ecd14d5e28be6176f87` |
| 5 | `deps/v8/src/base/debug/stack_trace.o` | [deps/v8/src/base/debug/stack_trace.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/debug/stack_trace.cc) | yes | `1a3cce7f1bac5223b7c3e2990742282363c0f657622185a8867d685ff23b0d0b` |
| 6 | `deps/v8/src/base/division-by-constant.o` | [deps/v8/src/base/division-by-constant.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/division-by-constant.cc) | yes | `ccc04bd0ce98d8d88d26ee8c3138b6f2ebff5f2b24c60f2542cdbec9791a47c7` |
| 7 | `deps/v8/src/base/emulated-virtual-address-subspace.o` | [deps/v8/src/base/emulated-virtual-address-subspace.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/emulated-virtual-address-subspace.cc) | yes | `d61e59c20fd512da0fa8d7268452c5c7b75a0eb6801b1142a11cfa2100e3341c` |
| 8 | `deps/v8/src/base/file-utils.o` | [deps/v8/src/base/file-utils.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/file-utils.cc) | yes | `550b9f25caa25c4f0fb51cace671b7905499f13c72d59734481bcf0ee7bdabe1` |
| 9 | `deps/v8/src/base/fpu.o` | [deps/v8/src/base/fpu.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/fpu.cc) | yes | `74e37a8428c1e7949a1a23bf4e11009b77a0184443744ec8ea239d14a98474aa` |
| 10 | `deps/v8/src/base/ieee754.o` | [deps/v8/src/base/ieee754.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/ieee754.cc) | yes | `1bf999809d4c4c1d31ad5ff3578d32614796f159e08b9e7782560d017721a0c2` |
| 11 | `deps/v8/src/base/logging.o` | [deps/v8/src/base/logging.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/logging.cc) | yes | `f358594c0228da3195b6b0241afb99558d3b30b295545c0c9c14b2d488efb3eb` |
| 12 | `deps/v8/src/base/numbers/bignum-dtoa.o` | [deps/v8/src/base/numbers/bignum-dtoa.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/bignum-dtoa.cc) | yes | `95f5da6eddd22593f29ddfc220d9e875ad072607ebb39a34b16b450e4fc7f39f` |
| 13 | `deps/v8/src/base/numbers/bignum.o` | [deps/v8/src/base/numbers/bignum.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/bignum.cc) | yes | `fc29cffe67ef84dd9254b0db015a50b7f3aff5905d44921051a1eb5182491da1` |
| 14 | `deps/v8/src/base/numbers/cached-powers.o` | [deps/v8/src/base/numbers/cached-powers.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/cached-powers.cc) | yes | `0c052308447b845ecd02ad23a074812f99251cebd7dd60df5d42231e5af8e8da` |
| 15 | `deps/v8/src/base/numbers/diy-fp.o` | [deps/v8/src/base/numbers/diy-fp.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/diy-fp.cc) | yes | `a866972a7e243b639530585bc67fb40de1a3be494209df4ed947dd4202330325` |
| 16 | `deps/v8/src/base/numbers/dtoa.o` | [deps/v8/src/base/numbers/dtoa.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/dtoa.cc) | yes | `55a7f9e2a82d5dae21f43d7d3089ffb1372406acfedf1099258aee9cff36a6db` |
| 17 | `deps/v8/src/base/numbers/fast-dtoa.o` | [deps/v8/src/base/numbers/fast-dtoa.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/fast-dtoa.cc) | yes | `b51c3b37dbbf93cce1361edf37775a174b08fa3c093a71891f2bbedfb3d1b495` |
| 18 | `deps/v8/src/base/numbers/fixed-dtoa.o` | [deps/v8/src/base/numbers/fixed-dtoa.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/fixed-dtoa.cc) | yes | `e280d3825c9b6c695ca047628ed173e096f721f6f7a8d0ee40f09799aafe158a` |
| 19 | `deps/v8/src/base/numbers/strtod.o` | [deps/v8/src/base/numbers/strtod.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/numbers/strtod.cc) | yes | `c16ff8b357fd49e8ae86bdb0a414ed8a8fd7d48cce6ef14111c7396a4cbebb07` |
| 20 | `deps/v8/src/base/once.o` | [deps/v8/src/base/once.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/once.cc) | yes | `10ca64fffb257aadb05e8cb5b2d9b86890773986c73cf1a21d9b939f586d4bd1` |
| 21 | `deps/v8/src/base/page-allocator.o` | [deps/v8/src/base/page-allocator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/page-allocator.cc) | yes | `6318d05f601e67d27d7f7ea773956db77c1168138bf6bc48dc1dc4903bb873ac` |
| 22 | `deps/v8/src/base/platform/condition-variable.o` | [deps/v8/src/base/platform/condition-variable.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/condition-variable.cc) | yes | `c960c048308e661367b1e5df420ca136f4d6e34ac411c47855a08944e22402e0` |
| 23 | `deps/v8/src/base/platform/memory-protection-key.o` | [deps/v8/src/base/platform/memory-protection-key.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/memory-protection-key.cc) | no | `0b15893ec588465151bb326537b805707d51593c75dfedffd3e277204e0fe1a0` |
| 24 | `deps/v8/src/base/platform/mutex.o` | [deps/v8/src/base/platform/mutex.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/mutex.cc) | yes | `458b73df88d4b621132e2bfdfe10b0c42716d447b61f9598477b3aba686f7905` |
| 25 | `deps/v8/src/base/platform/platform.o` | [deps/v8/src/base/platform/platform.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/platform.cc) | yes | `98a6caf579d2bc2aabbedbafd51815b59e0d6e15ead78b7522ba4baa825ad7f8` |
| 26 | `deps/v8/src/base/platform/semaphore.o` | [deps/v8/src/base/platform/semaphore.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/semaphore.cc) | yes | `b4649c5024b4c92b0cbb50dd7e57cf2cc00d487953d2d3904df672fb0e74916c` |
| 27 | `deps/v8/src/base/platform/time.o` | [deps/v8/src/base/platform/time.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/time.cc) | yes | `177cf687e799f6b9c6f7c5aa53fe673604a5e1a6563122aca5abaad5ac04c275` |
| 28 | `deps/v8/src/base/region-allocator.o` | [deps/v8/src/base/region-allocator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/region-allocator.cc) | yes | `96aef11c8856fe097d6c1690624c5d68d94dbad35de0ba102b0fe7901753e6f4` |
| 29 | `deps/v8/src/base/sanitizer/lsan-page-allocator.o` | [deps/v8/src/base/sanitizer/lsan-page-allocator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/sanitizer/lsan-page-allocator.cc) | yes | `7d1f671dbf368e29845cdc4bdec2551cfc39d84f65359d1adef662dd3e2a1f4e` |
| 30 | `deps/v8/src/base/sanitizer/lsan-virtual-address-space.o` | [deps/v8/src/base/sanitizer/lsan-virtual-address-space.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/sanitizer/lsan-virtual-address-space.cc) | yes | `25f430a8795f7aa732e44b344338f9306a7415f3c16ab62f3c659d802145959d` |
| 31 | `deps/v8/src/base/strings.o` | [deps/v8/src/base/strings.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/strings.cc) | yes | `f99f4ba0a03499e5ba1f1772f946b48b99a33c5d8aaf7b353d14885bef8b7ff9` |
| 32 | `deps/v8/src/base/sys-info.o` | [deps/v8/src/base/sys-info.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/sys-info.cc) | yes | `1bddf26ff8424543a1be79a4dfb8c83d977f7d2ab101c90e13fc23f9a64f9b1c` |
| 33 | `deps/v8/src/base/utils/random-number-generator.o` | [deps/v8/src/base/utils/random-number-generator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/utils/random-number-generator.cc) | yes | `71d1cac5bd0c040b0e5f88d0917e3f72a9efb63dbebd2f69bd575e3de070109c` |
| 34 | `deps/v8/src/base/virtual-address-space-page-allocator.o` | [deps/v8/src/base/virtual-address-space-page-allocator.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/virtual-address-space-page-allocator.cc) | yes | `b91a90aa4c246a014659f908d0a72e4f74a4dac41d017aec24bb52f7c8c92c5f` |
| 35 | `deps/v8/src/base/virtual-address-space.o` | [deps/v8/src/base/virtual-address-space.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/virtual-address-space.cc) | yes | `d155c703230ca00f137bdb1733aea0c193012efb3c6ac1259f704a790018a1a9` |
| 36 | `deps/v8/src/base/vlq-base64.o` | [deps/v8/src/base/vlq-base64.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/vlq-base64.cc) | yes | `08ec47216f5ec734403e6883dcf60868c536e1b78cf17a846354f245cb6f6392` |
| 37 | `deps/v8/src/base/platform/platform-posix.o` | [deps/v8/src/base/platform/platform-posix.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/platform-posix.cc) | yes | `97649ffe21f781fd8045d4668359e7fb2ec66e55302e27cc0eac42ff7974b388` |
| 38 | `deps/v8/src/base/platform/platform-posix-time.o` | [deps/v8/src/base/platform/platform-posix-time.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/platform-posix-time.cc) | yes | `959d77d1dd7cfef874450cd258b1f5fa40f8fc2a7c77c059807db997f808bff1` |
| 39 | `deps/v8/src/base/debug/stack_trace_android.o` | [deps/v8/src/base/debug/stack_trace_android.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/debug/stack_trace_android.cc) | yes | `45d720531cefc54a8f5b0fe0df9d1764e760864cc7beef991b6fc15fba1ef3a2` |
| 40 | `deps/v8/src/base/platform/platform-linux.o` | [deps/v8/src/base/platform/platform-linux.cc](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/platform/platform-linux.cc) | yes | `011001c0c041c4da3c1ecb56d5befe45f131d263d78da5fa023f920cb6249220` |


## Source byte identity check

The 40 candidate `.cc` files were compared byte-for-byte with their raw paths at Node commit `e63cab040c09d43ceef8cb35508c40044614e906`: 39/40 match. The sole difference is `deps/v8/src/base/platform/platform-posix.cc`: candidate-local SHA-256 `97649ffe21f781fd8045d4668359e7fb2ec66e55302e27cc0eac42ff7974b388`; Node-base raw SHA-256 `ab02c74ee5acc2e517e6452e9e7ccf5be2c72140bf70bfdc2ca7626378c84a11`. The table's Node link for that row is path provenance only. For this audit, the member maps to the candidate-local file in the inventory-bound V8 tree `f291e09f79e4b197c356477fcdb800a22d24d038`, identified by the candidate-local hash above; the reason for the byte difference is unknown.

## Source and notice evidence

### V8 BSD-style scope

The pinned [V8 `LICENSE`](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/LICENSE) (local `deps/v8/LICENSE`, SHA-256 `6ab33af8774a0f396ee3aeeb761e3229057682d6f9fa7f572e390c2cb3a6e509`) supplies the V8 three-clause BSD text for V8-maintained files. Thirty-eight members have V8-project-author source headers only; this includes the unretained `memory-protection-key.o` member.

### fdlibm / Sun notice

Retained `deps/v8/src/base/ieee754.o` maps to [pinned `ieee754.cc`](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/ieee754.cc), local SHA-256 `1bf999809d4c4c1d31ad5ff3578d32614796f159e08b9e7782560d017721a0c2`. Its opening header says it is adapted from fdlibm, credits Sun Microsystems (1993), grants use/copy/modification/distribution provided that the notice is preserved, and credits V8 modifications. The distinct pinned [`LICENSE.fdlibm`](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/LICENSE.fdlibm), local SHA-256 `e7115e18444dae09d17f361ddc365fb1d342640fe500796209c63f7c80dfae10`, contains the corresponding Sun permission notice (with a 1993–2004 copyright range).

### Additional BSD attribution in a retained member

Retained `deps/v8/src/base/debug/stack_trace_android.o` maps to [pinned `stack_trace_android.cc`](https://github.com/nodejs/node/blob/e63cab040c09d43ceef8cb35508c40044614e906/deps/v8/src/base/debug/stack_trace_android.cc), local SHA-256 `45d720531cefc54a8f5b0fe0df9d1764e760864cc7beef991b6fc15fba1ef3a2`. Its header identifies Chromium Authors, copyright `(c) 2012`, says the file uses the BSD-style license in `LICENSE`, and says it was adapted for V8, with a 2016 V8-project-author notice.

This is an additional copyright attribution within the same BSD-3-Clause family, not evidence of a third license family. It is not listed in the archive's `licenseEvidence` entries, which enumerate V8 `LICENSE` and `LICENSE.fdlibm`. In the available audit APK, Chromium text appears in the Node aggregate license asset and the separate Inspector Protocol license as a 2016 Chromium Authors notice; that does not reproduce the exact 2012 attribution from `stack_trace_android.cc`. The APK inspection therefore leaves a notice-delivery gap for this member unless another authoritative packaging rule establishes that the existing text covers it.

The V8 tree also contains `LICENSE.strongtalk` and `LICENSE.v8`, but none of these 40 source members refers to those files or the corresponding source groups. No evidence was found that they add another license condition to this archive. No other distinct license text or separate permission/notice condition appeared in the 40 member source headers. This source review does not recursively inventory every header-only dependency or generated input.

## CycloneDX candidate and notice conditions

For this archive's combined source scope, the evidence supports a **conditional metadata candidate**:

```text
BSD-3-Clause AND LicenseRef-V8-fdlibm-Sun
```

The `LicenseRef` would need to mean the exact pinned `deps/v8/LICENSE.fdlibm` / in-source Sun notice, with a stable definition and the corresponding notice text distributed. `AND` reflects the cumulative BSD and fdlibm-derived terms represented in the archive; there is no evidence that these are alternative grants. The SPDX list was checked: it has no `fdlibm` entry, and the similarly named `BSD-3-Clause-Sun` text is not the short fdlibm notice in this source. Do not substitute that SPDX ID for the source's exact text.

This expression is a candidate for the archive-level scope; it is not a license conclusion for aggregate V8 or `libnode.so`. CycloneDX 1.6 permits an SPDX expression, but its expression object has no per-reference text field. CycloneDX maintainers state that expression-part text support arrived in 1.7; their suggested 1.6 `evidence.licenses` treatment is a workaround, not a demonstrated generator/consumer contract. Therefore the existing 1.6 library row is not ready to close solely from a schema-valid expression string. A 1.6 implementation would need a tested, traceable way to bind the custom reference to its full text and to include that text in recipient notices; a 1.7 representation can carry expression-part details. See the [CycloneDX 1.6 JSON model](https://cyclonedx.org/docs/1.6/json/), [CycloneDX maintainer clarification](https://github.com/CycloneDX/specification/discussions/713), and [SPDX license list](https://spdx.org/licenses/).

For a redistribution candidate, preserve at least the V8 BSD notice and conditions/disclaimer, the fdlibm/Sun notice, and the exact Chromium Authors 2012 source attribution (along with the applicable BSD text). The currently inventoried V8 root license assets include `LICENSE`, `LICENSE.fdlibm`, `LICENSE.strongtalk`, and `LICENSE.v8`; the source-derived package hash checks do not by themselves show that the `stack_trace_android.cc` attribution was carried into the notice bundle. Resolve that packaging gap and verify the exact recipient-facing license bundle before treating the notice condition as closed.

## Conclusion and limitations

- Exact archive membership: 40 members; 39 have retained sections in the bound linker map. The sole unretained object is `memory-protection-key.o`.
- Scope evidence shows V8 BSD-3-Clause code plus retained fdlibm/Sun material. The retained Android stack-trace member adds a Chromium copyright attribution governed by a BSD-style license; it does not establish another license family, but it creates a notice item not explicitly represented by the two-file archive `licenseEvidence` set. Source byte identity is 39/40 against Node e63; `platform-posix.cc` is recorded under candidate V8 tree f291 with its local hash, and the difference reason is unknown.
- `BSD-3-Clause AND LicenseRef-V8-fdlibm-Sun` is evidence-supported as a conditional archive candidate. CycloneDX 1.6 does not make the custom notice text self-contained in the expression, and the available packaging sample does not demonstrate the exact 2012 Chromium header attribution. Keep the current BOM/inventory row unresolved pending text binding, recipient notice verification, and legal review.
- This audit is limited to the specified Node commit, vendored V8 tree, NDK archive, and linker map. It does not establish a complete expression for V8 or `libnode.so`, audit every transitive/header-only file, certify the final unsigned release artifacts, or provide legal approval. The cause and provenance of the `platform-posix.cc` byte difference were not determined. The candidate inventory and source artifacts were read only; no BOM, inventory, generator, source, or other project file was changed by this task.
