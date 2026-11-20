# A3.6 Android Node runtime survey: Termux package route (2026-11-20)

**Checked:** 2026-11-20 UTC. This extends the project’s existing [upstream release status](android-a3-upstream-android-runtime-status-2026-11-20.md); it does not replace the checks of nodejs-mobile, fogtape, or digidem.

For comparison, the existing project evidence records nodejs-mobile `v18.20.4`, fogtape `v24.22.1-0` (Node `24.22.1`), and digidem `v24.20.0-0`; each predates Node `24.22.3`. Their original scope and ABI evidence are retained in the [A3 runtime research](android-a3-runtime-research.md) and [upstream release status](android-a3-upstream-android-runtime-status-2026-11-20.md).

## Finding

Termux’s official stable APT repository currently publishes **Node.js `24.22.3` Android binary packages** for four architecture labels. This is an exact match for the Node 24.22.3 security line released by Node.js on 2026-11-11. It is a real packaged binary distribution, not just a source-build recipe.

The Termux package is not documented as a Flutter-embeddable `libnode.so` SDK. Its recipe builds Node for Android and installs into Termux’s private prefix, with Termux runtime dependencies. The package route therefore adds a current Android binary candidate, while A3.6’s embeddable-runtime and product-readiness gates remain open.

## Published packages observed

