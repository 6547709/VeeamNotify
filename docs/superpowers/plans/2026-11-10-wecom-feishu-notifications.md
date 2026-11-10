# 企业微信与飞书通知支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 VeeamNotify 增加企业微信群机器人（template_card / text_notice）和飞书自定义机器人（Card 2.0）通知，内容与 Slack 一致，并把仓库作为公开的 `6547709/VeeamNotify` 发布 v2.2.0。

**Architecture:** 沿用现有分层：`NotificationBuilder.psm1` 负责生成各服务消息体，`NotificationSender.psm1` 负责 HTTP 发送和业务错误码校验，`AlertSender.ps1` 按配置分发。企业微信与飞书复用 `Send-WebhookNotification`；新增 `NotificationResult.Response` 暴露原始响应，新增 UTF-8 请求体编码。配置、安装器和更新工具同步扩展。

**Tech Stack:** Windows PowerShell 5.1（生产）/ PowerShell 7.6.9（本地测试）、Pester 5+、Newtonsoft.Json.Schema、企业微信群机器人 webhook、飞书自定义机器人 webhook（Card JSON 2.0）。

**Spec:** `docs/superpowers/specs/2026-11-10-wecom-feishu-design.md`

## Global Constraints

- 所有新代码必须兼容 Windows PowerShell 5.1；禁止三元运算符、`??`、`-Parallel` 等 PS7 语法。
- 通知文案全部英文，逐字对齐 Slack：`Session result:`、`Job type:`、`A new version of VeeamNotify is available! See release *<version>* on GitHub.`
- 功能性 GitHub 地址统一使用 `6547709/VeeamNotify`；上游 wiki 链接、README 署名和 `LICENSE` 保留。
- 企业微信使用 `msgtype: template_card` + `card_type: text_notice`；飞书使用 `msg_type: interactive` + `card.schema: "2.0"`。
- 新服务只有 `enabled` + `webhook` 两个配置项，不实现 @ 成员。
- 普通任务字段：Backup Size、Transferred Data、Dedup Ratio、Compression Ratio、Processing Rate、Bottleneck、Start Time、End Time、Duration。
- Agent/磁带任务字段：Processed Size、Transferred Data、Processing Rate、Bottleneck、Start Time、End Time、Duration。
- 版本号：`resources/version.txt` 为 `v2.2.0`；release 资产名 `VeeamNotify-v2.2.0.zip`，zip 顶层目录 `VeeamNotify-v2.2.0/`。
- 除非任务明确要求，不修改现有 Discord/Slack/Teams/Telegram/HTTP 的消息内容。

## Review Focus

- 作业名或页脚含中文时，JSON 请求体必须按 UTF-8 发送，不能乱码（Task 2 测试）。
- 企业微信/飞书返回 HTTP 200 但 `errcode`/`code` 非 0 时，必须判定为发送失败（Task 5 测试）。
- Agent / 磁带任务必须使用 Processed Size 分支，不能显示空的 Backup Size（Task 3、Task 4 测试）。
- `New-Payload @Parameters` 会把 ordered dictionary 的所有键传入；两个新 builder 必须能接收 `AlertSender.ps1` 传入的完整参数集（Task 5 用完整参数测试）。
- 未知/空 Status 必须落到默认颜色；更新提示必须同时满足 `NotifyUpdate` 和 `UpdateAvailable`（Task 3、Task 4 测试）。

---

### Task 1: Git 基线、`.gitignore` 与设计文档提交

**Files:**
- Create: `.gitignore`
- Create: `docs/superpowers/plans/2026-11-10-wecom-feishu-notifications.md`（本文件）
- Existing: 当前工作树全部文件

**Interfaces:**
- Consumes: 无
- Produces: 一个带基线提交的本地 git 仓库，后续任务可以按任务提交。

- [ ] **Step 1: 初始化仓库并设置本地身份**

```bash
cd /Users/liguoqiang/project/VeeamNotify
git init -b main
git config user.name "6547709"
git config user.email "6547709@users.noreply.github.com"
```

- [ ] **Step 2: 创建 `.gitignore`**

内容必须为：

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

- [ ] **Step 3: 提交基线（排除 docs/）**

```bash
git add -A -- . ':(exclude)docs'
git commit -m "Import VeeamNotify v2.1.2 (upstream main snapshot)"
```

Expected: 提交成功，`git status` 只剩未跟踪的 `docs/`。

- [ ] **Step 4: 提交设计文档与计划**

```bash
git add docs
git commit -m "docs: add WeCom and Feishu notification design and plan"
```

- [ ] **Step 5: 验证**

```bash
git log --oneline
git status --short
```

Expected: 两条提交记录，工作树干净。

---

### Task 2: 传输层 — 原始响应与 UTF-8 请求体

