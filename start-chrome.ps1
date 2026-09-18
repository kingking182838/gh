$ErrorActionPreference = "Stop"

$chromePath = $env:CHROME_PATH
if ([string]::IsNullOrWhiteSpace($chromePath)) { throw "CHROME_PATH empty" }
if (-not (Test-Path $chromePath)) { throw "Chrome exe not found" }

$chromeProfile = "C:\temp\ChromeProfile"
$targetUrl = "about:blank"

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
    "--user-data-dir=$chromeProfile",
    "--remote-debugging-port=9222",
    "--remote-debugging-address=127.0.0.1",
    $targetUrl
)

Write-Host "Starting Chrome..."
$chromeProcess = Start-Process -FilePath $chromePath -ArgumentList $arguments -PassThru
Write-Host "Chrome PID: $($chromeProcess.Id)"

# صبر تا پورت debug باز بشه
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3
        Write-Host "✅ Chrome debug ready"
        $ok = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
if (-not $ok) { throw "Chrome debug port 9222 not reachable" }

# چک اینکه پنجره داره یا نه
Start-Sleep -Seconds 3
$win = Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
if ($null -eq $win) {
    Write-Host "⚠️  Chrome window not found (session 0 - no desktop)"
    Write-Host "ℹ️  Video recording will use CDP screenshots"
} else {
    Write-Host "✅ Chrome window found: HWND=$($win.MainWindowHandle)"
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public const int SW_MAXIMIZE = 3;
}
"@
    [Win]::ShowWindow($win.MainWindowHandle, [Win]::SW_MAXIMIZE) | Out-Null
    [Win]::SetForegroundWindow($win.MainWindowHandle) | Out-Null
}
