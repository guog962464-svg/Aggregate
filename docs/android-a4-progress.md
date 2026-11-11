# A4 npm 包与 CLI 兼容性实验

> 2026-11-11 启动。仅在 Debug 独立探针上验证真实 npm 包；A3.6 尚未完成，本记录不构成发布资格或设备端 npm/通用 CLI 支持。

## 首个样本：JSON5 2.2.3

- `npm view json5@2.2.3` 报包入口 `lib/index.js`、bin `lib/cli.js`、无运行依赖，tarball integrity 为 `sha512-XmOWe7eyHYH14cLdVPoyg+GOH3rYX++KpzrylJwSW98t3Nk+U8XOl8FWfxasyg==`；本地 tarball SHA-256 为 `08afb33db600d11fc89b98fac4054f19d5d3e0fe527063116150e1ecc2d2377b`。`nodeprobe/prepare_a4.sh` 校验该摘要、名称/版本/入口后，把源码、分发文件、包元数据与 MIT LICENSE 暂存于忽略目录。包源不入 Git。
- 独立 Debug App 通过 `--es probe a4-json5` 选择实验入口；Service 把包复制至应用私有 `files/node_modules/json5`，在隔离的 `:node` 进程运行固定脚本。Flutter 产品界面和 `ConnectionSetupPort` 未开放该入口，现有能力查询仍只声明 `a3-fixed`。
- LGE AN10、Android 15/API 35、arm64、4 KB 页：原始包 `require`、运行时拼接路径的动态 `require`、包自带 `dist/index.js`、`dist/index.mjs` 的动态 `import` 均成功解析同一 JSON5 输入；`package.json` 资源读取正确，配置写在应用私有目录并可读回。整 App `force-stop` 后第二次运行成功且 Service generation 不同。`verify_a4.py` 用固定结果断言复现；没有独立外部实现对照。
- `dist/index.js` 是包自带的分发文件，不是本项目生成的 esbuild 产物。A4.1 尚需 esbuild 对照、真实包版本升级和资源清理；A4.2 的 `bin` 参数/输出/取消/并发尚未试。更没有在设备上运行 `npm install` 或验证任意 CLI。

复现：在 `app/android/` 先运行 `nodeprobe/prepare.sh`，再运行 `nodeprobe/prepare_a4.sh [/path/to/json5-2.2.3.tgz]`、`./gradlew :nodeprobe:assembleDebug --offline` 和 `python3 nodeprobe/verify_a4.py`。脚本使用当前连接真机，不启动模拟器，实验结束卸载独立探针 App。

## 下一步

1. 用固定 esbuild 版本从同一包源码生成 bundle，比较体积和真机行为，再做 versionCode/包版本变化的文件清理。
2. 以包的 `lib/cli.js` 为固定 bin 入口，验证参数、stdout/stderr、退出码、取消与并发，仍不执行任意 shebang。
3. 再进入设备端 npm 安装、原生扩展/子进程/TUI 边界和 `@music163/ncm-cli` 样本；这些实验的失败不得反向打开用户可见适配器。
