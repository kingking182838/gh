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

# استفاده از headless=new برای Session 0
$arguments = @(
    "--headless=new",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-session-crashed-bubble",
    "--disable-features=Translate,OptimizationHints",
    "--disable-blink-features=AutomationControlled",
    "--window-size=1366,900",
    "--user-data-dir=$chromeProfile",
    "--remote-debugging-port=9222",
    "--remote-debugging-address=127.0.0.1",
    $targetUrl
)

Write-Host "Starting Chrome (headless=new)..."
$chromeProcess = Start-Process -FilePath $chromePath -ArgumentList $arguments -PassThru
if ($null -eq $chromeProcess) { throw "Chrome failed to start" }
Write-Host "Chrome PID: $($chromeProcess.Id)"

# انتظار برای پورت debug
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
