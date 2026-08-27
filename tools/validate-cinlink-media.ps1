param(
    [object[]]$Artifacts = @(),
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceName
)

$ErrorActionPreference = 'Stop'
$ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
if ($null -eq $ffprobe) {
    [pscustomobject]@{ status = 'ffprobe-unavailable'; files = @() }
    return
}

$localFiles = @($Artifacts | ForEach-Object {
    $candidate = if ($_ -is [string]) { $_ } elseif ($null -ne $_.path) { $_.path } else { $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        [IO.Path]::GetFullPath($candidate)
    }
})

if ($localFiles.Count -eq 0) {
    [pscustomobject]@{ status = 'no-local-artifact'; files = @() }
    return
}

$results = @($localFiles | ForEach-Object {
    $raw = @(& $ffprobe.Source -v error -show_entries 'format=duration:stream=index,codec_type,width,height,r_frame_rate' -of json $_) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $_" }
    [pscustomobject]@{ path = $_; probe = ($raw | ConvertFrom-Json) }
})
$outputPath = Join-Path $EvidenceDirectory "$EvidenceName-ffprobe.json"
$results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding UTF8

[pscustomobject]@{ status = 'validated'; files = @($localFiles); evidence = $outputPath }
