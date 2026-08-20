param(
    [Parameter(Mandatory = $true)]
    [string]$ProcessName,
    [Parameter(Mandatory = $true)]
    [int]$OuterWidth,
    [Parameter(Mandatory = $true)]
    [int]$OuterHeight
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeResize {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
}
"@

$process = Get-Process -Name $ProcessName -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $process) {
    throw "No visible window found for process '$ProcessName'."
}

$noMove = 0x0002
$noZOrder = 0x0004
if (-not [NativeResize]::SetWindowPos($process.MainWindowHandle, [IntPtr]::Zero, 0, 0, $OuterWidth, $OuterHeight, $noMove -bor $noZOrder)) {
    throw 'Could not resize the application window.'
}

Start-Sleep -Milliseconds 750
