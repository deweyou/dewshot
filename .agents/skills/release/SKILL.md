---
name: release
description: 为 DewShot 筹备 Mac App Store 首发、major 或 minor 版本，或继续已有候选的送测、审核和上线收尾。
---

先读[发包规范](../../../docs/release.md)、[CLI 操作手册](../../../docs/store-cli.md)和[商店文案与素材](../../../store-listing/README.md)。若用户要求继续已有版本，先用 CLI 识别分支、候选记录和 Apple 状态，接着上次的阶段做。

1. 先运行 `scripts/store-release.py review`，列出比较基线、候选 SHA、两个具体版本和初步差异；用该 SHA 审阅完整 diff。找上一正式商店版本及其 tag，查看基线到该 SHA 的 git log、完整 diff 和关联 PR。首发时注明历史 GitHub tag 的用途，并覆盖首次上架的完整用户能力。
2. **先在对话中展示**仓库 changelog 草案、中英文用户更新说明、基线和候选 SHA。根据实际改动推荐 major 或 minor，给出理由和两个具体版本号。首发说明版本比较起点。等待用户确认范围及版本；这个阶段只读，不建分支、不改文件、不预分配 build。
3. 从用户审阅的 SHA 创建 release/X.Y，目标 X.Y.0。提交确认过的双语文案并推送，创建指向 main 的 Draft PR。按共享 SOP 预留 build、等该次 push 的 CI、生成并登记候选。若要带入后来合入 main 的功能，重新确认新增范围。
4. 按[填报与提审](../../../docs/release.md#填报与提审)逐项对照，复用仓库里的文案和截图，变动时同步更新。按[持续推进与交接](../../../docs/release.md#持续推进与交接)循环执行和核验。遇到需要用户操作的卡点，明确当前状态、具体操作和恢复步骤。
5. 测试或审核期间的代码修复留在这条分支，只升 build，PR 保持 Draft。确认正式上架并从获批 SHA 打 tag 后，按 SOP 核对 PR 范围、转为可审阅并合回 main。
