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

	$versionFunctionAst = $ast.Find({
			param($node)
			$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-InstalledVersion'
		}, $true)

	if (-not $versionFunctionAst) {
		throw 'Get-InstalledVersion not found in Installer.ps1'
	}

	. ([scriptblock]::Create($versionFunctionAst.Extent.Text))
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

Describe 'Get-InstalledVersion' {
	It 'returns null when no installation exists' {
		$path = Join-Path $TestDrive 'empty'
		New-Item -ItemType Directory -Path $path -Force | Out-Null

		Get-InstalledVersion -Project 'VeeamNotify' -InstallParentPath $path | Should -BeNullOrEmpty
	}

	It 'returns the trimmed version when an installation exists' {
		$path = Join-Path $TestDrive 'installed'
		$versionDir = Join-Path $path 'VeeamNotify\resources'
		New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
		Set-Content -Path (Join-Path $versionDir 'version.txt') -Value "v2.2.0`n"

		Get-InstalledVersion -Project 'VeeamNotify' -InstallParentPath $path | Should -Be 'v2.2.0'
	}
}
