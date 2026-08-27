$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\sync-yunxiao-defects.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cinlink-yunxiao-regression-' + [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $fixtureRoot 'defects.json'
$evidencePath = Join-Path $fixtureRoot 'evidence.png'

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force
    [System.IO.File]::WriteAllBytes($evidencePath, [byte[]](1, 2, 3))
    @{
        runId = 'regression-fixture'
        testTime = '2026-08-26'
        defects = @(
            @{
                key = 'REG-001'
                level = 'P1'
                subject = '[CinLink][AI冒烟][P1] 新根因'
                matchSubjects = @('[CinLink][AI冒烟][P1] 已有同根因')
                jobId = 'run_fixture'
                material = 'fixture.mp4'
                prompt = 'fixture prompt'
                steps = @('提交任务')
                actual = @('结果错误')
                expected = @('结果正确')
                impact = 'fixture impact'
                evidence = @('evidence.png')
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    $dryRunJson = & $scriptPath -DryRun -ConfigPath $configPath -EvidenceDirectory $fixtureRoot
    $dryRun = $dryRunJson | ConvertFrom-Json

    if ($dryRun.runId -ne 'regression-fixture') {
        throw 'External regression run ID was not preserved.'
    }
    if ($dryRun.testTime -ne '2026-08-26') {
        throw 'External regression test date was not preserved.'
    }
    if (@($dryRun.defects).Count -ne 1) {
        throw 'External defect configuration was not loaded.'
    }
    if (@($dryRun.defects[0].matchSubjects) -notcontains '[CinLink][AI冒烟][P1] 已有同根因') {
        throw 'Root-cause alias was not exposed for duplicate matching.'
    }
    if ($dryRun.defects[0].syncMarker -ne '<!-- cinlink-sync:regression-fixture:REG-001 -->') {
        throw 'Stable idempotency marker was not generated.'
    }
    if ($dryRun.defects[0].evidence[0] -ne $evidencePath) {
        throw 'Evidence path was not resolved from the selected run directory.'
    }
    if ($dryRun.reopenExisting -ne $true) {
        throw 'Existing matched defects must be configured for reopening.'
    }
    if ($dryRun.existingTargetStatus -ne '再次打开') {
        throw 'Existing matched defects must target the 再次打开 status.'
    }
    if (@($dryRun.createFields) -contains 'status') {
        throw 'New defects must retain the Yunxiao default initial status.'
    }
    if ($dryRun.existingResultChannel -ne 'comment') {
        throw 'Existing matched defects must publish regression results as comments.'
    }
    if (@($dryRun.existingUpdateFields) -contains 'description') {
        throw 'Normal existing-defect synchronization must not rewrite the description.'
    }
    if ($dryRun.commentPreviewMaxWidth -ne 1000) {
        throw 'Comment screenshot previews must be constrained to 1000 pixels wide.'
    }
    if ($dryRun.defects[0].commentPreviewEvidence[0] -ne (Join-Path $fixtureRoot 'evidence-comment-preview.png')) {
        throw 'DryRun must expose the generated full-image comment preview path.'
    }
    if ($dryRun.defects[0].commentPreviewMarker -ne '<!-- cinlink-sync-preview-v3:regression-fixture:REG-001 -->') {
        throw 'Corrected comment previews must use a new idempotency marker.'
    }
    if ($dryRun.existingResultFormat -ne 'RICHTEXT') {
        throw 'Yunxiao comments containing images must use the native rich-text format.'
    }

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw 'Could not parse the Yunxiao synchronizer for workflow status behavior.'
    }
    $resolverAst = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-WorkflowStatus'
    }, $true))
    if ($resolverAst.Count -ne 1) {
        throw 'Expected one Get-WorkflowStatus implementation.'
    }
    Invoke-Expression $resolverAst[0].Extent.Text
    function Invoke-JsonRequest {
        return [pscustomobject]@{
            name = '缺陷工作流'
            statuses = @(
                [pscustomobject]@{ name = '再次打开'; nameEn = 'Reopen'; displayName = '再次打开'; id = '30' }
            )
            id = 'workflow-fixture'
            defaultStatusId = '10'
        }
    }
    $resolvedStatus = Get-WorkflowStatus -Client $null -WorkitemUri 'https://fixture/workitems/1' -StatusName '再次打开'
    if ($resolvedStatus.identifier -ne '30') {
        throw 'The real Yunxiao workflow status id field was not resolved.'
    }

    $removeSectionAst = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Remove-SyncedRegressionSection'
    }, $true))
    if ($removeSectionAst.Count -ne 1) {
        throw 'Expected one Remove-SyncedRegressionSection implementation.'
    }
    Invoke-Expression $removeSectionAst[0].Extent.Text
    $fixtureMarker = '<!-- cinlink-sync:fixture:REG-001 -->'
    $originalDescription = "原始缺陷描述`r`n`r`n保留内容"
    $appendedDescription = $originalDescription + "`r`n`r`n---`r`n`r`n" + $fixtureMarker + "`r`n`r`n## 回归验证：fixture`r`n`r`n本次测试结果"
    $restoredDescription = Remove-SyncedRegressionSection -Description $appendedDescription -SyncMarker $fixtureMarker
    if ($restoredDescription -ne $originalDescription) {
        throw 'Only the appended synchronized regression section should be removed.'
    }
    if ((Remove-SyncedRegressionSection -Description $originalDescription -SyncMarker $fixtureMarker) -ne $originalDescription) {
        throw 'Descriptions without the synchronization marker must remain unchanged.'
    }

    $commentRichTextAst = @($scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-CommentRichTextContent'
    }, $true))
    if ($commentRichTextAst.Count -ne 1) {
        throw 'Expected one Get-CommentRichTextContent implementation.'
    }
    Invoke-Expression $commentRichTextAst[0].Extent.Text
    $richTextContent = Get-CommentRichTextContent -Marker '<!-- preview-fixture -->' `
        -TestTime '2026-08-26' -JobId 'run_fixture' `
        -Actual @('任务仍然失败') -Expected @('任务应成功完成') -Images @(
        [ordered]@{
            Name = 'evidence.png'
            PreviewUrl = 'https://fixture/preview'
            OriginalUrl = 'https://fixture/original'
            Width = 1000
            Height = 571
            Size = 12345
        }
    )
    $richText = $richTextContent | ConvertFrom-Json
    if (-not $richText.htmlValue.Contains('<img src="https://fixture/preview"')) {
        throw 'Rich-text HTML must embed the preview as an image.'
    }
    if (-not $richText.htmlValue.Contains('href="https://fixture/original"')) {
        throw 'Rich-text HTML must include the full-resolution link.'
    }
    if (-not $richText.htmlValue.Contains('任务仍然失败') -or -not $richText.htmlValue.Contains('run_fixture')) {
        throw 'The single rich-text comment must include the latest test result and job ID.'
    }
    if (-not $richTextContent.Contains('<!-- preview-fixture -->')) {
        throw 'Rich-text content must retain the idempotency marker.'
    }
    $jsonMlText = $richText.jsonMLValue | ConvertTo-Json -Depth 15 -Compress
    if (-not $jsonMlText.Contains('"img"') -or -not $jsonMlText.Contains('https://fixture/preview')) {
        throw 'Rich-text JSONML must contain the native Yunxiao image node.'
    }
    if ($richTextContent.Contains('![evidence.png]')) {
        throw 'Rich-text comments must not contain Markdown image syntax.'
    }

    Write-Output 'PASS: Yunxiao regression configuration and idempotency checks.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
