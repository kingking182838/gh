# ==========================================================
# BRING CHROME TO FRONT + FILL INSTAGRAM SIGNUP FORM
# ==========================================================

$ErrorActionPreference = "Continue"

$logFile        = "C:\temp\click-record.log"
$videoFile      = "C:\temp\rdp-click-video.mp4"
$screenshotFile = "C:\temp\rdp-click-screenshot.png"
$ffmpegOutput   = "C:\temp\ffmpeg-output.log"
$ffmpegError    = "C:\temp\ffmpeg-error.log"

# ── ساخت پوشه و فایل‌های خالی ──
New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
if (-not (Test-Path $logFile))      { New-Item -Path $logFile      -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegOutput)) { New-Item -Path $ffmpegOutput -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegError))  { New-Item -Path $ffmpegError  -ItemType File -Force | Out-Null }

function Log($text) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')  $text"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Log "========== SCRIPT STARTED =========="

# ── Native API قوی برای foreground کردن پنجره ──
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int dwProcessId);

    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;
    public const int SW_SHOW = 5;
    public static readonly IntPtr HWND_TOP = new IntPtr(0);
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP   = 0x0004;
}
"@

# ═══════════════════════════════════════════════════════════
# تابع قوی برای آوردن کروم به جلو
# ═══════════════════════════════════════════════════════════
function ForceChromeToFront {
    param([int]$MaxAttempts = 10)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {

        # پیدا کردن پنجره اصلی کروم
        $proc = Get-Process chrome -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime -Descending | Select-Object -First 1

        if (-not $proc) {
            Log "  [attempt $attempt] Chrome window not found yet..."
            Start-Sleep -Milliseconds 800
            continue
        }

        $hwnd = $proc.MainWindowHandle

        # روش ۱: ShowWindow + BringWindowToTop + SetForegroundWindow
        [NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 200
        [NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_MAXIMIZE) | Out-Null
        Start-Sleep -Milliseconds 300
        [NativeWin]::BringWindowToTop($hwnd) | Out-Null
        [NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_TOPMOST, 0, 0, 0, 0,
            ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE -bor [NativeWin]::SWP_SHOWWINDOW)) | Out-Null
        [NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_TOP, 0, 0, 0, 0,
            ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE -bor [NativeWin]::SWP_SHOWWINDOW)) | Out-Null
        [NativeWin]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 400

        # روش ۲: AttachThreadInput برای دور زدن محدودیت SetForegroundWindow
        try {
            $fgHwnd = [NativeWin]::GetForegroundWindow()
            $fgPid = 0
            [NativeWin]::GetWindowThreadProcessId($fgHwnd, [ref]$fgPid) | Out-Null
            $currentThread = [NativeWin]::GetCurrentThreadId()
            $targetThread = [NativeWin]::GetWindowThreadProcessId($hwnd, [ref]$fgPid)

            if ($currentThread -ne $targetThread) {
                [NativeWin]::AttachThreadInput($currentThread, $targetThread, $true) | Out-Null
                [NativeWin]::SetForegroundWindow($hwnd) | Out-Null
                [NativeWin]::AttachThreadInput($currentThread, $targetThread, $false) | Out-Null
            }
        } catch { }

        # روش ۳: WScript.Shell AppActivate به عنوان fallback
        try {
            $wshell = New-Object -ComObject WScript.Shell
            $wshell.AppActivate($proc.Id) | Out-Null
        } catch { }

        Start-Sleep -Milliseconds 500

        # بررسی اینکه آیا کروم واقعاً foreground شده
        $fgNow = [NativeWin]::GetForegroundWindow()
        if ($fgNow -eq $hwnd) {
            Log "  [attempt $attempt] Chrome is now FOREGROUND ✓"
            return $true
        }

        Log "  [attempt $attempt] Chrome not in foreground yet, retrying..."
        Start-Sleep -Milliseconds 500
    }

    Log "  WARNING: Could not force Chrome to foreground after $MaxAttempts attempts."
    return $false
}

# ═══════════════════════════════════════════════════════════
# مرحله ۱: منتظر باز شدن کروم می‌مانیم و آن را به جلو می‌آوریم
# ═══════════════════════════════════════════════════════════
Log "Waiting for Chrome to appear..."
Start-Sleep -Seconds 3
ForceChromeToFront | Out-Null
Log "Chrome brought to front (initial)."

# ═══════════════════════════════════════════════════════════
# مرحله ۲: انتظار برای لود کامل شدن صفحه اینستاگرام
# ═══════════════════════════════════════════════════════════
Log "Waiting 15 seconds for Instagram page to load..."
Start-Sleep -Seconds 15

