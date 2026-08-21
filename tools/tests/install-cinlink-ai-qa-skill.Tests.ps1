$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\install-cinlink-ai-qa-skill.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-skill-install-' + [guid]::NewGuid().ToString('N'))

try {
    $source = Join-Path $fixtureRoot 'source'
    $destination = Join-Path $fixtureRoot 'installed\cinlink-ai-qa'
    $null = New-Item -ItemType Directory -Path $source -Force
    @'
---
name: cinlink-ai-qa
description: Use when running fixture tests.
---
'@ | Set-Content -LiteralPath (Join-Path $source 'SKILL.md') -Encoding UTF8

    $plan = & $scriptPath -SourcePath $source -DestinationPath $destination -DryRun | ConvertFrom-Json
    if ($plan.action -ne 'create-junction' -or $plan.destination -ne [IO.Path]::GetFullPath($destination)) {
        throw 'Installer DryRun did not plan the expected junction.'
    }
    if (Test-Path -LiteralPath $destination) {
        throw 'Installer DryRun changed the filesystem.'
    }

    Write-Output 'PASS: CinLink Skill installer dry-run behavior.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
