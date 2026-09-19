# ==========================================================
# FILL INSTAGRAM SIGNUP FORM VIA CDP
# ==========================================================

$email    = "kingkngdbjodbno@llf.com"
$password = "Kingking00Q)@)"
$fullname = "fjofjinoervnervnioernvemoe"
$username = "klfeir"
$month    = "1"
$day      = "1"
$year     = "1999"

Log "Connecting to Chrome DevTools..."

$targets = $null
for ($i = 0; $i -lt 20; $i++) {
    try {
        $targets = Invoke-RestMethod "http://localhost:9222/json"
        if ($targets) { break }
    } catch {}
    Start-Sleep -Milliseconds 500
}
if (-not $targets) { throw "Cannot connect to debug port 9222" }

$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
if (-not $page) { throw "No active page" }
Log "Page: $($page.url)"

$wsUrl = $page.webSocketDebuggerUrl
Log "WS: $wsUrl"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
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
  var r = [];

  // Email
  var el = document.querySelector("input[name='email']")
        || document.querySelector("input[aria-label='Mobile number or email']");
  r.push('email:' + (setNative(el, '$email') ? 'OK' : 'FAIL'));

  // Password
  el = document.querySelector("input[type='password']");
  r.push('pass:' + (setNative(el, '$password') ? 'OK' : 'FAIL'));

  // Full name
  el = document.querySelector("input[name='fullName']")
    || document.querySelector("input[aria-label='Full name']");
  r.push('name:' + (setNative(el, '$fullname') ? 'OK' : 'FAIL'));

  // Username
  el = document.querySelector("input[name='username']")
    || document.querySelector("input[aria-label='Username']");
  r.push('user:' + (setNative(el, '$username') ? 'OK' : 'FAIL'));

  // Dropdowns (select مخفی)
  var mSel = document.querySelector("select[title='Month']") || document.querySelector("select[name='month']");
  r.push('month:' + (setNative(mSel, '$month') ? 'OK' : 'FAIL'));

  var dSel = document.querySelector("select[title='Day']") || document.querySelector("select[name='day']");
  r.push('day:' + (setNative(dSel, '$day') ? 'OK' : 'FAIL'));

  var ySel = document.querySelector("select[title='Year']") || document.querySelector("select[name='year']");
  r.push('year:' + (setNative(ySel, '$year') ? 'OK' : 'FAIL'));

  // Submit
  var submit = document.querySelector("button[type='submit']");
  if(!submit){
    var all = document.querySelectorAll("div[role='button'], button");
    for(var i=0;i<all.length;i++){
      if(all[i].innerText && all[i].innerText.trim()==='Submit'){ submit = all[i]; break; }
    }
  }
  if(submit){ submit.click(); r.push('submit:CLICKED'); }
  else { r.push('submit:FAIL'); }

  return r.join(' | ');
})()
"@

$msg = @{
    id = 1
    method = "Runtime.evaluate"
    params = @{ expression = $js; returnByValue = $true }
} | ConvertTo-Json -Compress -Depth 10

Log "Sending CDP command..."

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
Log "Typing COMPLETED."
