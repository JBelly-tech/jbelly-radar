# scripts/correct-window-entries.ps1 - demote first sightings that were really
# the fetch window moving, not an item arriving.
#
# On 2026-09-23 the catalogue sources were given a deeper fetch cap
# (`catalogueMax`), which made 1,262 items visible in one sync. Every one was
# written to the ledger as `firstSeenBasis: observed` on that date, including 247
# with more than 100,000 installs. None of them arrived that day. The window
# moved; the world did not.
#
# `observed` is a claim the radar watched an item appear. For these rows it is
# false, and it is the one claim a match report leans on to argue that a record
# beats a search. They are demoted to `snapshot-floor`, which renders everywhere
# as "on the radar by" -- true, and a lower bound, which is exactly what it is.
#
# A genuinely new item from that same sync is demoted too. That cannot be helped:
# nothing distinguishes it in the record, and a floor is the weaker, honest claim.
#
#   pwsh -File scripts/correct-window-entries.ps1 -On 2026-09-23 -DryRun
#   pwsh -File scripts/correct-window-entries.ps1 -On 2026-09-23
#
# Safe to re-run: it only ever weakens a claim, never strengthens one, so a
# second pass finds nothing left to do.
#
# lib/sources.ps1 now prevents this going forward -- a source whose cap grew has
# its new items recorded as floors at the time. This is only for what was already
# written before that existed.

[CmdletBinding()]
param(
    [string]$On = '',
    [string]$LedgerPath = '',
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $LedgerPath) { $LedgerPath = Join-Path $root 'data/ledger.json' }
if (-not $On) { Write-Output 'pass -On <yyyy-MM-dd>: the sync date whose first sightings were a widened window'; exit 1 }
if ($On -notmatch '^\d{4}-\d{2}-\d{2}$') { Write-Output "-On must be yyyy-MM-dd, got '$On'"; exit 1 }
if (-not (Test-Path $LedgerPath)) { Write-Output "no ledger at $LedgerPath"; exit 1 }

$loaded = Get-Content -Raw -Encoding UTF8 $LedgerPath | ConvertFrom-Json
$ledger = [ordered]@{}
foreach ($p in $loaded.PSObject.Properties) { $ledger[$p.Name] = $p.Value }

$demoted = 0
$examined = 0
$biggest = New-Object System.Collections.Generic.List[object]
foreach ($id in @($ledger.Keys)) {
    $row = $ledger[$id]
    $fs = $null
    if ($row.PSObject.Properties.Name -contains 'firstSeen') { $fs = $row.firstSeen }
    # ConvertFrom-Json turns an ISO 8601 string into a [datetime], so "$fs" is a
    # locale-formatted date and a string comparison against yyyy-MM-dd silently
    # matches nothing. Normalise, and do it in UTC, which is what the ledger stores.
    if (-not $fs) { continue }
    $day = ''
    if ($fs -is [datetime]) { $day = $fs.ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }
    else { try { $day = ([datetime]::Parse("$fs")).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue } }
    if ($day -ne $On) { continue }
    $examined++
    $basis = $null
    if ($row.PSObject.Properties.Name -contains 'firstSeenBasis') { $basis = $row.firstSeenBasis }
    if ($basis -ne 'observed') { continue }

    $row.firstSeenBasis = 'snapshot-floor'
    $demoted++
    $metric = 0
    if ($row.PSObject.Properties.Name -contains 'metric' -and $null -ne $row.metric) { $metric = [double]$row.metric }
    if ($metric -gt 0) {
        $title = ''
        if ($row.PSObject.Properties.Name -contains 'title') { $title = "$($row.title)" }
        $unit = ''
        if ($row.PSObject.Properties.Name -contains 'metricLabel') { $unit = "$($row.metricLabel)" }
        $biggest.Add([pscustomobject]@{ title = $title; metric = $metric; unit = $unit })
    }
}

if (-not $Quiet) {
    Write-Output ("rows first seen on {0}          : {1}" -f $On, $examined)
    Write-Output ("  demoted observed -> floor     : {0}" -f $demoted)
    $top = @($biggest | Sort-Object -Property metric -Descending | Select-Object -First 5)
    if ($top.Count -gt 0) {
        Write-Output ''
        Write-Output 'the least believable of them, before the correction:'
        foreach ($b in $top) {
            Write-Output ("  {0,-44} {1,12:N0} {2}" -f $b.title.Substring(0, [Math]::Min(44, $b.title.Length)), $b.metric, $b.unit)
        }
    }
}

if ($DryRun) { Write-Output ''; Write-Output '-DryRun: nothing written'; exit 0 }
if ($demoted -eq 0) { Write-Output ''; Write-Output 'nothing to correct'; exit 0 }

$tmp = $LedgerPath + '.tmp'
[System.IO.File]::WriteAllText($tmp, ($ledger | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmp -Destination $LedgerPath -Force
Write-Output ''
Write-Output ("written: {0}" -f $LedgerPath)
exit 0