**Files:**
- Modify: `resources/NotificationSender.psm1`（`NotificationResult`、`Send-Payload`）
- Test: `tests/NotificationSender.Tests.ps1`

**Interfaces:**
- Consumes: 现有 `NotificationResult` 类、`Send-Payload` 函数。
- Produces:
  - `NotificationResult` 新增 `[object]$Response`
  - `Send-Payload` 的 `Body` 为 UTF-8 `byte[]`，`ContentType` 为 `application/json; charset=utf-8`
  - 后续 Task 5 通过 `$result.Response.errcode` / `.code` 读取业务错误。

- [ ] **Step 1: 写失败测试**

创建 `tests/NotificationSender.Tests.ps1`：

```powershell
BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '..\resources\NotificationSender.psm1') -Force
}

Describe 'Send-Payload transport' {
	BeforeAll {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ errcode = 0; errmsg = 'ok' }
		}
	}

	It 'exposes the parsed provider response on NotificationResult.Response' {
		$result = InModuleScope NotificationSender {
			Send-Payload -Uri 'https://example.com/hook' -Payload ([PSCustomObject]@{ job = 'daily' })
		}

		$result.Success | Should -BeTrue
		$result.Response.errcode | Should -Be 0
	}

	It 'sends the JSON body as UTF-8 bytes with charset=utf-8' {
		InModuleScope NotificationSender {
			$null = Send-Payload -Uri 'https://example.com/hook' -Payload ([PSCustomObject]@{ name = '备份任务' })
		}

		Should -Invoke Invoke-RestMethod -ModuleName NotificationSender -ParameterFilter {
			$Body -is [byte[]] -and $ContentType -eq 'application/json; charset=utf-8'
		}
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationSender.Tests.ps1 -Output Detailed"
```

Expected: FAIL——`NotificationResult` 没有 `Response` 属性，且 `Body` 不是 `byte[]`。

- [ ] **Step 3: 实现**

在 `resources/NotificationSender.psm1` 中：

1. `NotificationResult` 类增加：

```powershell
[object]$Response
```

2. `Send-Payload` 的成功分支改为：

```powershell
return [NotificationResult]@{
    Success  = $true
    Message  = $request
    Response = $request
}
```

3. `Send-Payload` 的 POST 分支改为：

```powershell
$postParams.Body = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 100 -Compress))
$postParams.ContentType = 'application/json; charset=utf-8'
```

- [ ] **Step 4: 运行测试并确认通过**

Run:

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationSender.Tests.ps1 -Output Detailed"
```

Expected: PASS（2 个测试）。

- [ ] **Step 5: 提交**

```bash
git add resources/NotificationSender.psm1 tests/NotificationSender.Tests.ps1
git commit -m "feat: expose provider response and send JSON as UTF-8"
```

---

### Task 3: 企业微信 template_card payload builder

**Files:**
- Modify: `resources/NotificationBuilder.psm1`（新增 `New-WeComPayload`，`New-Payload` 分发）
- Test: `tests/NotificationBuilder.Tests.ps1`

**Interfaces:**
- Consumes: 无（独立纯函数）。
- Produces:
  - `New-WeComPayload` 接受与 `AlertSender.ps1` 相同的 19 个参数：`JobName`、`JobType`、`Status`、`DataSize`、`TransferSize`、`ProcessedSize`、`DedupRatio`、`CompressRatio`、`Speed`、`Bottleneck`、`Duration`、`StartTime`、`EndTime`、`Mention`、`ThumbnailUrl`、`FooterMessage`、`NotifyUpdate`、`UpdateAvailable`、`LatestVersion`
  - 返回 `PSCustomObject`：`@{ msgtype = 'template_card'; template_card = @{ card_type = 'text_notice'; ... } }`
  - `New-Payload -Service WeCom` 调用它。

- [ ] **Step 1: 写失败测试**

创建 `tests/NotificationBuilder.Tests.ps1`，先写企业微信部分：

```powershell
BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '..\resources\NotificationBuilder.psm1') -Force

	$script:common = @{
		JobName       = 'Daily VM Backup'
		Status        = 'Success'
		DataSize      = '1.2 TB'
		TransferSize  = '300 GB'
		ProcessedSize = '900 GB'
		DedupRatio    = 2
		CompressRatio = 2
		Speed         = '120 MB/s'
		Bottleneck    = 'Source'
		Duration      = '1h 2m 3s'
		StartTime     = Get-Date '2026-11-10 01:00'
		EndTime       = Get-Date '2026-11-10 02:02'
		Mention       = $false
		ThumbnailUrl  = 'https://example.com/logo.png'
		FooterMessage = "tigattack's VeeamNotify v2.2.0 - Up to date."
		NotifyUpdate  = $false
		UpdateAvailable = $false
		LatestVersion = ''
	}
}

