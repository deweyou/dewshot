# Mac App Store 文案与素材

以下是 2026-11-24 提交的 DewShot macOS 1.0.0（构建 4）的商店资料。每次候选准备时按实际功能和生产配置核对。商店描述、关键词、网址、截图或声明有变化时，同步更新这里和 App Store Connect。每版「此版本的新内容」从 `release-notes/<版本>/` 取用。首发留空。提交步骤见[发包规范](../docs/release.md#填报与提审)。

## 本地化字段

商店主语言为简体中文。两种语言的 Name 都是 `DewShot`，Subtitle 和 Promotional Text 留空。

| 字段 | 中文（简体）`zh-Hans` | English (U.S.) `en-US` |
| --- | --- | --- |
| Description | [中文描述](zh-Hans/description.txt) | [英文描述](en-US/description.txt) |
| Keywords | `截图,录屏,滚动截图,长截图,文字识别,屏幕录制,GIF,OCR` | `screenshot,screen recording,scrolling capture,screen capture,OCR,GIF` |
| Support URL | `https://dewshot.deweyou.me/#support` | `https://dewshot.deweyou.me/en/#support` |
| Marketing URL | `https://dewshot.deweyou.me/` | `https://dewshot.deweyou.me/en/` |
| Privacy Policy URL | `https://dewshot.deweyou.me/privacy/` | `https://dewshot.deweyou.me/en/privacy/` |
| macOS Screenshots | [中文 PNG](zh-Hans/screenshots/) | [英文 PNG](en-US/screenshots/) |

每个语言目录有四张 1440 × 900 RGB PNG，按文件名前缀上传：截图、录屏、滚动截图、文字识别。更新时用候选对应的真实界面和可公开的演示内容，沿用[仓库品牌标识](../assets/brand/dewshot-lockup.svg)和衬线标题的海报版式。上传后逐个语言核对图片数量、顺序和预览。

## 版本和 App 级字段

| App Store Connect 位置 | 1.0.0 用值及后续核对 |
| --- | --- |
| App Information | 主分类 `Utilities`。年龄分级 `4+`，按实重新核对问卷。Content Rights 选择 `No`，首版没有展示或访问需要申报的第三方内容。 |
| macOS App Version | 版本 `1.0.0`，选择已验收候选的 build。Copyright 为 `2026 Dewey Ou`，更新时核对年份和权利人。 |
| App Review Information | `Sign-in required` 未勾选。首发 Notes 和 Attachment 留空。使用 App Store Connect 中已保存的审核联系人，核对姓名、含区号电话和邮箱。联系人变更时向维护者确认。 |
| Pricing and Availability | 免费（`$0`）。选择全部 175 个当时可选的国家和地区。每次检查实际可选地区和计划覆盖。 |
| App Store Version Release | `Manually release this version`。 |
| App Compliance · China mainland | `Security Assessment: No`、`AI Generated or Synthetic Content: No`。首版没有端到端加密即时通信或生成合成内容服务。系统 OCR 从已有图像识别文字。保存后两项显示 `Active`。后续按实际功能及 Apple 最新问卷重新判断。 |
| Build · Export Compliance | 首发构建在 TestFlight 的加密问卷选 `None of the algorithms mentioned above`。每次按所选构建实际加密实现及 Apple 最新问卷重新核对。 |

审核联系人电话、登录凭据、短期 JWT 和密钥保存在原系统或凭据管理工具里。准备审核时可从 App Store Connect 读取已保存的联系人，切勿提交到 Git。

## App Privacy

1.0.0 提交时选择 `Yes, we collect data from this app`。下表记录已发布的回答。若 SDK、埋点、生产开关或数据共享设置变动，核对表格、隐私政策、候选包中的隐私清单和 App Store Connect。产品数据范围见[遥测 PRD](../docs/dewshot-telemetry-prd.md)。

| Apple 数据类型 | 用途 | Linked to You | Tracking |
| --- | --- | --- | --- |
| Device ID | Analytics | Yes | No |
| Product Interaction | Analytics | Yes | No |
| Performance Data | App Functionality, Analytics | Yes | No |
| Coarse Location | Analytics | Yes | No |
| Crash Data | App Functionality | No | No |
| Other Diagnostic Data | App Functionality, Analytics | No | No |

GA4 用安装实例 ID 关联用量和计时事件，并由 IP 推导粗略位置。首发核对时 Google Signals 未启用，生产属性没有关联 Google Ads、AdMob、Display & Video 360 或 Search Ads 360。GA4 账号开启了 Google 产品和服务的数据共享，设置页说明 Google 不将此数据用于其自身广告个性化或定位。Sentry 会在发送前移除身份字段，Firebase 的诊断 user agent 也不关联用户或设备 ID。判定依据见 [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)、[Google Analytics 披露说明](https://support.google.com/analytics/answer/10285841)和 [Firebase 披露说明](https://firebase.google.com/docs/ios/app-store-data-collection)。

首发提交时已知差异：官网隐私政策没有明确描述 GA4 推导的粗略位置。构建 4 的 App 隐私清单没有列出粗略位置，且将设备 ID、产品交互和性能数据标为未关联。下次准备候选时同步核对并修正这些差异。
