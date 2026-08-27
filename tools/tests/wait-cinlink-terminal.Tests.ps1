$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$waitPath = Join-Path $workspace 'tools\wait-cinlink-terminal.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-wait-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $fakeCdp = Join-Path $fixtureRoot 'fake-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_direct_error',text:'prompt\nSubtitle file does not contain any usable cues.',assistantText:'Subtitle file does not contain any usable cues.',artifacts:[],stop:false}}}));
'@ | Set-Content -LiteralPath $fakeCdp -Encoding UTF8
    $fakeCapture = Join-Path $fixtureRoot 'capture.ps1'
    @'
param([string]$ProcessName, [string]$OutputPath)
Set-Content -LiteralPath $OutputPath -Value 'screenshot' -Encoding UTF8
'@ | Set-Content -LiteralPath $fakeCapture -Encoding UTF8

    $result = & $waitPath -Prompt 'prompt' -TimeoutMinutes 1 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'direct-error' -CdpCommandPath $fakeCdp -CapturePath $fakeCapture
    if ($result.status -ne 'failed' -or $result.jobId -ne 'run_direct_error') {
        throw 'A direct assistant error must be treated as a failed terminal state.'
    }

    $balanceCdp = Join-Path $fixtureRoot 'balance-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_balance',text:'账户余额不足。请购买点数。',assistantText:'账户余额不足。请购买点数。',artifacts:[],stop:false}}}));
'@ | Set-Content -LiteralPath $balanceCdp -Encoding UTF8
    $balance = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'balance-error' -CdpCommandPath $balanceCdp -CapturePath $fakeCapture
    if ($balance.status -ne 'failed' -or $balance.jobId -ne 'run_balance') {
        throw 'An insufficient balance response must be treated as a failed terminal state.'
    }

    $planCdp = Join-Path $fixtureRoot 'plan-error-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_plan_error',text:'云端结果与本地渲染步骤之间缺少明确依赖。未启动任何云端处理。',assistantText:'云端结果与本地渲染步骤之间缺少明确依赖。未启动任何云端处理。',artifacts:[],stop:false}}}));
'@ | Set-Content -LiteralPath $planCdp -Encoding UTF8
    $planError = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'plan-error' -CdpCommandPath $planCdp -CapturePath $fakeCapture
    if ($planError.status -ne 'failed' -or $planError.jobId -ne 'run_plan_error') {
        throw 'A rejected execution plan must be treated as a failed terminal state.'
    }

    $alternativeCdp = Join-Path $fixtureRoot 'alternative-error-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_alternative',text:'请选择替代交付：仅烧录中文字幕。',assistantText:'请选择替代交付：仅烧录中文字幕。',artifacts:[],stop:false}}}));
'@ | Set-Content -LiteralPath $alternativeCdp -Encoding UTF8
    $alternative = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'alternative-error' -CdpCommandPath $alternativeCdp -CapturePath $fakeCapture
    if ($alternative.status -ne 'failed') {
        throw 'An unsupported request with suggested alternatives must be treated as a failed terminal state.'
    }

    $successCdp = Join-Path $fixtureRoot 'success-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_artifact_success',text:'prompt\n已将视频制作成中文配音版：dubbed.mp4',assistantText:'已将视频制作成中文配音版：dubbed.mp4',artifacts:[{name:'dubbed.mp4'}],stop:false}}}));
'@ | Set-Content -LiteralPath $successCdp -Encoding UTF8
    $success = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'artifact-success' -CdpCommandPath $successCdp -CapturePath $fakeCapture
    if ($success.status -ne 'completed' -or $success.jobId -ne 'run_artifact_success') {
        throw 'A stopped job with a result artifact must be treated as completed.'
    }

    $conditionalCdp = Join-Path $fixtureRoot 'conditional-success-cdp.mjs'
    @'
process.stdout.write(JSON.stringify({result:{type:'object',value:{jobId:'run_conditional_success',text:'若运行时无法提供真实 4K 将中止。视频画质增强已经完成：4K.mp4',assistantText:'若运行时无法提供真实 4K 将中止。视频画质增强已经完成：4K.mp4',artifacts:[{name:'4K.mp4'}],stop:false}}}));
'@ | Set-Content -LiteralPath $conditionalCdp -Encoding UTF8
    $conditional = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'conditional-success' -CdpCommandPath $conditionalCdp -CapturePath $fakeCapture
    if ($conditional.status -ne 'completed') {
        throw 'An explicit completion with a result artifact must override hypothetical failure wording.'
    }

    $chainCdp = Join-Path $fixtureRoot 'chain-cdp.mjs'
    @'
const index = process.argv.indexOf('--params-base64');
const params = JSON.parse(Buffer.from(process.argv[index + 1], 'base64').toString('utf8'));
const followsLatest = params.expression.includes('startIndex') && params.expression.includes("title !== '—'") && params.expression.includes('jobIds.at(-1)');
const value = followsLatest
  ? {jobId:'run_followup_final',text:'result.mp4',assistantText:'result.mp4',artifacts:[{name:'result.mp4'}],stop:false}
  : {jobId:'run_initial',text:'需要补充信息',assistantText:'需要补充信息',artifacts:[],stop:false};
process.stdout.write(JSON.stringify({result:{type:'object',value}}));
'@ | Set-Content -LiteralPath $chainCdp -Encoding UTF8
    $chain = & $waitPath -Prompt 'prompt' -TimeoutMinutes 0 -EvidenceDirectory $fixtureRoot `
        -EvidenceName 'followup-chain' -CdpCommandPath $chainCdp -CapturePath $fakeCapture
    if ($chain.status -ne 'completed' -or $chain.jobId -ne 'run_followup_final') {
        throw 'The terminal waiter must follow clarification messages to the latest Job ID.'
    }
    Write-Output 'PASS: direct CinLink errors reach failed terminal state.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
