$script:DefaultYunxiaoCredentialPath = 'C:\Users\chen\.codex\.sandbox-secrets\yunxiao-pat.clixml'

function ConvertTo-YunxiaoSecureValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $secureValue = [System.Security.SecureString]::new()
    foreach ($character in $Value.ToCharArray()) {
        $secureValue.AppendChar($character)
    }
    $secureValue.MakeReadOnly()
    return $secureValue
}

function Save-YunxiaoAccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [string]$CredentialPath = $script:DefaultYunxiaoCredentialPath
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw '不能缓存空的云效令牌。'
    }

    $credentialDirectory = Split-Path -Parent $CredentialPath
    if (-not (Test-Path -LiteralPath $credentialDirectory)) {
        $null = New-Item -ItemType Directory -Path $credentialDirectory -Force
    }

    $secureToken = ConvertTo-YunxiaoSecureValue -Value $Token
    $credential = [System.Management.Automation.PSCredential]::new('yunxiao-pat', $secureToken)
    $credential | Export-Clixml -LiteralPath $CredentialPath -Force
}

function Get-YunxiaoAccessToken {
    param(
        [string]$CredentialPath = $script:DefaultYunxiaoCredentialPath,
        [switch]$NoPrompt
    )

    $environmentToken = [Environment]::GetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', 'Process')
    if ([string]::IsNullOrWhiteSpace($environmentToken)) {
        $environmentToken = [Environment]::GetEnvironmentVariable('YUNXIAO_ACCESS_TOKEN', 'User')
    }
    if (-not [string]::IsNullOrWhiteSpace($environmentToken)) {
        Save-YunxiaoAccessToken -Token $environmentToken -CredentialPath $CredentialPath
        return $environmentToken
    }

    if (Test-Path -LiteralPath $CredentialPath -PathType Leaf) {
        try {
            $credential = Import-Clixml -LiteralPath $CredentialPath
            if ($credential -isnot [System.Management.Automation.PSCredential]) {
                throw '凭据文件格式无效。'
            }
            $cachedToken = $credential.GetNetworkCredential().Password
            if ([string]::IsNullOrWhiteSpace($cachedToken)) {
                throw '凭据文件中没有令牌。'
            }
            return $cachedToken
        }
        catch {
            throw "无法读取云效 DPAPI 凭据，请删除后重新授权：$($_.Exception.Message)"
        }
    }

    if ($NoPrompt) {
        throw '没有可用的云效环境变量或 DPAPI 凭据。'
    }

    $secureInput = Read-Host '首次配置：请输入云效个人访问令牌' -AsSecureString
    $promptToken = [System.Net.NetworkCredential]::new('', $secureInput).Password
    if ([string]::IsNullOrWhiteSpace($promptToken)) {
        throw '未输入云效令牌。'
    }
    Save-YunxiaoAccessToken -Token $promptToken -CredentialPath $CredentialPath
    Write-Host ("云效令牌已使用 Windows DPAPI 加密缓存：{0}" -f $CredentialPath)
    return $promptToken
}

function Clear-YunxiaoAccessToken {
    param(
        [string]$CredentialPath = $script:DefaultYunxiaoCredentialPath
    )

    if (Test-Path -LiteralPath $CredentialPath -PathType Leaf) {
        Remove-Item -LiteralPath $CredentialPath -Force
    }
}
