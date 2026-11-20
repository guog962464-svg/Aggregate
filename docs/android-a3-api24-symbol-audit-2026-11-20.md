# A3 NodeProbe Android API 24 symbol audit (2026-11-20)

## Result

An exact test-signed arm64 NodeProbe APK declares `minSdkVersion=24`. Its three packaged native libraries have hashes matching the 2026-11-19 A3.6 inventory. Using the matching NDK r28c sysroot, I recursively followed each library's `DT_NEEDED` dependencies and compared its strong undefined dynamic symbols with exports in that dependency closure, including the Android system stub libraries for API 24. **No strong undefined symbol was missing from any closure.** This narrows the API compatibility evidence for this exact candidate; it does not complete the Android OS or runtime closure gate.

The Android NDK documentation says its system stub libraries model the OS-provided interface and the stubs matching an app's `minSdkVersion` are used to check symbol availability at build time; the stubs themselves are loaded from Android at runtime ([NDK r28 build system guide](https://android.googlesource.com/platform/ndk/+/ndk-r28-release/docs/BuildSystemMaintainers.md)). Therefore this result concerns the NDK r28c API 24 symbol interface, not a tested Android 24 system image or the exact library implementations on the LGE Android 15 device.

## Exact candidate and inputs

- APK: `/private/tmp/aggregate-nodeprobe-release-24.22.3-2026-11-19/nodeprobe-release-debug-signed.apk`, SHA-256 `b13c9446eba58647077a4740ca38edfe998e815ce70ba9dbc2b811397bd5036d`.
- `aapt dump badging`: package `io.github.guog962464.aggregate.nodeprobe`, `sdkVersion=24`, `targetSdkVersion=36`; this is a verification-only debug-signed probe, not a product Release.
- NDK: `28.2.13676358` (r28c). `source.properties` SHA-256 `c00aa236fdb205e9be9edd9e2169763e48aca52735efff4e16f34205d49783b5`, matching the [static link inventory](android-a3-node-static-link-inventory-2026-11-19.json).
- The API 24 arm64 stub libraries examined were `libc.so`, `libdl.so`, `liblog.so`, and `libm.so`. Their SHA-256 values were respectively `3751ff3d8b61db86ca69d8ae5c646c8346750e83433fe1abd17885c48b47efea`, `be8fd669d4afe85483da999e7d56ea5e01a9d01d8315b402a70e3bac858cf6a3`, `ae592b3e8aced4ab769a9d94b5444093ea0968dc1491f5245909c4966af4d57d`, and `b566f9cdbbba24b4c6cb9e207beb4b6e8259776ac1305944afa6c8eae3aefc91`.

| Packaged library | SHA-256 (verified against inventory) | Direct `DT_NEEDED` | Strong undefined symbols | Missing from dependency closure + API 24 stubs |
| --- | --- | --- | ---: | ---: |
| `libaggregate_node_probe.so` | `98a9351dfc6020299f10c6e80027ae0bfeceaa4e41fcce531ca7d9a43e2e6654` | `libnode.so`, `liblog.so`, `libm.so`, `libdl.so`, `libc.so` | 159 | 0 |
| `libc++_shared.so` | `cd61762848882a16c8244c964a6f396c0caa0b440588a210ce9cc4ab0e6d9f0c` | `libc.so`, `libm.so`, `libdl.so` | 160 | 0 |
| `libnode.so` | `51a9366831b157e4e6056d54f487903a04286f8ec89a4b6c2405ac4cbaa2c418` | `libm.so`, `libdl.so`, `liblog.so`, `libc++_shared.so`, `libc.so` | 568 | 0 |

Across the three libraries, 632 distinct strong undefined symbol names were checked. Seven weak undefined names were observed; they were not included in the strong-symbol result.

## Method and limits

The APK SHA-256 was checked before inspection. The three `lib/arm64-v8a/*.so` members were extracted to a temporary directory; each extracted file hash was compared with the inventory. NDK r28c `llvm-readelf --dynamic -W` was used to read `DT_NEEDED` entries, and `llvm-readelf --dyn-syms -W` to collect dynamic undefined and exported names. For each packaged library, the transitive `DT_NEEDED` closure was followed through packaged DSOs and the matching API 24 stubs for `libc.so`, `libdl.so`, `liblog.so`, and `libm.so`; its own exports were excluded from the provider set.

This is a bounded static symbol-set check. It does not map every imported name to its specific provider, prove exact dependency search behavior for the Android loader, pin Android OS build versions, inspect hidden or private runtime symbols, or exercise loading on devices at each supported API level. The candidate remains arm64-only and verification-signed. It does not establish 16 KB device behavior, a complete transitive platform SBOM, licensing approval, or product-release readiness. The system-library build/version and runtime closure gates remain open in A3.6.

No build, test suite, device operation, or accessibility test was run for this audit.