Describe 'New-WeComPayload' {
	It 'returns a text_notice template card' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		$p.msgtype | Should -Be 'template_card'
		$p.template_card.card_type | Should -Be 'text_notice'
		$p.template_card.main_title.title | Should -Be 'Daily VM Backup'
		$p.template_card.main_title.desc | Should -Be 'Session result: Success'
	}

	It 'maps statuses to source description colours' {
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Success').template_card.source.desc_color | Should -Be 3
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Warning').template_card.source.desc_color | Should -Be 2
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Failed').template_card.source.desc_color | Should -Be 2
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'None').template_card.source.desc_color | Should -Be 0
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Success').template_card.source.desc | Should -Be 'Success'
	}

	It 'includes job type and timing in sub_title_text' {
		$text = (New-WeComPayload @common -JobType 'VM Backup').template_card.sub_title_text
		$text | Should -Match 'Job type: VM Backup'
		$text | Should -Match 'Start Time:'
		$text | Should -Match 'End Time:'
		$text | Should -Match 'Duration:'
	}

	It 'lists all six VM horizontal metrics' {
		$rows = (New-WeComPayload @common -JobType 'VM Backup').template_card.horizontal_content_list
		$rows.Count | Should -Be 6
		$names = $rows | ForEach-Object { $_.keyname }
		$names | Should -Contain 'Backup Size'
		$names | Should -Contain 'Transferred Data'
		$names | Should -Contain 'Dedup Ratio'
		$names | Should -Contain 'Compression Ratio'
		$names | Should -Contain 'Processing Rate'
		$names | Should -Contain 'Bottleneck'
		($rows | ForEach-Object { $_.value }) | Should -Contain '1.2 TB'
	}

	It 'uses Processed Size for Agent and Tape jobs' {
		$agentRows = (New-WeComPayload @common -JobType 'Windows Agent Backup').template_card.horizontal_content_list
		$agentRows.Count | Should -Be 4
		$agentNames = $agentRows | ForEach-Object { $_.keyname }
		$agentNames | Should -Contain 'Processed Size'
		$agentNames | Should -Not -Contain 'Backup Size'

		$tapeRows = (New-WeComPayload @common -JobType 'File Tape Backup').template_card.horizontal_content_list
		$tapeNames = $tapeRows | ForEach-Object { $_.keyname }
		$tapeNames | Should -Contain 'Processed Size'
		$tapeNames | Should -Not -Contain 'Backup Size'
	}

	It 'puts the footer and update notice in quote_area only when both flags are set' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		$p.template_card.quote_area.quote_text | Should -Match ([regex]::Escape($common.FooterMessage))
		$p.template_card.card_action.url | Should -Be 'https://github.com/6547709/VeeamNotify'

		$yes = New-WeComPayload @common -JobType 'VM Backup' -NotifyUpdate $true -UpdateAvailable $true -LatestVersion 'v2.3.0'
		$yes.template_card.quote_area.quote_text | Should -Match 'A new version of VeeamNotify is available!'
		$yes.template_card.card_action.url | Should -Be 'https://github.com/6547709/VeeamNotify/releases/v2.3.0'

		$no = New-WeComPayload @common -JobType 'VM Backup' -NotifyUpdate $false -UpdateAvailable $true -LatestVersion 'v2.3.0'
		$no.template_card.quote_area.quote_text | Should -Not -Match 'A new version of VeeamNotify is available!'
	}

	It 'serialises to JSON' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		{ $p | ConvertTo-Json -Depth 100 -Compress } | Should -Not -Throw
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationBuilder.Tests.ps1 -Output Detailed"
```

Expected: FAIL——`New-WeComPayload` 未定义。

- [ ] **Step 3: 实现**

在 `resources/NotificationBuilder.psm1`：

1. `New-Payload` 的 `ValidateSet` 改为 `'Discord', 'Slack', 'Teams', 'Telegram', 'HTTP', 'WeCom', 'Feishu'`，并增加：

```powershell
'WeCom' { New-WeComPayload @Parameters }
'Feishu' { New-FeishuPayload @Parameters }
```

2. 新增 `New-WeComPayload`，签名与 Task 3 Interfaces 完全一致。实现要点：

- `Status` 映射：Success→`desc_color = 3`，Warning/Failed→`2`，其他→`0`
- 时间：`$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()`，`$timestampEnd` 同理
- 字段分支：`$JobType.EndsWith('Agent Backup') -or $JobType.EndsWith('Tape Backup')`
  - 是：`horizontal_content_list` 4 项（Processed Size、Transferred Data、Processing Rate、Bottleneck）
  - 否：`horizontal_content_list` 6 项（Backup Size、Transferred Data、Dedup Ratio、Compression Ratio、Processing Rate、Bottleneck）
- `sub_title_text`：

```powershell
$subTitle = "Job type: $JobType`nStart Time: $timestampStart`nEnd Time: $timestampEnd`nDuration: $Duration"
```

- `quote_area.quote_text`：先放 `$FooterMessage`；若 `$UpdateAvailable -and $NotifyUpdate`，追加：

```powershell
$quoteText += "`nA new version of VeeamNotify is available! See release $LatestVersion on GitHub."
```

- `card_action` 必填，`type = 1`；`url` 有更新时为 `https://github.com/6547709/VeeamNotify/releases/$LatestVersion`，否则为 `https://github.com/6547709/VeeamNotify`。
- 返回：

