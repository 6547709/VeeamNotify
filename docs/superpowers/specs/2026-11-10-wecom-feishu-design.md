# 企业微信与飞书通知支持 — 设计文档

日期：2026-11-10
基于：VeeamNotify v2.1.2（tigattack）

## 1. 背景与目标

VeeamNotify 是一个 PowerShell 项目，在 Veeam Backup & Replication 任务结束后，把会话摘要推送到 Discord、Slack、Microsoft Teams、Telegram 或通用 HTTP 端点。

本次改造目标：

1. 新增**企业微信**（群机器人 webhook）和**飞书**（自定义机器人 webhook）两个通知服务。
2. 通知内容与现有 **Slack** 通知保持一致，不新增字段、不做内容扩展。
3. 代码提交到一个新的公开仓库：`github.com/6547709/VeeamNotify`，保留 MIT 协议和原作者署名。

成功标准：在 `conf.json` 中启用 `wecom` 或 `feishu` 并填入群机器人 webhook 后，Veeam 任务结束时会收到与 Slack 内容一致的通知；消息在两家客户端中呈现为卡片样式。

## 2. 非目标

- 不实现 @ 成员/提及。用户明确只需要“群里一个机器人 + webhook 地址”。企业微信 markdown 其实支持 `<@userid>`，飞书卡片也支持 `<at id=ou_xxx></at>`，但两者都需要额外的成员标识，本次不配置。配置中的 `mentions` 对这两个服务不生效，也不报错。
- 企业微信使用 `template_card` 的 `text_notice`（文本通知型）模板卡片，不使用 markdown，也不使用应用消息的 `textcard`（群机器人 webhook 不支持 `textcard`）。
- 不修改现有 Discord / Slack / Teams / Telegram / HTTP 的消息内容与发送行为。
- 不修改 `Updater.ps1` 的升级通知内容（该通知只面向 Discord，属于升级工具自身功能）。
- **会**把功能性的 GitHub 仓库地址从 `tigattack/VeeamNotify` 改为 `6547709/VeeamNotify`（更新检查、Installer/Updater 下载、更新提示链接），并发布 `v2.2.0` release。上游 wiki 链接和 README 署名保留。

## 3. 约束

- 必须兼容 Windows PowerShell 5.1（Veeam 服务器的常见运行环境）。禁止使用 PowerShell 7 专属语法（三元运算符、`??`、`-Parallel` 等）。
- 保持现有模块边界与调用约定：
  - 消息体构造在 `resources/NotificationBuilder.psm1`
  - 发送逻辑在 `resources/NotificationSender.psm1`
  - 服务分发在 `AlertSender.ps1`
- 企业微信 `text_notice` 模板卡片限制：`horizontal_content_list` 最多 6 项，`sub_title_text` 建议最多 8 行 / 112 字，`quote_area.quote_text` 最多 3 行，`jump_list` 最多 3 项，`card_action` 必填。
- 飞书自定义机器人单次请求上限 20 KB；本通知远低于该值。
- 两个服务都使用 `enabled` + `webhook` 两个配置项（飞书是否额外需要 `secret` 取决于用户机器人是否开启签名校验，见第 13 节）。
- 通知文案全部使用英文，与 Slack 完全一致；不翻译。
- 为保证包含中文的作业名/页脚不乱码，`Send-Payload` 改为以 UTF-8 字节发送 JSON 请求体（`Content-Type: application/json; charset=utf-8`）。这是对所有服务都成立的编码修正。
- macOS 本地验证使用 `pwsh` 7.6.9；Veeam 集成只能在 Windows 上人工验证。

## 4. 配置

`config/conf.example.json` 新增：

```json
"wecom": {
    "enabled": false,
    "webhook": "WeComWebhook"
},
"feishu": {
    "enabled": false,
    "webhook": "FeishuWebhook"
}
```

`config/schema.json`：

- 在 `services.properties` 中新增 `wecom`、`feishu`，各自 `required: ["enabled", "webhook"]`。
- **不**把 `wecom`、`feishu` 加入 `services.required`，以兼容已有 `conf.json`（旧配置缺少这两个键时仍能通过校验）。

`Installer.ps1`：

- 在服务选择菜单末尾追加两项：`5 = 企业微信`、`6 = 飞书`。追加到末尾可以保持现有 0–4 的索引不变。
- 选 5/6 时只提示输入 webhook URL。
- `Set-MentionPreference` 对 5/6 跳过（与现有 HTTP 的处理方式一致）。

