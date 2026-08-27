param(
    [switch]$DryRun,
    [string]$ConfigPath,
    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'yunxiao-credential.ps1')

$organizationId = '645887adc88feae8ff9706ae'
$projectId = '9eddb6cefdaaf7f910039fed2d'
$workitemTypeId = '37da3a07df4d08aef2e3b393'
$assignedTo = '68998708f9007d7e33d2960b'
$sprintId = '8adf37ede6ec567e4e17eaebfe'
$labelId = '04a2db058d968d47138880459e'
$runId = 'ai-core-smoke-2026-08-20'
$testTime = '2026-08-20'
$evidenceDirectory = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    'C:\Users\chen\Documents\ChatGPT\test\output\ui-test\ai-core-smoke-2026-08-20'
}
else {
    [System.IO.Path]::GetFullPath($EvidenceDirectory)
}
$statePath = Join-Path $evidenceDirectory 'yunxiao-defects-batch-state.json'
$resultPath = Join-Path $evidenceDirectory 'yunxiao-defects-batch-result.json'
$errorPath = Join-Path $evidenceDirectory 'yunxiao-defects-batch-error.json'
$skipExisting = $true
$reopenExisting = $true
$existingTargetStatus = '再次打开'
$commentPreviewMaxWidth = 1000

$levelFields = @{
    P0 = @{ priority = '946f97777897cdeac653bbc22a'; seriousLevel = 'b160e371d7f312ac01b0a4e513' }
    P1 = @{ priority = '5341ff22ce75040255752bb465'; seriousLevel = '91721612f43903f6a1a438ba98' }
    P2 = @{ priority = '0302d601f492838ff405113d00'; seriousLevel = 'b68befd018ae163c4165329608' }
}

function New-DefectConfig {
    param(
        [string]$Key,
        [string]$Level,
        [string]$Title,
        [string]$JobId,
        [string]$Material,
        [string]$Prompt,
        [string[]]$Steps,
        [string[]]$Actual,
        [string[]]$Expected,
        [string]$Impact,
        [string[]]$Evidence
    )
    $subject = "[CinLink][AI冒烟][$Level] $Title"
    return [ordered]@{
        key = $Key
        level = $Level
        subject = $subject
        jobId = $JobId
        material = $Material
        prompt = $Prompt
        steps = @($Steps)
        actual = @($Actual)
        expected = @($Expected)
        impact = $Impact
        evidence = @($Evidence)
    }
}

