# scripts/backfill-ledger.ps1 — rebuild firstSeen and identity in the ledger from
# the daily snapshots.
#
# The ledger (data/ledger.json) records, per item id, the first sync that
# ever saw it. That field is written going forward by Set-RadarMomentum, but the
# radar kept dated full snapshots (data/history/YYYY-MM-DD.json) before the ledger
# existed, and those snapshots prove an earlier sighting. This replays them oldest
# first and lowers firstSeen wherever a snapshot proves the item was already there.
#
# It also restores IDENTITY — title, url, summary, tech, install, publisher. The
# ledger only started carrying those on 2026-09-23, so every row written before
# that is an anonymous date: proof that something existed, with no way to say what.
# The snapshots are full trends.json dumps and still hold all of it, so a row that
# rotated off the radar before the change can be named from the last snapshot that
# saw it. Without this the catalogue starts at the day it was invented rather than
# at the day the record does.
#
#   pwsh -File scripts/backfill-ledger.ps1            # apply
#   pwsh -File scripts/backfill-ledger.ps1 -DryRun    # report, change nothing
#
# Deterministic, no model call, no network. Safe to re-run: firstSeen is only ever
# moved EARLIER, never later, and identity is only ever FILLED IN, never overwritten
# — a live sync is fresher than any snapshot, so it always wins. Replaying the same
# snapshots twice is a no-op.
# It is also the recovery path — a lost ledger can be rebuilt from the snapshots.

[CmdletBinding()]
param(
    [string]$HistoryDir = '',
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $HistoryDir) { $HistoryDir = Join-Path $root 'data/history' }
$ledgerPath = Join-Path (Split-Path -Parent $HistoryDir) 'ledger.json'

function Read-Json([string]$Path) {
    # -Encoding UTF8 also copes with a BOM left by an older run
    return (Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json)
}

if (-not (Test-Path $HistoryDir)) { Write-Output "no history directory at $HistoryDir"; exit 0 }

# The identity a ledger row carries, in the order Set-RadarMomentum writes them, so
# a backfilled row and a freshly written one are indistinguishable in the file.
$identityFields = @('title', 'url', 'summary', 'sourceId', 'category', 'tech', 'install', 'author', 'metricLabel')
$identityAll = $identityFields + @('publisherName', 'publisherTier')

function Get-SnapshotIdentity($Item) {
    $out = [ordered]@{}
    foreach ($f in $identityFields) {
        $p = $Item.PSObject.Properties[$f]
        if ($p -and $null -ne $p.Value -and '' -ne "$($p.Value)") { $out[$f] = $p.Value }
    }
    # the snapshot nests the publisher; the ledger flattens the two fields a matcher reads
    if ($Item.PSObject.Properties['publisher'] -and $Item.publisher) {
        $pn = $Item.publisher.PSObject.Properties['name']
        $pt = $Item.publisher.PSObject.Properties['tier']
        if ($pn -and $pn.Value) { $out['publisherName'] = $pn.Value }
        if ($pt -and $pt.Value) { $out['publisherTier'] = $pt.Value }
    }
    return $out
}

# ── the snapshots, oldest first ───────────────────────────────────────────────
# Order by the generatedAt inside the file, not by the filename or the file's
# mtime: a snapshot can be copied or restored and its mtime then lies.

$snapshots = New-Object System.Collections.Generic.List[object]
foreach ($f in Get-ChildItem -Path $HistoryDir -Filter '*.json' -File) {
    if ($f.Name -notmatch '^\d{4}-\d{2}-\d{2}\.json$') { continue }
    try { $doc = Read-Json $f.FullName } catch { Write-Output "  skipped $($f.Name): unreadable"; continue }
    $items = $null
    if ($doc.PSObject.Properties.Name -contains 'items') { $items = $doc.items } else { $items = $doc }
    if (-not $items) { continue }
    $stamp = $null
    if ($doc.PSObject.Properties.Name -contains 'generatedAt' -and $doc.generatedAt) {
        try { $stamp = ([datetime]::Parse($doc.generatedAt)).ToUniversalTime() } catch { $stamp = $null }
    }
    # a snapshot with no generatedAt still carries its date in the filename
    if (-not $stamp) { $stamp = ([datetime]::ParseExact($f.BaseName, 'yyyy-MM-dd', $null)).ToUniversalTime() }
    $snapshots.Add([pscustomobject]@{ name = $f.Name; at = $stamp; items = @($items) })
}

if ($snapshots.Count -eq 0) { Write-Output 'no dated snapshots to replay'; exit 0 }
$ordered = @($snapshots | Sort-Object at)

if (-not $Quiet) {
    Write-Output ("replaying {0} snapshot(s), {1} to {2}" -f $ordered.Count,
        $ordered[0].at.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture), $ordered[$ordered.Count - 1].at.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture))
}

# ── earliest proven sighting per id ───────────────────────────────────────────

