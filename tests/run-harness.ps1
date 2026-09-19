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
param([int]$Port = 8477, [string]$Only = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$harnessDir = Join-Path $root 'tests\harness'

$browser = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { Write-Output 'FAIL no headless browser (Edge or Chrome) found'; exit 1 }

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

$failed = 0
try {
foreach ($f in $files) {
    $profile = Join-Path $env:TEMP ('radar-harness-' + $f.BaseName)
    $dom = Join-Path $env:TEMP ('radar-harness-' + $f.BaseName + '.html')
    $url = "http://localhost:$Port/tests/harness/$($f.Name)"
    $args = @('--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run', '--disable-extensions',
              "--user-data-dir=$profile", '--virtual-time-budget=8000', '--dump-dom', $url)
    $p = Start-Process -FilePath $browser -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $dom
    $html = ''
    if (Test-Path $dom) { $html = [System.IO.File]::ReadAllText($dom, [System.Text.Encoding]::UTF8) }
    $m = [regex]::Match($html, '<pre id="out"[^>]*>(.*?)</pre>', 'Singleline')
    $lines = @()
    if ($m.Success) { $lines = @(([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

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
