# ==========================================================
# FIXED CHROME WINDOW + FILL INSTAGRAM SIGNUP FORM
# ==========================================================

$ErrorActionPreference = "Continue"

$logFile        = "C:\temp\click-record.log"
$videoFile      = "C:\temp\rdp-click-video.mp4"
$screenshotFile = "C:\temp\rdp-click-screenshot.png"
$ffmpegOutput   = "C:\temp\ffmpeg-output.log"
$ffmpegError    = "C:\temp\ffmpeg-error.log"

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
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;
    public const int SW_SHOW = 5;
    public static readonly IntPtr HWND_TOP = new IntPtr(0);
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP   = 0x0004;
}
"@

# ═══════════════════════════════════════════════════════════
# پیدا کردن پنجره کروم (بدون تغییر z-order)
# ═══════════════════════════════════════════════════════════
function FindChrome {
    for ($i = 1; $i -le 20; $i++) {
        $p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# ═══════════════════════════════════════════════════════════
# مرحله ۱: کروم را پیدا کن، ماکسیمایز کن، TOPMOST دائمی کن
# ═══════════════════════════════════════════════════════════
Log "Waiting for Chrome window..."
$chromeProc = FindChrome
if (-not $chromeProc) {
    Log "FATAL: Chrome window not found!"
    exit 1
}

$hwnd = $chromeProc.MainWindowHandle
Log "Chrome HWND = $hwnd"

# بازیابی و ماکسیمایز
[NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 500
[NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_MAXIMIZE) | Out-Null
Start-Sleep -Milliseconds 800

# تنظیم TOPMOST دائمی — این پنجره روی همه چیز می‌ماند
[NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_TOPMOST, 0, 0, 0, 0,
    ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE -bor [NativeWin]::SWP_SHOWWINDOW)) | Out-Null
Start-Sleep -Milliseconds 300

# فعال کردن
[NativeWin]::BringWindowToTop($hwnd) | Out-Null
[NativeWin]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# تأیید
$fgCheck = [NativeWin]::GetForegroundWindow()
if ($fgCheck -eq $hwnd) {
    Log "Chrome is FOREGROUND and TOPMOST."
} else {
    Log "WARNING: Chrome may not be foreground (fg=$fgCheck, chrome=$hwnd)."
}

# رزولوشن صفحه برای بررسی
$screenW = [NativeWin]::GetSystemMetrics([NativeWin]::SM_CXSCREEN)
$screenH = [NativeWin]::GetSystemMetrics([NativeWin]::SM_CYSCREEN)
Log "Screen resolution: ${screenW}x${screenH}"

# بررسی موقعیت پنجره کروم
$rect = New-Object NativeWin+RECT
[NativeWin]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Log "Chrome rect: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

# ═══════════════════════════════════════════════════════════
# مرحله ۲: انتظار برای لود شدن صفحه اینستاگرام
# ═══════════════════════════════════════════════════════════
Log "Waiting 15 seconds for Instagram page to load..."
Start-Sleep -Seconds 15

# فقط یک بار چک کن که هنوز TOPMOST و foreground هست (بدون تغییر z-order)
$fgCheck2 = [NativeWin]::GetForegroundWindow()
if ($fgCheck2 -ne $hwnd) {
    Log "Chrome lost focus, restoring once..."
    [NativeWin]::BringWindowToTop($hwnd) | Out-Null
    [NativeWin]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    $fgCheck3 = [NativeWin]::GetForegroundWindow()
    Log "After restore: fg=$fgCheck3 (chrome=$hwnd)"
} else {
    Log "Chrome still foreground after page load."
}

# ═══════════════════════════════════════════════════════════
# مرحله ۳: FFmpeg مخفی — بدون هیچ پنجره‌ای که فوکوس بدزدد
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
        # -WindowStyle Hidden + CreateNoWindow
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $ffmpegExe
        $startInfo.Arguments = ($ffmpegArgs -join ' ')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $false

        $ffmpegProcess = New-Object System.Diagnostics.Process
        $ffmpegProcess.StartInfo = $startInfo
        $ffmpegProcess.Start() | Out-Null
        Log "FFmpeg started (hidden, no window), PID=$($ffmpegProcess.Id)"
    } catch {
        Log "FFmpeg FAILED to start: $($_.Exception.Message)"
        $ffmpegProcess = $null
    }
} else {
    Log "FFmpeg not found. Skipping video recording."
}

