$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\update-yunxiao-defect-evidence.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Expected script to exist: $scriptPath"
}

$rawScript = Get-Content -Raw -LiteralPath $scriptPath
if ($rawScript -match 'pt-[A-Za-z0-9_-]+') {
    throw 'The script must not contain a literal Yunxiao token.'
}
if ($rawScript -notmatch 'Get-YunxiaoAccessToken') {
    throw 'The script must use the shared DPAPI credential helper.'
}
foreach ($requiredPattern in @('MultipartFormDataContent', 'embedMarkdown', 'IsSuccessStatusCode', 'ReadAsStringAsync')) {
    if ($rawScript -notmatch $requiredPattern) {
        throw "Missing required upload or verification behavior: $requiredPattern"
    }
}
if ($rawScript -notmatch 'embedFileNames') {
    throw 'Permanent-link verification must be limited to configured embedded images.'
}

$dryRunJson = & $scriptPath -DryRun
$dryRun = $dryRunJson | ConvertFrom-Json

if ($dryRun.workitemId -ne 'dc2ee9a5bf080b4ee4f730e34d') {
    throw 'Unexpected target work item.'
}
if ($dryRun.serialNumber -ne 'MXIV-8') {
    throw 'Unexpected serial number.'
}

$expectedFiles = @(
    '10-subtitle-before-submit.png',
    '11-subtitle-running.png',
    '12-subtitle-failed.png',
    'subtitle-diagnostic.zip',
    'smoke-test-report.md'
)
$actualFiles = @($dryRun.files | ForEach-Object { $_.name })
if (@($actualFiles).Count -ne $expectedFiles.Count) {
    throw 'Unexpected evidence file count.'
}
foreach ($fileName in $expectedFiles) {
    if ($actualFiles -notcontains $fileName) {
        throw "Missing evidence file: $fileName"
    }
}
if (-not $dryRun.skipExistingAttachments) {
    throw 'The script must skip attachments that already exist.'
}
if (-not $dryRun.embedPngImages) {
    throw 'The script must embed PNG evidence in the description.'
}

$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$legacyOutput = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DryRun
if ($LASTEXITCODE -ne 0) {
    throw 'Windows PowerShell 5.1 could not parse and execute the evidence script.'
}
$legacyDryRun = $legacyOutput | ConvertFrom-Json
if ($legacyDryRun.workitemId -ne $dryRun.workitemId) {
    throw 'Windows PowerShell 5.1 produced a different target.'
}

Write-Output 'PASS: Yunxiao evidence upload safety and compatibility checks.'
