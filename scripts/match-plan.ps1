# scripts/match-plan.ps1 - join a build plan to the catalogue and report coverage.
#
# Answers one question per requirement: is there already a skill or an MCP server
# that covers this, and is it worth anything. It does NOT recommend, rank quality
# or choose. A match means something exists and how much use it has.
#
#   pwsh -File scripts/match-plan.ps1 -Plan config/build.example.json
#   pwsh -File scripts/match-plan.ps1 -Plan mine.json -Top 5
#
# It matches against data/ledger.json - every item the radar has EVER seen - and
# never against data/trends.json, which holds one sync with every source capped.
# Asked against the feed, "no coverage" usually means "not in today's top N",
# which reads identically to "does not exist" and is wrong. That distinction is
# the whole reason this script exists.
#
# Every word it writes lives in config/match-template.json: the wording is
# editorial, and Windows PowerShell reads .ps1 as ANSI, so non-ASCII in a script
# corrupts. This file stays ASCII.
#
# Deterministic: no model call, no network. Same plan + same catalogue = same report.

[CmdletBinding()]
param(
    [string]$Plan = '',
    [int]$Top = 3,
    [string]$OutDir = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Read-Json([string]$Path) {
    if (-not (Test-Path $Path)) { throw "missing $Path" }
    return (Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json)
}

function Get-P {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or '' -eq "$($p.Value)") { return $Default }
    return $p.Value
}

function Format-Line {
    param([string]$Template, [hashtable]$Values)
    $out = $Template
    foreach ($k in $Values.Keys) { $out = $out.Replace('{' + $k + '}', [string]$Values[$k]) }
    return $out
}

if (-not $Plan) { $Plan = Join-Path $root 'config/build.example.json' }
if (-not (Test-Path $Plan)) { Write-Output "no plan at $Plan"; exit 1 }

# NOTE: not $plan -- PowerShell variable names are case-insensitive, so $plan and
# the [string]$Plan parameter are one variable, and the assignment would coerce
# the parsed document back to a string.
$planDoc = Read-Json $Plan
$template = Read-Json (Join-Path $root 'config/match-template.json')
$ledgerPath = Join-Path $root 'data/ledger.json'
if (-not (Test-Path $ledgerPath)) { Write-Output 'no data/ledger.json - run a sync first'; exit 1 }
$ledgerRaw = Read-Json $ledgerPath

# -- the catalogue ------------------------------------------------------------
# Only named rows can be matched. A row with no title is a date and nothing else:
# proof the radar saw something, with no way to say what. They are counted and
# reported rather than quietly dropped, because "no coverage" from a catalogue
# that is partly anonymous is a weaker claim than it looks.

function Get-RowKind($Row) {
    if ((Get-P $Row 'category' '') -eq 'skill') { return 'skill' }
    $tech = @(Get-P $Row 'tech' @())
    if ($tech -contains 'mcp') { return 'mcp' }
    return 'other'
}

# The searchable text is built once for the whole catalogue, not once per
# requirement: a plan has a dozen requirements and the catalogue has thousands of
# rows, so lowercasing them again for each one is the same work done twelve times.
$catalogue = New-Object System.Collections.Generic.List[object]
$anonymous = 0
foreach ($p in $ledgerRaw.PSObject.Properties) {
    $r = $p.Value
    if (-not (Get-P $r 'title' '')) { $anonymous++; continue }
    $catalogue.Add([pscustomobject]@{
        row     = $r
        kind    = (Get-RowKind $r)
        title   = ("" + (Get-P $r 'title' '')).ToLowerInvariant()
        tech    = ((@(Get-P $r 'tech' @()) -join ' ') + ' ' + (@(Get-P $r 'tags' @()) -join ' ')).ToLowerInvariant()
        summary = ("" + (Get-P $r 'summary' '')).ToLowerInvariant()
        author  = ("" + (Get-P $r 'author' '')).ToLowerInvariant()
        metric  = (Get-P $r 'metric' $null)
        unit    = ("" + (Get-P $r 'metricLabel' ''))
        tier    = (Get-P $r 'publisherTier' $null)
    })
}
if ($catalogue.Count -eq 0) { Write-Output 'the ledger holds no named rows - run a sync first'; exit 1 }

