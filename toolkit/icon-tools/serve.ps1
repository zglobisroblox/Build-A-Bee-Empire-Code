# Serves the pictures in ..\ui-icons on this computer only (http://localhost:8617/Coin.png),
# so Roblox Studio can pick them up for uploading. Stops by itself: open /quit, or after 15 minutes.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path (Split-Path -Parent $here) 'ui-icons'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:8617/')
$listener.Start()
"serving $root on http://localhost:8617/"
$until = (Get-Date).AddMinutes(15)
$pending = $null
while ($listener.IsListening -and (Get-Date) -lt $until) {
    if (-not $pending) { $pending = $listener.BeginGetContext($null, $null) }
    if (-not $pending.AsyncWaitHandle.WaitOne(2000)) { continue }
    $context = $listener.EndGetContext($pending)
    $pending = $null
    $name = [System.IO.Path]::GetFileName($context.Request.Url.LocalPath)
    if ($name -eq 'quit') {
        $context.Response.StatusCode = 200
        $context.Response.Close()
        break
    }
    $file = Join-Path $root $name
    if ($name -like '*.png' -and (Test-Path $file)) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $context.Response.ContentType = 'image/png'
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        "sent $name"
    } else {
        $context.Response.StatusCode = 404
    }
    $context.Response.Close()
}
$listener.Stop()
"stopped"
