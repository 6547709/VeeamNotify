BeforeAll {
	$installerPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Installer.ps1'
	$tokens = $null
	$parseErrors = $null
	$ast = [System.Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
	$functionAst = $ast.Find({
			param($node)
			$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Initialize-ServiceConfig'
		}, $true)

	if (-not $functionAst) {
		throw 'Initialize-ServiceConfig not found in Installer.ps1'
	}

	. ([scriptblock]::Create($functionAst.Extent.Text))
}

Describe 'Initialize-ServiceConfig' {
	It 'adds a missing service with disabled defaults' {
		$config = [PSCustomObject]@{
			services = [PSCustomObject]@{
				http = [PSCustomObject]@{ enabled = $false }
			}
		}

		$result = Initialize-ServiceConfig -Config $config -Service 'wecom'

		$result.services.wecom.enabled | Should -BeFalse
		$result.services.wecom.webhook | Should -Be ''

		$result.services.wecom.enabled = $true
		$result.services.wecom.enabled | Should -BeTrue
	}

	It 'leaves an existing service unchanged' {
		$config = [PSCustomObject]@{
			services = [PSCustomObject]@{
				wecom = [PSCustomObject]@{ enabled = $true; webhook = 'https://example.com/hook' }
			}
		}

		$result = Initialize-ServiceConfig -Config $config -Service 'wecom'

		$result.services.wecom.enabled | Should -BeTrue
		$result.services.wecom.webhook | Should -Be 'https://example.com/hook'
	}
}