The canonical [Termux main repository](https://github.com/termux/termux-packages/wiki/Mirrors) stable `Release` metadata advertised architectures `aarch64`, `arm`, `i686`, and `x86_64`, with a repository timestamp of **2026-11-20 07:33:29 UTC**. Each architecture’s `Packages` record named `nodejs-lts` version `24.22.3`. The ABI names below map Termux’s architecture labels to Android NDK ABI names using the [NDK ABI table](https://developer.android.com/ndk/guides/abis).

| Termux architecture | Android ABI | Published package | Size | SHA-256 from APT metadata |
| --- | --- | --- | ---: | --- |
| `aarch64` | `arm64-v8a` | [`nodejs-lts_24.22.3_aarch64.deb`](https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs-lts/nodejs-lts_24.22.3_aarch64.deb) | 10,000,924 B | `80edcc73db025db0baa09be27e3d65a16e6f2a72ab925f1873a1b808ab857c28` |
| `arm` | `armeabi-v7a` | [`nodejs-lts_24.22.3_arm.deb`](https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs-lts/nodejs-lts_24.22.3_arm.deb) | 8,950,300 B | `e7a65deb94edf1fe1a369cee48081de987d4e1d400ed38f7cc115e5739416383` |
| `i686` | `x86` | [`nodejs-lts_24.22.3_i686.deb`](https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs-lts/nodejs-lts_24.22.3_i686.deb) | 11,415,004 B | `8f75eb28a2c52625ebf139ac0d692c1ec79301204e722fe19a3323b0dd663598` |
| `x86_64` | `x86_64` | [`nodejs-lts_24.22.3_x86_64.deb`](https://packages.termux.dev/apt/termux-main/pool/main/n/nodejs-lts/nodejs-lts_24.22.3_x86_64.deb) | 10,434,768 B | `d73ab1303aa1a8ecca188795f536279c7ef196c4e3f72b645e443501b03247e4` |

The corresponding first-party package records are in the [aarch64](https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages), [arm](https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-arm/Packages), [i686](https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-i686/Packages), and [x86_64](https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-x86_64/Packages) `Packages` indexes; the repository timestamp is in its [`Release` file](https://packages.termux.dev/apt/termux-main/dists/stable/Release). A HEAD request to the aarch64 `.deb` returned HTTP 200 and `Last-Modified: 2026-11-11 19:55:13 UTC`.

## Source and maintenance evidence

- Node.js’s [official `v24.22.3` release](https://nodejs.org/en/blog/release/v24.22.3/) identifies it as the Node 24 LTS security release.
- The current [Termux `nodejs-lts` build recipe](https://raw.githubusercontent.com/termux/termux-packages/master/packages/nodejs-lts/build.sh) pins `TERMUX_PKG_VERSION=24.22.3`, fetches the official Node source tarball `https://nodejs.org/dist/v24.22.3/node-v24.22.3.tar.xz`, and pins its SHA-256 to `48ca3aa8a9b02133356922ef4fc80200e00598c80a4ef446f7c39a459222593d`.
- The same recipe maps Termux `aarch64`, `arm`, `i686`, and `x86_64` to Node targets `arm64`, `arm`, `ia32`, and `x64`; it configures `--dest-os=android`, applies Termux package patches, and installs through Node’s `tools/install.py` into `$TERMUX_PREFIX`. Runtime dependencies are `libc++`, OpenSSL, c-ares, ICU, SQLite, and zlib.
- The recipe configures Node with `--without-npm`, sets `TERMUX_PKG_RECOMMENDS="npm"`, and its package script says npm is installed separately for `nodejs-lts` versions starting at 24.13.0. The `nodejs-lts` binary package alone therefore does not include the npm CLI; an Android app would need to package and integrate the separate Termux npm package as well.
- The recipe identifies the upstream Node source version, but does not declare a nodejs-mobile revision or expose a `process.versions.mobile` value; that runtime field was not measured here.
- The recipe names maintainer Yaksh Bariya and sets automatic version updates off. Its maintainer comment says the package is manually updated because one-architecture builds take about two hours and that tests are run on updates. The live APT index observed on the checked date contains 24.22.3 packages for all four advertised architectures. These are concrete maintenance signals; they do not establish a release SLA or a separate Node-for-mobile support commitment.
- The package repository’s `Packages` records expose package filenames, sizes, dependencies, and SHA-256 values. This survey did not independently verify the repository signing key, reproduce the builds, or inspect attestations/SBOMs.

## Embedding and release limits

Termux documents its package prefix as `/data/data/com.termux/files/usr`, and says packages are built for Termux’s root filesystem and have paths rewritten for that prefix ([filesystem layout](https://github.com/termux/termux-packages/wiki/Termux-file-system-layout), [execution environment](https://github.com/termux/termux-packages/wiki/Termux-execution-environment)). Android’s app-specific storage documentation says internal app data is private to that app and other apps cannot access it ([Android Developers](https://developer.android.com/training/data-storage/app-specific)). A Flutter app cannot depend on files installed inside Termux’s private prefix as though they were its own APK libraries.

The surfaced artifact contract is an architecture-specific Termux `.deb` package. The recipe declares an Android Node build and Termux-prefix installation; it does not declare a Flutter/Java embedding API, JNI bridge, or a `libnode.so` SDK release. Reuse would require a separate packaging and integration effort that resolves Termux prefix assumptions and dependencies. The exact `.deb` file inventory was not established in this survey: a read-only download attempt timed out partway through, so no claim is made about its internal member list.

This evidence also does not establish 16 KB ELF load-segment alignment, APK ZIP alignment, or execution on a physical 16 KB-page device. No package was installed or executed, and no accessibility or other tests were run. Treat Termux as a **current-source/current-binary lead**, not as a qualified Aggregate embed-ready runtime: the package installs into Termux’s private prefix, npm is separate, and the checked artifacts/recipe do not expose a Flutter/JNI `libnode.so` embedding SDK. A3.6 still needs a deliberate embedding path, complete source-to-binary and license review, target ABI packaging, and the project’s 16 KB and signing checks.

This was a bounded check of Termux’s official main APT repository and `termux-packages` source, alongside the prior project checks of nodejs-mobile, fogtape, and digidem. It does not establish that all Android Node providers or third-party repositories were surveyed.

### Project-knowledge retrieval feedback

- **Query:** Aggregate A3.6 runtime provenance, Node 24.22.3 Android binary, nodejs-mobile/fogtape/digidem.
- **Partly adopted:** `2026-11-20/aggregate/01a1c4f2-53d2-7c80-889d-ea988fc30461__daily-task.md`. Its bounded findings on the previously checked mobile providers remain applicable; this note adds current Termux package metadata and does not treat the Termux `.deb` as evidence of an embeddable `libnode.so` release.