```powershell
[PSCustomObject]@{
    msgtype       = 'template_card'
    template_card = [PSCustomObject]@{
        card_type              = 'text_notice'
        source                 = [PSCustomObject]@{ icon_url = $ThumbnailUrl; desc = $Status; desc_color = $statusColour }
        main_title             = [PSCustomObject]@{ title = $JobName; desc = "Session result: $Status" }
        sub_title_text         = $subTitle
        horizontal_content_list = $horizontalContentList
        quote_area             = [PSCustomObject]@{ type = 0; title = 'VeeamNotify'; quote_text = $quoteText }
        card_action            = [PSCustomObject]@{ type = 1; url = $cardActionUrl }
    }
}
```

- 为 `Mention` 添加 `PSReviewUnusedParameter` 抑制属性，避免 PSScriptAnalyzer 警告。

- [ ] **Step 4: 运行企业微信测试并确认通过**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationBuilder.Tests.ps1 -Output Detailed"
```

Expected: 企业微信测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add resources/NotificationBuilder.psm1 tests/NotificationBuilder.Tests.ps1
git commit -m "feat: add WeCom template_card notification payload"
```

---

### Task 4: 飞书 Card 2.0 payload builder

**Files:**
- Modify: `resources/NotificationBuilder.psm1`（新增 `New-FeishuPayload`）
- Test: `tests/NotificationBuilder.Tests.ps1`

**Interfaces:**
- Consumes: 同 Task 3 的 19 个参数。
- Produces: `New-FeishuPayload` 返回：

```powershell
@{
    msg_type = 'interactive'
    card = @{
        schema = '2.0'
        config = @{ update_multi = $true }
        header = @{ template = <string>; title = @{ tag = 'plain_text'; content = <JobName> } }
        body   = @{ direction = 'vertical'; padding = '12px'; elements = @(<object[]>) }
    }
}
```

- [ ] **Step 1: 追加失败测试**

在 `tests/NotificationBuilder.Tests.ps1` 追加：

```powershell
Describe 'New-FeishuPayload' {
	It 'returns a Card 2.0 interactive message' {
		$p = New-FeishuPayload @common -JobType 'VM Backup'
		$p.msg_type | Should -Be 'interactive'
		$p.card.schema | Should -Be '2.0'
		$p.card.header.title.content | Should -Be 'Daily VM Backup'
	}

	It 'maps statuses to card header templates' {
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Success').card.header.template | Should -Be 'green'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Warning').card.header.template | Should -Be 'orange'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Failed').card.header.template | Should -Be 'red'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'None').card.header.template | Should -Be 'grey'
	}

	It 'splits the nine VM fields across two weighted columns' {
		$elements = (New-FeishuPayload @common -JobType 'VM Backup').card.body.elements
		$columns = $elements | Where-Object { $_.tag -eq 'column_set' }
		$columns.columns.Count | Should -Be 2
		$left = $columns.columns[0].elements[0].content
		$right = $columns.columns[1].elements[0].content
		$left | Should -Match ([regex]::Escape('**Backup Size**'))
		$left | Should -Match ([regex]::Escape('**Dedup Ratio**'))
		$left | Should -Match ([regex]::Escape('**Processing Rate**'))
		$left | Should -Match ([regex]::Escape('**Start Time**'))
		$left | Should -Match ([regex]::Escape('**Duration**'))
		$right | Should -Match ([regex]::Escape('**Transferred Data**'))
		$right | Should -Match ([regex]::Escape('**Compression Ratio**'))
		$right | Should -Match ([regex]::Escape('**Bottleneck**'))
		$right | Should -Match ([regex]::Escape('**End Time**'))
	}

	It 'uses Processed Size for Agent and Tape jobs' {
		$agent = (New-FeishuPayload @common -JobType 'Linux Agent Backup').card.body.elements
		($agent | ConvertTo-Json -Depth 20) | Should -Match 'Processed Size'
		($agent | ConvertTo-Json -Depth 20) | Should -Not -Match 'Backup Size'

		$tape = (New-FeishuPayload @common -JobType 'Repo Tape Backup').card.body.elements
		($tape | ConvertTo-Json -Depth 20) | Should -Match 'Processed Size'
		($tape | ConvertTo-Json -Depth 20) | Should -Not -Match 'Backup Size'
	}

	It 'adds an open_url button for updates only when both flags are set' {
		$yes = (New-FeishuPayload @common -JobType 'VM Backup' -NotifyUpdate $true -UpdateAvailable $true -LatestVersion 'v2.3.0').card.body.elements
		$button = $yes | Where-Object { $_.tag -eq 'button' }
		$button.behaviors[0].type | Should -Be 'open_url'
		$button.behaviors[0].default_url | Should -Be 'https://github.com/6547709/VeeamNotify/releases/v2.3.0'

		$no = (New-FeishuPayload @common -JobType 'VM Backup' -NotifyUpdate $false -UpdateAvailable $true -LatestVersion 'v2.3.0').card.body.elements
		($no | Where-Object { $_.tag -eq 'button' }) | Should -BeNullOrEmpty
	}

	It 'includes the footer and serialises to JSON' {
		$p = New-FeishuPayload @common -JobType 'VM Backup'
		($p.card.body.elements | ConvertTo-Json -Depth 20) | Should -Match ([regex]::Escape($common.FooterMessage))
		{ $p | ConvertTo-Json -Depth 100 -Compress } | Should -Not -Throw
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationBuilder.Tests.ps1 -Output Detailed"
```

