$ErrorActionPreference = "Stop"

$logFile        = "C:\temp\click-record.log"
$videoFile      = "C:\temp\rdp-click-video.mp4"
$screenshotFile = "C:\temp\rdp-click-screenshot.png"
$ffmpegOutput   = "C:\temp\ffmpeg-output.log"
$ffmpegError    = "C:\temp\ffmpeg-error.log"

function Log($text) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $text"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# پاک‌سازی فایل‌های قبلی
Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Remove-Item $videoFile -Force -ErrorAction SilentlyContinue
Remove-Item $screenshotFile -Force -ErrorAction SilentlyContinue
Remove-Item $ffmpegOutput -Force -ErrorAction SilentlyContinue
Remove-Item $ffmpegError -Force -ErrorAction SilentlyContinue

# چک کردن پورت debug
Log "Checking Chrome debug port 9222..."
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
if (-not $ok) { throw "Chrome debug port 9222 not reachable" }
Log "Chrome debug port OK."

# شروع ضبط
Log "Starting FFmpeg recording (max 300s)..."
$ffmpegArgs = @(
    "-y",
    "-f", "gdigrab",
    "-framerate", "15",
    "-draw_mouse", "1",
    "-i", "desktop",
    "-t", "300",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-pix_fmt", "yuv420p",
    $videoFile
)
$ffmpegProcess = Start-Process -FilePath "ffmpeg.exe" -ArgumentList $ffmpegArgs -PassThru `
    -RedirectStandardOutput $ffmpegOutput -RedirectStandardError $ffmpegError
Log "FFmpeg PID = $($ffmpegProcess.Id)"

Start-Sleep -Seconds 3

# اجرای اسکریپت اینستاگرام
Log "Running instagram_signup.py..."
try {
    $pyScript = Join-Path $env:GITHUB_WORKSPACE "instagram_signup.py"
    python $pyScript 2>&1 | Tee-Object -FilePath $logFile -Append
    $pyExit = $LASTEXITCODE
    Log "Python exited with code $pyExit"
} catch {
    Log "Python error: $($_.Exception.Message)"
    $pyExit = 1
}

Log "Waiting 3s before stopping FFmpeg..."
Start-Sleep -Seconds 3

if (-not $ffmpegProcess.HasExited) {
    Log "Stopping FFmpeg (PID $($ffmpegProcess.Id))..."
    try { taskkill /PID $ffmpegProcess.Id /F | Out-Null } catch {}
    Start-Sleep -Seconds 4
} else {
    Log "FFmpeg already exited."
}

# اسکرین‌شات
Log "Taking final screenshot..."
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bmp = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bmp.Size)
    $bmp.Save($screenshotFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Log "Screenshot saved."
} catch {
    Log "Screenshot error: $($_.Exception.Message)"
}

if (Test-Path $videoFile) {
    $size = (Get-Item $videoFile).Length
    Log "Video size: $size bytes"
} else {
    Log "⚠️  Video file not found"
}

Log "Done."
exit $pyExit
