param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    [Parameter(Mandatory = $true)]
    [string[]]$Files,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceName,
    [string]$EvidenceDirectory,
    [string]$NodePath = 'node',
    [string]$CdpCommandPath,
    [string]$ContextUploaderPath,
    [string]$CapturePath
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CdpCommandPath)) { $CdpCommandPath = Join-Path $PSScriptRoot 'cdp-command.mjs' }
if ([string]::IsNullOrWhiteSpace($ContextUploaderPath)) { $ContextUploaderPath = Join-Path $PSScriptRoot 'upload-cinlink-context.ps1' }
if ([string]::IsNullOrWhiteSpace($CapturePath)) { $CapturePath = Join-Path $PSScriptRoot 'capture-window.ps1' }
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $workspace ('output\ui-test\manual-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if ($EvidenceName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw 'EvidenceName 包含文件名不允许的字符。'
}
$null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force

function Invoke-CdpEvaluate {
    param([Parameter(Mandatory = $true)][string]$Expression)
    $params = @{ expression = $Expression; returnByValue = $true } | ConvertTo-Json -Compress
    $paramsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($params))
    $rawLines = @(& $NodePath $CdpCommandPath Runtime.evaluate --params-base64 $paramsBase64)
    $nodeSucceeded = $?
    $raw = $rawLines -join [Environment]::NewLine
    if (-not $nodeSucceeded) { throw 'CDP evaluation failed.' }
    return (($raw | ConvertFrom-Json).result.value)
}

$sessionButton = Invoke-CdpEvaluate '(()=>{const buttons=[...document.querySelectorAll("button")];const b=buttons.find(e=>e.getAttribute("aria-label")==="新建无项目会话")||buttons.find(e=>/^在 .+ 中新建会话$/.test(e.getAttribute("aria-label")||""));b?.click();return b?.getAttribute("aria-label")||null})()'
if ([string]::IsNullOrWhiteSpace([string]$sessionButton)) {
    throw 'CinLink new-session button was not found.'
}
Start-Sleep -Seconds 1
$initialContextCount = [int](Invoke-CdpEvaluate 'document.querySelectorAll("[data-context-file]").length')
if ($initialContextCount -ne 0) {
    throw 'CinLink new session retained stale context; submission stopped before upload.'
}

for ($index = 0; $index -lt $Files.Count; $index++) {
    $selector = if ($index -eq 0) { '.composer-context-thumb' } else { '.composer-context-mini-add' }
    $uploadOutput = @(& $ContextUploaderPath -Selector $selector -FilePath $Files[$index] -NodePath $NodePath -CdpCommandPath $CdpCommandPath)
    $uploadSucceeded = $?
    $uploadOutput | Out-Host
    if (-not $uploadSucceeded) { throw "CDP file upload failed: $($Files[$index])" }
    Start-Sleep -Seconds 3
}

$expectedNames = @($Files | ForEach-Object { [IO.Path]::GetFileName($_) })
$context = @(Invoke-CdpEvaluate '([...document.querySelectorAll("[data-context-file]")].map(e=>{const value=e.getAttribute("data-context-file")||"";return value.split(/[\\/]/).pop()}))')
foreach ($expectedName in $expectedNames) {
    if ($context -notcontains $expectedName) {
        throw "CinLink context validation failed; expected attachment was not present: $expectedName"
    }
}

$null = Invoke-CdpEvaluate '(()=>{const e=document.querySelector(".composer-prompt-editor");e.innerHTML="";e.focus();return true})()'
$textParams = @{ text = $Prompt } | ConvertTo-Json -Compress
$textParamsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($textParams))
$inputOutput = @(& $NodePath $CdpCommandPath Input.insertText --params-base64 $textParamsBase64)
$inputSucceeded = $?
$inputOutput | Out-Host
if (-not $inputSucceeded) { throw 'CDP text input failed.' }
Start-Sleep -Seconds 1

$ready = Invoke-CdpEvaluate '({text:document.querySelector(".composer-prompt-editor")?.innerText,sendDisabled:document.querySelector(".composer-send")?.disabled,context:[...document.querySelectorAll("[data-context-file]")].map(e=>e.getAttribute("data-context-file"))})'
if ([string]$ready.text -ne $Prompt -or [bool]$ready.sendDisabled) {
    throw 'CinLink composer validation failed before submission.'
}
& $CapturePath -ProcessName CinLink -OutputPath (Join-Path $EvidenceDirectory "$EvidenceName-before-submit.png") | Out-Null
$null = Invoke-CdpEvaluate 'document.querySelector(".composer-send")?.click(); true'
Start-Sleep -Seconds 3
Invoke-CdpEvaluate '({tail:document.body.innerText.slice(-2500),stop:!!document.querySelector(".composer-stop"),jobs:[...document.querySelectorAll(".message-job-id")].slice(-4).map(e=>e.innerText)})'
