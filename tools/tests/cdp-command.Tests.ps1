$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\cdp-command.mjs'
$payload = [ordered]@{
    expression = '(()=>{const e=document.querySelector(".composer-prompt-editor");return "中文提示词"})()'
    returnByValue = $true
}
$json = $payload | ConvertTo-Json -Compress
$base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$decodedJson = & node $scriptPath '--decode-only' '--params-base64' $base64
if ($LASTEXITCODE -ne 0) { throw 'CDP base64 decode command failed.' }
$decoded = $decodedJson | ConvertFrom-Json
if ($decoded.expression -cne $payload.expression -or $decoded.returnByValue -ne $true) {
    throw 'CDP base64 parameter round-trip changed the payload.'
}

$submitPath = Join-Path $PSScriptRoot '..\cinlink-submit-task.ps1'
$submitRaw = Get-Content -Raw -LiteralPath $submitPath
if ($submitRaw -notmatch 'params-base64') {
    throw 'CinLink submit tool must pass CDP parameters as base64.'
}

Write-Output 'PASS: CDP command preserves PowerShell JSON parameters.'
