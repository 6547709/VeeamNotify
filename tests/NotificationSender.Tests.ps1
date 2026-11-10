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
