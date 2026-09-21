# ==========================================================
# FIXED CHROME + FILL INSTAGRAM SIGNUP FORM (CDP VERIFIED)
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
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
}
"@

# ═══════════════════════════════════════════════════════════
# پیدا کردن پنجره کروم
# ═══════════════════════════════════════════════════════════
function FindChrome {
    for ($i = 1; $i -le 20; $i++) {
        $p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

Log "Waiting for Chrome window..."
$chromeProc = FindChrome
if (-not $chromeProc) {
    Log "FATAL: Chrome window not found!"
    exit 1
}

$hwnd = $chromeProc.MainWindowHandle
Log "Chrome HWND = $hwnd"

# ماکسیمایز و TOPMOST دائمی
[NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 500
[NativeWin]::ShowWindow($hwnd, [NativeWin]::SW_MAXIMIZE) | Out-Null
Start-Sleep -Milliseconds 800

[NativeWin]::SetWindowPos($hwnd, [NativeWin]::HWND_TOPMOST, 0, 0, 0, 0,
    ([NativeWin]::SWP_NOMOVE -bor [NativeWin]::SWP_NOSIZE -bor [NativeWin]::SWP_SHOWWINDOW)) | Out-Null
Start-Sleep -Milliseconds 300

[NativeWin]::BringWindowToTop($hwnd) | Out-Null
[NativeWin]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

$fgCheck = [NativeWin]::GetForegroundWindow()
if ($fgCheck -eq $hwnd) {
    Log "Chrome is FOREGROUND and TOPMOST."
} else {
    Log "WARNING: Chrome may not be foreground (fg=$fgCheck, chrome=$hwnd)."
}

$screenW = [NativeWin]::GetSystemMetrics([NativeWin]::SM_CXSCREEN)
$screenH = [NativeWin]::GetSystemMetrics([NativeWin]::SM_CYSCREEN)
Log "Screen resolution: ${screenW}x${screenH}"

$rect = New-Object NativeWin+RECT
[NativeWin]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Log "Chrome rect: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

# ── انتظار برای لود صفحه اینستاگرام ──
Log "Waiting 15 seconds for Instagram page to load..."
Start-Sleep -Seconds 15

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
# FFmpeg مخفی — بدون پنجره
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
# انتظار کوتاه قبل از CDP (بدون کلیک فیزیکی)
# ═══════════════════════════════════════════════════════════
Log "Waiting 5 seconds before CDP..."
Start-Sleep -Seconds 5

# ═══════════════════════════════════════════════════════════
# CDP — پر کردن فرم با بررسی و تلاش مجدد
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
(async function(){
  function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }

  function findBySelectors(selectors){
    for(var i=0;i<selectors.length;i++){
      try{
        var el = document.querySelector(selectors[i]);
        if(el) return el;
      }catch(e){}
    }
    return null;
  }

  function setNativeValue(el, value){
    if(!el) return false;
    try {
      var proto = el.tagName==='SELECT' ? window.HTMLSelectElement.prototype :
                  el.tagName==='TEXTAREA' ? window.HTMLTextAreaElement.prototype :
                  window.HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto,'value').set;
      setter.call(el, value);
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new Event('change',{bubbles:true}));
      el.dispatchEvent(new Event('blur',{bubbles:true}));
      return true;
    } catch(e) { return false; }
  }

  async function fillAndVerify(selectors, value, label, maxAttempts){
    var result = { label: label, found: false, attempts: 0, finalValue: '', ok: false };

    for(var attempt = 1; attempt <= maxAttempts; attempt++){
      result.attempts = attempt;

      var el = findBySelectors(selectors);
      if(!el) {
        await sleep(500);
        continue;
      }
      result.found = true;

      try { el.scrollIntoView({block:'center'}); } catch(e){}
      await sleep(150);

      try { el.focus(); } catch(e){}
      await sleep(100);

      setNativeValue(el, value);
      await sleep(250);

      if(el.value === value){
        result.finalValue = el.value;
        result.ok = true;
        return result;
      }

      await sleep(300);
    }

    var finalEl = findBySelectors(selectors);
    result.finalValue = finalEl ? finalEl.value : '(not found)';
    return result;
  }

  var results = [];

  results.push(await fillAndVerify([
    "input[name='email']",
    "input[aria-label='Mobile number or email']",
    "input[aria-label*='Mobile']",
    "input[aria-label*='email']",
    "input[type='text'][autocomplete='username']"
  ], '$email', 'email', 3));
  await sleep(400);

  results.push(await fillAndVerify([
    "input[name='password']",
    "input[type='password']",
    "input[aria-label='Password']"
  ], '$password', 'pass', 3));
  await sleep(400);

  results.push(await fillAndVerify([
    "input[name='fullName']",
    "input[aria-label='Full name']",
    "input[aria-label*='Full']"
  ], '$fullname', 'name', 3));
  await sleep(400);

  results.push(await fillAndVerify([
    "input[name='username']",
    "input[aria-label='Username']",
    "input[aria-label*='Username']"
  ], '$username', 'user', 3));
  await sleep(500);

  var out = [];
  for(var i=0;i<results.length;i++){
    var r = results[i];
    out.push(r.label + ':' + (r.ok ? 'OK' : (r.found ? 'FAIL' : 'NOT_FOUND')) +
             '(att=' + r.attempts + ',val="' + r.finalValue.substring(0,20) + '")');
  }

  var allInputs = document.querySelectorAll('input');
  var inputList = [];
  for(var k=0;k<allInputs.length;k++){
    var inp = allInputs[k];
    inputList.push('[' + k + '] type=' + (inp.type||'?') +
                   ' name=' + (inp.name||'') +
                   ' aria=' + (inp.getAttribute('aria-label')||'') +
                   ' val="' + (inp.value||'').substring(0,15) + '"');
  }
  out.push('INPUTS_COUNT:' + allInputs.length);
  out.push('INPUTS_LIST:' + inputList.join(' || '));

  var submit = document.querySelector("button[type='submit']");
  if(!submit){
    var btns = document.querySelectorAll("div[role='button'], button");
    for(var b=0;b<btns.length;b++){
      if(btns[b].innerText && btns[b].innerText.trim()==='Submit'){ submit = btns[b]; break; }
    }
  }
  if(submit){
    try { submit.scrollIntoView({block:'center'}); } catch(e){}
    await sleep(300);
    submit.click();
    out.push('submit:CLICKED');
  } else {
    out.push('submit:FAIL');
  }

  return out.join(' | ');
})()
"@
            $msg = @{
                id = 1
                method = "Runtime.evaluate"
                params = @{
                    expression    = $js
                    returnByValue = $true
                    awaitPromise  = $true
                }
            } | ConvertTo-Json -Compress -Depth 10
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
            $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

            $fullResp = ""
            do {
                $buf = New-Object byte[] 65536
                $recvSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
                $result = $ws.ReceiveAsync($recvSeg, $ct).Result
                $fullResp += [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
            } while (-not $result.EndOfMessage)

            Log "CDP Response: $fullResp"

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
# اسکرین‌شات
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
# انتظار برای پایان FFmpeg
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