# The usage floor is the catalogue's own median, computed here rather than frozen
# into the script, and keyed by KIND AND UNIT.
#
# The unit is the part that is easy to get wrong, and this script got it wrong.
# A kind does not have one unit: skills arrive measured in installs from the
# directory and in stars from GitHub, MCP servers in weekly downloads, uses and
# stars. Taking one median per kind compares them to each other. Measured on the
# live ledger, the single skill median was 82,554 while the median of the 198
# star-measured skills was 918 -- so two of them could ever clear the bar, and
# every GitHub-sourced project was structurally excluded from being called
# strong. The report still said "usage above the catalogue median for its kind",
# which was true and meant nothing.
#
# A unit with too few rows has no trustworthy median, so it gets no usage floor
# at all and those rows lean on the publisher tier instead. Guessing a floor from
# four data points is the same mistake one step smaller.
$minForFloor = 8
$median = @{}
$unitCount = @{}
foreach ($c in $catalogue) {
    if ($null -eq $c.metric) { continue }
    # A number whose unit nobody recorded cannot be compared to anything, so it
    # forms no floor and clears none. That is the same rule one size smaller.
    if (-not $c.unit) { continue }
    $key = $c.kind + '|' + $c.unit
    if (-not $unitCount.ContainsKey($key)) { $unitCount[$key] = New-Object System.Collections.Generic.List[double] }
    $unitCount[$key].Add([double]$c.metric)
}
foreach ($key in $unitCount.Keys) {
    $vals = @($unitCount[$key] | Sort-Object)
    # [math]::Floor, not [int]: PowerShell's [int] cast rounds .5 to EVEN, so
    # [int](11/2) is 6 while [int](13/2) is 6 -- the index walks one past the
    # median for half of all odd counts. Measured on the live ledger: mcp|stars
    # (n=95) read index 48 instead of 47, mcp|uses (n=47) index 24 instead of 23.
    if ($vals.Count -ge $minForFloor) { $median[$key] = $vals[[int][math]::Floor($vals.Count / 2)] }
}

# -- matching -----------------------------------------------------------------
# Word-boundary keyword matching over four fields, strongest field per keyword.
# A hit in the title or a technology tag is worth three times a hit in a summary,
# because a summary mentions what a thing talks to and a title says what it is.

function Test-Word {
    param([string]$Haystack, [string]$Needle)
    if (-not $Haystack -or -not $Needle) { return $false }
    return ($Haystack -match ('\b' + [regex]::Escape($Needle) + '\b'))
}

function Get-Pool {
    param($Mode)
    if ($Mode -eq 'build') { return @($catalogue | Where-Object { $_.kind -eq 'skill' }) }
    if ($Mode -eq 'runtime') { return @($catalogue | Where-Object { $_.kind -eq 'mcp' }) }
    return @($catalogue | Where-Object { $_.kind -ne 'other' })
}

# A keyword that matches a quarter of the pool is not evidence, it is the pool.
#
# Measured: the `assistant` requirement asks for an MCP server, `mode: runtime`
# already narrows the pool to MCP servers, and the keyword "mcp" then matched all
# 440 of them. Every candidate scored identically, the ranking fell through to
# usage, and the report announced "covered" with a random server at the top --
# confidently, and about nothing.
#
# So a keyword is weighed by how much it narrows: one matching more than
# BroadAt of the pool is dropped and NAMED in the report, because a plan whose
# keywords are all that generic has learned something worth knowing.
function Select-Discriminating {
    param($Pool, [string[]]$Keywords, [double]$BroadAt = 0.25)
    $keep = New-Object System.Collections.Generic.List[string]
    $broad = New-Object System.Collections.Generic.List[string]
    $limit = [math]::Max(2, [int]($Pool.Count * $BroadAt))
    foreach ($kw in $Keywords) {
        $k = ("" + $kw).ToLowerInvariant().Trim()
        if (-not $k) { continue }
        $n = 0
        foreach ($c in $Pool) {
            if ((Test-Word $c.title $k) -or (Test-Word $c.tech $k) -or
                (Test-Word $c.summary $k) -or (Test-Word $c.author $k)) { $n++ }
            if ($n -gt $limit) { break }
        }
        if ($n -gt $limit) { $broad.Add($k) } else { $keep.Add($k) }
    }
    return [pscustomobject]@{
        keep  = @($keep | ForEach-Object { $_ })
        broad = @($broad | ForEach-Object { $_ })
    }
}

