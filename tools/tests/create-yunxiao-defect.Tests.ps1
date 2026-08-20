$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\create-yunxiao-defect.ps1'

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
if ($rawScript -notmatch 'StringContent' -or $rawScript -notmatch 'Encoding\]::UTF8') {
    throw 'The create request must send explicitly UTF-8 encoded JSON.'
}
if ($rawScript -notmatch 'IsSuccessStatusCode' -or $rawScript -notmatch 'ReadAsStringAsync') {
    throw 'The create request must preserve the response body for diagnostics.'
}

$payloadJson = & $scriptPath -DryRun
$payload = $payloadJson | ConvertFrom-Json

$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$legacyOutput = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DryRun
if ($LASTEXITCODE -ne 0) {
    throw 'Windows PowerShell 5.1 could not parse and execute the script.'
}
$legacyPayload = $legacyOutput | ConvertFrom-Json
if ($legacyPayload.subject -ne $payload.subject) {
    throw 'Windows PowerShell 5.1 produced a different payload.'
}

if ($payload.subject -ne '[CinLink][AI冒烟][P0] 自动字幕任务完成但客户端无法获取结果产物') {
    throw 'Unexpected defect subject.'
}
if ($payload.spaceId -ne '9eddb6cefdaaf7f910039fed2d') {
    throw 'Unexpected target project.'
}
if ($payload.workitemTypeId -ne '37da3a07df4d08aef2e3b393') {
    throw 'Unexpected work item type.'
}
if ($payload.assignedTo -ne '68998708f9007d7e33d2960b') {
    throw 'Unexpected assignee.'
}
if ($payload.sprint -ne '8adf37ede6ec567e4e17eaebfe') {
    throw 'Unexpected sprint.'
}
if ($payload.labels.Count -ne 1 -or $payload.labels[0] -ne '04a2db058d968d47138880459e') {
    throw 'Unexpected label.'
}
if ($payload.customFieldValues.priority -ne '946f97777897cdeac653bbc22a') {
    throw 'Unexpected priority.'
}
if ($payload.customFieldValues.seriousLevel -ne 'b160e371d7f312ac01b0a4e513') {
    throw 'Unexpected severity.'
}
if ($payload.description -notmatch 'run_6ee3c572081a70e211c840ba') {
    throw 'Job ID is missing from the description.'
}

Write-Output 'PASS: Yunxiao defect payload and secret-safety checks.'
