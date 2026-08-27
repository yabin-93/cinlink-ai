param(
    [Parameter(Mandatory = $true)][string]$CaseId,
    [Parameter(Mandatory = $true)][string[]]$ManualActions,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceName
)

$ErrorActionPreference = 'Stop'
$ocu = Get-Command open-computer-use -ErrorAction SilentlyContinue
if ($null -eq $ocu) {
    throw 'Open Computer Use is required for CinLink desktop actions but is not installed.'
}

$snapshotPath = Join-Path $EvidenceDirectory "$EvidenceName-open-computer-use.txt"
$snapshot = @(& $ocu.Source snapshot CinLink) -join [Environment]::NewLine
$snapshot | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

Write-Host "用例 $CaseId 需要桌面动作（Open Computer Use 已记录当前状态）：" -ForegroundColor Yellow
foreach ($action in $ManualActions) { Write-Host "- $action" -ForegroundColor Yellow }
$null = Read-Host '完成上述应用内动作后按 Enter；按 Ctrl+C 可安全停止'

[pscustomobject]@{
    status = 'completed'
    tool = 'open-computer-use'
    snapshot = $snapshotPath
}