## 5. 消息内容映射

以下内容与 Slack 一致，**全部使用英文原文**：

- 标题：`JobName`
- 会话信息：`*Session result:* $Status`、`*Job type:* $JobType`
- 页脚：`FooterMessage` 原文
- 更新提示（当 `UpdateAvailable` 且 `NotifyUpdate`）：`A new version of VeeamNotify is available! See release *$LatestVersion* on GitHub.` + release 链接
- 时间格式：`Get-Date -UFormat '%d %B %Y %R'`（与 Slack 相同）

字段分支：

- 普通 VM 备份/复制（`JobType` 不以 `Agent Backup` 或 `Tape Backup` 结尾）：
  `Backup Size`、`Transferred Data`、`Dedup Ratio`、`Compression Ratio`、`Processing Rate`、`Bottleneck`、`Start Time`、`End Time`、`Duration`
- Agent 备份 / 磁带备份（`JobType` 以 `Agent Backup` 或 `Tape Backup` 结尾）：
  `Processed Size`、`Transferred Data`、`Processing Rate`、`Bottleneck`、`Start Time`、`End Time`、`Duration`

说明：Slack 当前用 `-not ($JobType.EndsWith('Agent Backup'))` 判断，导致“File Tape Backup”/“Repo Tape Backup”会进入普通分支并显示空的 Backup Size（`AlertSender.ps1` 对磁带任务只传 `ProcessedSize`）。新服务采用 Teams 的正确分支（Agent 或 Tape 都用 Processed Size）。这是修正，不改变普通备份的内容。

缩略图/头像：Slack 会显示 Veeam logo 缩略图和页脚头像。企业微信模板卡片可以用 `source.icon_url` 显示缩略图；飞书 Card 2.0 的图片组件需要先上传图片拿 `img_key`，为保持两端一致，飞书不展示图片。

## 6. 企业微信消息体

使用**文本通知型模板卡片**（`msgtype: template_card`，`card_type: text_notice`）。模板卡片的结构化字段可以完整承载 Slack 的 9 项指标，不需要 markdown。

请求骨架：

```json
{
  "msgtype": "template_card",
  "template_card": {
    "card_type": "text_notice",
    "source": {
      "icon_url": "<ThumbnailUrl>",
      "desc": "<Status>",
      "desc_color": 3
    },
    "main_title": {
      "title": "<JobName>",
      "desc": "Session result: <Status>"
    },
    "sub_title_text": "Job type: <JobType>\nStart Time: <start>\nEnd Time: <end>\nDuration: <duration>",
    "horizontal_content_list": [
      { "keyname": "Backup Size", "value": "<DataSize>" },
      { "keyname": "Transferred Data", "value": "<TransferSize>" },
      { "keyname": "Dedup Ratio", "value": "<DedupRatio>" },
      { "keyname": "Compression Ratio", "value": "<CompressRatio>" },
      { "keyname": "Processing Rate", "value": "<Speed>" },
      { "keyname": "Bottleneck", "value": "<Bottleneck>" }
    ],
    "quote_area": {
      "type": 0,
      "title": "VeeamNotify",
      "quote_text": "<FooterMessage>\n<optional update notice>"
    },
    "card_action": {
      "type": 1,
      "url": "https://github.com/6547709/VeeamNotify"
    }
  }
}
```

字段映射：

- `source.icon_url` = `$ThumbnailUrl`
- `source.desc` = `$Status`，`source.desc_color`：Success→`3`（绿），Warning/Failed→`2`（红），其他→`0`（灰）
- `main_title.title` = `$JobName`
- `main_title.desc` = `Session result: $Status`
- `sub_title_text` = 4 行：`Job type: $JobType`、`Start Time: $timestampStart`、`End Time: $timestampEnd`、`Duration: $Duration`
- `horizontal_content_list`：
  - 普通任务（6 项）：Backup Size、Transferred Data、Dedup Ratio、Compression Ratio、Processing Rate、Bottleneck
  - Agent/磁带任务（4 项）：Processed Size、Transferred Data、Processing Rate、Bottleneck
- `quote_area`（`type: 0`，不可点击）：`title = 'VeeamNotify'`，`quote_text` 为页脚；若有更新，再追加一行更新提示（总共不超过 3 行）
- `card_action`（必填，`type: 1`）：有更新时 `url` = release 链接，否则 `url` = `https://github.com/6547709/VeeamNotify`
- `emphasis_content` / `jump_list` 不使用：`quote_area` 与 `emphasis_content` 不建议共用，且横向字段已经足够