$defects = @(
    New-DefectConfig -Key 'CL-SMOKE-02' -Level 'P0' -Title '积分确认缺失且 UI 余额长期不刷新' `
        -JobId '跨任务积分问题，无单一 Job ID；涉及本轮全部 AI 任务。' -Material '7MB.mp4、1270510918-1-12.mp4' -Prompt '分别按本轮字幕、翻译、画质增强、水印、混剪及长视频变短提示词提交任务。' `
        -Steps @('记录任务开始前积分。','依次提交本轮全部 AI 工作流，观察提交确认区域和任务进度。','每项任务结束后查看积分余额和流水。','重新加载账号信息并核对真实最终余额。') `
        -Actual @('所有任务提交前均未显示预计费用或费用确认弹窗。','客户端积分菜单从始至终显示 3334。','账号重新加载后的真实余额为 2827，本轮实际消耗 507。','界面没有逐任务扣费流水，无法判断失败或取消任务是否收费。') `
        -Expected @('提交任务前明确显示预计消耗并由用户确认。','任务状态变化后及时刷新积分余额。','提供逐任务扣费、退款和取消处理流水，最终余额与账号数据一致。') `
        -Impact '用户无法预知、核对或追溯 507 积分消耗，存在严重计费透明度和信任风险。' `
        -Evidence @('00-baseline.png','90-final-ui-credits.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-03' -Level 'P1' -Title '长视频变短因字幕产物类型错误永久卡在结果回写' `
        -JobId 'run_a0979febe49a13d8be09b1c1' -Material '1270510918-1-12.mp4（169 秒，1280×720）' `
        -Prompt '将 @1270510918-1-12.mp4 提炼为 30 秒横屏短视频；优先保留信息完整、人物发言清晰的高光片段，删除停顿和重复内容，保持原声并添加简体中文字幕，输出 1280×720 MP4。' `
        -Steps @('上传长视频并输入上述提示词。','提交任务并确认生成的 17 秒 + 13 秒高光方案。','等待字幕本地化、烧录和最终结果回写。','观察 88% 状态并检查磁盘产物。') `
        -Actual @('客户端提示 `$select_highlights.subtitle` 本地化后的文件类型与执行计划不一致。','最终烧录节点保持 waiting_for_local，UI 长期停在 88%。','磁盘出现两个内容相同的 29.897 秒 MP4，但 UI 没有成品结果。','中间视频没有简体中文字幕。') `
        -Expected @('字幕产物类型正确且能完成本地化和烧录。','任务进入明确终态，UI 展示唯一一个约 30 秒的最终成片。','成片包含简体中文字幕且没有结尾截断。') `
        -Impact '用户已等待并生成中间产物，但任务永久无法闭环，无法从客户端取得最终结果。' `
        -Evidence @('70-long-to-short-before-submit.png','71-long-to-short-plan.png','72-long-to-short-88-type-error.png','73-long-to-short-stuck-final.png','frame-long-short-05s.png','frame-long-short-20s.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-04' -Level 'P1' -Title '混剪忽略目标时长和内容选择要求' `
        -JobId 'run_a173f6954ced1597f14fe456' -Material '7MB.mp4、1270510918-1-12.mp4' `
        -Prompt '将 @7MB.mp4 和 @1270510918-1-12.mp4 混剪成 45 秒横屏视频；从两个视频中各选取代表性片段，使用自然转场，保留主要对白并统一音量，输出 1280×720 MP4。' `
        -Steps @('同时上传两个源视频并输入上述提示词。','提交混剪任务并等待完成。','预览结果并用 ffprobe 检查时长。','抽检 10 秒和 100 秒画面来源。') `
        -Actual @('任务约 1 秒完成。','输出时长为 229.529 秒，接近两个源视频总时长。','抽帧表明实际行为接近顺序拼接，没有按 45 秒目标选择代表性片段。') `
        -Expected @('输出约 45 秒的 1280×720 MP4。','两个来源均包含可识别的代表性片段。','使用自然转场并统一主要对白音量。') `
        -Impact '核心混剪指令被忽略，结果与用户目标严重不符且不可直接使用。' `
        -Evidence @('60-mix-before-submit.png','61-mix-complete.png','frame-mix-010s.png','frame-mix-100s.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-05' -Level 'P1' -Title '画质增强文件名声称 1080p，实际仍为 720p' `
        -JobId 'run_bd5e93a02598b761943c927c' -Material '7MB.mp4（60.5 秒，1280×720）' `
        -Prompt '将 @7MB.mp4 画质增强到 1920×1080，提升清晰度并去除轻微噪点；保持原始时长、画幅比例、内容和音频同步。' `
        -Steps @('上传 7MB.mp4 并输入上述提示词。','提交画质增强任务并等待完成。','下载或读取结果文件。','使用 ffprobe 检查分辨率、时长和音轨。') `
        -Actual @('生成文件名为 7MB_1080p_enhanced.mp4。','ffprobe 显示实际分辨率仍为 1280×720。','结果时长 60.488 秒且音轨存在，但没有达到 1920×1080。') `
        -Expected @('结果分辨率约为 1920×1080，时长偏差不超过 1 秒且音轨同步。','如果能力不支持升至 1080p，应在提交前明确提示，不应生成误导性文件名。') `
        -Impact '用户会把未达到目标规格的文件误认为 1080p 成片，影响交付质量。' `
        -Evidence @('33-enhance-retry-before-submit.png','34-enhance-retry-complete.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-06' -Level 'P1' -Title '取消无确认、无原生重试且服务端状态未收敛' `
        -JobId 'run_9efcb9312cece0925d71ded4' -Material '7MB.mp4（60.5 秒，1280×720）' `
        -Prompt '将 @7MB.mp4 画质增强到 1920×1080，提升清晰度并去除轻微噪点；保持原始时长、画幅比例、内容和音频同步。' `
        -Steps @('提交画质增强任务。','任务进入执行中且进度到 45% 后点击停止。','观察是否出现二次确认以及任务最终状态。','检查原生重试入口和服务端任务状态。') `
        -Actual @('点击停止后任务直接取消，没有确认弹窗。','取消后 UI 没有原生重试入口。','客户端显示已取消，但服务端仍为 waiting_for_local 10%，状态未收敛。','只能用相同提示词新建任务代替重试。') `
        -Expected @('取消前显示确认弹窗，避免误操作。','取消后客户端与服务端均进入明确的取消终态，进度停止且不产生结果。','任务卡片提供保留相同参数的原生重试入口，并明确取消任务的积分处理。') `
        -Impact '取消语义不可靠，后台可能遗留任务，用户也无法按原参数便捷重试或核对费用。' `
        -Evidence @('30-enhance-cancel-before-submit.png','31-enhance-running-45.png','32-enhance-canceled.png','33-enhance-retry-before-submit.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-07' -Level 'P1' -Title '翻译任务生成云端 SRT 但结果区和本地成片均缺字幕' `
        -JobId 'run_72be89ef2f43f3eddb6e13c9' -Material '7MB.mp4（60.5 秒，1280×720）' `
        -Prompt '将 @7MB.mp4 中的英文语音翻译为简体中文，生成中文字幕并合成中文配音；保留原画面，输出翻译后视频和 SRT 字幕文件。' `
        -Steps @('上传 7MB.mp4 并输入上述提示词。','提交翻译任务并等待完成。','检查结果区的成片与 SRT 下载入口。','应用内预览视频并抽检 30 秒画面。') `
        -Actual @('服务端生成的 translated.srt 非空且中文内容有效。','客户端结果区只展示 dubbed.mp4，没有展示或提供 SRT 下载。','本地成片抽帧没有烧录简体中文字幕。','中文配音存在，原文/译文音频可以切换。') `
        -Expected @('结果区同时展示并可下载翻译后视频和 SRT 文件。','视频按提示词包含可见的简体中文字幕。','字幕、配音和画面时间轴保持同步。') `
        -Impact '任务仅部分满足提示词，用户无法取得承诺的字幕文件或带字幕成片。' `
        -Evidence @('20-translation-before-submit.png','21-translation-complete.png','80-translation-preview.png','frame-translation-030s.png','smoke-test-report.md')

    New-DefectConfig -Key 'CL-SMOKE-08' -Level 'P2' -Title '图片水印任务 UI 与后端节点状态不一致' `
        -JobId 'run_c878f1f5dd7c824e876424e6' -Material '7MB.mp4、cinlink-smoke-watermark.png' `
        -Prompt '为 @7MB.mp4 添加 @cinlink-smoke-watermark.png 图片水印，放在右下角，宽度约为画面宽度的 15%，透明度约 70%，距离边缘约 24 像素；保持原始时长和音频。' `
        -Steps @('上传视频和透明 PNG 水印并输入上述提示词。','提交任务并等待 UI 显示完成。','预览结果视频并抽检 5 秒画面。','查询运行、内部节点及 artifacts 状态。') `
        -Actual @('UI 显示完成并生成可用的视频结果。','运行查询状态为 done。','内部节点仍为 queued，artifacts 数组为空，与 UI 和运行状态不一致。') `
        -Expected @('任务、内部节点和产物清单都进入一致的完成状态。','artifacts 能记录可恢复、可审计的最终视频产物。') `
        -Impact '不一致状态会影响任务恢复、审计、重试和后续自动化判断。' `
        -Evidence @('50-image-watermark-before-submit.png','51-image-watermark-complete.png','frame-image-watermark-05s.png','smoke-test-report.md')
)

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        throw "缺陷配置文件不存在：$resolvedConfigPath"
    }
    $externalConfig = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($externalConfig.runId)) {
        throw '外部缺陷配置缺少 runId。'
    }
    $runId = [string]$externalConfig.runId
    if (-not [string]::IsNullOrWhiteSpace($externalConfig.testTime)) {
        $testTime = [string]$externalConfig.testTime
    }
    $defects = @($externalConfig.defects)
    if ($defects.Count -eq 0) {
        throw '外部缺陷配置没有 defects。'
    }
}

