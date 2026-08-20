$ErrorActionPreference = 'Stop'

$helperPath = Join-Path $PSScriptRoot '..\yunxiao-credential.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Expected credential helper to exist: $helperPath"
}

$rawScript = Get-Content -Raw -LiteralPath $helperPath
if ($rawScript -match 'ConvertTo-SecureString') {
    throw 'Credential helper must not depend on the unavailable Microsoft.PowerShell.Security module.'
}

. $helperPath

$testDirectory = Join-Path $env:TEMP ("cinlink-yunxiao-credential-test-" + [guid]::NewGuid().ToString('N'))
$testCredentialPath = Join-Path $testDirectory 'yunxiao-pat.clixml'
$previousToken = [Environment]::GetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', 'Process')
$testToken = 'credential-test-value-' + [guid]::NewGuid().ToString('N')

try {
    [Environment]::SetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', $testToken, 'Process')
    $resolvedFromEnvironment = Get-YunxiaoAccessToken -CredentialPath $testCredentialPath -NoPrompt
    if ($resolvedFromEnvironment -ne $testToken) {
        throw 'Credential helper did not return the process environment token.'
    }
    if (-not (Test-Path -LiteralPath $testCredentialPath)) {
        throw 'Credential helper did not create the DPAPI cache.'
    }
    if ((Get-Content -Raw -LiteralPath $testCredentialPath) -match [regex]::Escape($testToken)) {
        throw 'DPAPI cache contains the plaintext token.'
    }

    [Environment]::SetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', $null, 'Process')
    $resolvedFromCache = Get-YunxiaoAccessToken -CredentialPath $testCredentialPath -NoPrompt
    if ($resolvedFromCache -ne $testToken) {
        throw 'Credential helper did not decrypt the cached token.'
    }

    Clear-YunxiaoAccessToken -CredentialPath $testCredentialPath
    if (Test-Path -LiteralPath $testCredentialPath) {
        throw 'Credential helper did not clear the cache.'
    }
}
finally {
    [Environment]::SetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', $previousToken, 'Process')
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}

Write-Output 'PASS: Yunxiao DPAPI credential cache checks.'
