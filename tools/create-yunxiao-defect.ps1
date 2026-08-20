param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'yunxiao-credential.ps1')

$projectId = '9eddb6cefdaaf7f910039fed2d'
$workitemTypeId = '37da3a07df4d08aef2e3b393'
$assigneeId = '68998708f9007d7e33d2960b'
$sprintId = '8adf37ede6ec567e4e17eaebfe'
$labelId = '04a2db058d968d47138880459e'
$evidenceDirectory = 'C:\Users\chen\Documents\ChatGPT\test\output\ui-test\ai-core-smoke-2026-08-20'
$resultPath = Join-Path $evidenceDirectory 'yunxiao-p0-subtitle-create-result.json'

$description = @'
## 测试环境

- 应用：CinLink 1.6.19
- 测试类型：AI 核心工作流冒烟测试
- 测试素材：7MB.mp4
- 素材信息：60.5 秒，1280×720，H.264 + AAC
- 测试时间：2026-08-20

## Job ID

`run_6ee3c572081a70e211c840ba`

## 前置条件

1. 使用当前已登录账号启动 CinLink。
2. 账号积分充足。
3. 将 7MB.mp4 添加到当前会话。

## 测试步骤

1. 在 CinLink 中上传 7MB.mp4。
2. 输入提示词：`为 @7MB.mp4 自动识别英文语音，生成简体中文字幕并烧录到视频中；同时输出 SRT 字幕文件，保持时间轴与说话内容同步。`
3. 提交任务。
4. 观察任务排队、执行和进度变化。
5. 等待任务完成并尝试打开、预览或下载结果文件。

## 实际结果

1. 客户端进度运行至约 58% 后失败。
2. 页面提示“结果文件获取失败”。
3. 错误码为 `artifact_not_found`。
4. 错误阶段为 `generate_video (2/3)`。
5. 操作为 `translateAndBurn.artifactGate`。
6. 服务端任务实际已为 `done/100%`，但客户端无法获取或本地化结果。
7. 用户无法预览、下载成片和 SRT 字幕。
8. 任务仍产生约 30 积分消耗。

## 预期结果

1. 任务正常完成，不出现产物丢失或本地化失败。
2. 客户端能够预览和下载烧录简体中文字幕的视频。
3. 客户端能够下载非空、时间戳正确的 SRT 文件。
4. 服务端完成状态与客户端结果状态保持一致。
5. 若结果不可用，不应收费；如收费，应在界面中明确展示费用明细。

## 错误信息

- Task ID：`c73378c9-94b1-493a-9f0d-1f63e086f309`
- Fingerprint：`tf-5b750b0b`
- Source：`artifact_storage`
- Retryable：`false`

## 证据附件

- 10-subtitle-before-submit.png
- 11-subtitle-running.png
- 12-subtitle-failed.png
- subtitle-diagnostic.zip
- smoke-test-report.md
'@

$createBody = [ordered]@{
    subject = '[CinLink][AI冒烟][P0] 自动字幕任务完成但客户端无法获取结果产物'
    description = $description
    formatType = 'MARKDOWN'
    assignedTo = $assigneeId
    spaceId = $projectId
    workitemTypeId = $workitemTypeId
    sprint = $sprintId
    labels = @($labelId)
    customFieldValues = [ordered]@{
        priority = '946f97777897cdeac653bbc22a'
        seriousLevel = 'b160e371d7f312ac01b0a4e513'
    }
}

if ($DryRun) {
    $createBody | ConvertTo-Json -Depth 10
    return
}

