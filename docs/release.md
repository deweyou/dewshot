# Mac App Store 发包规范

DewShot 使用 TestFlight 验收候选，通过 App Store 发布。官网独立跟随 main 部署。
[release](../.agents/skills/release/SKILL.md) 从审阅 main 的差异开始；
[patch](../.agents/skills/patch/SKILL.md) 从确认问题及已上架基线开始。
两个流程按[持续推进与交接](#持续推进与交接)执行。恢复时先查当前分支、远端候选记录和 Apple 状态。

## 分支与文案

| 入口 | 用户确认后切分支 | 产品版本 | 上线前返工 |
| --- | --- | --- | --- |
| release | 从审阅过的 main SHA 切 release/X.Y | X.Y.0 | 原分支升 build |
| patch | 从正式 tag 切 patch/X.Y.Z | 下一补丁号 | 原分支升 build |

对 diff 同时看提交、PR 和实际文件。仓库级 CHANGELOG.md 保留工程变化和有助追溯的 PR 引用。功能分支上的条目写入 Unreleased。记录本次候选覆盖的条目，版本段的发布日期在上架核对后填写。

每个版本提交两份用户文案至 `release-notes/<版本>/zh-Hans.md` 和 `en.md`。两份覆盖同样的用户变化。首发说明描述产品能力，更新版本的正文用于 App Store 的「此版本的新内容」。商店描述长期维护在 [store-listing](../store-listing/README.md)。官网、CI 和纯工程调整按实际用户影响决定是否写入。历史 v0.1.x 是 GitHub 版本，1.0.0 是首个送审的商店版本。已发布 tag 可通过其提交上的 store-package 记录与 Apple 商店版本核对。

## 准备与出包

以下以 1.0.0 为例。在临时分支上提交已审阅的内容，保持工作区干净。日常分支和本地 Dev 沿用原有打包方式。

1. 运行 `scripts/store-release.py reserve 1.0.0`。脚本读取候选、远端 main 和远端已预留的 build，递增全局编号，更新 FrameVersion 并提交，将分支与轻量 tag `store-build/N` 原子推送。首次启用时与 TestFlight 上传历史核对编号上限；现有 0.1.2 (3) 已记录在 FrameVersion。之后所有候选统一从这个入口分配。不要删除或移动候选记录。
2. 等同一 SHA 的分支 push CI 通过。根据[签名与打包说明](development.md#mac-app-store-and-testflight)运行 `scripts/package-app-store.sh`。入口检查分支、SHA、预留号、双语文案和 CI，校验签名及 dSYM，并将版本、build、SHA 和最终 pkg 的 SHA-256 写入远端附注 tag `store-package/N`。该记录在临时分支删除后仍可读取。
3. 取得凭据的机器保留对应 pkg 和 dSYM。按 [App Store Connect CLI 操作手册](store-cli.md)上传已登记的包、等 Apple 处理并加到 TestFlight 内部组。在真机安装该 build，验证首次授权、截图与录屏、保存、历史和隐私入口。验收后挂同一 build 提审。
4. 若只改商店素材，继续用原包并更新[仓库素材](../store-listing/README.md)。需要修改发包内容时在临时分支提交修复、更新相关说明，再运行 reserve 分配下一号。临时分支允许直接 push，CI 验证每次候选。开发流程自身无需新增产品埋点。

## 填报与提审

在 CI 或 Apple 处理包期间，按 [CLI 操作手册](store-cli.md)核对[商店文案与素材](../store-listing/README.md)，把可以独立完成的字段填好。功能、界面、隐私做法或发售设置有变化时，在同一任务更新仓库资料与商店字段。

1. Mac App Store 的版本字段用三段产品版本 `X.Y.Z`。build 是独立的数字，核对 App Store Connect 的 `X.Y.Z (N)`、TestFlight 验收和 `store-package/N` 是同一候选。
2. 先核对 App Information、Pricing and Availability、App Compliance 和 App Privacy。预览差异再写入。出现保存超时或通用错误时，先读回状态，再决定是否重试。首发部分表单曾提示失败，后来读回发现数据已保存。
3. 通过 CLI 同步两种语言的文案、网址和截图，再核对审核联系人、登录说明、发布方式、导出合规和选定 build。记录 TestFlight 上实际完成的交互验收。
4. 通过 `asc validate` 和 `asc review doctor` 排查缺项，能独立解决的一次处理完。`Ready for Review` 表示已加入审核草稿。按授权执行 `asc review submit` 后，用 `scripts/store-release.py status` 核对版本、build 与 `WAITING_FOR_REVIEW` 或后续状态。

## 持续推进与交接

代理持续执行当前授权范围内的发布步骤，直到达到本次目标或出现必须由他人解除的阻塞。对同一版本按以下顺序循环。

1. 核对当前版本、build、候选 SHA、CI 和 Apple 当前状态，用 Git 和 Apple 记录确认最近完成的步骤。收到「可以了」或其他接手完成通知后，先核验对应页面或状态，再接着做。
2. 自行执行下一项已授权的操作，按结果继续。CI、构建处理或审核仍在等待，并且用户要求跟进到后续状态时，先推进其他独立步骤，再适度轮询。可恢复的错误先诊断，根据远端记录安全重试。状态有实质变化再更新用户。
3. 遇到需要用户登录、授权、真机操作或即时确认的步骤，尽量把页面停在可执行的位置。一次说清**版本和 build、当前阶段、已完成或已验证项、卡点和证据、具体谁要在哪个页面做什么、完成后如何继续**。同批可预见的操作集中说明，等待回复期间继续独立工作。
4. 如果当前环境不能继续等待或执行，把上述进度和下一个检查入口留在当前会话。恢复时从该检查点核对实际状态，避免重复上传、分配 build 或提交。审核拒绝时先读 Apple 给出的具体原因，能通过素材和表单处理的继续用原 build，涉及发包变更时按原候选分支返工。

例如：「1.0.0（构建 4）已挂载，公开 API 校验已过。Apple 网页会话已过期，App Privacy 发布状态待核验。请在终端运行 `asc web auth login --apple-id <Apple Account>` 并完成 2FA。登录后我会读回隐私与合规状态，再跑提审校验。」

## 恢复中断

- 先执行 `git fetch origin --tags`。预留已成功且 HEAD 未变时 reserve 返回原 build。原子推送失败时先查远端；分支未推进且号码仍空闲，可按脚本输出的提交重新原子推送。同号已被另一条线占用时，在最新远端状态分配下一号；若本分支同时推进，先整合其改动。
- 包已登记时，核对校验和后复用同一文件。pkg 已写出但登记推送中断时，确认它是本次打包产物、签名有效且本机保留匹配的 SHA 和 dSYM，再在原候选 checkout 执行 `scripts/store-release.py record <pkg绝对路径> <候选SHA>` 重试登记。已有远端记录不符时停止。包已遗失且需要重新构建时，执行 `reserve <版本> --replacement` 从相同产品代码分配新 build。
- 审核等待、拒绝、撤回或待开发者发布时保留分支；继续已有版本时按 Apple 实际状态恢复。

## 上架核对与回合

`status` 和 `finalize` 通过 `asc` 的公开 API 核对发布状态和关联 build。沿用 `asc` 已设置的凭据，也兼容原先传入的短期 `ASC_JWT`。当 Apple 显示待开发者发布时，按授权使用 `asc versions release --version-id "$VERSION_ID" --confirm`，再核对上架状态。

1. `scripts/store-release.py status 1.0.0` 查询 DewShot 的 macOS 商店版本及其关联 build。首次配置时让商店版本号与三段产品版本一致。
2. `scripts/store-release.py finalize 1.0.0` 重新查询 Apple。只有状态为 READY_FOR_DISTRIBUTION 且关联 build 与远端候选记录、源码版本一致，才把 v1.0.0 推到实际发布的 SHA。该条件代表版本发布状态，各地区可下载性单独核查。重复执行保留已有同提交 tag；不同提交的同名 tag 不得覆盖。
3. **从这一步才启动回合。** 用普通 merge PR 把获批提交合回 main。分支 tip 与 tag 不同就从 tag 建收尾分支，再带入应保留的商店素材和流程文档提交。整理 CHANGELOG.md，把本次条目移至带实际发布日期的版本段，保留 main 新增的 Unreleased 条目、更新的产品版本和 build。正式 tag 始终指向出包提交。如果 patch 还影响正在送审的版本，单独将修复同步到其候选分支并重新验收。
4. PR 合入后 fetch，核对远端 tag，运行 `git merge-base --is-ancestor v1.0.0 origin/main`。检查原临时分支 tip 已合入或其额外提交已妥善保留，再删临时分支；保留正式 tag 和候选记录。

仓库规则应允许维护者在 release/*、patch/* 直接推送，合入 main 走 PR。
正式 tag 及 store-build/*、store-package/* 应限制改写和删除，临时分支须允许收尾后删除。
