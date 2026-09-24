# radar.ps1 — run JBelly Radar: serve the dashboard on localhost, keep the data
# fresh in the background, open the browser.
#
#   ./radar.ps1                 sync when data is older than -StaleMinutes, then serve;
#                               re-sync every -Every minutes while running
#   ./radar.ps1 -Sync           sync first, whatever the cache age
#   ./radar.ps1 -NoSync         serve the cache, never touch the network
#   ./radar.ps1 -Every 10       background sync interval in minutes (0 = off)
#   ./radar.ps1 -Port 9000      different port
#   ./radar.ps1 -NoOpen         do not launch a browser
#
# Sync runs in a child PowerShell process, so the server keeps answering while
# ~55 sources are being read; the dashboard follows data/status.json for progress.
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

# -- platform -----------------------------------------------------------------
# $IsWindows exists only on PowerShell 6 and later. On Windows PowerShell 5.1 it
# is undefined, and undefined means Windows, because 5.1 runs nowhere else.
$script:onWindows = $true
if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) { $script:onWindows = [bool]$IsWindows }

# The child sync must run on the SAME PowerShell that started the server, or a
# machine with both installed can run the server on one and the sync on another.
$script:psExe = 'powershell'
try { $script:psExe = ([System.Diagnostics.Process]::GetCurrentProcess()).MainModule.FileName } catch {
    if (Get-Command 'pwsh' -ErrorAction SilentlyContinue) { $script:psExe = 'pwsh' }
}

function Open-InBrowser {
    param([string]$Url)
    # -ExecutionPolicy and the shell-execute URL handler are Windows-only; macOS
    # and Linux each have their own opener and neither errors usefully if it is
    # missing, so a failure here must never take the server down with it.
    try {
        if ($script:onWindows) { Start-Process $Url | Out-Null }
        elseif ($IsMacOS) { & '/usr/bin/open' $Url }
        else { & 'xdg-open' $Url }
    }
    catch { Write-Host ("  could not open a browser - visit {0}" -f $Url) -ForegroundColor DarkGray }
}
$dataDir    = Join-Path $root 'data'
$dataFile   = Join-Path $dataDir 'trends.json'
$statusFile = Join-Path $dataDir 'status.json'
$syncScript = Join-Path $root 'scripts/sync.ps1'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

# -- background sync ----------------------------------------------------------

$script:syncProc = $null
$script:lastSyncStart = [datetime]::MinValue

function Test-Syncing {
    if ($script:syncProc -and -not $script:syncProc.HasExited) { return $true }
    $script:syncProc = $null
    # a sync started elsewhere (Task Scheduler, a previous window) holds data/sync.lock
    $lockPath = Join-Path $dataDir 'sync.lock'
    if (Test-Path $lockPath) {
        $ownerPid = 0
        try { $ownerPid = [int](Get-Content -Raw $lockPath -ErrorAction Stop) } catch { }
        if ($ownerPid -gt 0 -and (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue)) { return $true }
    }
    return $false
}

# Read a file the sync may be replacing at this very moment: share everything,
# never hold the handle longer than the read.
function Read-SharedText {
    param([string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8); try { return $sr.ReadToEnd() } finally { $sr.Close() } }
    finally { $fs.Close() }
}

