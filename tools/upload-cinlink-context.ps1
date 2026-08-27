param(
    [Parameter(Mandatory = $true)][string]$Selector,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string]$NodePath = 'node',
    [string]$CdpCommandPath,
    [string]$OpenComputerUsePath = 'open-computer-use',
    [int]$ClientOffsetX = 8,
    [int]$ClientOffsetY = 31
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($CdpCommandPath)) { $CdpCommandPath = Join-Path $PSScriptRoot 'cdp-command.mjs' }

$selectorJson = ConvertTo-Json $Selector -Compress
$expression = "(()=>{const e=document.querySelector($selectorJson);if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})()"
$parameters = @{ expression = $expression; returnByValue = $true } | ConvertTo-Json -Compress
$parametersBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($parameters))
$cdpOutput = @(& $NodePath $CdpCommandPath Runtime.evaluate --params-base64 $parametersBase64)
$cdpSucceeded = $?
if (-not $cdpSucceeded) { throw "Failed to open the CinLink file dialog for $FilePath" }
$cdpResult = (($cdpOutput -join [Environment]::NewLine) | ConvertFrom-Json).result.value
if ($null -eq $cdpResult) { throw "CinLink context target was not found: $Selector" }

$targetX = [int][Math]::Round([double]$ClientOffsetX + [double]$cdpResult.x + ([double]$cdpResult.width / 2))
$targetY = [int][Math]::Round([double]$ClientOffsetY + [double]$cdpResult.y + ([double]$cdpResult.height / 2))

$openDialogCalls = @(
    @{ tool = 'get_app_state'; args = @{ app = 'CinLink' } },
    @{ tool = 'click'; args = @{ app = 'CinLink'; x = $targetX; y = $targetY; click_method = 'app_post' } }
) | ConvertTo-Json -Depth 6 -Compress
$openDialogOutput = @(& $OpenComputerUsePath call --calls $openDialogCalls)
if (-not $?) {
    $openDialogOutput | Out-Host
    throw "Open Computer Use could not open the file dialog for: $FilePath"
}

Start-Sleep -Milliseconds 1000
$focusFileNameCalls = @(
    @{ tool = 'get_app_state'; args = @{ app = 'CinLink' } },
    @{ tool = 'press_key'; args = @{ app = 'CinLink'; key = 'ALT+N' } },
    @{ tool = 'press_key'; args = @{ app = 'CinLink'; key = 'CTRL+A' } }
) | ConvertTo-Json -Depth 6 -Compress
$focusOutput = @(& $OpenComputerUsePath call --calls $focusFileNameCalls)
if (-not $?) {
    $focusOutput | Out-Host
    throw "Open Computer Use could not focus the file-name field for: $FilePath"
}

$selectFileCalls = @(
    @{ tool = 'get_app_state'; args = @{ app = 'CinLink' } },
    @{ tool = 'type_text'; args = @{ app = 'CinLink'; text = $FilePath } },
    @{ tool = 'press_key'; args = @{ app = 'CinLink'; key = 'ENTER' } }
) | ConvertTo-Json -Depth 6 -Compress
$ocuOutput = @(& $OpenComputerUsePath call --calls $selectFileCalls)
$ocuSucceeded = $?
if (-not $ocuSucceeded) {
    $ocuOutput | Out-Host
    throw "Open Computer Use could not select the file: $FilePath"
}

[pscustomobject]@{ selector = $Selector; file = $FilePath; tool = 'open-computer-use' }