function Get-Matches {
    param($Pool, [string[]]$Keywords)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in $Pool) {
        $score = 0
        $sharp = $false          # matched where it counts: the title or a tech tag
        $hitWords = New-Object System.Collections.Generic.List[string]
        foreach ($kw in $Keywords) {
            $k = ("" + $kw).ToLowerInvariant().Trim()
            if (-not $k) { continue }
            if ((Test-Word $c.title $k) -or (Test-Word $c.tech $k)) {
                $score += 3; $sharp = $true; $hitWords.Add($k)
            }
            elseif ((Test-Word $c.summary $k) -or (Test-Word $c.author $k)) {
                $score += 1; $hitWords.Add($k)
            }
        }
        if ($score -eq 0) { continue }

        # a known publisher, or usage above the median for THIS unit; a unit with
        # no established floor cannot vouch for anything, so it does not try
        $backed = ($null -ne $c.tier)
        if (-not $backed -and $null -ne $c.metric) {
            $key = $c.kind + '|' + $c.unit
            if ($median.ContainsKey($key)) { $backed = ([double]$c.metric -ge $median[$key]) }
        }
        $out.Add([pscustomobject]@{
            row = $c.row; kind = $c.kind; score = $score; sharp = $sharp
            strong = ($sharp -and $backed); hits = ($hitWords | Select-Object -Unique)
        })
    }
    # rank: match quality, then a known publisher, then usage
    return @($out | Sort-Object `
        @{ Expression = { $_.score }; Descending = $true }, `
        @{ Expression = { if ($null -ne (Get-P $_.row 'publisherTier' $null)) { [int](Get-P $_.row 'publisherTier' 9) } else { 9 } }; Descending = $false }, `
        @{ Expression = { if ($null -ne (Get-P $_.row 'metric' $null)) { [double](Get-P $_.row 'metric' 0) } else { -1 } }; Descending = $true })
}

$stamp = ([datetime]::UtcNow).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$planName = [System.IO.Path]::GetFileNameWithoutExtension($Plan)
if (-not $OutDir) { $OutDir = Join-Path $root ('content/matches/' + $stamp) }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$skillCount = @($catalogue | Where-Object { $_.kind -eq 'skill' }).Count
$mcpCount = @($catalogue | Where-Object { $_.kind -eq 'mcp' }).Count

# -- evaluate once, render twice ----------------------------------------------
# The two languages must report the same findings, so the matching runs once and
# both documents render from the same result.

$results = New-Object System.Collections.Generic.List[object]
foreach ($req in @($planDoc.requirements)) {
    $mode = Get-P $req 'mode' 'build'
    $decision = Get-P $req 'decision' 'open'
    if ($mode -eq 'manual') {
        $results.Add([pscustomobject]@{ req = $req; status = 'manual'; matches = @(); alts = @(); broad = @() })
        continue
    }
    # the capability tags and the chosen technology are keywords too: a plan that
    # says "mcp" should find things tagged mcp without repeating it in keywords
    $words = @()
    $words += @(Get-P $req 'keywords' @())
    $words += @(Get-P $req 'capability' @())
    $choice = Get-P $req 'choice' ''
    if ($choice -and $choice -ne 'undecided') { $words += $choice }
    $words = @($words | Where-Object { $_ } | Select-Object -Unique)

    $pool = Get-Pool -Mode $mode
    $sel = Select-Discriminating -Pool $pool -Keywords $words
    $m = @()
    if (@($sel.keep).Count -gt 0) { $m = Get-Matches -Pool $pool -Keywords $sel.keep }
    $strong = @($m | Where-Object { $_.strong })
    $status = 'none'
    if ($strong.Count -gt 0) { $status = 'covered' } elseif (@($m).Count -gt 0) { $status = 'thin' }

    # Only a requirement the architect left OPEN may have its alternatives raised.
    # A `firm` row was decided before the radar was asked, and reopening it every
    # time something new ships is how a project never ships.
    $alts = New-Object System.Collections.Generic.List[object]
    $altsChecked = ($decision -eq 'open' -and $status -ne 'covered')
    if ($altsChecked) {
        foreach ($a in @(Get-P $req 'alternatives' @())) {
            # Through Select-Discriminating, exactly like the main path. Skipping
            # it here is the same defect that block was written to stop, one
            # branch over: an alternative named `mcp` matched all 466 MCP rows,
            # the ranking fell through to raw usage, and the report answered
            # "covered: <whatever has the most stars>" -- confidently, about
            # nothing. An alternative too broad to discriminate is no evidence
            # that the alternative is covered.
            $asel = Select-Discriminating -Pool $pool -Keywords @($a)
            $am = @()
            if (@($asel.keep).Count -gt 0) { $am = Get-Matches -Pool $pool -Keywords $asel.keep }
            $as = @($am | Where-Object { $_.strong })
            $alts.Add([pscustomobject]@{
                name  = $a
                hit   = $(if ($as.Count -gt 0) { $as[0] } else { $null })
                broad = (@($asel.keep).Count -eq 0)
            })
        }
    }
    # Windows PowerShell 5.1 throws "Argument types do not match" on @() over an
    # empty generic List inside a hashtable literal; copy through the pipeline.
    $altList = @($alts | ForEach-Object { $_ })
    $results.Add([pscustomobject]@{
        req = $req; status = $status; matches = $m; alts = $altList
        broad = @($sel.broad); altsChecked = $altsChecked })
}

function Write-Report {
    param([string]$Lang, $T)

    $sb = New-Object System.Text.StringBuilder
    $add = { param([string]$line) [void]$sb.AppendLine($line) }

    & $add (Format-Line $T.title @{ project = (Get-P $planDoc 'project' $planName) })
    & $add ''
    & $add (Format-Line $T.meta @{ date = $stamp; rows = $catalogue.Count; skills = $skillCount; mcp = $mcpCount })
    & $add ''
    foreach ($l in $T.intro) { & $add $l }
    & $add ''

    $sections = @(
        @{ key = 'covered'; heading = $T.headingCovered },
        @{ key = 'thin';    heading = $T.headingThin },
        @{ key = 'none';    heading = $T.headingNone },
        @{ key = 'manual';  heading = $T.headingManual }
    )

    foreach ($sec in $sections) {
        $rows = @($results | Where-Object { $_.status -eq $sec.key })
        if ($rows.Count -eq 0) { continue }
        & $add $sec.heading
        & $add ''
        foreach ($res in $rows) {
            $req = $res.req
            & $add (Format-Line $T.reqHeading @{ id = (Get-P $req 'id' '?'); need = (Get-P $req 'need' '') })
            & $add ''
            if ($res.status -eq 'manual') {
                & $add $T.manualLine
                & $add ''
                continue
            }
            $choice = Get-P $req 'choice' ''
            if ($choice) { & $add (Format-Line $T.chose @{ choice = $choice }); & $add '' }

            if ($res.status -eq 'none') { & $add $T.noneLine }
            elseif ($res.status -eq 'thin') { & $add (Format-Line $T.thinLine @{ count = $res.matches.Count }) }
            else { & $add (Format-Line $T.coveredLine @{ count = $res.matches.Count }) }
            & $add ''

            foreach ($c in @($res.matches | Select-Object -First $Top)) {
                $r = $c.row
                $who = Get-P $r 'publisherName' ''
                if (-not $who) { $who = Get-P $r 'author' '' }
                if (-not $who) { $who = $T.unattributed }

                $seen = ''
                $fs = Get-P $r 'firstSeen' ''
                if ($fs) {
                    # UTC, like the report's own date: rendering one in local time and
                    # the other in UTC puts an item's first sighting a day after the
                    # report that found it
                    $day = ([datetime]::Parse($fs)).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    if ((Get-P $r 'firstSeenBasis' '') -eq 'observed') { $seen = (Format-Line $T.seenObserved @{ date = $day }) }
                    else { $seen = (Format-Line $T.seenFloor @{ date = $day }) }
                }
                $metric = Get-P $r 'metric' $null
                $metricText = '-'
                if ($null -ne $metric) { $metricText = ('{0:N0}' -f [double]$metric) }
                $techText = ''
                $hits = @($c.hits)
                if ($hits.Count -gt 0) { $techText = ' - ' + ($hits -join ', ') }

                & $add (Format-Line $T.candidate @{ title = (Get-P $r 'title' ''); url = (Get-P $r 'url' ''); who = $who })
                & $add (Format-Line $T.candidateMeta @{
                    metric = $metricText; metricLabel = (Get-P $r 'metricLabel' ''); seen = $seen; tech = $techText })
                $install = Get-P $r 'install' ''
                if ($install) { & $add (Format-Line $T.installLine @{ install = $install }) }
            }
            & $add ''

            if (@($res.alts).Count -gt 0) {
                & $add $T.altHeading
                & $add ''
                foreach ($a in @($res.alts)) {
                    if ($a.broad) { & $add (Format-Line $T.altBroad @{ alt = $a.name }); continue }
                    if ($a.hit) {
                        $hr = $a.hit.row
                        # A figure with no unit, or no figure at all, must not be
                        # printed as one: "(18,176 )" and "(- )" both read as
                        # evidence and are neither. The row still qualified --
                        # through its publisher tier -- so it is reported as
                        # covered, without a number it cannot support.
                        $hm = Get-P $hr 'metric' $null
                        $unit = Get-P $hr 'metricLabel' ''
                        $usage = ''
                        if ($null -ne $hm -and $unit) { $usage = (Format-Line $T.altUsage @{ metric = ('{0:N0}' -f [double]$hm); metricLabel = $unit }) }
                        elseif (Get-P $hr 'publisherName' '') { $usage = (Format-Line $T.altByPublisher @{ who = (Get-P $hr 'publisherName' '') }) }
                        & $add (Format-Line $T.altCovered @{ alt = $a.name; title = (Get-P $hr 'title' ''); usage = $usage })
                    }
                    else { & $add (Format-Line $T.altNone @{ alt = $a.name }) }
                }
                & $add ''
                & $add $T.altAdvice
                & $add ''
            }

            if (@($res.broad).Count -gt 0) {
                & $add (Format-Line $T.broadNote @{ words = (@($res.broad) -join ', ') })
                & $add ''
            }
            # "the alternatives were checked too" is only true when they were.
            # They are raised solely for an `open` requirement that did NOT come
            # back covered, so on the shipped example that note was appearing
            # under four requirements with no alternatives block above it.
            $decision = Get-P $req 'decision' 'open'
            if ($decision -eq 'firm') { & $add $T.firmNote }
            elseif ($res.altsChecked) { & $add $T.openNote }
            else { & $add $T.openCovered }
            & $add ''
        }
    }

    foreach ($l in $T.footer) { & $add $l }

    $path = Join-Path $OutDir ("$planName.$Lang.md")
    [System.IO.File]::WriteAllText($path, $sb.ToString(), $utf8)
    return $path
}

$enPath = Write-Report -Lang 'en' -T $template.en
$arPath = Write-Report -Lang 'ar' -T $template.ar

if (-not $Quiet) {
    Write-Output ("catalogue: {0} named rows ({1} skills, {2} MCP servers), {3} anonymous" -f
        $catalogue.Count, $skillCount, $mcpCount, $anonymous)
    Write-Output 'usage floor, per kind and unit (the catalogue median; a unit with fewer'
    Write-Output ("than {0} rows gets none and leans on the publisher tier instead):" -f $minForFloor)
    foreach ($key in ($unitCount.Keys | Sort-Object)) {
        $parts = $key -split '\|'
        if ($parts[0] -eq 'other') { continue }
        $unitName = $parts[1]
        if (-not $unitName) { $unitName = '(no unit given)' }
        $floor = 'none'
        if ($median.ContainsKey($key)) { $floor = ('{0:N0}' -f $median[$key]) }
        Write-Output ("  {0,-6} {1,-18} n={2,-5} floor {3}" -f $parts[0], $unitName, $unitCount[$key].Count, $floor)
    }
    Write-Output ''
    Write-Output ("{0,-18} {1,-9} {2,-6} {3}" -f 'requirement', 'status', 'hits', 'strongest')
    foreach ($res in $results) {
        $best = ''
        if (@($res.matches).Count -gt 0) { $best = (Get-P $res.matches[0].row 'title' '') }
        Write-Output ("{0,-18} {1,-9} {2,-6} {3}" -f (Get-P $res.req 'id' '?'), $res.status, @($res.matches).Count, $best)
    }
    Write-Output ''
    Write-Output ("  " + $enPath)
    Write-Output ("  " + $arPath)
}
exit 0
