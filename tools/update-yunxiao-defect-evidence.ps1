param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'yunxiao-credential.ps1')

$organizationId = '645887adc88feae8ff9706ae'
$projectId = '9eddb6cefdaaf7f910039fed2d'
$workitemId = 'dc2ee9a5bf080b4ee4f730e34d'
$serialNumber = 'MXIV-8'
$evidenceDirectory = 'C:\Users\chen\Documents\ChatGPT\test\output\ui-test\ai-core-smoke-2026-08-20'
$manifestPath = Join-Path $evidenceDirectory 'yunxiao-mxiv-8-evidence-upload.json'
$resultPath = Join-Path $evidenceDirectory 'yunxiao-mxiv-8-evidence-update-result.json'
$errorPath = Join-Path $evidenceDirectory 'yunxiao-mxiv-8-evidence-update-error.json'

$evidenceFiles = @(
    [ordered]@{ name = '10-subtitle-before-submit.png'; title = '提交前提示词与素材'; path = (Join-Path $evidenceDirectory '10-subtitle-before-submit.png'); embed = $true },
    [ordered]@{ name = '11-subtitle-running.png'; title = '任务运行与进度'; path = (Join-Path $evidenceDirectory '11-subtitle-running.png'); embed = $true },
    [ordered]@{ name = '12-subtitle-failed.png'; title = '失败结果与错误信息'; path = (Join-Path $evidenceDirectory '12-subtitle-failed.png'); embed = $true },
    [ordered]@{ name = 'subtitle-diagnostic.zip'; title = '字幕任务诊断包'; path = (Join-Path $evidenceDirectory 'subtitle-diagnostic.zip'); embed = $false },
    [ordered]@{ name = 'smoke-test-report.md'; title = '完整冒烟测试报告'; path = (Join-Path $evidenceDirectory 'smoke-test-report.md'); embed = $false }
)
$embedFileNames = @($evidenceFiles | Where-Object { $_.embed } | ForEach-Object { $_.name })

$dryRunConfig = [ordered]@{
    organizationId = $organizationId
    projectId = $projectId
    workitemId = $workitemId
    serialNumber = $serialNumber
    skipExistingAttachments = $true
    embedPngImages = $true
    files = @($evidenceFiles | ForEach-Object { [ordered]@{ name = $_.name; path = $_.path; embed = $_.embed } })
}

if ($DryRun) {
    $dryRunConfig | ConvertTo-Json -Depth 8
    return
}

function Get-MediaType {
    param([string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.png' { return 'image/png' }
        '.zip' { return 'application/zip' }
        '.md' { return 'text/markdown' }
        default { return 'application/octet-stream' }
    }
}

function Read-JsonResponse {
    param(
        [System.Net.Http.HttpResponseMessage]$Response,
        [string]$Operation
    )
    $responseText = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $Response.IsSuccessStatusCode) {
        throw "$Operation 返回 HTTP $([int]$Response.StatusCode)：$responseText"
    }
    if ([string]::IsNullOrWhiteSpace($responseText)) {
        return $null
    }
    return ($responseText | ConvertFrom-Json)
}

