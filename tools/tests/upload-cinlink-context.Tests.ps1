$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$uploadPath = Join-Path $workspace 'tools\upload-cinlink-context.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-upload-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $ocuLog = Join-Path $fixtureRoot 'ocu.txt'
    $fakeNode = Join-Path $fixtureRoot 'node.ps1'
    @'
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
'{"result":{"type":"object","value":{"x":100,"y":200,"width":40,"height":40}}}'
'@ | Set-Content -LiteralPath $fakeNode -Encoding UTF8
    $fakeOcu = Join-Path $fixtureRoot 'ocu.ps1'
    @'
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
if ($Arguments -contains '--sleep') { throw 'unknown call option: --sleep' }
Add-Content -LiteralPath $env:CINLINK_UPLOAD_OCU_LOG -Value ($Arguments -join '|')
'@ | Set-Content -LiteralPath $fakeOcu -Encoding UTF8

    $env:CINLINK_UPLOAD_OCU_LOG = $ocuLog
    & $uploadPath -Selector '.target' -FilePath 'E:\fixture\video.mp4' `
        -NodePath $fakeNode -CdpCommandPath 'fake-cdp.mjs' -OpenComputerUsePath $fakeOcu `
        -ClientOffsetX 8 -ClientOffsetY 31 | Out-Null
    $calls = @(Get-Content -LiteralPath $ocuLog)
    if ($calls.Count -ne 3) {
        throw "Native upload must split dialog opening, field focus, and path entry; observed $($calls.Count) OCU call(s)."
    }
    if ($calls[0] -notmatch 'app_post' -or $calls[0] -notmatch '"x":128' -or $calls[0] -notmatch '"y":251' -or $calls[0] -match 'E:\\\\fixture\\\\video.mp4') {
        throw "The first OCU call must only open the native dialog: $($calls[0])"
    }
    if ($calls[1] -notmatch 'ALT\+N' -or $calls[1] -notmatch 'CTRL\+A' -or $calls[1] -match 'E:\\\\fixture\\\\video.mp4') {
        throw "The second OCU call must focus and clear the file-name field: $($calls[1])"
    }
    if ($calls[2] -notmatch 'E:\\\\fixture\\\\video.mp4' -or $calls[2] -notmatch 'ENTER') {
        throw "The third OCU call must enter and confirm the file path: $($calls[2])"
    }
    Write-Output 'PASS: native context upload uses CDP coordinates and Open Computer Use.'
}
finally {
    Remove-Item Env:CINLINK_UPLOAD_OCU_LOG -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
