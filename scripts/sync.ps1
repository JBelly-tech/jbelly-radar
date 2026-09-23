# scripts/sync.ps1 — fetch every enabled source and rewrite data/trends.json.
#
# Headless: safe to run from Task Scheduler. radar.ps1 calls the same function,
# so the dashboard and the scheduled job can never drift apart.
#
#   pwsh -File scripts/sync.ps1

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib/sources.ps1')

if (-not $Quiet) { Write-Host "JBelly Radar - syncing sources" -ForegroundColor Cyan }

$result = Invoke-RadarSync -Root $root -Quiet:$Quiet

$ok     = @($result.sources | Where-Object { $_.status -eq 'ok' }).Count
$failed = @($result.sources | Where-Object { $_.status -eq 'failed' }).Count

if (-not $Quiet) {
    Write-Host ""
    Write-Host ("  {0} items from {1} sources ({2} failed) in {3} ms" -f $result.counts.total, $ok, $failed, $result.durationMs) -ForegroundColor Green
    Write-Host ("  written: data/trends.json") -ForegroundColor DarkGray
}

# A failed source is reported, never fatal: one dead feed must not cost the run.
exit 0
