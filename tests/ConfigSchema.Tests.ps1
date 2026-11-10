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
		$config = Get-Content -Path $examplePath -Raw | ConvertFrom-Json
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
