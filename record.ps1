# ==========================================================
# RECORD + FILL INSTAGRAM SIGNUP FORM
# ==========================================================

$ErrorActionPreference = "Continue"   # مهم: Continue نه Stop

$logFile        = "C:\temp\click-record.log"
$videoFile      = "C:\temp\rdp-click-video.mp4"
$screenshotFile = "C:\temp\rdp-click-screenshot.png"
$ffmpegOutput   = "C:\temp\ffmpeg-output.log"
$ffmpegError    = "C:\temp\ffmpeg-error.log"

New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null

# ── تابع لاگ ──────────────────────────────────────────────
function Log($text) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')  $text"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# ── پیدا کردن مسیر FFmpeg ─────────────────────────────────
$ffmpegExe = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source
if (-not $ffmpegExe) {
    $candidates = @(
        "C:\ProgramData\chocolatey\bin\ffmpeg.exe",
        "C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg\bin\ffmpeg.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ffmpegExe = $c; break }
    }
}
Log "FFmpeg path: $ffmpegExe"

# ── پیدا کردن و ماکسیمایز کردن پنجره کروم ─────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;
}
"@

$chromeWindow = $null
for ($i = 0; $i -lt 20; $i++) {
    $chromeWindow = Get-Process chrome -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime -Descending | Select-Object -First 1
    if ($chromeWindow) { break }
    Start-Sleep -Milliseconds 500
}

if ($chromeWindow) {
    [NativeWin]::ShowWindow($chromeWindow.MainWindowHandle, [NativeWin]::SW_MAXIMIZE) | Out-Null
    Start-Sleep -Milliseconds 500
    [NativeWin]::SetForegroundWindow($chromeWindow.MainWindowHandle) | Out-Null
    Log "Chrome maximized."
} else {
    Log "WARNING: Chrome window not found. Continuing..."
}

# ── تلاش برای ضبط ویدیو (اگر FFmpeg بود) ──────────────────
$ffmpegProcess = $null
if ($ffmpegExe) {
    Remove-Item $videoFile -Force -ErrorAction SilentlyContinue
    $ffmpegArgs = @(
        "-y","-f","gdigrab","-framerate","30","-draw_mouse","1",
        "-i","desktop","-t","20","-c:v","libx264",
        "-preset","veryfast","-pix_fmt","yuv420p",$videoFile
    )
    try {
        $ffmpegProcess = Start-Process -FilePath $ffmpegExe -ArgumentList $ffmpegArgs `
            -PassThru -RedirectStandardOutput $ffmpegOutput -RedirectStandardError $ffmpegError
        Log "FFmpeg started, PID=$($ffmpegProcess.Id)"
    } catch {
        Log "FFmpeg FAILED to start: $($_.Exception.Message)"
        $ffmpegProcess = $null
    }
} else {
    Log "FFmpeg not found. Skipping video recording."
}

# ── CDP: پر کردن فرم اینستاگرام ────────────────────────────
Log "Waiting 5 seconds before CDP..."
Start-Sleep -Seconds 5

$email    = "kingkngdbjodbno@llf.com"
$password = "Kingking00Q)@)"
$fullname = "fjofjinoervnervnioernvemoe"
$username = "klfeir"

$targets = $null
for ($i = 0; $i -lt 20; $i++) {
    try {
        $targets = Invoke-RestMethod "http://localhost:9222/json" -ErrorAction Stop
        if ($targets) { break }
    } catch {}
    Start-Sleep -Milliseconds 500
}

if ($targets) {
    $page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    if ($page) {
        Log "Page: $($page.url)"
        try {
            $ws = New-Object System.Net.WebSockets.ClientWebSocket
            $ct = [System.Threading.CancellationToken]::None
            $ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $ct).Wait()
            Log "WS connected."

            $js = @"
(function(){
  function setNative(el, value){
    if(!el) return false;
    var proto = el.tagName==='SELECT' ? window.HTMLSelectElement.prototype :
                window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto,'value').set;
    setter.call(el, value);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
    el.dispatchEvent(new Event('blur',{bubbles:true}));
    return true;
  }
  var r = [];
  var el = document.querySelector("input[name='email']");
  r.push('email:' + (setNative(el, '$email') ? 'OK' : 'FAIL'));
  el = document.querySelector("input[type='password']");
  r.push('pass:' + (setNative(el, '$password') ? 'OK' : 'FAIL'));
  el = document.querySelector("input[name='fullName']");
  r.push('name:' + (setNative(el, '$fullname') ? 'OK' : 'FAIL'));
  el = document.querySelector("input[name='username']");
  r.push('user:' + (setNative(el, '$username') ? 'OK' : 'FAIL'));
  var submit = document.querySelector("button[type='submit']");
  if(submit){ submit.click(); r.push('submit:CLICKED'); }
  else { r.push('submit:FAIL'); }
  return r.join(' | ');
})()
"@
            $msg = @{ id=1; method="Runtime.evaluate"; params=@{ expression=$js; returnByValue=$true } } | ConvertTo-Json -Compress -Depth 10
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
            $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

            $buf = New-Object byte[] 16384
            $recvSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
            $result = $ws.ReceiveAsync($recvSeg, $ct).Result
            $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
            Log "CDP Response: $resp"

            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $ct).Wait()
            $ws.Dispose()
        } catch {
            Log "CDP ERROR: $($_.Exception.Message)"
        }
    }
} else {
    Log "CDP: cannot connect to port 9222"
}

# ── اسکرین‌شات نهایی ──────────────────────────────────────
Log "Taking screenshot..."
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($screen) {
        $bmp = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen(0,0,0,0,$screen.Bounds.Size)
        $bmp.Save($screenshotFile, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Log "Screenshot saved."
    }
} catch {
    Log "Screenshot failed: $($_.Exception.Message)"
}

# ── انتظار برای FFmpeg (اگر در حال اجرا بود) ──────────────
if ($ffmpegProcess -and -not $ffmpegProcess.HasExited) {
    Log "Waiting for FFmpeg..."
    $ffmpegProcess.WaitForExit()
    Log "FFmpeg exit code = $($ffmpegProcess.ExitCode)"
}

# ── ساخت فایل‌های لاگ خالی تا artifact حتماً چیزی داشته باشد ──
if (-not (Test-Path $ffmpegOutput)) { New-Item -Path $ffmpegOutput -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegError))  { New-Item -Path $ffmpegError  -ItemType File -Force | Out-Null }

Log "ALL COMPLETED"
exit 0