# ═══════════════════════════════════════════════════════════
# مرحله ۴: تأیید نهایی که کروم هنوز جلو و TOPMOST است
# ═══════════════════════════════════════════════════════════
Start-Sleep -Seconds 2
$fgCheck4 = [NativeWin]::GetForegroundWindow()
if ($fgCheck4 -ne $hwnd) {
    Log "WARNING: Chrome lost focus after FFmpeg start. Restoring..."
    [NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_TOPMOST, 0, 0, 0, 0,
        ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE -bor [NativeWin]::SWP_SHOWWINDOW)) | Out-Null
    [NativeWin]::BringWindowToTop($hwnd) | Out-Null
    [NativeWin]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
} else {
    Log "Chrome still foreground after FFmpeg start."
}

# ═══════════════════════════════════════════════════════════
# مرحله ۵: کلیک فیزیکی روی (84, 614)
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
# مرحله ۶: CDP — پر کردن فرم
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
                el.tagName==='TEXTAREA' ? window.HTMLTextAreaElement.prototype :
                window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto,'value').set;
    setter.call(el, value);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
    el.dispatchEvent(new Event('blur',{bubbles:true}));
    return true;
  }
  function findBySelectors(selectors){
    for(var i=0;i<selectors.length;i++){
      try{
        var el = document.querySelector(selectors[i]);
        if(el) return el;
      }catch(e){}
    }
    return null;
  }
  function fillField(selectors, value, label){
    var el = findBySelectors(selectors);
    if(!el) return label + ':NOT_FOUND';
    try { el.scrollIntoView({block:'center'}); } catch(e){}
    var ok = setNative(el, value);
    return label + ':' + (ok ? 'OK' : 'FAIL');
  }

  var r = [];
  r.push(fillField(["input[name='email']","input[aria-label='Mobile number or email']","input[aria-label*='Mobile']","input[aria-label*='email']"], '$email', 'email'));
  r.push(fillField(["input[name='password']","input[type='password']"], '$password', 'pass'));
  r.push(fillField(["input[name='fullName']","input[aria-label='Full name']","input[aria-label*='Full']"], '$fullname', 'name'));
  r.push(fillField(["input[name='username']","input[aria-label='Username']","input[aria-label*='Username']"], '$username', 'user'));

  var allInputs = document.querySelectorAll('input');
  var inputList = [];
  for(var i=0;i<allInputs.length;i++){
    var inp = allInputs[i];
    inputList.push('[' + i + '] type=' + (inp.type||'?') + ' name=' + (inp.name||'') + ' aria=' + (inp.getAttribute('aria-label')||''));
  }
  r.push('INPUTS_COUNT:' + allInputs.length);
  r.push('INPUTS_LIST:' + inputList.join(' || '));

  var submit = document.querySelector("button[type='submit']");
  if(!submit){
    var all = document.querySelectorAll("div[role='button'], button");
    for(var k=0;k<all.length;k++){
      if(all[k].innerText && all[k].innerText.trim()==='Submit'){ submit = all[k]; break; }
    }
  }
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

Log "Waiting 5 seconds after submit..."
Start-Sleep -Seconds 5

# ═══════════════════════════════════════════════════════════
# مرحله ۷: اسکرین‌شات
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

# ═══════════════════════════════════════════════════════════
# مرحله ۸: انتظار برای پایان FFmpeg
# ═══════════════════════════════════════════════════════════
if ($ffmpegProcess) {
    Log "Waiting for FFmpeg to finish naturally..."
    try {
        $ffmpegProcess.WaitForExit()
        Log "FFmpeg finished. Exit code = $($ffmpegProcess.ExitCode)"
    } catch {
        Log "FFmpeg wait failed: $($_.Exception.Message)"
    }
}

# ── برداشتن TOPMOST از کروم (نظم محیط) ──
try {
    [NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_NOTOPMOST, 0, 0, 0, 0,
        ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE)) | Out-Null
} catch {}

Log "===== File sizes ====="
foreach ($f in @($videoFile, $screenshotFile, $ffmpegOutput, $ffmpegError, $logFile)) {
    if (Test-Path $f) {
        $size = (Get-Item $f).Length
        Log "  $f => $size bytes"
    } else {
        Log "  $f => MISSING"
    }
}

if (-not (Test-Path $videoFile))      { New-Item -Path $videoFile      -ItemType File -Force | Out-Null }
if (-not (Test-Path $screenshotFile)) { New-Item -Path $screenshotFile -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegOutput))   { New-Item -Path $ffmpegOutput   -ItemType File -Force | Out-Null }
if (-not (Test-Path $ffmpegError))    { New-Item -Path $ffmpegError    -ItemType File -Force | Out-Null }

Log "========== ALL COMPLETED =========="
exit 0