$dryRunConfig = [ordered]@{
    runId = $runId
    testTime = $testTime
    organizationId = $organizationId
    projectId = $projectId
    workitemTypeId = $workitemTypeId
    assignedTo = $assignedTo
    sprint = $sprintId
    labels = @($labelId)
    skipExisting = $skipExisting
    reopenExisting = $reopenExisting
    existingTargetStatus = $existingTargetStatus
    existingResultChannel = 'comment'
    existingResultFormat = 'RICHTEXT'
    commentPreviewMaxWidth = $commentPreviewMaxWidth
    createFields = @('subject', 'description', 'formatType', 'assignedTo', 'spaceId', 'workitemTypeId', 'sprint', 'labels', 'customFieldValues')
    updateFields = @('description', 'formatType', 'assignedTo')
    existingUpdateFields = @('assignedTo', 'status')
    defects = @($defects | ForEach-Object {
        [ordered]@{
            key = $_.key; level = $_.level; subject = $_.subject; jobId = $_.jobId
            matchSubjects = @($_.matchSubjects)
            syncMarker = "<!-- cinlink-sync:${runId}:$($_.key) -->"
            commentPreviewMarker = "<!-- cinlink-sync-preview-v3:${runId}:$($_.key) -->"
            evidence = @($_.evidence | ForEach-Object { Join-Path $evidenceDirectory $_ })
            commentPreviewEvidence = @($_.evidence | Where-Object { $_.ToLowerInvariant().EndsWith('.png') } | ForEach-Object {
                $previewName = [System.IO.Path]::GetFileNameWithoutExtension($_) + '-comment-preview.png'
                Join-Path $evidenceDirectory $previewName
            })
        }
    })
}

if ($DryRun) {
    $dryRunConfig | ConvertTo-Json -Depth 10
    return
}

function ConvertTo-MarkdownList {
    param([string[]]$Items)
    return (($Items | ForEach-Object { "{0}. {1}" -f ([array]::IndexOf($Items, $_) + 1), $_ }) -join "`r`n")
}

function Get-BaseDescription {
    param([object]$Defect)
    $jobText = if ($Defect.jobId -like 'run_*') { "``$($Defect.jobId)``" } else { $Defect.jobId }
    return @"
## 测试环境

- 应用：CinLink 1.6.19 / Electron 35.2.0 / Windows
- 测试类型：AI 核心工作流冒烟测试
- 测试时间：$testTime
- 测试素材：$($Defect.material)

## Job ID

$jobText

## 测试提示词

``$($Defect.prompt)``

## 测试步骤

$(ConvertTo-MarkdownList -Items $Defect.steps)

## 实际结果

$(ConvertTo-MarkdownList -Items $Defect.actual)

## 预期结果

$(ConvertTo-MarkdownList -Items $Defect.expected)

## 影响

$($Defect.impact)
"@
}