Expected: FAIL——`New-FeishuPayload` 未定义。

- [ ] **Step 3: 实现**

新增 `New-FeishuPayload`（参数同上）。实现要点：

- `Status` 映射：`Success`→`green`，`Warning`→`orange`，`Failed`→`red`，其他→`grey`
- 字段列表按 Task 3 的分支规则生成；按下标奇偶分成两列
- 每列内容：`**<label>**` + 换行 + 值，多个字段之间用两个换行分隔
- 元素顺序：
  1. `markdown`：`**Session result:** $Status` + `**Job type:** $JobType`
  2. `column_set`：两个 `column`（`width = 'weighted'`、`weight = 1`），每个 column 的 `elements` 是一个 `markdown`
  3. `hr`
  4. 若 `UpdateAvailable -and NotifyUpdate`：`markdown` 更新提示 + `button`
  5. `markdown` 页脚：`<font color='grey'>$FooterMessage</font>`，`text_size = 'small'`
- `button` 结构：

```powershell
[PSCustomObject]@{
    tag       = 'button'
    text      = [PSCustomObject]@{ tag = 'plain_text'; content = 'Open on GitHub' }
    type      = 'default'
    behaviors = @(
        [PSCustomObject]@{
            type        = 'open_url'
            default_url = "https://github.com/6547709/VeeamNotify/releases/$LatestVersion"
        }
    )
}
```

- 返回 Card 2.0 对象（见 Interfaces）。
- 为 `Mention` 和 `ThumbnailUrl` 添加 `PSReviewUnusedParameter` 抑制属性。

- [ ] **Step 4: 运行测试并确认通过**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationBuilder.Tests.ps1 -Output Detailed"
```

Expected: 企业微信和飞书测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add resources/NotificationBuilder.psm1 tests/NotificationBuilder.Tests.ps1
git commit -m "feat: add Feishu Card 2.0 notification payload"
```

---

### Task 5: 发送分发与业务错误码校验

**Files:**
- Modify: `resources/NotificationSender.psm1`（`Send-WebhookNotification`）
- Modify: `AlertSender.ps1`（服务 switch）
- Test: `tests/NotificationSender.Tests.ps1`

**Interfaces:**
- Consumes: Task 2 的 `NotificationResult.Response`；Task 3/4 的 `New-Payload -Service WeCom|Feishu`。
- Produces:
  - `Send-WebhookNotification` 的 `ValidateSet` 为 `Discord, Slack, Teams, WeCom, Feishu`
  - WeCom `errcode != 0`、Feishu `code`/`StatusCode != 0` 时返回 `Success = $false`，`Detail` 包含 `Code` 和 `Message`
  - 新的 `Send-WebhookNotification -Service WeCom|Feishu` 可在 `AlertSender.ps1` 中直接调用。

- [ ] **Step 1: 追加失败测试**

在 `tests/NotificationSender.Tests.ps1` 追加：