function Save-UploadManifest {
    param([object[]]$Records)
    $manifest = [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId
        projectId = $projectId
        workitemId = $workitemId
        serialNumber = $serialNumber
        uploads = @($Records)
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

foreach ($file in $evidenceFiles) {
    if (-not (Test-Path -LiteralPath $file.path -PathType Leaf)) {
        throw "证据文件不存在：$($file.path)"
    }
}

$plainToken = $null
$httpClient = $null
try {
    $plainToken = Get-YunxiaoAccessToken

    Add-Type -AssemblyName System.Net.Http
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.DefaultRequestHeaders.Add('x-yunxiao-token', $plainToken)

    $workitemUri = "https://openapi-rdc.aliyuncs.com/oapi/v1/projex/organizations/$organizationId/workitems/$workitemId"
    $attachmentsUri = "$workitemUri/attachments"

    Write-Host "正在验证缺陷 $serialNumber ..."
    $workitemResponse = $httpClient.GetAsync($workitemUri).GetAwaiter().GetResult()
    $workitem = Read-JsonResponse -Response $workitemResponse -Operation '读取工作项'
    if ($workitem.serialNumber -ne $serialNumber) {
        throw "工作项编号不匹配：预期 $serialNumber，实际 $($workitem.serialNumber)。"
    }
    Write-Host ("目标缺陷：{0} {1}" -f $serialNumber, $workitem.subject)

    $existingResponse = $httpClient.GetAsync($attachmentsUri).GetAwaiter().GetResult()
    $existingAttachments = @(Read-JsonResponse -Response $existingResponse -Operation '读取附件列表')

    $uploadRecords = @()
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $savedManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
            if ($savedManifest.workitemId -eq $workitemId) {
                $uploadRecords = @($savedManifest.uploads)
            }
        }
        catch {
            Write-Host '已有上传清单无法读取，将依据云效附件列表继续。' -ForegroundColor Yellow
        }
    }

    foreach ($file in $evidenceFiles) {
        $existing = @($existingAttachments | Where-Object { $_.fileName -eq $file.name -or $_.name -eq $file.name })
        $savedRecord = @($uploadRecords | Where-Object { $_.name -eq $file.name } | Select-Object -First 1)
        if ($existing.Count -gt 0) {
            Write-Host ("跳过已存在附件：{0}" -f $file.name)
            if ($savedRecord.Count -eq 0) {
                $uploadRecords += [pscustomobject]@{
                    name = $file.name
                    path = $file.path
                    status = 'existing'
                    response = $null
                }
                Save-UploadManifest -Records $uploadRecords
            }
            continue
        }

        Write-Host ("正在上传：{0}" -f $file.name)
        $fileStream = $null
        $fileContent = $null
        $multipart = $null
        try {
            $fileStream = [System.IO.File]::OpenRead($file.path)
            $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
            $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new((Get-MediaType -Path $file.path))
            $multipart = [System.Net.Http.MultipartFormDataContent]::new()
            $multipart.Add($fileContent, 'file', $file.name)

            $uploadResponse = $httpClient.PostAsync($attachmentsUri, $multipart).GetAwaiter().GetResult()
            $uploaded = Read-JsonResponse -Response $uploadResponse -Operation "上传 $($file.name)"
            $uploadRecords = @($uploadRecords | Where-Object { $_.name -ne $file.name })
            $uploadRecords += [pscustomobject]@{
                name = $file.name
                path = $file.path
                status = 'uploaded'
                response = $uploaded
            }
            Save-UploadManifest -Records $uploadRecords
        }
        finally {
            if ($null -ne $multipart) { $multipart.Dispose() }
            elseif ($null -ne $fileContent) { $fileContent.Dispose() }
            elseif ($null -ne $fileStream) { $fileStream.Dispose() }
        }
    }

    $imageSections = @()
    foreach ($file in @($evidenceFiles | Where-Object { $_.embed })) {
        $record = @($uploadRecords | Where-Object { $_.name -eq $file.name } | Select-Object -First 1)
        if ($record.Count -eq 0 -or [string]::IsNullOrWhiteSpace($record[0].response.embedMarkdown)) {
            throw "图片附件缺少永久 embedMarkdown，暂不更新描述以避免产生失效链接：$($file.name)"
        }
        $imageSections += "### $($file.title)`r`n`r`n$($record[0].response.embedMarkdown)"
    }

    $evidenceSection = @"
## 证据附件

$($imageSections -join "`r`n`r`n")

### 可下载附件

以下文件已上传到本工作项的“附件”区域，可直接点击文件名下载：

- `subtitle-diagnostic.zip`：字幕失败任务诊断包
- `smoke-test-report.md`：本轮 AI 核心工作流冒烟测试报告
"@

    $currentDescription = [string]$workitem.description
    $evidenceMatch = [regex]::Match($currentDescription, '(?ms)^## 证据附件\s*.*$')
    if ($evidenceMatch.Success) {
        $newDescription = $currentDescription.Substring(0, $evidenceMatch.Index).TrimEnd() + "`r`n`r`n" + $evidenceSection.Trim()
    }
    else {
        $newDescription = $currentDescription.TrimEnd() + "`r`n`r`n" + $evidenceSection.Trim()
    }

    Write-Host '正在把永久图片链接写入缺陷描述...'
    $updateJson = ([ordered]@{ description = $newDescription; formatType = 'MARKDOWN' } | ConvertTo-Json -Depth 8)
    $updateContent = [System.Net.Http.StringContent]::new($updateJson, [System.Text.Encoding]::UTF8, 'application/json')
    try {
        $updateResponse = $httpClient.PutAsync($workitemUri, $updateContent).GetAwaiter().GetResult()
        $null = Read-JsonResponse -Response $updateResponse -Operation '更新工作项描述'
    }
    finally {
        $updateContent.Dispose()
    }

    Write-Host '正在回读验证附件和描述...'
    $verifiedWorkitemResponse = $httpClient.GetAsync($workitemUri).GetAwaiter().GetResult()
    $verifiedWorkitem = Read-JsonResponse -Response $verifiedWorkitemResponse -Operation '回读工作项'
    $verifiedAttachmentsResponse = $httpClient.GetAsync($attachmentsUri).GetAwaiter().GetResult()
    $verifiedAttachments = @(Read-JsonResponse -Response $verifiedAttachmentsResponse -Operation '回读附件列表')

    $verifiedNames = @($verifiedAttachments | ForEach-Object { if ($_.fileName) { $_.fileName } else { $_.name } })
    $missingFiles = @($evidenceFiles | Where-Object { $verifiedNames -notcontains $_.name } | ForEach-Object { $_.name })
    if ($missingFiles.Count -gt 0) {
        throw "回读时缺少附件：$($missingFiles -join ', ')"
    }
    foreach ($record in @($uploadRecords | Where-Object { $embedFileNames -contains $_.name -and $_.response.embedUrl })) {
        if ($verifiedWorkitem.description -notlike "*$($record.response.embedUrl)*") {
            throw "描述中缺少图片永久链接：$($record.name)"
        }
    }

    $result = [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId
        projectId = $projectId
        workitemId = $workitemId
        serialNumber = $serialNumber
        subject = $verifiedWorkitem.subject
        attachmentCount = $verifiedAttachments.Count
        verifiedFileNames = $verifiedNames
        embeddedImages = @($uploadRecords | Where-Object { $embedFileNames -contains $_.name -and $_.response.embedUrl } | ForEach-Object { [ordered]@{ name = $_.name; embedUrl = $_.response.embedUrl } })
        descriptionUpdated = $true
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8

    Write-Host ''
    Write-Host '附件上传和描述更新成功。' -ForegroundColor Green
    Write-Host ("缺陷：{0}" -f $serialNumber)
    Write-Host ("已验证附件：{0}" -f ($verifiedNames -join ', '))
    Write-Host ("结果记录：{0}" -f $resultPath)
}
catch {
    $errorResult = [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId
        projectId = $projectId
        workitemId = $workitemId
        serialNumber = $serialNumber
        error = $_.Exception.Message
    }
    $errorResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $errorPath -Encoding utf8
    Write-Host ''
    Write-Host '附件更新失败：' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ("错误记录：{0}" -f $errorPath)
    Read-Host '按 Enter 关闭窗口'
    exit 1
}
finally {
    if ($null -ne $httpClient) { $httpClient.Dispose() }
    $plainToken = $null
}

Read-Host '按 Enter 关闭窗口'