function Read-JsonResponse {
    param([System.Net.Http.HttpResponseMessage]$Response, [string]$Operation)
    $text = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $Response.IsSuccessStatusCode) {
        throw "$Operation 返回 HTTP $([int]$Response.StatusCode)：$text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

function Invoke-JsonRequest {
    param([System.Net.Http.HttpClient]$Client, [string]$Method, [string]$Uri, [object]$Body, [string]$Operation)
    $content = $null
    try {
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 15
            $content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
        }
        if ($Method -eq 'POST') { $response = $Client.PostAsync($Uri, $content).GetAwaiter().GetResult() }
        elseif ($Method -eq 'PUT') { $response = $Client.PutAsync($Uri, $content).GetAwaiter().GetResult() }
        elseif ($Method -eq 'GET') { $response = $Client.GetAsync($Uri).GetAwaiter().GetResult() }
        else { throw "不支持的 HTTP 方法：$Method" }
        try { return Read-JsonResponse -Response $response -Operation $Operation }
        finally { $response.Dispose() }
    }
    finally { if ($null -ne $content) { $content.Dispose() } }
}

function Get-WorkflowStatus {
    param(
        [System.Net.Http.HttpClient]$Client,
        [string]$WorkitemUri,
        [string]$StatusName
    )
    $response = Invoke-JsonRequest -Client $Client -Method 'GET' -Uri "$WorkitemUri/workflow" -Body $null -Operation '读取工作项工作流'
    $workflow = if ($null -ne $response.workflow) { $response.workflow } else { $response }
    $matchingStatuses = @($workflow.statuses | Where-Object { [string]$_.name -ceq $StatusName })
    if ($matchingStatuses.Count -ne 1) {
        throw ('工作流状态「{0}」必须唯一，实际匹配 {1} 个。' -f $StatusName, $matchingStatuses.Count)
    }
    $identifier = [string]$matchingStatuses[0].identifier
    if ([string]::IsNullOrWhiteSpace($identifier)) {
        $identifier = [string]$matchingStatuses[0].id
    }
    if ([string]::IsNullOrWhiteSpace($identifier)) {
        throw ('工作流状态「{0}」缺少状态标识。' -f $StatusName)
    }
    return [ordered]@{ name = $StatusName; identifier = $identifier }
}

function Get-WorkitemStatus {
    param([object]$Workitem)
    $statusName = $null
    $statusIdentifier = [string]$Workitem.statusIdentifier
    if ($Workitem.status -is [string]) {
        $statusName = [string]$Workitem.status
    }
    elseif ($null -ne $Workitem.status) {
        $statusName = [string]$Workitem.status.name
        if ([string]::IsNullOrWhiteSpace($statusIdentifier)) {
            $statusIdentifier = [string]$Workitem.status.identifier
        }
        if ([string]::IsNullOrWhiteSpace($statusIdentifier)) {
            $statusIdentifier = [string]$Workitem.status.id
        }
    }
    if ([string]::IsNullOrWhiteSpace($statusName)) {
        $statusName = [string]$Workitem.statusName
    }
    return [ordered]@{ name = $statusName; identifier = $statusIdentifier }
}

function Remove-SyncedRegressionSection {
    param(
        [string]$Description,
        [string]$SyncMarker
    )
    if ([string]::IsNullOrEmpty($Description) -or [string]::IsNullOrWhiteSpace($SyncMarker)) {
        return $Description
    }
    $pattern = '(?s)\r?\n\r?\n---\r?\n\r?\n' + [regex]::Escape($SyncMarker) + '.*$'
    return [regex]::Replace($Description, $pattern, '')
}