更新提示文本（追加在 `quote_area.quote_text`）：

```
A new version of VeeamNotify is available! See release <version> on GitHub.
```

说明：`horizontal_content_list` 的 `keyname` 官方建议不超过 5 个字，但英文指标名较长；本次保留完整英文标签，让客户端按可用宽度换行。若实际客户端截断明显，可改用短标签（Backup / Transfer / Dedup / Compress / Rate / Bottleneck）。

响应判定：HTTP 200 不代表成功，需检查响应 JSON 的 `errcode == 0`；否则视为发送失败，把 `errcode` / `errmsg` 放进 `NotificationResult.Detail`。

## 7. 飞书消息体

使用最新的交互式卡片 **Card JSON 2.0**（`schema: "2.0"` + `body.elements`）。约束：

- 必须显式写 `"schema": "2.0"`，否则按 v1 解析。
- Card 2.0 需要飞书客户端 ≥ 7.20。
- 单卡最多 200 个元素。
- `config.update_multi` 在 2.0 中固定为 `true`。

请求骨架：

```json
{
  "msg_type": "interactive",
  "card": {
    "schema": "2.0",
    "config": { "update_multi": true },
    "header": {
      "template": "green",
      "title": { "tag": "plain_text", "content": "<JobName>" }
    },
    "body": {
      "direction": "vertical",
      "padding": "12px",
      "elements": [
        {
          "tag": "markdown",
          "content": "**Session result:** Success\n**Job type:** VM Backup"
        },
        {
          "tag": "column_set",
          "flex_mode": "none",
          "columns": [
            {
              "tag": "column",
              "width": "weighted",
              "weight": 1,
              "elements": [
                {
                  "tag": "markdown",
                  "content": "**Backup Size**\n1.2 TB\n\n**Dedup Ratio**\n2\n\n**Processing Rate**\n120 MB/s\n\n**Start Time**\n10 November 2026 01:00\n\n**Duration**\n1h 2m 3s"
                }
              ]
            },
            {
              "tag": "column",
              "width": "weighted",
              "weight": 1,
              "elements": [
                {
                  "tag": "markdown",
                  "content": "**Transferred Data**\n300 GB\n\n**Compression Ratio**\n2\n\n**Bottleneck**\nSource\n\n**End Time**\n10 November 2026 02:02"
                }
              ]
            }
          ]
        },
        { "tag": "hr" },
        {
          "tag": "markdown",
          "text_size": "small",
          "content": "<font color='grey'><FooterMessage></font>"
        }
      ]
    }
  }
}
```

字段布局：普通任务 9 项按下标奇偶分成两列（左列 0/2/4/6/8，右列 1/3/5/7）；Agent/磁带任务 7 项同样分两列（左列 0/2/4/6，右列 1/3/5）。每列用一个 `markdown` 元素承载多行 `**标签**\n值`，列之间用空行分隔，近似 Slack 的两列 field 布局。

状态对应的 header 颜色（Card 2.0 支持的颜色）：

| Status | `header.template` |
|--------|-------------------|
| Success | `green` |
| Warning | `orange` |
| Failed | `red` |
| 其他/None | `grey` |

更新提示追加在页脚之前，使用 Card 2.0 的 `markdown` + `button`（注意 2.0 的按钮跳转用 `behaviors`，不是 v1 的 `url`）：

```json
{
  "tag": "markdown",
  "content": "**Update Available**\nA new version of VeeamNotify is available!"
},
{
  "tag": "button",
  "text": { "tag": "plain_text", "content": "Open on GitHub" },
  "type": "default",
  "behaviors": [
    {
      "type": "open_url",
      "default_url": "https://github.com/6547709/VeeamNotify/releases/<version>"
    }
  ]
}
```

响应判定：检查 `code == 0`（旧版飞书可能返回 `StatusCode == 0`）；非 0 视为失败，把 `code`/`msg` 放进 `NotificationResult.Detail`。

## 8. 代码改动清单

### `resources/NotificationBuilder.psm1`

- `New-Payload`：
  - `ValidateSet` 增加 `WeCom`、`Feishu`
  - `switch` 增加两个分支
