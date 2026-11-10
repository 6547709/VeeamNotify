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