function Get-MediaType {
    param([string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.png' { 'image/png' }
        '.md' { 'text/markdown' }
        default { 'application/octet-stream' }
    }
}

function Save-State {
    param([object[]]$Items)
    [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId
        projectId = $projectId
        items = @($Items)
    } | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Get-AttachmentName {
    param([object]$Attachment)
    if (-not [string]::IsNullOrWhiteSpace($Attachment.fileName)) { return $Attachment.fileName }
    return $Attachment.name
}

function Get-EmbedMarkdown {
    param([object]$Attachment, [string]$Name)
    if (-not [string]::IsNullOrWhiteSpace($Attachment.embedMarkdown)) { return $Attachment.embedMarkdown }
    $identifier = if ($Attachment.id) { $Attachment.id } else { $Attachment.fileIdentifier }
    if ([string]::IsNullOrWhiteSpace($identifier)) { throw "附件缺少永久标识：$Name" }
    return "![$Name](https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=$identifier)"
}

function Get-EmbedUrl {
    param([object]$Attachment, [string]$Name)
    if (-not [string]::IsNullOrWhiteSpace($Attachment.embedUrl)) { return $Attachment.embedUrl }
    $identifier = if ($Attachment.id) { $Attachment.id } else { $Attachment.fileIdentifier }
    if ([string]::IsNullOrWhiteSpace($identifier)) { throw "附件缺少永久标识：$Name" }
    return "https://devops.aliyun.com/projex/api/workitem/file/url?fileIdentifier=$identifier"
}

function Get-CommentPreviewName {
    param([string]$Name)
    return ([System.IO.Path]::GetFileNameWithoutExtension($Name) + '-comment-preview.png')
}

function New-CommentPreview {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$MaxWidth
    )
    Add-Type -AssemblyName System.Drawing
    $sourceImage = $null
    $previewImage = $null
    $graphics = $null
    try {
        $sourceImage = [System.Drawing.Image]::FromFile($SourcePath)
        $previewWidth = [Math]::Min($sourceImage.Width, $MaxWidth)
        $previewHeight = [int][Math]::Round($sourceImage.Height * ($previewWidth / [double]$sourceImage.Width))
        $previewImage = [System.Drawing.Bitmap]::new($previewWidth, $previewHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($previewImage)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($sourceImage, 0, 0, $previewWidth, $previewHeight)
        $previewImage.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $previewImage) { $previewImage.Dispose() }
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
    }
}

function Get-CommentRichTextContent {
    param(
        [string]$Marker,
        [string]$TestTime,
        [string]$JobId,
        [string[]]$Actual,
        [string[]]$Expected,
        [object[]]$Images
    )
    $htmlParts = @(
        '<article class="4ever-article">',
        $Marker,
        '<p><span>补充：完整截图预览</span></p>',
        '<p><span>以下截图已等比例缩小以完整适配评论区；点击“查看完整原图”可打开原始分辨率。</span></p>'
    )
    $jsonChildren = @(
        ,@('p', @{}, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, '补充：完整截图预览'))),
        ,@('p', @{}, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, '以下截图已等比例缩小以完整适配评论区；点击“查看完整原图”可打开原始分辨率。')))
    )
    $resultLines = @("测试时间：$TestTime", "Job ID：$JobId", '本次实际结果：') + @($Actual) + @('预期结果：') + @($Expected)
    foreach ($resultLine in $resultLines) {
        $encodedLine = [System.Net.WebUtility]::HtmlEncode([string]$resultLine)
        $htmlParts += "<p><span>$encodedLine</span></p>"
        $jsonChildren += ,@('p', @{}, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, [string]$resultLine)))
    }
    $imageIndex = 0
    foreach ($image in $Images) {
        $imageIndex++
        $name = [System.Net.WebUtility]::HtmlEncode([string]$image.Name)
        $previewUrl = [System.Net.WebUtility]::HtmlEncode([string]$image.PreviewUrl)
        $originalUrl = [System.Net.WebUtility]::HtmlEncode([string]$image.OriginalUrl)
        $width = [double]$image.Width
        $height = [double]$image.Height
        $size = [long]$image.Size
        $htmlParts += "<p><span>$name</span></p>"
        $htmlParts += ('<p><span></span><img src="{0}" style="width:{1}px;height:{2}px"><span></span></p>' -f $previewUrl, $width, $height)
        $htmlParts += ('<p><a href="{0}">查看完整原图</a></p>' -f $originalUrl)
        $jsonChildren += ,@('p', @{}, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, [string]$image.Name)))
        $jsonChildren += ,@(
            'p', @{},
            @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, '')),
            @('img', @{
                id = "cinlink-preview-$imageIndex"
                name = [string]$image.Name
                size = $size
                width = $width
                height = $height
                rotation = 0
                src = [string]$image.PreviewUrl
            }, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, ''))),
            @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, ''))
        )
        $jsonChildren += ,@('p', @{}, @('a', @{ href = [string]$image.OriginalUrl }, @('span', @{ 'data-type' = 'text' }, @('span', @{ 'data-type' = 'leaf' }, '查看完整原图'))))
    }
    $htmlParts += '</article>'
    $jsonMlValue = @('root', @{}) + $jsonChildren
    return ([ordered]@{
        htmlValue = ($htmlParts -join '')
        jsonMLValue = $jsonMlValue
    } | ConvertTo-Json -Depth 20 -Compress)
}

