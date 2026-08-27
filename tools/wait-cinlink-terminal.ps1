param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][int]$TimeoutMinutes,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceName,
    [string]$CdpCommandPath,
    [string]$CapturePath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($CdpCommandPath)) { $CdpCommandPath = Join-Path $PSScriptRoot 'cdp-command.mjs' }
if ([string]::IsNullOrWhiteSpace($CapturePath)) { $CapturePath = Join-Path $PSScriptRoot 'capture-window.ps1' }

function Invoke-CinLinkEvaluation {
    param([Parameter(Mandatory = $true)][string]$Expression)
    $parameters = @{ expression = $Expression; returnByValue = $true } | ConvertTo-Json -Compress
    $parametersBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($parameters))
    $raw = @(node $CdpCommandPath Runtime.evaluate --params-base64 $parametersBase64) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) { throw 'CinLink CDP evaluation failed.' }
    return (($raw | ConvertFrom-Json).result.value)
}

$promptJson = $Prompt | ConvertTo-Json -Compress
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$lastState = $null

do {
    $expression = @"
(()=>{
  const prompt = $promptJson;
  const messages = [...document.querySelectorAll('article.message')];
  let startIndex = -1;
  for (let index = messages.length - 1; index >= 0; index--) {
    if (messages[index].classList.contains('user') && messages[index].innerText.includes(prompt)) {
      startIndex = index;
      break;
    }
  }
  const chain = startIndex >= 0 ? messages.slice(startIndex) : [];
  const jobIds = chain.map(message => message.querySelector('.message-job-id')?.getAttribute('title')).filter(title => title && title !== '—');
  const jobId = jobIds.at(-1) || null;
  const related = jobId ? chain : [];
  const text = related.map(message => message.innerText).join('\n');
  const assistantText = related.filter(message => message.classList.contains('assistant')).map(message => message.innerText).join('\n');
  const artifacts = related.flatMap(message => [...message.querySelectorAll('.attachment-entry strong')].map(element => ({name: element.innerText})));
  return { jobId, text, assistantText, artifacts, stop: !!document.querySelector('.composer-stop') };
})()
"@
    $state = Invoke-CinLinkEvaluation -Expression $expression
    if ($null -ne $state) { $lastState = $state }

    if (-not [string]::IsNullOrWhiteSpace([string]$state.jobId)) {
        if ([string]$state.assistantText -match '已完成全部 DAG 节点|视频处理已经完成|视频画质增强已经完成|任务已完成') {
            $status = 'completed'
            break
        }
        $resultArtifacts = @($state.artifacts | Where-Object { [string]$_.name -notmatch '^highlight_plan\.json$' })
        if (-not [bool]$state.stop -and $resultArtifacts.Count -gt 0) {
            $status = 'completed'
            break
        }
        if ([string]$state.assistantText -match '(?i)DAG 执行失败|任务执行失败|任务发生未分类错误|账户余额不足|未启动任何云端处理|缺少明确依赖|请选择(?:改为|替代)|未知错误|\b(error|failed|failure|invalid|requires|cannot|unable|does not|not supported)\b|失败|错误|无效|无法|不支持|不包含') {
            $status = 'failed'
            break
        }
        if ([string]$state.assistantText -match '已停止|已取消|任务取消') {
            $status = 'cancelled'
            break
        }
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ([string]::IsNullOrWhiteSpace($status)) { $status = 'timeout' }

if (Test-Path -LiteralPath $CapturePath -PathType Leaf) {
    & $CapturePath -ProcessName CinLink -OutputPath (Join-Path $EvidenceDirectory "$EvidenceName-terminal.png") | Out-Null
}

[pscustomobject]@{
    status = $status
    jobId = $lastState.jobId
    terminalText = $lastState.text
    artifacts = @($lastState.artifacts)
    finishedAt = (Get-Date).ToString('o')
}
