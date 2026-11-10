BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '..\resources\NotificationBuilder.psm1') -Force

	$script:common = @{
		JobName       = 'Daily VM Backup'
		Status        = 'Success'
		DataSize      = '1.2 TB'
		TransferSize  = '300 GB'
		ProcessedSize = '900 GB'
		DedupRatio    = 95
		CompressRatio = 35
		Speed         = '120 MB/s'
		Bottleneck    = 'Source'
		Duration      = '1h 2m 3s'
		StartTime     = Get-Date '2026-11-10 01:00'
		EndTime       = Get-Date '2026-11-10 02:02'
		Mention       = $false
		ThumbnailUrl  = 'https://example.com/logo.png'
		FooterMessage = 'GuoqiangLi VeeamNotify v2.3.0 - 已是最新版本。'
		NotifyUpdate  = $false
		UpdateAvailable = $false
		LatestVersion = ''
	}
}

Describe 'Chinese value helpers' {
	It 'translates session statuses' {
		ConvertTo-ChineseStatus -Status 'Success' | Should -Be '成功'
		ConvertTo-ChineseStatus -Status 'Warning' | Should -Be '警告'
		ConvertTo-ChineseStatus -Status 'Failed' | Should -Be '失败'
		ConvertTo-ChineseStatus -Status 'None' | Should -Be '无'
		ConvertTo-ChineseStatus -Status 'Unknown' | Should -Be 'Unknown'
	}

	It 'translates bottleneck values' {
		ConvertTo-ChineseBottleneck -Bottleneck 'Source' | Should -Be '源'
		ConvertTo-ChineseBottleneck -Bottleneck 'Proxy' | Should -Be '代理'
		ConvertTo-ChineseBottleneck -Bottleneck 'Network' | Should -Be '网络'
		ConvertTo-ChineseBottleneck -Bottleneck 'Target' | Should -Be '目标'
		ConvertTo-ChineseBottleneck -Bottleneck 'Source, Proxy' | Should -Be '源、代理'
	}

	It 'formats percentages idempotently' {
		Format-Percentage -Value '95' | Should -Be '95%'
		Format-Percentage -Value '95%' | Should -Be '95%'
		Format-Percentage -Value '35' | Should -Be '35%'
	}
}

Describe 'New-WeComPayload' {
	It 'returns a text_notice template card with Chinese status' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		$p.msgtype | Should -Be 'template_card'
		$p.template_card.card_type | Should -Be 'text_notice'
		$p.template_card.main_title.title | Should -Be 'Daily VM Backup'
		$p.template_card.main_title.desc | Should -Be '会话结果：成功'
		$p.template_card.source.desc | Should -Be '成功'
	}

	It 'maps statuses to source description colours' {
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Success').template_card.source.desc_color | Should -Be 3
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Warning').template_card.source.desc_color | Should -Be 2
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'Failed').template_card.source.desc_color | Should -Be 2
		(New-WeComPayload @common -JobType 'VM Backup' -Status 'None').template_card.source.desc_color | Should -Be 0
	}

	It 'includes Chinese job type and timing in sub_title_text' {
		$text = (New-WeComPayload @common -JobType 'VM Backup').template_card.sub_title_text
		$text | Should -Match '作业类型：VM Backup'
		$text | Should -Match '开始时间：'
		$text | Should -Match '结束时间：'
		$text | Should -Match '持续时间：'
	}

	It 'lists Chinese horizontal metrics with percentages and translated bottleneck' {
		$rows = (New-WeComPayload @common -JobType 'VM Backup').template_card.horizontal_content_list
		$rows.Count | Should -Be 6
		$names = $rows | ForEach-Object { $_.keyname }
		$names | Should -Contain '备份大小'
		$names | Should -Contain '传输数据'
		$names | Should -Contain '去重率'
		$names | Should -Contain '压缩率'
		$names | Should -Contain '处理速率'
		$names | Should -Contain '瓶颈'
		$values = $rows | ForEach-Object { $_.value }
		$values | Should -Contain '1.2 TB'
		$values | Should -Contain '95%'
		$values | Should -Contain '35%'
		$values | Should -Contain '源'
	}

	It 'uses Processed Size for Agent and Tape jobs' {
		$agentRows = (New-WeComPayload @common -JobType 'Windows Agent Backup').template_card.horizontal_content_list
		$agentRows.Count | Should -Be 4
		$agentNames = $agentRows | ForEach-Object { $_.keyname }
		$agentNames | Should -Contain '处理大小'
		$agentNames | Should -Not -Contain '备份大小'

		$tapeRows = (New-WeComPayload @common -JobType 'File Tape Backup').template_card.horizontal_content_list
		$tapeNames = $tapeRows | ForEach-Object { $_.keyname }
		$tapeNames | Should -Contain '处理大小'
		$tapeNames | Should -Not -Contain '备份大小'
	}

	It 'adds the VM result line when VM stats are available' {
		$stats = @{ Success = 5; Warning = 1; Failed = 0; Total = 6 }
		$text = (New-WeComPayload @common -JobType 'VM Backup' -VmStats $stats).template_card.sub_title_text
		$text | Should -Match '虚拟机结果：成功 5 / 警告 1 / 失败 0'

		$noStats = (New-WeComPayload @common -JobType 'VM Backup').template_card.sub_title_text
		$noStats | Should -Not -Match '虚拟机结果'
	}

	It 'puts the Chinese footer and update notice in quote_area only when both flags are set' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		$p.template_card.quote_area.quote_text | Should -Match ([regex]::Escape($common.FooterMessage))
		$p.template_card.card_action.url | Should -Be 'https://github.com/6547709/VeeamNotify'

		$yes = New-WeComPayload @common -JobType 'VM Backup' -NotifyUpdate $true -UpdateAvailable $true -LatestVersion 'v2.3.0'
		$yes.template_card.quote_area.quote_text | Should -Match 'VeeamNotify 有新版本可用！'
		$yes.template_card.card_action.url | Should -Be 'https://github.com/6547709/VeeamNotify/releases/v2.3.0'

		$no = New-WeComPayload @common -JobType 'VM Backup' -NotifyUpdate $false -UpdateAvailable $true -LatestVersion 'v2.3.0'
		$no.template_card.quote_area.quote_text | Should -Not -Match 'VeeamNotify 有新版本可用！'
	}

	It 'serialises to JSON' {
		$p = New-WeComPayload @common -JobType 'VM Backup'
		{ $p | ConvertTo-Json -Depth 100 -Compress } | Should -Not -Throw
	}

	It 'serialises numeric metric values as percentage strings' {
		$rows = (New-WeComPayload @common -JobType 'VM Backup').template_card.horizontal_content_list
		$dedup = $rows | Where-Object { $_.keyname -eq '去重率' }
		$compress = $rows | Where-Object { $_.keyname -eq '压缩率' }
		$dedup.value | Should -BeOfType [string]
		$compress.value | Should -BeOfType [string]
		$dedup.value | Should -Be '95%'
		$compress.value | Should -Be '35%'
	}
}

