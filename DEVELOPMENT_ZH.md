# DewShot 开发指南

[English](DEVELOPMENT.md)

开发环境需要 macOS 26 或更高版本、Swift 6.2，以及包含 macOS 26 或更高版本 SDK 的 Xcode 命令行工具。在仓库根目录运行 `swift build` 即可编译 Swift 包。本地编译和临时签名打包都无需开发者账号。

## 本地提交前

用 `git diff --cached` 审阅暂存改动，用 `git diff --cached --check` 检查空白错误，再按改动选择验证。

| 改动 | 本地检查 |
| --- | --- |
| 文档 | 检查改过的链接和标题锚点，对照脚本核对命令示例。 |
| Swift 逻辑 | 跑受影响的测试。例如修改录屏命名时，运行 `swift test --filter RecordingNamingTests`。 |
| 打包 | 验证受影响的变体。改包名映射时可用 `scripts/package-app.sh --print-configuration`。改包内文件时，生成并检查产物。 |
| AppKit 或桌面交互 | 跑相关的[组件测试](docs/testing.md#ci-expectations)。用签名后的应用验证本次改动涉及的快捷键、权限或捕获流程。 |

## 合入与发布前

合入前检查 PR 当前提交的 CI 结果。GitHub Actions 在 PR 和推送到 `main` 时运行稳定测试集、构建、打包并检查产物。三组依赖真实窗口的 AppKit 测试按需在本机运行。提审前用 TestFlight 安装指定构建进行验收。

Dev 签名安装、沙盒验证及分发步骤见[构建与发布手册](docs/development.md)。产品、设计、架构和测试文档见[知识库索引](docs/README.md)。

新版本、线上补丁及上架后的回合见[发包规范](docs/release.md)。