```powershell
BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '..\resources\NotificationBuilder.psm1') -Force
	Import-Module (Join-Path $PSScriptRoot '..\resources\New-OrderedDictionary.psm1') -Force
}

Describe 'Send-WebhookNotification provider responses' {
	BeforeEach {
		$script:params = [ordered]@{
			JobName         = 'Daily VM Backup'
			JobType         = 'VM Backup'
			Status          = 'Success'
			DataSize        = '1.2 TB'
			TransferSize    = '300 GB'
			DedupRatio      = 2
			CompressRatio   = 2
			Speed           = '120 MB/s'
			Bottleneck      = 'Source'
			Duration        = '1h 2m 3s'
			StartTime       = Get-Date '2026-11-10 01:00'
			EndTime         = Get-Date '2026-11-10 02:02'
			Mention         = $false
			ThumbnailUrl    = 'https://example.com/logo.png'
			FooterMessage   = 'VeeamNotify test'
			NotifyUpdate    = $false
			UpdateAvailable = $false
			LatestVersion   = ''
		}
		$script:serviceConfig = [PSCustomObject]@{ webhook = 'https://example.com/hook' }
	}

	It 'succeeds for WeCom when errcode is 0' {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ errcode = 0; errmsg = 'ok' }
		}

		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = $script:serviceConfig
		} {
			Send-WebhookNotification -Service WeCom -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeTrue
	}

	It 'fails for WeCom when errcode is not 0' {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ errcode = 93000; errmsg = 'invalid webhook' }
		}

		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = $script:serviceConfig
		} {
			Send-WebhookNotification -Service WeCom -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeFalse
		$result.Detail.Code | Should -Be 93000
		$result.Detail.Message | Should -Be 'invalid webhook'
	}

	It 'succeeds for Feishu when code is 0' {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ code = 0; msg = 'success' }
		}

		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = $script:serviceConfig
		} {
			Send-WebhookNotification -Service Feishu -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeTrue
	}

	It 'fails for Feishu when code is not 0' {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ code = 19021; msg = 'sign match fail or timestamp is not within one hour from sign time' }
		}

		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = $script:serviceConfig
		} {
			Send-WebhookNotification -Service Feishu -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeFalse
		$result.Detail.Code | Should -Be 19021
	}

	It 'treats a response without an error code as success' {
		Mock Invoke-RestMethod -ModuleName NotificationSender {
			[PSCustomObject]@{ ok = $true }
		}

		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = $script:serviceConfig
		} {
			Send-WebhookNotification -Service Feishu -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeTrue
	}

	It 'skips notification when the webhook is not an http URL' {
		$result = InModuleScope NotificationSender -Parameters @{
			Parameters    = $script:params
			ServiceConfig = [PSCustomObject]@{ webhook = '' }
		} {
			Send-WebhookNotification -Service WeCom -Parameters $Parameters -ServiceConfig $ServiceConfig
		}

		$result.Success | Should -BeFalse
		$result.Message | Should -Match 'unconfigured'
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationSender.Tests.ps1 -Output Detailed"
```

Expected: FAIL——`ValidateSet` 不接受 `WeCom`/`Feishu`，且没有错误码校验。

- [ ] **Step 3: 实现**

在 `resources/NotificationSender.psm1`：

1. `Send-WebhookNotification` 的 `ValidateSet` 改为 `'Discord', 'Slack', 'Teams', 'WeCom', 'Feishu'`。
2. 提及块只在 `$Service -in 'Discord', 'Slack', 'Teams'` 时执行；WeCom/Feishu 即使 `Mention = $true` 也跳过，不访问 `user_id`。
3. 发送成功返回后，增加业务错误码检查：

```powershell
if ($response.Success -and $Service -in 'WeCom', 'Feishu') {
    if ($Service -eq 'WeCom') {
        $code = $response.Response.errcode
        $providerMessage = $response.Response.errmsg
    }
    else {
        $code = $response.Response.code
        $providerMessage = $response.Response.msg
        if ($null -eq $code) {
            $code = $response.Response.StatusCode
            $providerMessage = $response.Response.StatusMessage
        }
    }

    if ($null -ne $code -and "$code" -ne '0') {
        return [NotificationResult]@{
            Success = $false
            Message = "$Service returned error code $code"
            Detail  = @{
                Service = $Service
                Code    = $code
                Message = $providerMessage
            }
        }
    }
}
```

在 `AlertSender.ps1` 的 `switch ($serviceName.ToLower())` 中增加：

```powershell
'wecom' {
    $result = Send-WebhookNotification -Service 'WeCom' -Parameters $payloadParams -ServiceConfig $service.Value
}
'feishu' {
    $result = Send-WebhookNotification -Service 'Feishu' -Parameters $payloadParams -ServiceConfig $service.Value
}
```

- [ ] **Step 4: 运行测试并确认通过**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/NotificationSender.Tests.ps1 -Output Detailed"
```

Expected: 所有发送测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add resources/NotificationSender.psm1 AlertSender.ps1 tests/NotificationSender.Tests.ps1
git commit -m "feat: send WeCom and Feishu notifications with error-code checks"
```

---

### Task 6: 配置 schema、示例、安装器与 schema 测试

**Files:**
- Modify: `config/schema.json`
- Modify: `config/conf.example.json`
- Modify: `Installer.ps1`
- Test: `tests/ConfigSchema.Tests.ps1`

**Interfaces:**
- Consumes: 现有 `Test-JsonValid`。
- Produces: `conf.example.json` 含 `services.wecom`、`services.feishu`；schema 校验这两个对象；Installer 提供 5/6 两个选择。

- [ ] **Step 1: 写失败测试**

