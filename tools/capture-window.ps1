param(
    [Parameter(Mandatory = $true)]
    [string]$ProcessName,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
}
"@

Add-Type -AssemblyName System.Drawing

$process = Get-Process -Name $ProcessName -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $process) {
    throw "No visible window found for process '$ProcessName'."
}

[NativeWindow]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
[NativeWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 750

$rect = New-Object NativeWindow+RECT
if (-not [NativeWindow]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
    throw "Could not read window bounds."
}

[NativeWindow]::SetCursorPos($rect.Left + 8, $rect.Top + 8) | Out-Null
Start-Sleep -Milliseconds 500

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

[pscustomobject]@{
    ProcessId = $process.Id
    Title = $process.MainWindowTitle
    Handle = $process.MainWindowHandle
    Width = $width
    Height = $height
    OutputPath = (Resolve-Path $OutputPath).Path
}
