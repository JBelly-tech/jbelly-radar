# tests/run-harness.ps1 — run every browser harness under tests/harness/ in
# headless Edge (or Chrome) against a running radar.ps1 and report PASS/FAIL.
#
#   .\radar.ps1 -NoOpen -NoSync          # in one window
#   powershell -File tests\run-harness.ps1   # in another
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

$failed = 0
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

if ($failed -gt 0) { Write-Output ("{0} harness file(s) failed" -f $failed); exit 1 }
Write-Output ("harness OK - {0} file(s)" -f $files.Count)
exit 0