创建 `tests/ConfigSchema.Tests.ps1`：

```powershell
BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '..\resources\JsonValidator.psm1') -Force
	$script:schemaPath = Join-Path $PSScriptRoot '..\config\schema.json'
	$script:examplePath = Join-Path $PSScriptRoot '..\config\conf.example.json'
}

Describe 'Configuration schema' {
	It 'validates the example configuration' {
		$result = Test-JsonValid -JsonPath $examplePath -SchemaPath $schemaPath
		$result.IsValid | Should -BeTrue -Because $result.Message
	}

	It 'includes WeCom and Feishu webhook settings in the example' {
		$config = Get-Content -Path $examplePath -Raw | ConvertFrom-Json
		$config.services.wecom.webhook | Should -Not -BeNullOrEmpty
		$config.services.feishu.webhook | Should -Not -BeNullOrEmpty
		$config.services.wecom.enabled | Should -BeOfType [bool]
		$config.services.feishu.enabled | Should -BeOfType [bool]
	}

	It 'rejects a WeCom service without a webhook' {
		$json = Get-Content -Path $examplePath -Raw
		$config = $json | ConvertFrom-Json
		$config.services.wecom.PSObject.Properties.Remove('webhook')
		$tempPath = Join-Path $TestDrive 'wecom-missing-webhook.json'
		$config | ConvertTo-Json -Depth 20 | Set-Content -Path $tempPath

		$result = Test-JsonValid -JsonPath $tempPath -SchemaPath $schemaPath
		$result.IsValid | Should -BeFalse
	}

	It 'rejects a Feishu service without a webhook' {
		$config = Get-Content -Path $examplePath -Raw | ConvertFrom-Json
		$config.services.feishu.PSObject.Properties.Remove('webhook')
		$tempPath = Join-Path $TestDrive 'feishu-missing-webhook.json'
		$config | ConvertTo-Json -Depth 20 | Set-Content -Path $tempPath

		$result = Test-JsonValid -JsonPath $tempPath -SchemaPath $schemaPath
		$result.IsValid | Should -BeFalse
	}
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/ConfigSchema.Tests.ps1 -Output Detailed"
```

Expected: FAIL——示例配置没有 `wecom` / `feishu`。

- [ ] **Step 3: 实现配置**

1. `config/conf.example.json` 的 `services` 中、`http` 之后加入：

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

2. `config/schema.json` 的 `services.properties` 中加入两个对象（各自 `required: ["enabled", "webhook"]`，`enabled` 为 boolean、`webhook` 为 string）。**不要**把它们加入 `services.required`。

3. `Installer.ps1`：
   - 在 `Set-NotificationService` 中新增两个 `ChoiceDescription`：`'&WeCom'` 和 `'&Feishu'`，追加到选择数组末尾（索引 5、6）。
   - `switch ($servicePrompt_result)` 增加：

```powershell
5 {
    $Config.services.wecom.enabled = $true
    $Config.services.wecom.webhook = Read-Host -Prompt $webhookPrompt
}
6 {
    $Config.services.feishu.enabled = $true
    $Config.services.feishu.webhook = Read-Host -Prompt $webhookPrompt
}
```

   - `Set-ProjectConfiguration` 中把 `if ($serviceType -ne 4)` 改为 `if ($serviceType -notin 4, 5, 6)`。

- [ ] **Step 4: 运行测试并确认通过**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests/ConfigSchema.Tests.ps1 -Output Detailed"
```

Expected: 4 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add config/schema.json config/conf.example.json Installer.ps1 tests/ConfigSchema.Tests.ps1
git commit -m "feat: add WeCom and Feishu configuration and installer options"
```

---

### Task 7: 文档、GitHub 地址、版本号与全量验证

**Files:**
- Modify: `README.md`
- Modify: `Installer.ps1`（功能性 GitHub 地址）
- Modify: `Updater.ps1`
- Modify: `resources/UpdateInfo.psm1`
- Modify: `resources/NotificationBuilder.psm1`（现有服务更新链接）
- Modify: `resources/version.txt`

**Interfaces:**
- Consumes: 前六个任务的代码。
- Produces: 自洽的 fork 工具链、v2.2.0 版本号、更新后的 README。

- [ ] **Step 1: 更新 README**

- 第 1 行加入企业微信和飞书。
- `## Supported Notification Services` 列表加入：

```
* WeCom (企业微信群机器人)
* Feishu (飞书自定义机器人)
```

- 在 Configuration 段后增加最小配置示例：

```json
"wecom":  { "enabled": true, "webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=..." },
"feishu": { "enabled": true, "webhook": "https://open.feishu.cn/open-apis/bot/v2/hook/..." }
```

- 保留所有原作者署名与上游 wiki 链接。

- [ ] **Step 2: 替换功能性 GitHub 地址**

