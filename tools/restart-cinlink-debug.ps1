param(
    [int]$Port = 9222
)

$main = Get-Process CinLink -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $main) {
    throw 'CinLink main window not found.'
}

$null = $main.CloseMainWindow()
if (-not $main.WaitForExit(10000)) {
    throw 'CinLink did not exit after a normal close; stopped before forcing termination.'
}

$exePath = 'D:\Users\chen\AppData\Local\Programs\CinLink\CinLink.exe'
Start-Process -FilePath $exePath -ArgumentList "--remote-debugging-port=$Port"

$deadline = (Get-Date).AddSeconds(20)
$targets = $null
do {
    Start-Sleep -Milliseconds 500
    try {
        $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
    }
    catch {
        $targets = $null
    }
} until ($targets -or (Get-Date) -gt $deadline)

if (-not $targets) {
    throw 'CinLink restarted but the debug endpoint did not become available.'
}

$targets | Select-Object id, type, title, url, webSocketDebuggerUrl
