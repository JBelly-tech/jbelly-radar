# radar.ps1 — start JBelly Radar: sync if the data is stale, serve the dashboard
# on localhost, open the browser.
#
#   .\radar.ps1                 sync when data is older than 30 minutes, then serve
#   .\radar.ps1 -Sync           always sync first
#   .\radar.ps1 -NoSync         serve whatever is cached
#   .\radar.ps1 -Port 9000      different port
#   .\radar.ps1 -NoOpen         do not launch a browser
#
# The listener binds to localhost only. Nothing is exposed to the network.

[CmdletBinding()]
param(
    [int]$Port = 8477,
    [int]$StaleMinutes = 30,
    [switch]$Sync,
    [switch]$NoSync,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'lib\sources.ps1')

$dataFile = Join-Path $root 'data\trends.json'

# -- 1. refresh on start ------------------------------------------------------

function Get-DataAgeMinutes {
    if (-not (Test-Path $dataFile)) { return [double]::PositiveInfinity }
    return ((Get-Date) - (Get-Item $dataFile).LastWriteTime).TotalMinutes
}

$age = Get-DataAgeMinutes
$shouldSync = $false
if ($Sync) { $shouldSync = $true }
elseif ($NoSync) { $shouldSync = $false }
elseif ($age -gt $StaleMinutes) { $shouldSync = $true }

Write-Host ""
Write-Host "  JBelly Radar" -ForegroundColor Yellow
Write-Host ""

if ($shouldSync) {
    $why = 'forced'
    if (-not $Sync) {
        $why = 'no data yet'
        if ([double]::IsInfinity($age) -eq $false) { $why = ("data is {0:N0} min old" -f $age) }
    }
    Write-Host "  syncing ($why)" -ForegroundColor DarkGray
    Invoke-RadarSync -Root $root | Out-Null
    Write-Host ""
}
elseif (Test-Path $dataFile) {
    Write-Host ("  using cached data ({0:N0} min old)" -f $age) -ForegroundColor DarkGray
}

# -- 2. serve -----------------------------------------------------------------

$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
    '.woff2' = 'font/woff2'; '.map' = 'application/json'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() }
catch {
    Write-Host "  cannot listen on port $Port - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  try: .\radar.ps1 -Port 9000" -ForegroundColor DarkGray
    exit 1
}

$url = "http://localhost:$Port/app/"
Write-Host "  serving  $url" -ForegroundColor Green
Write-Host "  stop     Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoOpen) { Start-Process $url | Out-Null }

function Write-Text {
    param($Response, [int]$Status, [string]$ContentType, [string]$Body)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $Status
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        # Poll rather than block, so Ctrl+C is honoured between requests.
        while (-not $task.AsyncWaitHandle.WaitOne(250)) { }
        $ctx = $task.GetAwaiter().GetResult()

        $req = $ctx.Request
        $res = $ctx.Response
        $path = [uri]::UnescapeDataString($req.Url.AbsolutePath)

        try {
            if ($path -eq '/' -or $path -eq '') {
                $res.StatusCode = 302
                $res.RedirectLocation = '/app/'
                $res.Close()
                continue
            }

            if ($path -eq '/api/sync' -and $req.HttpMethod -eq 'POST') {
                Write-Host ("  sync requested {0:HH:mm:ss}" -f (Get-Date)) -ForegroundColor DarkGray
                $result = Invoke-RadarSync -Root $root -Quiet
                Write-Text $res 200 'application/json; charset=utf-8' ($result | ConvertTo-Json -Depth 8 -Compress)
                continue
            }

            if ($path -eq '/api/data') {
                if (Test-Path $dataFile) { Write-Text $res 200 'application/json; charset=utf-8' (Get-Content -Raw -Encoding UTF8 $dataFile) }
                else { Write-Text $res 404 'application/json; charset=utf-8' '{"error":"no data - run scripts/sync.ps1"}' }
                continue
            }

            if ($path -eq '/app/' -or $path -eq '/app') { $path = '/app/index.html' }

            # Static file, confined to the project folder.
            $relative = $path.TrimStart('/').Replace('/', '\')
            $full = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
                Write-Text $res 404 'text/plain; charset=utf-8' 'not found'
                continue
            }

            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            $type = 'application/octet-stream'
            if ($mime.ContainsKey($ext)) { $type = $mime[$ext] }

            $bytes = [System.IO.File]::ReadAllBytes($full)
            $res.StatusCode = 200
            $res.ContentType = $type
            $res.Headers['Cache-Control'] = 'no-store'
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.OutputStream.Close()
        }
        catch {
            try { Write-Text $res 500 'application/json; charset=utf-8' (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress) } catch { }
            Write-Host ("  error on {0}: {1}" -f $path, $_.Exception.Message) -ForegroundColor DarkRed
        }
    }
}
finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
    Write-Host ""
    Write-Host "  stopped" -ForegroundColor DarkGray
}
