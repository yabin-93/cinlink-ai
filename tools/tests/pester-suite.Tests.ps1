$checkFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' |
    Where-Object { $_.Name -ne 'pester-suite.Tests.ps1' } |
    Sort-Object Name)

Describe 'CinLink PowerShell checks' {
    foreach ($checkFile in $checkFiles) {
        It "$($checkFile.BaseName) passes" {
            { & $checkFile.FullName | Out-Host } | Should Not Throw
        }
    }
}
