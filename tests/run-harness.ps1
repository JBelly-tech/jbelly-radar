# tests/run-harness.ps1 — run every browser harness under tests/harness/ in
# headless Edge (or Chrome) against a running radar.ps1 and report PASS/FAIL.
#
#   .\radar.ps1 -NoOpen -NoSync          # in one window
#   powershell -File tests\run-harness.ps1   # in another
#
# No sync is needed first: when data\trends.json is absent this script seeds
# tests\fixtures\trends.min.json in its place and removes it again afterwards.
#
# Each harness writes "PASS name" / "FAIL name: detail" lines and a final
# "DONE n/total" into <pre id="out">; this script greps the rendered DOM.

[CmdletBinding()]
param([int]$Port = 8477, [string]$Only = '', [string]$Browser = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$harnessDir = Join-Path $root 'tests\harness'

# -Browser wins; then the usual install locations, per-user Chrome included (its
# non-admin installer lands in LOCALAPPDATA, which is not under Program Files);
# then whatever is on PATH. A machine with no Chromium browser says so and how.
if ($Browser) {
    if (-not (Test-Path $Browser)) { Write-Output "FAIL -Browser not found: $Browser"; exit 1 }
    $browserExe = $Browser
} else {
    $browserExe = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe",
        "${env:LOCALAPPDATA}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Chromium\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $browserExe) {
        $browserExe = (Get-Command msedge.exe, chrome.exe, chromium.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Source)
    }
}
if (-not $browserExe) {
    Write-Output 'FAIL no headless browser found (looked for Edge, Chrome and Chromium in the usual locations and on PATH)'
    Write-Output '     pass one explicitly:  powershell -File tests\run-harness.ps1 -Browser "C:\path\to\chrome.exe"'
    exit 1
}

try { Invoke-WebRequest -Uri "http://localhost:$Port/api/status" -UseBasicParsing -TimeoutSec 5 | Out-Null }
catch { Write-Output "FAIL radar.ps1 is not serving on port $Port - start it with .\radar.ps1 -NoOpen -NoSync"; exit 1 }

$files = @(Get-ChildItem -Path $harnessDir -Filter *.html -File | Sort-Object Name)
if ($Only) { $files = @($files | Where-Object { $_.BaseName -like $Only }) }
if ($files.Count -eq 0) { Write-Output 'no harness files'; exit 0 }

# The `live` harness asserts that a real fetch of data/trends.json delivers
# items. That file is generated and git-ignored, so on a fresh clone -- and on
# CI -- it is absent, and the assertion would fail for a reason that has nothing
# to do with the code. Seed a fixed fixture when it is missing and remove it
# afterwards. A real synced file is never touched and never overwritten.
$dataFile = Join-Path $root 'data\trends.json'
$fixture = Join-Path $root 'tests\fixtures\trends.min.json'
$seeded = $false
if (-not (Test-Path $dataFile)) {
    if (-not (Test-Path $fixture)) { Write-Output 'FAIL missing fixture tests\fixtures\trends.min.json'; exit 1 }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dataFile) | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $dataFile -Force
    $seeded = $true
    Write-Output 'seeded data\trends.json from tests\fixtures\trends.min.json'
}

# ── reading the result out of the page ────────────────────────────────────────
# Chromium's --dump-dom stopped producing anything in Edge 153: exit 0, empty
# stdout, no stderr, in every headless mode and with a clean profile, while
# --screenshot still renders, so headless itself is fine. A test runner cannot
# pin a browser version on someone else's machine, so it stopped depending on
# that flag and asks the page over the DevTools protocol instead.
#
# This is the better tool anyway. It reads the exact text the harness prints --
# no HTML to un-escape -- and it polls until the harness writes DONE instead of
# guessing a fixed wait, so a slow harness is not a failure and a fast one is
# not billed for time it never needed.

