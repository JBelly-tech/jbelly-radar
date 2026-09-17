# radar.ps1 — run JBelly Radar: serve the dashboard on localhost, keep the data
# fresh in the background, open the browser.
#
#   .\radar.ps1                 sync when data is older than -StaleMinutes, then serve;
#                               re-sync every -Every minutes while running
#   .\radar.ps1 -Sync           sync first, whatever the cache age
#   .\radar.ps1 -NoSync         serve the cache, never touch the network
#   .\radar.ps1 -Every 10       background sync interval in minutes (0 = off)
#   .\radar.ps1 -Port 9000      different port
#   .\radar.ps1 -NoOpen         do not launch a browser
#
# Sync runs in a child PowerShell process, so the server keeps answering while
# 27 feeds are being read; the dashboard follows data\status.json for progress.
# The listener binds to localhost only. Nothing is exposed to the network.

[CmdletBinding()]
param(
    [int]$Port = 8477,
    [int]$StaleMinutes = 30,
    [int]$Every = 20,
    [switch]$Sync,
    [switch]$NoSync,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dataDir    = Join-Path $root 'data'
$dataFile   = Join-Path $dataDir 'trends.json'
$statusFile = Join-Path $dataDir 'status.json'
$syncScript = Join-Path $root 'scripts\sync.ps1'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

# -- background sync ----------------------------------------------------------

$script:syncProc = $null
$script:lastSyncStart = [datetime]::MinValue

function Test-Syncing {
    if ($null -eq $script:syncProc) { return $false }
    if ($script:syncProc.HasExited) { $script:syncProc = $null; return $false }
    return $true
}

function Start-BackgroundSync {
    param([string]$Why)
    if (Test-Syncing) { return $false }
    $script:lastSyncStart = [datetime]::UtcNow
    Write-Host ("  {0:HH:mm:ss}  sync started ({1})" -f (Get-Date), $Why) -ForegroundColor DarkGray
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$syncScript`" -Quiet"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $root
    $script:syncProc = [System.Diagnostics.Process]::Start($psi)
    return $true
}

function Get-DataAgeMinutes {
    if (-not (Test-Path $dataFile)) { return [double]::PositiveInfinity }
    return ((Get-Date) - (Get-Item $dataFile).LastWriteTime).TotalMinutes
}

Write-Host ""
Write-Host "  JBelly Radar" -ForegroundColor Yellow
Write-Host ""

$age = Get-DataAgeMinutes
if (-not $NoSync) {
    if ($Sync) { Start-BackgroundSync -Why 'forced' | Out-Null }
    elseif ([double]::IsInfinity($age)) { Start-BackgroundSync -Why 'no data yet' | Out-Null }
    elseif ($age -gt $StaleMinutes) { Start-BackgroundSync -Why ("data is {0:N0} min old" -f $age) | Out-Null }
    else { Write-Host ("  using cached data ({0:N0} min old)" -f $age) -ForegroundColor DarkGray }
}

# -- serve --------------------------------------------------------------------

$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
    '.woff2' = 'font/woff2'; '.md' = 'text/markdown; charset=utf-8'
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
if ($Every -gt 0 -and -not $NoSync) { Write-Host "  re-sync  every $Every min" -ForegroundColor DarkGray }
Write-Host "  stop     Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoOpen) { Start-Process $url | Out-Null }

function Write-Text {
    param($Response, [int]$Status, [string]$ContentType, [string]$Body)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $Status
    $Response.ContentType = $ContentType
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Get-StatusJson {
    $status = $null
    if (Test-Path $statusFile) {
        try { $status = Get-Content -Raw -Encoding UTF8 $statusFile | ConvertFrom-Json } catch { $status = $null }
    }
    if ($null -eq $status) { $status = [pscustomobject]@{ state = 'idle'; done = 0; total = 0; current = ''; sources = @() } }
    # The process is the truth about "running"; the file can lag by one write.
    $running = Test-Syncing
    if ($running -and $status.state -ne 'syncing') { $status.state = 'syncing' }
    if (-not $running -and $status.state -eq 'syncing') { $status.state = 'idle' }
    $status | Add-Member -NotePropertyName 'dataAt' -NotePropertyValue $(if (Test-Path $dataFile) { (Get-Item $dataFile).LastWriteTimeUtc.ToString('o') } else { '' }) -Force
    $status | Add-Member -NotePropertyName 'everyMinutes' -NotePropertyValue $Every -Force
    $status | Add-Member -NotePropertyName 'serverTime' -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
    return ($status | ConvertTo-Json -Depth 5 -Compress)
}

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        # Poll rather than block: Ctrl+C is honoured between requests, and the
        # interval sync can fire while nobody is asking for a page.
        while (-not $task.AsyncWaitHandle.WaitOne(250)) {
            if ($Every -gt 0 -and -not $NoSync -and -not (Test-Syncing)) {
                if (([datetime]::UtcNow - $script:lastSyncStart).TotalMinutes -ge $Every -and (Get-DataAgeMinutes) -ge $Every) {
                    Start-BackgroundSync -Why "interval $Every min" | Out-Null
                }
            }
        }
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
                $started = Start-BackgroundSync -Why 'dashboard'
                Write-Text $res 202 'application/json; charset=utf-8' ('{"started":' + $started.ToString().ToLower() + ',"status":' + (Get-StatusJson) + '}')
                continue
            }

            if ($path -eq '/api/status') {
                Write-Text $res 200 'application/json; charset=utf-8' (Get-StatusJson)
                continue
            }

            if ($path -eq '/api/data') {
                if (Test-Path $dataFile) { Write-Text $res 200 'application/json; charset=utf-8' ([System.IO.File]::ReadAllText($dataFile, [System.Text.Encoding]::UTF8)) }
                else { Write-Text $res 404 'application/json; charset=utf-8' '{"error":"no data yet - a sync is running or run scripts/sync.ps1"}' }
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
    if (Test-Syncing) { try { $script:syncProc.Kill() } catch { } }
    Write-Host ""
    Write-Host "  stopped" -ForegroundColor DarkGray
}
