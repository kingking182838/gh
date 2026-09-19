$ErrorActionPreference = "Stop"

$logFile   = "C:\temp\click-record.log"
$videoMp4  = "C:\temp\rdp-click-video.mp4"
$framesDir = "C:\temp\frames"
$ffOut     = "C:\temp\ffmpeg-output.log"
$ffErr     = "C:\temp\ffmpeg-error.log"

function Log($text) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $text"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Remove-Item $videoMp4 -Force -ErrorAction SilentlyContinue
Remove-Item $ffOut -Force -ErrorAction SilentlyContinue
Remove-Item $ffErr -Force -ErrorAction SilentlyContinue
Remove-Item $framesDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $framesDir -Force | Out-Null

Log "Checking Chrome debug port..."
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3
        $ok = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}
if (-not $ok) { throw "Chrome debug port not reachable" }
Log "Chrome debug OK"

Log "Starting FFmpeg..."
$ffArgs = @(
    "-y",
    "-f", "gdigrab",
    "-framerate", "15",
    "-draw_mouse", "1",
    "-i", "desktop",
    "-t", "300",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-pix_fmt", "yuv420p",
    $videoMp4
)

$ffProc = Start-Process -FilePath "ffmpeg.exe" -ArgumentList $ffArgs -PassThru -RedirectStandardOutput $ffOut -RedirectStandardError $ffErr
Log "FFmpeg PID: $($ffProc.Id)"
Start-Sleep -Seconds 3

Log "Running instagram_signup.py..."
$pyScript = Join-Path $env:GITHUB_WORKSPACE "instagram_signup.py"
python $pyScript 2>&1 | Tee-Object -FilePath $logFile -Append
$pyExit = $LASTEXITCODE
Log "Python exit code: $pyExit"

if ($null -ne $ffProc -and -not $ffProc.HasExited) {
    Log "Stopping FFmpeg..."
    try {
        taskkill /PID $ffProc.Id /F 2>&1 | Out-Null
    } catch {
        Log "taskkill failed"
    }
    Start-Sleep -Seconds 3
}

$videoSize = 0
if (Test-Path $videoMp4) {
    $videoSize = (Get-Item $videoMp4).Length
}
Log "Video size: $videoSize bytes"

if ($videoSize -eq 0) {
    Log "FFmpeg produced no video - trying frame fallback"
    $frames = Get-ChildItem $framesDir -Filter *.png -ErrorAction SilentlyContinue
    $frameCount = 0
    if ($null -ne $frames) {
        $frameCount = ($frames | Measure-Object).Count
    }
    Log "Frame count: $frameCount"
    if ($frameCount -gt 0) {
        $framePattern = Join-Path $framesDir "frame_%05d.png"
        ffmpeg -y -framerate 2 -i $framePattern -c:v libx264 -pix_fmt yuv420p -movflags +faststart $videoMp4 2>&1 | Out-Null
        if (Test-Path $videoMp4) {
            Log "Fallback video size: $((Get-Item $videoMp4).Length) bytes"
        }
    }
}

Log "Done"
exit $pyExit