function Start-BackgroundSync {
    param([string]$Why)
    if (Test-Syncing) { return $false }
    $script:lastSyncStart = [datetime]::UtcNow
    Write-Host ("  {0:HH:mm:ss}  sync started ({1})" -f (Get-Date), $Why) -ForegroundColor DarkGray
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:psExe
    # -ExecutionPolicy is a Windows-only parameter: pwsh on Linux and macOS
    # rejects it outright rather than ignoring it.
    $policy = ''
    if ($script:onWindows) { $policy = '-ExecutionPolicy Bypass ' }
    $psi.Arguments = "-NoProfile $policy-File `"$syncScript`" -Quiet"
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
    Write-Host "  try: ./radar.ps1 -Port 9000" -ForegroundColor DarkGray
    exit 1
}

$url = "http://localhost:$Port/app/"
Write-Host "  serving  $url" -ForegroundColor Green
if ($Every -gt 0 -and -not $NoSync) { Write-Host "  re-sync  every $Every min" -ForegroundColor DarkGray }
Write-Host "  stop     Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoOpen) { Open-InBrowser -Url $url }

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
        try { $status = (Read-SharedText $statusFile) | ConvertFrom-Json } catch { $status = $null }
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
                # A cross-origin POST with no custom header is a "simple request":
                # the browser sends it without a preflight, so any page open in
                # any tab could make this machine fetch 54 sources. The reply is
                # not readable cross-origin, so nothing leaks -- but nobody
                # else's page gets to spend your bandwidth either.
                #
                # Sec-Fetch-Site is sent by every current browser and says where
                # the request came from; a request without it is not from a
                # browser at all (curl, a script) and is allowed, because those
                # can run sync.ps1 directly anyway and blocking them would only
                # break tooling.
                $site = $req.Headers['Sec-Fetch-Site']
                $origin = $req.Headers['Origin']
                $sameOrigin = (-not $site) -or ($site -eq 'same-origin') -or ($site -eq 'none')
                if (-not $sameOrigin) {
                    Write-Text $res 403 'application/json; charset=utf-8' ('{"error":"cross-origin sync refused","origin":' + (ConvertTo-Json ("$origin")) + '}')
                    continue
                }
                $started = Start-BackgroundSync -Why 'dashboard'
                Write-Text $res 202 'application/json; charset=utf-8' ('{"started":' + $started.ToString().ToLower() + ',"status":' + (Get-StatusJson) + '}')
                continue
            }

            if ($path -eq '/api/status') {
                Write-Text $res 200 'application/json; charset=utf-8' (Get-StatusJson)
                continue
            }

            if ($path -eq '/api/data') {
                if (Test-Path $dataFile) { Write-Text $res 200 'application/json; charset=utf-8' (Read-SharedText $dataFile) }
                else { Write-Text $res 404 'application/json; charset=utf-8' '{"error":"no data yet - a sync is running or run scripts/sync.ps1"}' }
                continue
            }

            # A directory resolves to its index, the way any static host behaves:
            # /app/ -> /app/index.html, /app/ops/ -> /app/ops/index.html. Naming each
            # directory here instead would mean editing the server to add a page.
            if ($path -eq '/app') { $path = '/app/' }
            if ($path.EndsWith('/')) { $path = $path + 'index.html' }

            # Static file, confined to the project folder.
            #
            # The URL separator is left as '/'. Windows accepts it everywhere --
            # GetFullPath, Test-Path and File::Open all normalise it -- and on
            # Linux and macOS it is already the separator, so one spelling is
            # correct on every platform and the rewrite this line used to do was
            # work nobody needed.
            #
            # It was NOT the portability bug it looks like. '\' is an ordinary
            # filename character on Unix, so the rewritten path reads as one that
            # could never resolve -- yet the CI browser harness served five static
            # files from Ubuntu with the rewrite still in place, so something in
            # the Join-Path/GetFullPath chain was absorbing it. Removing it is a
            # simplification, A/B tested byte-identical on Windows including the
            # traversal guard, not a fix for a break anyone observed.
            #
            # GetFullPath still collapses '..', and the StartsWith check below is
            # what actually confines the result to the project folder.
            $relative = $path.TrimStart('/')

            # The dashboard, the harness, the config the page reads and the data
            # are the whole of what this server has any business handing out.
            # Without a list it served the entire working directory: verified,
            # GET /.git/config returned the file. On a developer's machine that
            # file can hold a credential, and .git beside it holds every version
            # of everything else. Rejecting any segment that begins with a dot
            # covers .git, .env and every other dotfile in one rule, including
            # inside an allowed folder.
            $allowedRoots = @('app', 'config', 'data', 'tests')
            $segments = @($relative -split '/' | Where-Object { $_ })
            $hidden = @($segments | Where-Object { $_.StartsWith('.') }).Count -gt 0
            if ($segments.Count -eq 0 -or $hidden -or ($allowedRoots -notcontains $segments[0].ToLowerInvariant())) {
                Write-Text $res 404 'text/plain; charset=utf-8' 'not found'
                continue
            }

            $full = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
                Write-Text $res 404 'text/plain; charset=utf-8' 'not found'
                continue
            }

            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            $type = 'application/octet-stream'
            if ($mime.ContainsKey($ext)) { $type = $mime[$ext] }

            $fsr = [System.IO.File]::Open($full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try { $ms = New-Object System.IO.MemoryStream; $fsr.CopyTo($ms); $bytes = $ms.ToArray() } finally { $fsr.Close() }
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
