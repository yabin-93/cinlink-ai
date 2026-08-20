param(
    [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
    [string]$CaseId,

    [Parameter(ParameterSetName = 'All', Mandatory = $true)]
    [switch]$All,

    [string]$CatalogPath,
    [string]$RunId,
    [switch]$NoRestart,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $workspace 'test-cases\cinlink-ai-core.json'
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = 'ai-core-smoke-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
}
if ($RunId -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'RunId 只能包含字母、数字、点、下划线和连字符。'
}

if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    throw "用例文件不存在：$CatalogPath"
}
$catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $CatalogPath | ConvertFrom-Json
if ($catalog.schemaVersion -ne 1) {
    throw "不支持的用例格式版本：$($catalog.schemaVersion)"
}
$enabledCases = @($catalog.cases | Where-Object { $_.enabled -ne $false })
if ($All) {
    $selectedCases = $enabledCases
}
else {
    $selectedCases = @($enabledCases | Where-Object { $_.id -eq $CaseId })
    if ($selectedCases.Count -ne 1) {
        throw "没有找到唯一且启用的用例：$CaseId"
    }
}

$runDirectory = Join-Path $workspace ("output\ui-test\{0}" -f $RunId)
$plan = [ordered]@{
    schemaVersion = 1
    suite = $catalog.suite
    runId = $RunId
    runDirectory = $runDirectory
    manualGateBetweenCases = [bool]$All
    cases = @($selectedCases | ForEach-Object {
        [ordered]@{
            id = $_.id
            name = $_.name
            evidenceName = $_.evidenceName
            files = @($_.files)
            timeoutMinutes = $_.timeoutMinutes
            manualActions = @($_.manualActions)
        }
    })
}

if ($DryRun) {
    $plan | ConvertTo-Json -Depth 10
    return
}

foreach ($case in $selectedCases) {
    foreach ($file in $case.files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "用例 $($case.id) 的素材不存在：$file"
        }
    }
}

$null = New-Item -ItemType Directory -Path $runDirectory -Force
$manifestPath = Join-Path $runDirectory 'run-manifest.json'
$records = @()

if (-not $NoRestart) {
    Write-Host '正在以 CDP 调试模式重启 CinLink...'
    & (Join-Path $PSScriptRoot 'restart-cinlink-debug.ps1') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CinLink 调试模式启动失败。' }
}

for ($index = 0; $index -lt $selectedCases.Count; $index++) {
    $case = $selectedCases[$index]
    Write-Host ("`n[{0}/{1}] {2} · {3}" -f ($index + 1), $selectedCases.Count, $case.id, $case.name) -ForegroundColor Cyan
    Write-Host ("最长等待：{0} 分钟" -f $case.timeoutMinutes)
    if (@($case.manualActions).Count -gt 0) {
        Write-Host '本用例需要人工动作：' -ForegroundColor Yellow
        foreach ($action in $case.manualActions) { Write-Host ("- {0}" -f $action) }
    }

    $startedAt = (Get-Date).ToString('o')
    & (Join-Path $PSScriptRoot 'cinlink-submit-task.ps1') `
        -Prompt $case.prompt `
        -Files @($case.files) `
        -EvidenceName $case.evidenceName `
        -EvidenceDirectory $runDirectory
    if ($LASTEXITCODE -ne 0) { throw "提交用例失败：$($case.id)" }

    $records += [ordered]@{
        id = $case.id
        name = $case.name
        status = 'submitted'
        submittedAt = $startedAt
        timeoutMinutes = $case.timeoutMinutes
        expected = @($case.expected)
        manualActions = @($case.manualActions)
        beforeSubmitScreenshot = Join-Path $runDirectory ("{0}-before-submit.png" -f $case.evidenceName)
    }
    [ordered]@{
        schemaVersion = 1
        suite = $catalog.suite
        runId = $RunId
        runDirectory = $runDirectory
        updatedAt = (Get-Date).ToString('o')
        cases = @($records)
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    if ($index -lt ($selectedCases.Count - 1)) {
        Write-Host ''
        Write-Host '请等待当前任务结束，完成结果、积分和证据检查后再继续。' -ForegroundColor Yellow
        $null = Read-Host '确认当前任务已结束后按 Enter 提交下一条；按 Ctrl+C 可安全停止'
    }
}

Write-Host ("`n用例提交完成。运行记录：{0}" -f $manifestPath) -ForegroundColor Green
Write-Host '注意：submitted 只表示已提交；最终通过/失败仍需根据结果文件和人工检查更新报告。'