function Invoke-CdpEvaluate {
    param([string]$WsUrl, [string]$Expression, [int]$TimeoutMs = 5000)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        if (-not $ws.ConnectAsync([uri]$WsUrl, [Threading.CancellationToken]::None).Wait($TimeoutMs)) { return $null }
        $req = (@{ id = 1; method = 'Runtime.evaluate'
                   params = @{ expression = $Expression; returnByValue = $true } } |
                ConvertTo-Json -Depth 5 -Compress)
        $outSeg = New-Object 'System.ArraySegment[byte]' -ArgumentList (, [Text.Encoding]::UTF8.GetBytes($req))
        if (-not $ws.SendAsync($outSeg, 'Text', $true, [Threading.CancellationToken]::None).Wait($TimeoutMs)) { return $null }

        # a reply can arrive across several frames; read until the message ends
        $sb = New-Object System.Text.StringBuilder
        $buf = New-Object byte[] 65536
        do {
            $inSeg = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $buf)
            $t = $ws.ReceiveAsync($inSeg, [Threading.CancellationToken]::None)
            if (-not $t.Wait($TimeoutMs)) { return $null }
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count))
        } while (-not $t.Result.EndOfMessage)

        $reply = $sb.ToString() | ConvertFrom-Json
        if ($reply.result -and $reply.result.result) { return [string]$reply.result.result.value }
        return $null
    }
    catch { return $null }
    finally { $ws.Dispose() }
}

function Get-HarnessOutput {
    param([string]$BrowserExe, [string]$Url, [string]$ProfileDir, [int]$TimeoutSec = 40)
    # a fresh profile every run: a locked or half-written one fails as silence
    if (Test-Path $ProfileDir) { Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    $portFile = Join-Path $ProfileDir 'DevToolsActivePort'

    # port 0 lets Chromium pick a free one and write it to DevToolsActivePort, so
    # two runs on one machine cannot collide the way a fixed port would
    $procArgs = @('--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
                  '--disable-extensions', '--remote-debugging-port=0',
                  "--user-data-dir=$ProfileDir", $Url)
    $p = Start-Process -FilePath $BrowserExe -ArgumentList $procArgs -PassThru -WindowStyle Hidden
    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        $wsUrl = $null
        while ((Get-Date) -lt $deadline -and -not $wsUrl) {
            Start-Sleep -Milliseconds 200
            if (-not (Test-Path $portFile)) { continue }
            try {
                $devPort = @(Get-Content -LiteralPath $portFile -ErrorAction Stop)[0]
                if (-not $devPort) { continue }
                $list = Invoke-RestMethod -Uri "http://127.0.0.1:$devPort/json/list" -TimeoutSec 3
                $target = @($list | Where-Object { $_.type -eq 'page' -and $_.url -like 'http*' }) | Select-Object -First 1
                if ($target) { $wsUrl = $target.webSocketDebuggerUrl }
            } catch { }
        }
        if (-not $wsUrl) { return '' }

        # ask the page for its own output until it says DONE, rather than guess a wait
        $expr = "(document.getElementById('out')||{}).textContent||''"
        $text = ''
        while ((Get-Date) -lt $deadline) {
            $got = Invoke-CdpEvaluate -WsUrl $wsUrl -Expression $expr
            if ($null -ne $got) { $text = $got }
            if ($text -match '(?m)^\s*DONE') { break }
            Start-Sleep -Milliseconds 250
        }
        return $text
    }
    finally {
        if ($p -and -not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(5000) }
    }
}

$failed = 0
try {
foreach ($f in $files) {
    $profileDir = Join-Path $env:TEMP ('radar-harness-' + $f.BaseName)
    $url = "http://localhost:$Port/tests/harness/$($f.Name)"
    $text = Get-HarnessOutput -BrowserExe $browserExe -Url $url -ProfileDir $profileDir
    $lines = @($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $done = $lines | Where-Object { $_ -like 'DONE*' } | Select-Object -Last 1
    $fails = @($lines | Where-Object { $_ -like 'FAIL*' })
    if (-not $done) { Write-Output ("FAIL {0}: harness produced no DONE line (page error?)" -f $f.BaseName); $failed++; continue }
    foreach ($x in $fails) { Write-Output ("FAIL {0}: {1}" -f $f.BaseName, $x.Substring(4).Trim()) }
    if ($fails.Count -gt 0) { $failed++ }
    Write-Output ("{0,-4} {1,-14} {2}" -f $(if ($fails.Count) { 'FAIL' } else { 'OK' }), $f.BaseName, $done)
}
}
finally {
    # never leave a seeded file behind: the next run must see a real sync, or none
    if ($seeded) { Remove-Item -LiteralPath $dataFile -Force -ErrorAction SilentlyContinue }
}

if ($failed -gt 0) { Write-Output ("{0} harness file(s) failed" -f $failed); exit 1 }
Write-Output ("harness OK - {0} file(s)" -f $files.Count)
exit 0
