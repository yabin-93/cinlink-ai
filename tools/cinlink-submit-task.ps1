param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    [Parameter(Mandatory = $true)]
    [string[]]$Files,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceName
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$cdp = Join-Path $PSScriptRoot 'cdp-command.mjs'
$capture = Join-Path $PSScriptRoot 'capture-window.ps1'
$evidenceDir = Join-Path $workspace 'output\ui-test\ai-core-smoke-2026-08-20'

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CinLinkWindowFocus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

function Invoke-CdpEvaluate {
    param([Parameter(Mandatory = $true)][string]$Expression)
    $params = @{ expression = $Expression; returnByValue = $true } | ConvertTo-Json -Compress
    node $cdp Runtime.evaluate $params
    if ($LASTEXITCODE -ne 0) { throw 'CDP evaluation failed.' }
}

function Wait-CinLinkDialog {
    param([Parameter(Mandatory = $true)][string]$Title)
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $dialog = Get-Process CinLink -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -eq $Title } |
            Select-Object -First 1
        if ($dialog) { return $dialog }
        Start-Sleep -Milliseconds 200
    } until ((Get-Date) -ge $deadline)
    throw "CinLink dialog '$Title' did not appear."
}

Invoke-CdpEvaluate '(()=>{const b=[...document.querySelectorAll("button")].find(e=>e.getAttribute("aria-label")==="新建无项目会话");b?.click();return !!b})()'
Start-Sleep -Seconds 1

for ($index = 0; $index -lt $Files.Count; $index++) {
    $selector = if ($index -eq 0) { '.composer-context-thumb' } else { '.composer-context-mini-add' }
    Invoke-CdpEvaluate "document.querySelector('$selector')?.click(); true"
    $dialog = Wait-CinLinkDialog -Title '打开'
    [CinLinkWindowFocus]::SetForegroundWindow($dialog.MainWindowHandle) | Out-Null
    Set-Clipboard -Value $Files[$index]
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Seconds 3
}

Invoke-CdpEvaluate '(()=>{const e=document.querySelector(".composer-prompt-editor");e.innerHTML="";e.focus();return true})()'
$textParams = @{ text = $Prompt } | ConvertTo-Json -Compress
node $cdp Input.insertText $textParams
if ($LASTEXITCODE -ne 0) { throw 'CDP text input failed.' }
Start-Sleep -Seconds 1

$ready = Invoke-CdpEvaluate '({text:document.querySelector(".composer-prompt-editor")?.innerText,sendDisabled:document.querySelector(".composer-send")?.disabled,context:[...document.querySelectorAll("[data-context-file]")].map(e=>e.getAttribute("data-context-file"))})'
& $capture -ProcessName CinLink -OutputPath (Join-Path $evidenceDir "$EvidenceName-before-submit.png") | Out-Null
Invoke-CdpEvaluate 'document.querySelector(".composer-send")?.click(); true'
Start-Sleep -Seconds 3
Invoke-CdpEvaluate '({tail:document.body.innerText.slice(-2500),stop:!!document.querySelector(".composer-stop"),jobs:[...document.querySelectorAll(".message-job-id")].slice(-4).map(e=>e.innerText)})'
