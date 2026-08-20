$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\sync-yunxiao-defects.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Expected batch sync script to exist: $scriptPath"
}

$rawScript = Get-Content -Raw -LiteralPath $scriptPath
if ($rawScript -match 'pt-[A-Za-z0-9_-]+') {
    throw 'The batch script must not contain a literal Yunxiao token.'
}
foreach ($requiredPattern in @('Get-YunxiaoAccessToken', 'MultipartFormDataContent', 'embedMarkdown', 'workitems:search', 'skipExisting')) {
    if ($rawScript -notmatch $requiredPattern) {
        throw "Missing required batch behavior: $requiredPattern"
    }
}

$dryRunJson = & $scriptPath -DryRun
$dryRun = $dryRunJson | ConvertFrom-Json
if (@($dryRun.defects).Count -ne 7) {
    throw 'Batch must contain exactly seven remaining defects.'
}
if ($dryRun.assignedTo -ne '68998708f9007d7e33d2960b') {
    throw 'Default assignee must be 占晶.'
}
if (@($dryRun.updateFields) -contains 'customFieldValues') {
    throw 'The Yunxiao PUT payload must not contain customFieldValues.'
}
if (@($dryRun.updateFields) -notcontains 'description' -or @($dryRun.updateFields) -notcontains 'assignedTo') {
    throw 'The Yunxiao PUT payload must retain description and assignee updates.'
}

$expectedKeys = 2..8 | ForEach-Object { 'CL-SMOKE-{0:D2}' -f $_ }
foreach ($key in $expectedKeys) {
    $defect = @($dryRun.defects | Where-Object { $_.key -eq $key })
    if ($defect.Count -ne 1) {
        throw "Missing or duplicate defect config: $key"
    }
    if ([string]::IsNullOrWhiteSpace($defect[0].subject)) {
        throw "Missing subject: $key"
    }
    if (@($defect[0].evidence).Count -lt 2) {
        throw "Insufficient evidence files: $key"
    }
}

$p0 = @($dryRun.defects | Where-Object { $_.level -eq 'P0' })
$p1 = @($dryRun.defects | Where-Object { $_.level -eq 'P1' })
$p2 = @($dryRun.defects | Where-Object { $_.level -eq 'P2' })
if ($p0.Count -ne 1 -or $p1.Count -ne 5 -or $p2.Count -ne 1) {
    throw 'Unexpected P0/P1/P2 distribution.'
}

$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$legacyOutput = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DryRun
if ($LASTEXITCODE -ne 0) {
    throw 'Windows PowerShell 5.1 could not execute the batch dry-run.'
}
$legacyDryRun = $legacyOutput | ConvertFrom-Json
if (@($legacyDryRun.defects).Count -ne 7) {
    throw 'Windows PowerShell 5.1 produced an invalid batch payload.'
}

Write-Output 'PASS: Yunxiao seven-defect batch safety checks.'
