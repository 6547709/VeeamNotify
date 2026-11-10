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