$earliest = @{}
$latest = @{}
$basis = @{}
$identity = @{}
$oldestIso = $ordered[0].at.ToString('o')
foreach ($snap in $ordered) {
    $iso = $snap.at.ToString('o')
    foreach ($it in $snap.items) {
        if (-not $it.id) { continue }
        # newest snapshot wins: we replay oldest first, so the last write is the most
        # recent description the radar ever held of this item
        $identity[$it.id] = (Get-SnapshotIdentity $it)
        if (-not $earliest.ContainsKey($it.id)) {
            $earliest[$it.id] = $iso
            # An item already present in the OLDEST snapshot was not born there - that
            # is simply as far back as the record goes. Its true first sighting is that
            # date or earlier, so it is a floor, never a birth date. An item that first
            # appears in any later snapshot was genuinely absent from the one before,
            # which is a real observation.
            if ($iso -eq $oldestIso) { $basis[$it.id] = 'snapshot-floor' } else { $basis[$it.id] = 'observed' }
        }
        $latest[$it.id] = $iso
    }
    if (-not $Quiet) { Write-Output ("  {0,-20} {1,5} items" -f $snap.name, @($snap.items).Count) }
}

# ── apply to the ledger ───────────────────────────────────────────────────────

$ledger = [ordered]@{}
if (Test-Path $ledgerPath) {
    try {
        $loaded = Read-Json $ledgerPath
        foreach ($p in $loaded.PSObject.Properties) { $ledger[$p.Name] = $p.Value }
    } catch { Write-Output 'ledger unreadable; rebuilding it from the snapshots alone' }
}

$lowered = 0; $added = 0; $unchanged = 0; $named = 0
foreach ($id in $earliest.Keys) {
    $proven = $earliest[$id]
    $provenAt = [datetime]::Parse($proven)
    $ident = $identity[$id]

    if (-not $ledger.Contains($id)) {
        # an item that has since dropped off the radar, but we saw it: it belongs in
        # the record, or the record is not a record
        $fresh = [ordered]@{}
        foreach ($k in $ident.Keys) { $fresh[$k] = $ident[$k] }
        $fresh['firstSeen'] = $proven
        $fresh['firstSeenBasis'] = $basis[$id]
        $fresh['lastSeen'] = $latest[$id]
        $ledger[$id] = [pscustomobject]$fresh
        $added++
        continue
    }

    $row = $ledger[$id]
    $current = $null
    if ($row.PSObject.Properties.Name -contains 'firstSeen') { $current = $row.firstSeen }

    $currentBasis = $null
    if ($row.PSObject.Properties.Name -contains 'firstSeenBasis') { $currentBasis = $row.firstSeenBasis }

    $needs = $false
    if (-not $current) { $needs = $true }
    elseif (-not $currentBasis) { $needs = $true }   # a row from before the basis existed
    else {
        try { if ([datetime]::Parse($current) -gt $provenAt) { $needs = $true } } catch { $needs = $true }
    }

    # fill only. A row that already has a title was named by a sync, and a sync is
    # never older than the snapshots, so overwriting it would trade fresh for stale.
    $needsName = ($row.PSObject.Properties.Name -notcontains 'title') -and ($ident.Count -gt 0)

    if (-not $needs -and -not $needsName) { $unchanged++; continue }

    # rebuild in the order Set-RadarMomentum uses: identity, then dates, then baseline
    $fresh = [ordered]@{}
    if ($needsName) {
        foreach ($k in $ident.Keys) { $fresh[$k] = $ident[$k] }
        $named++
    }
    else {
        foreach ($f in $identityAll) {
            if ($row.PSObject.Properties.Name -contains $f) { $fresh[$f] = $row.$f }
        }
    }
    if ($needs) {
        $fresh['firstSeen'] = $proven; $fresh['firstSeenBasis'] = $basis[$id]; $lowered++
    }
    else {
        $fresh['firstSeen'] = $current; $fresh['firstSeenBasis'] = $currentBasis
    }
    foreach ($p in $row.PSObject.Properties) {
        if ($fresh.Contains($p.Name)) { continue }
        $fresh[$p.Name] = $p.Value
    }
    if (-not $fresh.Contains('lastSeen')) { $fresh['lastSeen'] = $latest[$id] }
    $ledger[$id] = [pscustomobject]$fresh
}

$anonymous = 0
foreach ($k in $ledger.Keys) {
    if ($ledger[$k].PSObject.Properties.Name -notcontains 'title') { $anonymous++ }
}

Write-Output ''
Write-Output ("ids proven earlier by a snapshot : {0}" -f $lowered)
Write-Output ("ids restored to the ledger       : {0}" -f $added)
Write-Output ("ids given back their identity    : {0}" -f $named)
Write-Output ("ids already correct              : {0}" -f $unchanged)
Write-Output ("ledger rows                      : {0}" -f $ledger.Count)
Write-Output ("  still anonymous (no snapshot)  : {0}" -f $anonymous)

if ($DryRun) { Write-Output ''; Write-Output '-DryRun: nothing written'; exit 0 }

$tmp = $ledgerPath + '.tmp'
[System.IO.File]::WriteAllText($tmp, ($ledger | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tmp -Destination $ledgerPath -Force
Write-Output ''
Write-Output ("written: {0}" -f $ledgerPath)
exit 0