Describe 'New-FeishuPayload' {
	It 'returns a Card 2.0 interactive message with Chinese status' {
		$p = New-FeishuPayload @common -JobType 'VM Backup'
		$p.msg_type | Should -Be 'interactive'
		$p.card.schema | Should -Be '2.0'
		$p.card.header.title.content | Should -Be 'Daily VM Backup'
		($p.card.body.elements | ConvertTo-Json -Depth 20) | Should -Match '会话结果：.*成功'
	}

	It 'maps statuses to card header templates' {
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Success').card.header.template | Should -Be 'green'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Warning').card.header.template | Should -Be 'orange'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'Failed').card.header.template | Should -Be 'red'
		(New-FeishuPayload @common -JobType 'VM Backup' -Status 'None').card.header.template | Should -Be 'grey'
	}

	It 'splits the nine VM fields across two weighted columns in Chinese' {
		$elements = (New-FeishuPayload @common -JobType 'VM Backup').card.body.elements
		$columns = $elements | Where-Object { $_.tag -eq 'column_set' }
		$columns.columns.Count | Should -Be 2
		$left = $columns.columns[0].elements[0].content
		$right = $columns.columns[1].elements[0].content
		$left | Should -Match ([regex]::Escape('**备份大小**'))
		$left | Should -Match ([regex]::Escape('**去重率**'))
		$left | Should -Match ([regex]::Escape('**处理速率**'))
		$left | Should -Match ([regex]::Escape('**开始时间**'))
		$left | Should -Match ([regex]::Escape('**持续时间**'))
		$right | Should -Match ([regex]::Escape('**传输数据**'))
		$right | Should -Match ([regex]::Escape('**压缩率**'))
		$right | Should -Match ([regex]::Escape('**瓶颈**'))
		$right | Should -Match ([regex]::Escape('**结束时间**'))
		$left | Should -Match '95%'
		$right | Should -Match '35%'
		$right | Should -Match '源'
	}

	It 'uses Processed Size for Agent and Tape jobs' {
		$agent = (New-FeishuPayload @common -JobType 'Linux Agent Backup').card.body.elements
		($agent | ConvertTo-Json -Depth 20) | Should -Match '处理大小'
		($agent | ConvertTo-Json -Depth 20) | Should -Not -Match '备份大小'

		$tape = (New-FeishuPayload @common -JobType 'Repo Tape Backup').card.body.elements
		($tape | ConvertTo-Json -Depth 20) | Should -Match '处理大小'
		($tape | ConvertTo-Json -Depth 20) | Should -Not -Match '备份大小'
	}

	It 'adds the VM result line when VM stats are available' {
		$stats = @{ Success = 5; Warning = 1; Failed = 0; Total = 6 }
		$elements = (New-FeishuPayload @common -JobType 'VM Backup' -VmStats $stats).card.body.elements
		($elements | ConvertTo-Json -Depth 20) | Should -Match '虚拟机结果：.*成功 5 / 警告 1 / 失败 0'

		$noStats = (New-FeishuPayload @common -JobType 'VM Backup').card.body.elements
		($noStats | ConvertTo-Json -Depth 20) | Should -Not -Match '虚拟机结果'
	}

	It 'adds a Chinese open_url button for updates only when both flags are set' {
		$yes = (New-FeishuPayload @common -JobType 'VM Backup' -NotifyUpdate $true -UpdateAvailable $true -LatestVersion 'v2.3.0').card.body.elements
		$button = $yes | Where-Object { $_.tag -eq 'button' }
		$button.text.content | Should -Be '在 GitHub 查看'
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
