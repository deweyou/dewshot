# App Store Connect CLI 操作手册

[发包规范](release.md)中的 App Store Connect 操作默认从终端执行。以下命令适用于 `asc` 7.4.0，从仓库根目录运行。商店字段的预期值见[商店资料](../store-listing/README.md)。

## 登录与恢复

缺少 `asc` 时用 `brew install asc`。公开 API 沿用本机 `asc` 凭据，用 `asc auth status --validate` 检查。首次配置时按[上游认证说明](https://docs.asccli.sh/commands/auth/)导入团队 API key。密钥、审核联系人的私人信息和会话凭据保存在本机凭据管理工具中。

```bash
APP=6838558686
VERSION=1.0.0  # 恢复时填写本次版本
BUILD=4       # 与 store-package/N 和实际验收构建一致
scripts/store-release.py status "$VERSION"
asc builds info --app "$APP" --platform MAC_OS --version "$VERSION" --build-number "$BUILD"
```

每步执行后用 CLI 读回对应状态。恢复时先查 Apple 的构建、上传记录、版本或审核草稿，再跳到尚未完成的步骤。`BUILD_ID` 是 Apple 的构建资源 ID，`VERSION_ID` 是商店版本资源 ID，从相应查询的 JSON 取值。轮询中断后继续查询同一版本和构建。

## 上传与 TestFlight

```bash
scripts/store-release.py upload "$PKG"
asc builds wait --build-id "$BUILD_ID" --timeout 20m
asc builds add-groups --build-id "$BUILD_ID" --group "$INTERNAL_GROUP_ID"
```

`upload` 核对远端的预留记录、包登记和 SHA-256，再检查 Apple 有无同一上传。遇到上传超时或 Apple 尚未生成 build ID 时，用以下命令查看处理结果。`asc builds upload --dry-run` 在 7.4.0 会创建远端上传记录。只读核对用 `list`。

```bash
asc builds uploads list --app "$APP" --platform MAC_OS \
  --cf-bundle-short-version "$VERSION" --cf-bundle-version "$BUILD"
```

取到 `BUILD_ID` 后补上构建处理检查和内部组分发。若 Apple 要求导出合规，在核实本次构建适用豁免后用 `asc builds update --build-id "$BUILD_ID" --uses-non-exempt-encryption=false`，再用 `asc builds info` 读回。如果 Apple 要求文件，使用 `asc encryption declarations` 和 `asc encryption documents`。TestFlight 安装与真实交互验收按[开发指南](development.md#mac-app-store-and-testflight)执行。

## 版本、资料与截图

新版本用 `asc versions create --app "$APP" --platform MAC_OS --version "$VERSION" --release-type MANUAL --copyright "$COPYRIGHT" --if-exists skip`。已有版本用 `asc versions view` 核对，必要时以 `asc versions update --version-id "$VERSION_ID"` 修改发布方式或版权。

```bash
scripts/store-release.py metadata "$VERSION"
scripts/store-release.py metadata "$VERSION" --apply
asc screenshots upload --app "$APP" --version-id "$VERSION_ID" \
  --path store-listing --device-type APP_DESKTOP --skip-existing --dry-run
asc screenshots upload --app "$APP" --version-id "$VERSION_ID" \
  --path store-listing --device-type APP_DESKTOP --skip-existing
```

元数据默认预览。应用后再跑预览，确认差异为空。截图命令可批量处理两个语言目录。`--skip-existing` 按已有文件跳过，替换同名图片或重排时，先按语言预览 `--replace --dry-run`，确认目标集合和顺序后才执行 `--replace --confirm`。上传后用 `asc screenshots list --version-localization "$LOCALIZATION_ID"` 核对每种语言的资产状态和顺序。

| 字段 | CLI |
| --- | --- |
| 主分类与内容权利 | `asc apps info view`、`asc categories set`、`asc apps update --id "$APP" --content-rights` |
| 年龄分级 | `asc age-rating view --app "$APP"`，问卷变化时用 `asc age-rating edit` |
| 定价 | `asc pricing schedule view --app "$APP"`。确需改价时先用 `asc pricing price-points` 找到目标价位，再用 `asc pricing schedule create` 写入。该操作会替换整个价格计划 |
| 发售地区 | `asc pricing availability view --app "$APP"`，使用 `availability create` 或 `availability edit` 设置地区。全部地区用 `--all-territories --available true`，是否自动加入未来新增地区单独按发布决定填写 |
| 审核联系人、登录要求及审核备注 | `asc review details-for-version --version-id "$VERSION_ID"`，需要填写时用 `asc review details-create` 或 `asc review details-update`。读取时避免回显私人字段 |

## 隐私、地区合规与协议

`asc web` 使用独立的 Apple Account 会话，底层使用 Apple 网页接口。先用 `asc web auth status` 检查，缺少会话时在交互终端运行 `asc web auth login --apple-id "$APPLE_ACCOUNT"`，由账号持有人完成登录和 2FA。Apple 改动接口导致 CLI 无法完成时，从对应的 App Store Connect 页面接手。

```bash
asc web privacy pull --app "$APP" --out "$PRIVACY_JSON"
asc web privacy plan --app "$APP" --file "$PRIVACY_JSON"
asc web apps compliance list --app "$APP"
asc web agreements status
```

- 隐私有变动时，按更新后的[商店资料](../store-listing/README.md#app-privacy)编辑 `privacy pull` 导出的 JSON，用 `plan` 查看差异，再执行 `asc web privacy apply --app "$APP" --file "$PRIVACY_JSON" --confirm`。计划涉及删项时逐项核实，再按需加 `--allow-deletes`。回读确认后，按发布声明的授权用 `asc web privacy publish --app "$APP" --confirm`，再用 `asc validate --deep` 检查已发布状态。
- 中国大陆两项要求用 `asc web apps compliance set --app "$APP" --requirement SECURITY_ASSESSMENT --declared false --dry-run` 预览。另一项的代码是 `AI_GENERATED_CONTENT`。`false` 只用于确实不适用的功能，符合适用条件时按命令提示提供对应材料。确认后以 `--confirm` 代替 `--dry-run`，用 `compliance list` 读回。
- 待签协议用 `asc web agreements status` 识别。若 Apple 要求 Account Holder 确认，把具体协议和待办交给对方。继续处理其他可独立完成的步骤。

## 提审、跟进与发布

```bash
asc versions attach-build --version-id "$VERSION_ID" --build-id "$BUILD_ID"
asc validate --app "$APP" --platform MAC_OS --version "$VERSION"
asc review doctor --app "$APP" --platform MAC_OS --version "$VERSION"
asc review submit --app "$APP" --platform MAC_OS --version "$VERSION" --build-id "$BUILD_ID" --dry-run
```

有有效网页会话时给同一个 `asc validate` 命令加 `--deep`。只需创建审核草稿时，先用 `asc review submissions list --app "$APP" --platform MAC_OS --state READY_FOR_REVIEW` 找现有草稿。需要新建时用 `asc review submissions-create --app "$APP" --platform MAC_OS`，再用 `asc review items-add --submission "$SUBMISSION_ID" --item-type appStoreVersions --item-id "$VERSION_ID" --if-exists skip` 加入版本。获准提审后，将 `review submit` 的 `--dry-run` 换成 `--confirm`。

提交后用 `scripts/store-release.py status "$VERSION"` 核对审核状态与关联构建。此时 `asc validate` 会把已进入审核队列的版本判为不可编辑，后续查询用 `status`。需要持续跟进时，用 `asc status --app "$APP" --platform MAC_OS --until review-done --timeout 2h` 作为轮询入口，结束后再次核对指定版本。等待超时只代表本轮没有等到结果。获准手动发布时运行 `asc versions release --version-id "$VERSION_ID" --confirm`。上架核对、打 tag 和回合按[发包规范](release.md#上架核对与回合)执行。
