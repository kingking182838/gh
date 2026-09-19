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

$args1 = "--no-first-run"
$args2 = "--no-default-browser-check"
$args3 = "--disable-session-crashed-bubble"
$args4 = "--disable-features=Translate,OptimizationHints"
$args5 = "--disable-blink-features=AutomationControlled"
$args6 = "--start-maximized"
$args7 = "--user-data-dir=$chromeProfile"
$args8 = "--remote-debugging-port=9222"
$args9 = "--remote-debugging-address=127.0.0.1"

$argList = @($args1, $args2, $args3, $args4, $args5, $args6, $args7, $args8, $args9, $targetUrl)

Write-Host "Starting Chrome..."
$chromeProcess = Start-Process -FilePath $chromePath -ArgumentList $argList -PassThru
if ($null -eq $chromeProcess) { throw "Chrome failed to start" }
Write-Host "Chrome PID: $($chromeProcess.Id)"

$ok = $false
for ($i = 0; $i -lt 40; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3
        Write-Host "Chrome debug ready"
        $ok = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
if (-not $ok) { throw "Chrome debug port 9222 not reachable" }