# دوباره مطمئن شو کروم جلو هست
ForceChromeToFront | Out-Null
Log "Chrome re-focused after page load."

# ═══════════════════════════════════════════════════════════
# مرحله ۳: شروع FFmpeg در حالت مخفی
# ═══════════════════════════════════════════════════════════
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

$ffmpegProcess = $null
if ($ffmpegExe) {
    Remove-Item $videoFile -Force -ErrorAction SilentlyContinue
    $ffmpegArgs = @(
        "-y","-f","gdigrab","-framerate","30","-draw_mouse","1",
        "-i","desktop","-t","60","-c:v","libx264",
        "-preset","veryfast","-pix_fmt","yuv420p",$videoFile
    )
    try {
        $ffmpegProcess = Start-Process -FilePath $ffmpegExe -ArgumentList $ffmpegArgs `
            -PassThru -RedirectStandardOutput $ffmpegOutput -RedirectStandardError $ffmpegError `
            -WindowStyle Hidden
        Log "FFmpeg started (hidden), PID=$($ffmpegProcess.Id)"
    } catch {
        Log "FFmpeg FAILED to start: $($_.Exception.Message)"
        $ffmpegProcess = $null
    }
} else {
    Log "FFmpeg not found. Skipping video recording."
}

# بعد از شروع FFmpeg دوباره کروم را به جلو بیاور
Start-Sleep -Seconds 2
ForceChromeToFront | Out-Null
Log "Chrome re-focused after FFmpeg start."
Start-Sleep -Seconds 2

# ═══════════════════════════════════════════════════════════
# مرحله ۴: کلیک فیزیکی روی (84, 614)
# ═══════════════════════════════════════════════════════════
$clickX = 84
$clickY = 614

Log "Moving cursor to X=$clickX Y=$clickY..."
[NativeWin]::SetCursorPos($clickX, $clickY) | Out-Null
Start-Sleep -Milliseconds 500

Log "Clicking at ($clickX, $clickY)..."
[NativeWin]::mouse_event([NativeWin]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 150
[NativeWin]::mouse_event([NativeWin]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Log "Click COMPLETED."

Log "Waiting 10 seconds after click..."
Start-Sleep -Seconds 10

# ═══════════════════════════════════════════════════════════
# مرحله ۵: CDP — پر کردن فرم
# ═══════════════════════════════════════════════════════════
Log "Starting CDP..."

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
    } else {
        Log "No page target found."
    }
} else {
    Log "CDP: cannot connect to port 9222"
}

# ── انتظار ۵ ثانیه بعد از ارسال فرم ──
Log "Waiting 5 seconds after submit..."
Start-Sleep -Seconds 5

# ═══════════════════════════════════════════════════════════
# مرحله ۶: اسکرین‌شات
# ═══════════════════════════════════════════════════════════
Log "Taking screenshot..."
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($screen) {
        $w = $screen.Bounds.Width
        $h = $screen.Bounds.Height
        if ($w -le 0) { $w = 1920 }
        if ($h -le 0) { $h = 1080 }
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size($w, $h)))
        $bmp.Save($screenshotFile, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Log "Screenshot saved: $screenshotFile"
    } else {
        Log "PrimaryScreen is null."
    }
} catch {
    Log "Screenshot failed: $($_.Exception.Message)"
}

# ── انتظار برای پایان FFmpeg ──
if ($ffmpegProcess) {
    Log "Waiting for FFmpeg to finish naturally..."
    try {
        $ffmpegProcess.WaitForExit()
        Log "FFmpeg finished. Exit code = $($ffmpegProcess.ExitCode)"
    } catch {
        Log "FFmpeg wait failed: $($_.Exception.Message)"
    }
}

# ── بررسی اندازه فایل‌ها ──
Log "===== File sizes ====="
foreach ($f in @($videoFile, $screenshotFile, $ffmpegOutput, $ffmpegError, $logFile)) {
    if (Test-Path $f) {
        $size = (Get-Item $f).Length
        Log "  $f => $size bytes"
    } else {
        Log "  $f => MISSING"
    }
}

# ── ساخت فایل‌های غایب ──
if (-not (Test-Path $videoFile))      { New-Item -Path $videoFile      -ItemType File -Force | Out-Null; Log "Created placeholder for video." }
if (-not (Test-Path $screenshotFile)) { New-Item -Path $screenshotFile -ItemType File -Force | Out-Null; Log "Created placeholder for screenshot." }
if (-not (Test-Path $ffmpegOutput))   { New-Item -Path $ffmpegOutput   -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegError))    { New-Item -Path $ffmpegError    -ItemType File -Force | Out-Null }

Log "========== ALL COMPLETED =========="
exit 0