$plainToken = $null
$httpClient = $null
try {
    $plainToken = Get-YunxiaoAccessToken

    $headers = @{
        'x-yunxiao-token' = $plainToken
        'Content-Type' = 'application/json; charset=utf-8'
    }

    Write-Host '正在验证云效身份和目标项目...'
    $me = Invoke-RestMethod -Method Get -Uri 'https://openapi-rdc.aliyuncs.com/oapi/v1/platform/user' -Headers $headers
    $organizationId = $me.lastOrganization
    if ([string]::IsNullOrWhiteSpace($organizationId)) {
        throw '当前用户信息没有 lastOrganization，无法确定组织。'
    }

    $projectUri = "https://openapi-rdc.aliyuncs.com/oapi/v1/projex/organizations/$organizationId/projects/$projectId"
    $project = Invoke-RestMethod -Method Get -Uri $projectUri -Headers $headers

    Write-Host ("目标项目：{0} ({1})" -f $project.name, $projectId)
    Write-Host '正在创建第一条 P0 缺陷...'

    $createUri = "https://openapi-rdc.aliyuncs.com/oapi/v1/projex/organizations/$organizationId/workitems"
    Add-Type -AssemblyName System.Net.Http
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.DefaultRequestHeaders.Add('x-yunxiao-token', $plainToken)
    $createJson = $createBody | ConvertTo-Json -Depth 10
    $requestContent = [System.Net.Http.StringContent]::new(
        $createJson,
        [System.Text.Encoding]::UTF8,
        'application/json'
    )
    $createResponse = $httpClient.PostAsync($createUri, $requestContent).GetAwaiter().GetResult()
    $createResponseBody = $createResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $createResponse.IsSuccessStatusCode) {
        throw "云效创建接口返回 HTTP $([int]$createResponse.StatusCode)：$createResponseBody"
    }
    $created = $createResponseBody | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($created.id)) {
        throw '云效响应中没有工作项 ID，无法确认创建成功。'
    }

    Write-Host ("已创建工作项：{0}" -f $created.id)
    Write-Host '正在回读验证...'

    $workitemUri = "https://openapi-rdc.aliyuncs.com/oapi/v1/projex/organizations/$organizationId/workitems/$($created.id)"
    $verified = Invoke-RestMethod -Method Get -Uri $workitemUri -Headers $headers

    $result = [ordered]@{
        recordedAt = (Get-Date).ToString('o')
        organizationId = $organizationId
        projectId = $projectId
        projectName = $project.name
        workitemId = $created.id
        serialNumber = $verified.serialNumber
        subject = $verified.subject
        assignedTo = $verified.assignedTo
        priority = @($verified.customFieldValues | Where-Object { $_.fieldId -eq 'priority' })
        seriousLevel = @($verified.customFieldValues | Where-Object { $_.fieldId -eq 'seriousLevel' })
        sprint = $verified.sprint
        labels = $verified.labels
        rawCreateResponse = $created
    }

    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding utf8

    Write-Host ''
    Write-Host '创建并回读成功。' -ForegroundColor Green
    Write-Host ("缺陷编号：{0}" -f $verified.serialNumber)
    Write-Host ("缺陷标题：{0}" -f $verified.subject)
    Write-Host ("结果记录：{0}" -f $resultPath)
}
catch {
    $caughtError = $_
    $responseBody = $null
    $response = $caughtError.Exception.Response
    if ($null -ne $response) {
        try {
            $responseStream = $response.GetResponseStream()
            if ($null -ne $responseStream) {
                $reader = [System.IO.StreamReader]::new($responseStream)
                $responseBody = $reader.ReadToEnd()
                $reader.Dispose()
            }
        }
        catch {
            $responseBody = "无法读取云效错误响应：$($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host '创建失败：' -ForegroundColor Red
    Write-Host $caughtError.Exception.Message -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
        Write-Host '云效返回：' -ForegroundColor Yellow
        Write-Host $responseBody -ForegroundColor Yellow
        $errorResult = [ordered]@{
            recordedAt = (Get-Date).ToString('o')
            projectId = $projectId
            httpError = $caughtError.Exception.Message
            responseBody = $responseBody
        }
        $errorPath = Join-Path $evidenceDirectory 'yunxiao-p0-subtitle-create-error.json'
        $errorResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $errorPath -Encoding utf8
        Write-Host ("错误记录：{0}" -f $errorPath)
    }
    Read-Host '按 Enter 关闭窗口'
    exit 1
}
finally {
    if ($null -ne $httpClient) {
        $httpClient.Dispose()
    }
    $plainToken = $null
    Remove-Variable headers -ErrorAction SilentlyContinue
}

Read-Host '按 Enter 关闭窗口'
