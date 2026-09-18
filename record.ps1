$ErrorActionPreference = "Stop"

$logFile   = "C:\temp\click-record.log"
$videoMp4  = "C:\temp\rdp-click-video.mp4"
$framesDir = "C:\temp\frames"

function Log($text) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $text"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Remove-Item $videoMp4 -Force -ErrorAction SilentlyContinue
Remove-Item $framesDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $framesDir -Force | Out-Null

Log "Checking Chrome debug port..."
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 3
        $ok = $true; break
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ok) { throw "Chrome debug port not reachable" }
Log "Chrome debug OK."

# چک اینکه دسکتاپ تعاملی داریم یا نه
$hasDesktop = $false
try {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($null -ne $screen) { $hasDesktop = $true }
} catch {}
if ($null -ne (Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })) {
    $hasDesktop = $true
}

Log "hasDesktop=$hasDesktop"

# ── شروع FFmpeg (فقط اگه دسکتاپ داریم) ─────────────
$ffProc = $null
if ($hasDesktop) {
    Log "Starting FFmpeg gdigrab recording..."
    $ffArgs = @(
        "-y", "-f", "gdigrab", "-framerate", "15",
        "-draw_mouse", "1", "-i", "desktop",
        "-t", "300",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        $videoMp4
    )
    $ffProc = Start-Process -FilePath "ffmpeg.exe" -ArgumentList $ffArgs -PassThru `
        -RedirectStandardOutput "C:\temp\ffmpeg-output.log" `
        -RedirectStandardError "C:\temp\ffmpeg-error.log"
    Log "FFmpeg PID = $($ffProc.Id)"
    Start-Sleep -Seconds 3
} else {
    Log "No desktop available — using CDP screenshot fallback (instagram_signup.py handles it)"
}

# ── اجرای اسکریپت اینستاگرام ─────────────────────
Log "Running instagram_signup.py..."
$pyScript = Join-Path $env:GITHUB_WORKSPACE "instagram_signup.py"
python $pyScript 2>&1 | Tee-Object -FilePath $logFile -Append
$pyExit = $LASTEXITCODE
Log "Python exited with code $pyExit"

# ── توقف FFmpeg ─────────────────────────────────
if ($null -ne $ffProc -and -not $ffProc.HasExited) {
    Log "Stopping FFmpeg..."
    try { taskkill /PID $ffProc.Id /F | Out-Null } catch {}
    Start-Sleep -Seconds 3
}

# ── اگه FFmpeg ویدیو نساخت، از فریم‌ها بساز ───────
if (-not (Test-Path $videoMp4) -or (Get-Item $videoMp4).Length -eq 0) {
    $frameCount = (Get-ChildItem $framesDir -Filter *.png -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($frameCount -gt 0) {
        Log "FFmpeg failed — encoding from $frameCount CDP frames..."
        ffmpeg -y -framerate 2 -i "$framesDir\frame_%05d.png" `
            -c:v libx264 -pix_fmt yuv420p -movflags +faststart $videoMp4 2>&1 | Out-Null
    } else {
        Log "⚠️  No video and no frames"
    }
}

if (Test-Path $videoMp4) {
    Log "Video size: $((Get-Item $videoMp4).Length) bytes"
}

Log "Done."
exit $pyExit
