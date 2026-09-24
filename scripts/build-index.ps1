# scripts/build-index.ps1 - emit the published lookup index, data/index.json.
#
#   pwsh -File scripts/build-index.ps1
#
# The agent skill in skills/ fetches this file, not data/ledger.json. Two
# reasons, and the second is the one that matters:
#
#   Size. The ledger carries fields a lookup never reads -- momentum baselines,
#   the timestamps behind them, the basis of every date. Dropping them and the
#   rows with no title takes it from about 1.5 MB to something a person on a bad
#   connection will tolerate waiting for.
#
#   Contract. The ledger's shape is internal and has changed four times this
#   month. A file that other people's tools fetch must not move under them, so
#   this is a separate, versioned, deliberately boring shape.
#
# Rows with no title are excluded: the skill matches on text, and a row that is
# only a date cannot be matched or shown. Their count is reported in the header
# rather than being silently dropped, because "nothing covers this" from a
# partly anonymous catalogue is a weaker claim than it looks.
#
# Deterministic, no network. Run a sync first; this only reshapes what is there.

[CmdletBinding()]
param(
    [string]$OutFile = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ledgerPath = Join-Path $root 'data/ledger.json'
if (-not $OutFile) { $OutFile = Join-Path $root 'data/index.json' }

if (-not (Test-Path $ledgerPath)) {
    Write-Output 'no data/ledger.json - run a sync first (pwsh -File scripts/sync.ps1)'
    exit 1
}

function Get-P {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or '' -eq "$($p.Value)") { return $Default }
    return $p.Value
}

$loaded = Get-Content -Raw -Encoding UTF8 $ledgerPath | ConvertFrom-Json
$rows = New-Object System.Collections.Generic.List[object]
$anonymous = 0

foreach ($p in $loaded.PSObject.Properties) {
    $r = $p.Value
    $title = Get-P $r 'title' ''
    if (-not $title) { $anonymous++; continue }

    # one row, one shape, short keys -- this file is downloaded, not read by a
    # person, and the key names are repeated once per row
    $row = [ordered]@{
        t = $title
        u = (Get-P $r 'url' '')
        c = (Get-P $r 'category' '')
    }
    $summary = Get-P $r 'summary' ''
    if ($summary) { $row['s'] = $summary }
    $tech = @(Get-P $r 'tech' @())
    if ($tech.Count -gt 0) { $row['k'] = $tech }
    $metric = Get-P $r 'metric' $null
    $unit = Get-P $r 'metricLabel' ''
    # a figure with no unit cannot be compared to anything, so it is not carried
    if ($null -ne $metric -and $unit) { $row['n'] = [double]$metric; $row['nu'] = $unit }
    $install = Get-P $r 'install' ''
    if ($install) { $row['i'] = $install }
    $who = Get-P $r 'publisherName' ''
    if ($who) { $row['p'] = $who }
    $tier = Get-P $r 'publisherTier' $null
    if ($null -ne $tier) { $row['pt'] = [int]$tier }
    $author = Get-P $r 'author' ''
    if ($author -and -not $who) { $row['a'] = $author }
    $seen = Get-P $r 'firstSeen' ''
    if ($seen) {
        try { $row['f'] = ([datetime]::Parse($seen)).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    # a floor is a lower bound, not a birth date; the skill must not print it as one
    if ((Get-P $r 'firstSeenBasis' '') -eq 'observed') { $row['fo'] = $true }

    $rows.Add([pscustomobject]$row)
}

$payload = [pscustomobject]@{
    # bump when a key changes meaning; the skill checks it and says so rather
    # than silently misreading a file it does not understand
    schema     = 1
    builtAt    = ([datetime]::UtcNow).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    source     = 'https://github.com/JBelly-tech/jbelly-radar'
    licence    = 'CC BY 4.0'
    counts     = [pscustomobject]@{
        items     = $rows.Count
        skills    = @($rows | Where-Object { $_.c -eq 'skill' }).Count
        mcp       = @($rows | Where-Object { $_.k -and ($_.k -contains 'mcp') }).Count
        anonymous = $anonymous
    }
    items      = @($rows | ForEach-Object { $_ })
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$tmp = $OutFile + '.tmp'
[System.IO.File]::WriteAllText($tmp, ($payload | ConvertTo-Json -Depth 6 -Compress), $utf8)
Move-Item -LiteralPath $tmp -Destination $OutFile -Force

if (-not $Quiet) {
    $kb = [math]::Round((Get-Item $OutFile).Length / 1KB)
    $wasKb = [math]::Round((Get-Item $ledgerPath).Length / 1KB)
    Write-Output ("index: {0} items ({1} skills, {2} MCP), {3} anonymous rows left out" -f
        $payload.counts.items, $payload.counts.skills, $payload.counts.mcp, $anonymous)
    Write-Output ("  {0}  {1} KB, from a {2} KB ledger" -f $OutFile, $kb, $wasKb)
}
exit 0