- 新增 `New-WeComPayload`：
  - 参数列表必须包含 `AlertSender.ps1` 传入的所有键：`JobName`、`JobType`、`Status`、`DataSize`、`TransferSize`、`ProcessedSize`、`DedupRatio`、`CompressRatio`、`Speed`、`Bottleneck`、`Duration`、`StartTime`、`EndTime`、`Mention`、`ThumbnailUrl`、`FooterMessage`、`NotifyUpdate`、`UpdateAvailable`、`LatestVersion`
  - 不声明 `UserId`（该服务不走提及逻辑）
  - 返回 `PSCustomObject`
- 新增 `New-FeishuPayload`：参数同上，返回上述卡片对象。

### `resources/NotificationSender.psm1`

- `Send-WebhookNotification`：
  - `ValidateSet` 增加 `WeCom`、`Feishu`
  - 提及处理仅对 `Discord` / `Slack` / `Teams` 生效
  - 发送后按服务检查业务错误码（`errcode` / `code` / `StatusCode`），非 0 时返回 `Success = $false` 并填充 `Detail`
- `NotificationResult` 增加 `[object]$Response` 属性；`Send-Payload` 把 `Invoke-RestMethod` 的原始返回对象同时存入 `Response`，`Message` 仍保留原来的字符串化返回，避免影响现有日志。
- `Send-Payload` 请求体改为 UTF-8 字节，`Content-Type` 改为 `application/json; charset=utf-8`，解决 Windows PowerShell 5.1 下中文 JSON 乱码。

### `AlertSender.ps1`

`switch ($serviceName.ToLower())` 增加：

```powershell
'wecom' {
    $result = Send-WebhookNotification -Service 'WeCom' -Parameters $payloadParams -ServiceConfig $service.Value
}
'feishu' {
    $result = Send-WebhookNotification -Service 'Feishu' -Parameters $payloadParams -ServiceConfig $service.Value
}
```

### `config/schema.json`、`config/conf.example.json`

按第 4 节修改。

### `Installer.ps1`

按第 4 节修改（服务选项）。同时把功能性 GitHub 地址从 `tigattack` 改为 `6547709`：

- `Get-GitHubReleaseInfo` 的 releases / branches API
- `Get-GitHubPRInfo` 的 PR API
- 分支安装的 `zipball` 地址
- 发布安装的 release 列表 API

保留 `https://github.com/tigattack/VeeamNotify/wiki` 文档链接。

### `Updater.ps1` / `resources/UpdateInfo.psm1`

- 更新检查 API：`https://api.github.com/repos/6547709/VeeamNotify/releases`
- 升级包下载：`https://github.com/6547709/VeeamNotify/releases/download/$LatestVersion/VeeamNotify-$LatestVersion.zip`
- `resources/version.txt` 升到 `v2.2.0`。

### `resources/NotificationBuilder.psm1` 现有服务

Discord / Slack / Teams 的“Update Available”链接从 `tigattack` 改为 `6547709`，与新 release 保持一致。消息正文不变。

### `README.md`

- 标题行与 Supported Notification Services 列表加入企业微信、飞书。
- 增加一段最小配置示例。

### `tests/NotificationBuilder.Tests.ps1`（新增）

Pester 5 测试：

1. `New-WeComPayload` 返回 `msgtype = 'template_card'`、`template_card.card_type = 'text_notice'`，标题/状态/全部 9 个普通字段/页脚都能在对应字段中找到。
2. Agent/Tape 任务使用 `Processed Size`，不使用 `Backup Size`。
3. `New-FeishuPayload` 返回 `msg_type = 'interactive'`，`card.header.title.content` 为作业名，且不同状态得到 `green`/`orange`/`red`/`grey`。
4. 飞书字段数量与分支正确。
5. 更新提示在两种消息体中都出现。
6. 两种消息体都能被 `ConvertTo-Json -Depth 100` 序列化。

### `.gitignore`（新增，合并上游条目）

上游 `main` 的 `.gitignore` 内容一并保留：

```
.DS_Store
notes.md
ExampleData
/Test-*
log/*.log
config/conf.json
update-notification.marker
PesterResults.xml
```

## 9. 错误处理与日志

- webhook 未配置或不是 `http` 开头：沿用 `Send-WebhookNotification` 现有 early return。
- HTTP 非 2xx：沿用 `Send-Payload` 的 catch，返回失败详情。
- 业务错误码非 0：读取 `$response.Response` 中的 `errcode`（企业微信）或 `code` / `StatusCode`（飞书），非 0 时返回 `Success = $false`，`Detail` 包含服务名、错误码和错误信息。
- 响应为空或没有错误码字段时，按 HTTP 成功处理（避免误报）。
- `AlertSender.ps1` 现有的成功/失败日志、Veeam 会话日志无需改动。

