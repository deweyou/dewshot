# Mac App Store 发包规范

DewShot 使用 TestFlight 验收候选，通过 App Store 发布。官网独立跟随 main 部署。
[release](../.agents/skills/release/SKILL.md) 从审阅 main 的差异开始；
[patch](../.agents/skills/patch/SKILL.md) 从确认问题及已上架基线开始。
两个流程可以跨会话执行。恢复时先查当前分支、远端候选记录和 Apple 状态。

## 分支与文案

| 入口 | 用户确认后切分支 | 产品版本 | 上线前返工 |
| --- | --- | --- | --- |
| release | 从审阅过的 main SHA 切 release/X.Y | X.Y.0 | 原分支升 build |
| patch | 从正式 tag 切 patch/X.Y.Z | 下一补丁号 | 原分支升 build |

对 diff 同时看提交、PR 和实际文件。仓库级 CHANGELOG.md 保留工程变化和有助追溯的 PR 引用。功能分支上的条目写入 Unreleased。记录本次候选覆盖的条目，版本段的发布日期在上架核对后填写。

每个版本提交两份用户文案至 `release-notes/<版本>/zh-Hans.md` 和 `en.md`。两份覆盖同样的用户变化；首发描述产品能力，更新版本的正文用于 App Store 的「此版本的新内容」。官网、CI 和纯工程调整按实际用户影响决定是否写入。当前还没有正式发布的商店版本，历史 v0.1.x 是 GitHub 版本；第一次计算 major/minor 时注明此基线的区别。已发布 tag 可通过其提交上的 store-package 记录与 Apple 商店版本核对。

## 准备与出包

以下以 1.0.0 为例。在临时分支上提交已审阅的内容，保持工作区干净。日常分支和本地 Dev 沿用原有打包方式。

1. 运行 `scripts/store-release.py reserve 1.0.0`。脚本读取候选、远端 main 和远端已预留的 build，递增全局编号，更新 FrameVersion 并提交，将分支与轻量 tag `store-build/N` 原子推送。首次启用时与 TestFlight 上传历史核对编号上限；现有 0.1.2 (3) 已记录在 FrameVersion。之后所有候选统一从这个入口分配。不要删除或移动候选记录。
2. 等同一 SHA 的分支 push CI 通过。根据[签名与打包说明](development.md#mac-app-store-and-testflight)运行 `scripts/package-app-store.sh`。入口检查分支、SHA、预留号、双语文案和 CI，校验签名及 dSYM，并将版本、build、SHA 和最终 pkg 的 SHA-256 写入远端附注 tag `store-package/N`。该记录在临时分支删除后仍可读取。
3. 取得凭据的机器保留对应 pkg 和 dSYM。上传前用 `git tag -l --format='%(contents)' store-package/N` 和 `shasum -a 256 <pkg>` 核对。使用 Transporter 上传登记的 pkg。在 TestFlight 安装该 build，验证首次授权、截图与录屏、保存、历史和隐私入口。验收后在 App Store Connect 选择同一 build 提审。
4. 若只改商店素材，继续用原包。需要修改代码时在临时分支提交修复、更新相关说明，再运行 reserve 分配下一号。临时分支允许直接 push，CI 验证每次候选。开发流程自身无需新增产品埋点。

## 恢复中断

- 先执行 `git fetch origin --tags`。预留已成功且 HEAD 未变时 reserve 返回原 build。原子推送失败时先查远端；分支未推进且号码仍空闲，可按脚本输出的提交重新原子推送。同号已被另一条线占用时，在最新远端状态分配下一号；若本分支同时推进，先整合其改动。
- 包已登记时，核对校验和后复用同一文件。pkg 已写出但登记推送中断时，确认它是本次打包产物、签名有效且本机保留匹配的 SHA 和 dSYM，再在原候选 checkout 执行 `scripts/store-release.py record <pkg绝对路径> <候选SHA>` 重试登记。已有远端记录不符时停止。包已遗失且需要重新构建时，执行 `reserve <版本> --replacement` 从相同产品代码分配新 build。
- 审核等待、拒绝、撤回或待开发者发布时保留分支；继续已有版本时按 Apple 实际状态恢复。

## 上架核对与回合

命令读取短期 JWT 环境变量 `ASC_JWT`，仅向 Apple 发 GET 请求。使用有权读取 DewShot 版本和构建的 App Store Connect 凭据生成令牌；本机 Xcode 支持 `xcrun altool --generate-jwt --apiKey <key-id> --apiIssuer <issuer-id>`。私钥存于个人凭据目录，避免将 JWT 或私钥写入仓库、日志和聊天。无凭据时可以先在后台检查进度，自动收尾仍需 API 核对。

1. `scripts/store-release.py status 1.0.0` 查询 DewShot 的 macOS 商店版本及其关联 build。首次配置时让商店版本号与三段产品版本一致。
2. `scripts/store-release.py finalize 1.0.0` 重新查询 Apple。只有状态为 READY_FOR_DISTRIBUTION 且关联 build 与远端候选记录、源码版本一致，才把 v1.0.0 推到实际发布的 SHA。该条件代表版本发布状态，各地区可下载性单独核查。重复执行保留已有同提交 tag；不同提交的同名 tag 不得覆盖。
3. **从这一步才启动回合。** 用普通 merge PR 把获批提交合回 main。分支 tip 与 tag 不同就从 tag 建收尾分支。整理 CHANGELOG.md，把本次条目移至带实际发布日期的版本段；保留 main 新增的 Unreleased 条目、更新的产品版本和 build。收尾文档提交可以在获批提交之后，正式 tag 始终指向出包提交。如果 patch 还影响正在送审的版本，单独将修复同步到其候选分支并重新验收。
4. PR 合入后 fetch，核对远端 tag，运行 `git merge-base --is-ancestor v1.0.0 origin/main`。检查原临时分支 tip 已合入或其额外提交已妥善保留，再删临时分支；保留正式 tag 和候选记录。

仓库规则应允许维护者在 release/*、patch/* 直接推送，合入 main 走 PR。
正式 tag 及 store-build/*、store-package/* 应限制改写和删除，临时分支须允许收尾后删除。