把所有功能性 `tigattack/VeeamNotify` 改为 `6547709/VeeamNotify`：

- `Installer.ps1`：`Get-GitHubReleaseInfo`、`Get-GitHubPRInfo`、`zipball`、release 列表 API
- `Updater.ps1`：release 下载 URL
- `resources/UpdateInfo.psm1`：releases API
- `resources/NotificationBuilder.psm1`：Discord/Teams/Slack/Telegram 的更新提示链接（第 205、271、277、675、788 行附近）

不要修改：`Installer.ps1` 的 wiki 链接、issue 注释链接、`README.md` 的署名/wiki/截图链接、`LICENSE`、`THIRD_PARTY_LICENSES`。

- [ ] **Step 3: 升级版本号**

`resources/version.txt` 改为：

```
v2.2.0
```

- [ ] **Step 4: 全量运行测试**

```bash
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"
```

Expected: `tests/JsonValidator.Tests.ps1`、`tests/ConfigSchema.Tests.ps1`、`tests/NotificationBuilder.Tests.ps1`、`tests/NotificationSender.Tests.ps1` 全部 PASS。`tests/Installer.Tests.ps1` 若有环境相关失败，记录失败原因；不得把失败当作通过。

- [ ] **Step 5: 语法解析所有 PowerShell 文件**

```bash
pwsh -NoLogo -NoProfile -Command '
$errors = @()
Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors) { $errors += "$($_.FullName): $($parseErrors.Message -join '; ')" }
}
if ($errors) { $errors; exit 1 } else { "All PowerShell files parse cleanly." }
'
```

Expected: `All PowerShell files parse cleanly.`

- [ ] **Step 6: 检查没有遗漏的上游功能地址**

```bash
grep -rn "tigattack/VeeamNotify" --include='*.ps1' --include='*.psm1' .
```

Expected: 只剩 wiki 链接、issue 注释链接、README 署名类引用。

- [ ] **Step 7: 提交**

```bash
git add README.md Installer.ps1 Updater.ps1 resources/UpdateInfo.psm1 resources/NotificationBuilder.psm1 resources/version.txt
git commit -m "docs: document WeCom/Feishu and point tooling at fork v2.2.0"
```

---

### Task 8: 发布到 GitHub 并创建 v2.2.0 Release

**Files:**
- 无源码改动
- Create (临时): `/tmp/veeamnotify-release/VeeamNotify-v2.2.0/`
- Create (临时): `/tmp/veeamnotify-release/VeeamNotify-v2.2.0.zip`

**Interfaces:**
- Consumes: Task 1–7 的提交。
- Produces: `github.com/6547709/VeeamNotify` 公开仓库、`v2.2.0` tag/release、`VeeamNotify-v2.2.0.zip` 资产。

- [ ] **Step 1: 创建公开仓库并推送**

```bash
cd /Users/liguoqiang/project/VeeamNotify
gh repo create 6547709/VeeamNotify --public --source=. --remote=origin --push
```

Expected: 仓库创建成功，`main` 已推送。

- [ ] **Step 2: 构建 release zip**

```bash
set -e
rm -rf /tmp/veeamnotify-release
mkdir -p /tmp/veeamnotify-release/VeeamNotify-v2.2.0
rsync -a --exclude '.git' --exclude '.DS_Store' /Users/liguoqiang/project/VeeamNotify/ /tmp/veeamnotify-release/VeeamNotify-v2.2.0/
cd /tmp/veeamnotify-release
zip -r VeeamNotify-v2.2.0.zip VeeamNotify-v2.2.0
unzip -l VeeamNotify-v2.2.0.zip | head -5
```

Expected: zip 内第一层是 `VeeamNotify-v2.2.0/`。

- [ ] **Step 3: 创建 tag 与 release**

```bash
gh release create v2.2.0 /tmp/veeamnotify-release/VeeamNotify-v2.2.0.zip \
  --repo 6547709/VeeamNotify \
  --title "v2.2.0 - WeCom & Feishu notifications" \
  --notes "Adds WeCom (markdown) and Feishu (Card 2.0) notification support. Content mirrors Slack; no mention support for these two services. Points installer/updater at this fork."
```

Expected: release 创建成功，资产名为 `VeeamNotify-v2.2.0.zip`。

- [ ] **Step 4: 验证 release 与更新检查**

```bash
gh release view v2.2.0 --repo 6547709/VeeamNotify
pwsh -NoLogo -NoProfile -Command "
Import-Module ./resources/UpdateInfo.psm1 -Force
\$s = Get-UpdateStatus
\$s.Status
\$s.CurrentVersion
\$s.LatestStable
"
```

Expected: `Current`、`v2.2.0`、`v2.2.0`。

- [ ] **Step 5: 确认工作树干净**

```bash
git status --short
git log --oneline -8
```

Expected: 工作树干净，提交历史包含基线、设计、各功能任务和文档提交。