function Send-Attachment {
    param([System.Net.Http.HttpClient]$Client, [string]$Uri, [string]$Path)
    $stream = $null; $fileContent = $null; $multipart = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $fileContent = [System.Net.Http.StreamContent]::new($stream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new((Get-MediaType -Path $Path))
        $multipart = [System.Net.Http.MultipartFormDataContent]::new()
        $name = [System.IO.Path]::GetFileName($Path)
        $multipart.Add($fileContent, 'file', $name)
        $response = $Client.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
        try { return Read-JsonResponse -Response $response -Operation "上传附件 $name" }
        finally { $response.Dispose() }
    }
    finally {
        if ($null -ne $multipart) { $multipart.Dispose() }
        elseif ($null -ne $fileContent) { $fileContent.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

foreach ($defect in $defects) {
    foreach ($name in $defect.evidence) {
        $path = Join-Path $evidenceDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "证据文件不存在：$path" }
    }
}

$plainToken = $null
$httpClient = $null
$records = @()
try {
    $plainToken = Get-YunxiaoAccessToken -NoPrompt
    Add-Type -AssemblyName System.Net.Http
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromMinutes(5)
    $httpClient.DefaultRequestHeaders.Add('x-yunxiao-token', $plainToken)

    $baseUri = "https://openapi-rdc.aliyuncs.com/oapi/v1/projex/organizations/$organizationId"
    $searchBody = [ordered]@{ category = 'Bug'; orderBy = 'gmtCreate'; page = 1; perPage = 100; sort = 'desc'; spaceId = $projectId; spaceType = 'Project' }
    Write-Host '正在检索同名缺陷，防止重复创建...'
    $existingWorkitems = @(Invoke-JsonRequest -Client $httpClient -Method 'POST' -Uri "$baseUri/workitems:search" -Body $searchBody -Operation '检索工作项')

    foreach ($defect in $defects) {
        Write-Host ("`n[{0}] {1}" -f $defect.key, $defect.subject)
        $candidateSubjects = @([string]$defect.subject) + @($defect.matchSubjects | ForEach-Object { [string]$_ })
        $matching = @($existingWorkitems | Where-Object { $candidateSubjects -ccontains $_.subject })
        if ($matching.Count -gt 1) { throw "发现多个同根因工作项，停止以避免更新错误目标：$($candidateSubjects -join ' / ')" }

        $fields = $levelFields[$defect.level]
        $baseDescription = Get-BaseDescription -Defect $defect
        $createBody = [ordered]@{
            subject = $defect.subject
            description = $baseDescription
            formatType = 'MARKDOWN'
            assignedTo = $assignedTo
            spaceId = $projectId
            workitemTypeId = $workitemTypeId
            sprint = $sprintId
            labels = @($labelId)
            customFieldValues = [ordered]@{ priority = $fields.priority; seriousLevel = $fields.seriousLevel }
        }

        if ($matching.Count -eq 1 -and $skipExisting) {
            $workitemId = $matching[0].id
            $action = 'updated-existing'
            $matchedExisting = $true
            Write-Host ("跳过创建，续传并校验现有缺陷：{0}" -f $matching[0].serialNumber)
        }
        else {
            Write-Host '正在创建缺陷...'
            $created = Invoke-JsonRequest -Client $httpClient -Method 'POST' -Uri "$baseUri/workitems" -Body $createBody -Operation '创建工作项'
            if ([string]::IsNullOrWhiteSpace($created.id)) { throw "创建响应缺少工作项 ID：$($defect.key)" }
            $workitemId = $created.id
            $action = 'created'
            $matchedExisting = $false
        }

        $workitemUri = "$baseUri/workitems/$workitemId"
        $attachmentsUri = "$workitemUri/attachments"
        $commentsUri = "$workitemUri/comments"
        $current = Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $workitemUri -Body $null -Operation '读取工作项'
        $syncMarker = "<!-- cinlink-sync:${runId}:$($defect.key) -->"
        $createdByThisRun = $matchedExisting -and ([string]$current.description).TrimStart().StartsWith($syncMarker, [System.StringComparison]::Ordinal)
        $targetStatus = $null
        if ($matchedExisting -and -not $createdByThisRun -and $reopenExisting) {
            $targetStatus = Get-WorkflowStatus -Client $httpClient -WorkitemUri $workitemUri -StatusName $existingTargetStatus
        }
        $commentPreviewMap = @{}
        if ($matchedExisting -and -not $createdByThisRun) {
            foreach ($name in @($defect.evidence | Where-Object { $_.ToLowerInvariant().EndsWith('.png') })) {
                $previewName = Get-CommentPreviewName -Name $name
                $previewPath = Join-Path $evidenceDirectory $previewName
                New-CommentPreview -SourcePath (Join-Path $evidenceDirectory $name) -DestinationPath $previewPath -MaxWidth $commentPreviewMaxWidth
                $commentPreviewMap[$name] = $previewName
            }
        }
        $requiredEvidenceNames = @($defect.evidence) + @($commentPreviewMap.Values)
        $attachments = @(Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $attachmentsUri -Body $null -Operation '读取附件')
        $attachmentMap = @{}
        foreach ($attachment in $attachments) { $attachmentMap[(Get-AttachmentName -Attachment $attachment)] = $attachment }

        foreach ($name in $requiredEvidenceNames) {
            if ($attachmentMap.ContainsKey($name)) {
                Write-Host ("跳过已存在附件：{0}" -f $name)
                continue
            }
            Write-Host ("正在上传：{0}" -f $name)
            $uploaded = Send-Attachment -Client $httpClient -Uri $attachmentsUri -Path (Join-Path $evidenceDirectory $name)
            $attachmentMap[$name] = $uploaded
        }

        $imageBlocks = @()
        $downloadBlocks = @()
        foreach ($name in $defect.evidence) {
            $attachment = $attachmentMap[$name]
            if ($name.ToLowerInvariant().EndsWith('.png')) {
                $imageBlocks += "### $name`r`n`r`n$(Get-EmbedMarkdown -Attachment $attachment -Name $name)"
            }
            else {
                $downloadBlocks += "- [$name]($(Get-EmbedUrl -Attachment $attachment -Name $name))"
            }
        }
        $evidenceSection = "## 证据附件`r`n`r`n" + ($imageBlocks -join "`r`n`r`n")
        if ($downloadBlocks.Count -gt 0) {
            $evidenceSection += "`r`n`r`n### 可点击附件`r`n`r`n" + ($downloadBlocks -join "`r`n")
        }
        $commentImages = @()
        foreach ($name in $defect.evidence) {
            $attachment = $attachmentMap[$name]
            if ($name.ToLowerInvariant().EndsWith('.png') -and $commentPreviewMap.ContainsKey($name)) {
                $previewName = $commentPreviewMap[$name]
                $previewAttachment = $attachmentMap[$previewName]
                $previewPath = Join-Path $evidenceDirectory $previewName
                $previewImage = [System.Drawing.Image]::FromFile($previewPath)
                try {
                    $commentImages += [ordered]@{
                        Name = $name
                        PreviewUrl = Get-EmbedUrl -Attachment $previewAttachment -Name $previewName
                        OriginalUrl = Get-EmbedUrl -Attachment $attachment -Name $name
                        Width = $previewImage.Width
                        Height = $previewImage.Height
                        Size = (Get-Item -LiteralPath $previewPath).Length
                    }
                }
                finally {
                    $previewImage.Dispose()
                }
            }
        }
        $commentPreviewMarker = "<!-- cinlink-sync-preview-v3:${runId}:$($defect.key) -->"
        if ($action -eq 'created') {
            $finalDescription = $syncMarker + "`r`n`r`n" + $baseDescription.TrimEnd() + "`r`n`r`n" + $evidenceSection
            $commentContent = $null
            $descriptionNeedsRepair = $false
        }
        elseif ($createdByThisRun) {
            $finalDescription = [string]$current.description
            $commentContent = $null
            $descriptionNeedsRepair = $false
            $action = 'unchanged-existing'
        }
        else {
            $finalDescription = Remove-SyncedRegressionSection -Description ([string]$current.description) -SyncMarker $syncMarker
            $descriptionNeedsRepair = $finalDescription -cne [string]$current.description
            $commentContent = Get-CommentRichTextContent -Marker $commentPreviewMarker `
                -TestTime $testTime -JobId ([string]$defect.jobId) `
                -Actual @($defect.actual) -Expected @($defect.expected) -Images $commentImages
        }

        $commentCreated = $false
        $verifiedComment = $null
        if (-not [string]::IsNullOrWhiteSpace($commentContent)) {
            $comments = @(Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $commentsUri -Body $null -Operation '读取评论')
            $matchingComments = @($comments | Where-Object { [string]$_.content -like "*$commentPreviewMarker*" })
            if ($matchingComments.Count -gt 1) {
                throw "发现多个同一批次回归评论，停止以避免重复：$($defect.key)"
            }
            if ($matchingComments.Count -eq 0) {
                Write-Host '正在写入本次回归评论...'
                $commentBody = [ordered]@{ content = $commentContent; contentFormat = 'RICHTEXT' }
                $null = Invoke-JsonRequest -Client $httpClient -Method 'POST' -Uri $commentsUri -Body $commentBody -Operation '创建回归评论'
                $commentCreated = $true
            }
        }

        $updateBody = [ordered]@{}
        if ($action -eq 'created') {
            $updateBody.description = $finalDescription
            $updateBody.formatType = 'MARKDOWN'
            $updateBody.assignedTo = $assignedTo
        }
        else {
            if ($descriptionNeedsRepair) {
                $updateBody.description = $finalDescription
                $updateBody.formatType = 'MARKDOWN'
            }
            if ($current.assignedTo.id -ne $assignedTo) {
                $updateBody.assignedTo = $assignedTo
            }
            if ($null -ne $targetStatus) {
                $currentStatus = Get-WorkitemStatus -Workitem $current
                if ($currentStatus.identifier -ne $targetStatus.identifier) {
                    $updateBody.status = $targetStatus.identifier
                }
            }
        }
        if ($updateBody.Count -gt 0) {
            Write-Host '正在更新必要的工作项字段...'
            $null = Invoke-JsonRequest -Client $httpClient -Method 'PUT' -Uri $workitemUri -Body $updateBody -Operation '更新工作项'
        }
        elseif (-not $commentCreated) {
            $action = 'unchanged-existing'
        }

        $verified = Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $workitemUri -Body $null -Operation '回读工作项'
        $verifiedAttachments = @(Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $attachmentsUri -Body $null -Operation '回读附件')
        $verifiedNames = @($verifiedAttachments | ForEach-Object { Get-AttachmentName -Attachment $_ })
        $missing = @($requiredEvidenceNames | Where-Object { $verifiedNames -notcontains $_ })
        if ($candidateSubjects -cnotcontains $verified.subject) { throw "标题回读不一致：$($defect.key)" }
        if ($verified.assignedTo.id -ne $assignedTo) { throw "负责人回读不一致：$($defect.key)" }
        if (-not [string]::IsNullOrWhiteSpace($commentContent)) {
            $verifiedComments = @(Invoke-JsonRequest -Client $httpClient -Method 'GET' -Uri $commentsUri -Body $null -Operation '回读评论')
            $verifiedMatchingComments = @($verifiedComments | Where-Object { [string]$_.content -like "*$commentPreviewMarker*" })
            if ($verifiedMatchingComments.Count -ne 1) {
                throw "回归评论回读不一致：$($defect.key)"
            }
            $verifiedComment = $verifiedMatchingComments[0]
            if ([string]$verified.description -like "*$syncMarker*") {
                throw "既有缺陷描述仍包含本轮回归段落：$($defect.key)"
            }
        }
        if ($null -ne $targetStatus) {
            $verifiedStatus = Get-WorkitemStatus -Workitem $verified
            if ($verifiedStatus.identifier -ne $targetStatus.identifier) {
                throw "状态标识回读不一致 $($defect.key)：期望 $($targetStatus.identifier)，实际 $($verifiedStatus.identifier)"
            }
            if (-not [string]::IsNullOrWhiteSpace($verifiedStatus.name) -and $verifiedStatus.name -ne $existingTargetStatus) {
                throw "状态名称回读不一致 $($defect.key)：期望 $existingTargetStatus，实际 $($verifiedStatus.name)"
            }
        }
        if ($missing.Count -gt 0) { throw "附件回读缺失 $($defect.key)：$($missing -join ', ')" }
        foreach ($name in @($defect.evidence | Where-Object { $_.ToLowerInvariant().EndsWith('.png') })) {
            $url = Get-EmbedUrl -Attachment $attachmentMap[$name] -Name $name
            $verifiedEvidenceText = if ($null -ne $verifiedComment) { [string]$verifiedComment.content } else { [string]$verified.description }
            if ($verifiedEvidenceText -notlike "*$url*") { throw "回读内容缺少图片永久链接 $($defect.key)：$name" }
            if ($null -ne $verifiedComment) {
                $previewName = $commentPreviewMap[$name]
                $previewUrl = Get-EmbedUrl -Attachment $attachmentMap[$previewName] -Name $previewName
                if ($verifiedEvidenceText -notlike "*$previewUrl*") { throw "回归评论缺少完整截图预览 $($defect.key)：$name" }
            }
        }
        $priorityField = @($verified.customFieldValues | Where-Object { $_.fieldId -eq 'priority' })
        $severityField = @($verified.customFieldValues | Where-Object { $_.fieldId -eq 'seriousLevel' })
        if (@($priorityField[0].values | Where-Object { $_.identifier -eq $fields.priority }).Count -ne 1) { throw "优先级回读不一致：$($defect.key)" }
        if (@($severityField[0].values | Where-Object { $_.identifier -eq $fields.seriousLevel }).Count -ne 1) { throw "严重程度回读不一致：$($defect.key)" }

        $record = [ordered]@{
            key = $defect.key; action = $action; workitemId = $workitemId
            serialNumber = $verified.serialNumber; subject = $verified.subject
            assignedTo = $verified.assignedTo; level = $defect.level
            attachmentCount = $verifiedAttachments.Count; verifiedEvidence = @($requiredEvidenceNames)
            reopened = [bool]($null -ne $targetStatus)
            regressionChannel = if ($null -ne $verifiedComment) { 'comment' } else { 'description' }
            regressionCommentId = if ($null -ne $verifiedComment) { $verifiedComment.id } else { $null }
            verifiedWorkitemStatus = if ($null -ne $targetStatus) { [ordered]@{ name = $existingTargetStatus; identifier = $targetStatus.identifier } } else { $null }
            url = "https://devops.aliyun.com/projex/project/$projectId/bug/$workitemId"
            status = 'verified'
        }
        $records += $record
        Save-State -Items $records
        Write-Host ("已验证：{0}" -f $verified.serialNumber) -ForegroundColor Green
    }

    $result = [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId; projectId = $projectId
        requested = $defects.Count; verified = @($records | Where-Object { $_.status -eq 'verified' }).Count
        created = @($records | Where-Object { $_.action -eq 'created' }).Count
        updatedExisting = @($records | Where-Object { $_.action -eq 'updated-existing' }).Count
        skippedExisting = @($records | Where-Object { $_.action -eq 'unchanged-existing' }).Count
        items = @($records)
    }
    $result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if (Test-Path -LiteralPath $errorPath) { Remove-Item -LiteralPath $errorPath -Force }
    Write-Host ("`n批量同步完成：验证 {0}/{1}，新建 {2}，更新 {3}，幂等跳过 {4}。" -f $result.verified, $result.requested, $result.created, $result.updatedExisting, $result.skippedExisting) -ForegroundColor Green
    Write-Host ("结果记录：{0}" -f $resultPath)
}
catch {
    $errorRecord = [ordered]@{
        recordedAt = (Get-Date).ToString('o'); organizationId = $organizationId; projectId = $projectId
        completedItems = @($records); error = $_.Exception.Message; position = [string]$_.InvocationInfo.PositionMessage
    }
    $errorRecord | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $errorPath -Encoding UTF8
    Write-Host ("`n批量同步失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("错误记录：{0}" -f $errorPath)
    exit 1
}
finally {
    if ($null -ne $httpClient) { $httpClient.Dispose() }
    $plainToken = $null
}
