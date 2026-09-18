$ErrorActionPreference = "Stop"

$chromePath = $env:CHROME_PATH
if ([string]::IsNullOrWhiteSpace($chromePath)) { throw "CHROME_PATH empty" }
if (-not (Test-Path $chromePath)) { throw "Chrome exe not found" }

$chromeProfile = "C:\temp\ChromeProfile"
$targetUrl = "about:blank"

# اگه پروفایل قبلی هست، پاکش کن
if (Test-Path $chromeProfile) {
    Remove-Item $chromeProfile -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $chromeProfile -Force | Out-Null

$arguments = @(
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-session-crashed-bubble",
    "--disable-features=Translate,OptimizationHints",
    "--disable-blink-features=AutomationControlled",
    "--start-maximized",
    "--new-window",
    "--user-data-dir=$chromeProfile",
    "--remote-debugging-port=9222",
    "--remote-debugging-address=127.0.0.1",
    $targetUrl
)

Write-Host "Starting Chrome..."
$chromeProcess = Start-Process -FilePath $chromePath -ArgumentList $arguments -PassThru
if ($null -eq $chromeProcess) { throw "Chrome failed to start" }
Write-Host "Chrome PID: $($chromeProcess.Id)"

Start-Sleep -Seconds 10

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ChromeWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    public const int SW_MAXIMIZE = 3;
}
"@

$chromeWindow = Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

if ($null -eq $chromeWindow) { throw "Chrome window not found" }

[ChromeWindow]::ShowWindow($chromeWindow.MainWindowHandle, [ChromeWindow]::SW_MAXIMIZE) | Out-Null
Start-Sleep -Milliseconds 800
[ChromeWindow]::SetForegroundWindow($chromeWindow.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 2

# تست پورت debug
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 10
    Write-Host "✅ Chrome debug ready"
    Write-Host $resp.Content
} catch {
    throw "Chrome debug port not ready: $($_.Exception.Message)"
}
