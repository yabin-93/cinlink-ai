param(
    [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
    [string]$CaseId,

    [Parameter(ParameterSetName = 'All', Mandatory = $true)]
    [switch]$All,

    [Parameter(ParameterSetName = 'Workflow', Mandatory = $true)]
    [ValidateSet('subtitle', 'translation', 'enhance', 'text-watermark', 'image-watermark', 'mix', 'long-to-short')]
    [string]$Workflow,

    [string]$CatalogPath,
    [string]$RunId,
    [switch]$NoRestart,
    [switch]$DryRun,
    [ValidateSet('Hybrid')]
    [string]$ExecutionMode = 'Hybrid',
    [string]$SubmitterPath,
    [string]$TerminalWaiterPath,
    [string]$DesktopActionPath,
    [string]$MediaValidatorPath
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SubmitterPath)) { $SubmitterPath = Join-Path $PSScriptRoot 'cinlink-submit-task.ps1' }
if ([string]::IsNullOrWhiteSpace($TerminalWaiterPath)) { $TerminalWaiterPath = Join-Path $PSScriptRoot 'wait-cinlink-terminal.ps1' }
if ([string]::IsNullOrWhiteSpace($DesktopActionPath)) { $DesktopActionPath = Join-Path $PSScriptRoot 'invoke-cinlink-desktop-actions.ps1' }
if ([string]::IsNullOrWhiteSpace($MediaValidatorPath)) { $MediaValidatorPath = Join-Path $PSScriptRoot 'validate-cinlink-media.ps1' }
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
elseif (-not [string]::IsNullOrWhiteSpace($Workflow)) {
    $selectedCases = @($enabledCases | Where-Object { $_.workflow -eq $Workflow })
    if ($selectedCases.Count -eq 0) {
        throw "主流程没有启用的用例：$Workflow"
    }
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
    executionMode = $ExecutionMode.ToLowerInvariant()
    executionStrategy = [ordered]@{
        submission = 'repository-script'
        terminalGate = 'cdp'
        desktopActions = 'open-computer-use'
        mediaValidation = 'ffprobe'
        scriptTests = 'pester'
        browserAutomation = 'disabled'
    }
    manualGateBetweenCases = $false
    cases = @($selectedCases | ForEach-Object {
        [ordered]@{
            id = $_.id
            name = $_.name
            workflow = $_.workflow
            variant = $_.variant
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

foreach ($toolPath in @($SubmitterPath, $TerminalWaiterPath, $DesktopActionPath, $MediaValidatorPath)) {
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        throw "Hybrid execution tool does not exist: $toolPath"
    }
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
    $submitOutput = @(& $SubmitterPath `
        -Prompt $case.prompt `
        -Files @($case.files) `
        -EvidenceName $case.evidenceName `
        -EvidenceDirectory $runDirectory)
    $submitOutput | Out-Host

    $desktopResult = $null
    if (@($case.manualActions).Count -gt 0) {
        $desktopOutput = @(& $DesktopActionPath `
            -CaseId $case.id `
            -ManualActions @($case.manualActions) `
            -EvidenceDirectory $runDirectory `
            -EvidenceName $case.evidenceName)
        $desktopOutput | Out-Host
        $desktopResult = $desktopOutput | Select-Object -Last 1
    }

    $terminalOutput = @(& $TerminalWaiterPath `
        -Prompt $case.prompt `
        -TimeoutMinutes $case.timeoutMinutes `
        -EvidenceDirectory $runDirectory `
        -EvidenceName $case.evidenceName)
    $terminalOutput | Out-Host
    $terminalResult = $terminalOutput | Select-Object -Last 1
    if ($null -eq $terminalResult -or [string]::IsNullOrWhiteSpace([string]$terminalResult.status)) {
        throw "Terminal waiter returned no status for $($case.id)."
    }

    $mediaOutput = @(& $MediaValidatorPath `
        -Artifacts @($terminalResult.artifacts) `
        -EvidenceDirectory $runDirectory `
        -EvidenceName $case.evidenceName)
    $mediaOutput | Out-Host
    $mediaResult = $mediaOutput | Select-Object -Last 1

    $records += [ordered]@{
        id = $case.id
        name = $case.name
        status = [string]$terminalResult.status
        submittedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        jobId = $terminalResult.jobId
        desktopActions = $desktopResult
        mediaValidation = $mediaResult
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
        executionMode = $ExecutionMode.ToLowerInvariant()
        executionStrategy = $plan.executionStrategy
        updatedAt = (Get-Date).ToString('o')
        cases = @($records)
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    if ([string]$terminalResult.status -eq 'timeout') {
        throw "用例 $($case.id) 未在 $($case.timeoutMinutes) 分钟内进入终态；为防止任务重叠，已停止后续提交。"
    }
}

Write-Host ("`n用例提交完成。运行记录：{0}" -f $manifestPath) -ForegroundColor Green
Write-Host '注意：终态由 CDP 自动判定；最终通过/失败仍需结合媒体校验和人工视觉检查。'
$finalResult = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$finalResult | Add-Member -NotePropertyName executionMode -NotePropertyValue $ExecutionMode.ToLowerInvariant() -Force
$finalResult | Add-Member -NotePropertyName executionStrategy -NotePropertyValue ([pscustomobject]$plan.executionStrategy) -Force
$finalResult | ConvertTo-Json -Depth 15