## 10. 验证方式

1. 安装 Pester 5，运行 `Invoke-Pester -Path tests`（macOS，pwsh 7.6.9）。
2. 用 Python `jsonschema` 校验 `conf.example.json` 与 `schema.json`（draft-07）。
3. 用 `pwsh` 直接调用 `New-WeComPayload` / `New-FeishuPayload`，把输出 `ConvertTo-Json` 后人工检查结构。
4. 在 Windows/Veeam 环境人工验证：
   - 启用 `wecom`，填真实群机器人 webhook，跑一次测试任务。
   - 启用 `feishu`，填真实自定义机器人 webhook，跑一次测试任务。
   - 分别确认 Success / Warning / Failed 三种状态的颜色与内容。
   - 确认 webhook 错误时日志记录了失败原因。

无法在 macOS 验证的部分：Veeam 模块、Windows PowerShell 5.1 运行、真实 webhook 投递。

## 11. Git 与交付

1. `git init -b main`。
2. 首次提交以**当前工作树**为基线（文件内容对应上游 `main`，`resources/version.txt` 仍为 `v2.1.2`；本地缺少上游的 `.github/` 与 `.gitignore`，本次不引入 CI，只新增合并后的 `.gitignore`）。
3. 提交本设计文档。
4. 实现并测试后提交功能改动。
5. `gh repo create 6547709/VeeamNotify --public --source=. --remote=origin --push`。
6. 打 tag `v2.2.0` 并创建同版本 release，附一个 zip 资产：
   - 资产文件名：`VeeamNotify-v2.2.0.zip`
   - zip 内顶层目录必须是 `VeeamNotify-v2.2.0/`，因为 `Updater.ps1` 解压后会把 `VeeamNotify-v2.2.0` 重命名为 `VeeamNotify`
   - release 的 `assets[0]` 必须是这个 zip，因为 `Installer.ps1` 用 `assets[0].browser_download_url`
7. 推送后用 `gh release view v2.2.0` 和一次 `Get-UpdateStatus` 验证版本检查返回 `Current`。
8. 保留 `LICENSE`、`THIRD_PARTY_LICENSES` 和 README 中的原作者署名。

## 12. 风险

- **飞书 Card 2.0 客户端要求**：需要飞书客户端 ≥ 7.20；更老的客户端可能无法渲染。用户已明确要求使用 2.0，接受该要求。
- **企业微信模板卡片字段有限**：`horizontal_content_list` 最多 6 项，9 项指标需要拆成 6 项横向 + 4 行副标题 + 3 行引用块；英文 `keyname` 超过官方建议的 5 字，可能换行。内容不丢失，但排版可能与 Slack 不完全一致。
- **PowerShell 5.1 兼容性**：所有新代码避免 PS7 语法；在 macOS PS7 上测试不能完全代表 5.1 行为。
- **参数 splatting**：`New-Payload @Parameters` 会把 ordered dictionary 的所有键传入；新增函数必须声明全部键，否则运行时报“找不到参数”。
- **旧配置兼容**：schema 新增服务不加入 `required`，避免已有配置校验失败。
- **版本比较**：`UpdateInfo.psm1` 用字符串 `-gt` / `-lt` 比较版本，`v2.2.0` 与 `v2.1.2` 的比较结果正确；将来跨越 `v2.10.0` 时可能出错，属于既有实现限制，本次不修。
- **release 资产结构**：zip 顶层目录和文件名必须符合 Updater/Installer 的预期，否则升级/安装会失败。

## 13. 已确认的决定

1. **GitHub 工具链指向 fork。** Installer / Updater / UpdateInfo 的功能性地址改为 `6547709/VeeamNotify`；`resources/version.txt` 升到 `v2.2.0`；创建 `v2.2.0` release 和 `VeeamNotify-v2.2.0.zip` 资产。上游 wiki 链接和署名保留。
2. **飞书安全设置暂不确定。** 先按“无签名校验”实现，只发送 `msg_type` + `card`。如果实际发送返回 `19021`（签名校验失败）或关键词错误，`NotificationResult.Detail` 会记录错误码和信息；届时再增加可选 `secret` 配置与签名逻辑，不在本次范围内。

