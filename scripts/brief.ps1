# scripts/brief.ps1 - write a dated, bilingual brief for one business vertical.
#
# Joins two things the radar already holds: the hand-written judgement in
# config/taxonomy.json (which technologies matter for this industry, and why),
# and the evidence in data/trends.json (what actually moved, with its heat and
# its publisher). The judgement leads and the radar corroborates, never the
# reverse, or the brief becomes a list of whatever churned this week.
#
#   pwsh -File scripts/brief.ps1 -List
#   pwsh -File scripts/brief.ps1 -Vertical logistics
#   pwsh -File scripts/brief.ps1 -Vertical fintech -PerTech 4
#   pwsh -File scripts/brief.ps1 -All
#
# Citations are FROZEN into the file. At the measured churn rate a brief that
# points at the live radar loses about a sixth of its links within a day, so the
# title, url, publisher and heat are copied in at the moment of writing, each
# with the date it was seen and whether that date was observed or is only a floor.
#
# Every word it writes lives in config/brief-template.json, not here: the wording
# of a published brief is editorial, and Windows PowerShell reads .ps1 as ANSI,
# so non-ASCII text in a script corrupts. This file stays ASCII.
#
# Deterministic: no model call, no network. The same inputs give the same brief.

[CmdletBinding()]
param(
    [string]$Vertical = '',
    [int]$PerTech = 3,
    [string]$OutDir = '',
    [switch]$All,
    [switch]$List,
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

# one substitution helper, so a template string never has to be built by hand
function Format-Line {
    param([string]$Template, [hashtable]$Values)
    $out = $Template
    foreach ($k in $Values.Keys) { $out = $out.Replace('{' + $k + '}', [string]$Values[$k]) }
    return $out
}

$taxonomy = Read-Json (Join-Path $root 'config/taxonomy.json')

if ($List) {
    Write-Output 'verticals:'
    foreach ($v in $taxonomy.verticals) {
        Write-Output ("  {0,-14} {1}" -f $v.id, $v.label)
    }
    exit 0
}
if (-not $Vertical -and -not $All) {
    Write-Output 'pass -Vertical <id>, or -All, or -List to see the ids'
    exit 1
}

$template = Read-Json (Join-Path $root 'config/brief-template.json')
$data = Read-Json (Join-Path $root 'data/trends.json')
$items = @($data.items)
if ($items.Count -eq 0) { Write-Output 'no items - run a sync first'; exit 1 }
$okSources = @($data.sources | Where-Object { $_.status -eq 'ok' }).Count

# technology labels, so a brief names a tag the way a reader would
$label = @{}
$labelAr = @{}
foreach ($t in $taxonomy.technologies) {
    $label[$t.tag] = (Get-P $t 'label' $t.tag)
    $labelAr[$t.tag] = (Get-P $t 'label_ar' (Get-P $t 'label' $t.tag))
}

$targets = @()
if ($All) { $targets = @($taxonomy.verticals) }
else {
    $match = @($taxonomy.verticals | Where-Object { $_.id -eq $Vertical })
    if ($match.Count -eq 0) { $match = @($taxonomy.verticals | Where-Object { $_.id -like "$Vertical*" }) }
    if ($match.Count -eq 0) { Write-Output "no vertical '$Vertical' - run with -List"; exit 1 }
    $targets = @($match[0])
}

$stamp = ([datetime]::UtcNow).ToString('yyyy-MM-dd')
if (-not $OutDir) { $OutDir = Join-Path $root ('content/briefs/' + $stamp) }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Brief {
    param($Vertical, [string]$Lang, $T, [hashtable]$Labels)

    $sb = New-Object System.Text.StringBuilder
    $add = { param([string]$line) [void]$sb.AppendLine($line) }

    $vName = if ($Lang -eq 'ar') { Get-P $Vertical 'label_ar' $Vertical.label } else { $Vertical.label }
    & $add (Format-Line $T.title @{ vertical = $vName })
    & $add ''
    & $add (Format-Line $T.meta @{ date = $stamp; items = $items.Count; sources = $okSources })
    & $add ''
    foreach ($l in $T.intro) { & $add $l }
    & $add ''

    $cited = 0
    foreach ($tm in $Vertical.technologies_that_matter) {
        $tag = $tm.tag
        $hits = @($items | Where-Object { $_.tech -and ($_.tech -contains $tag) } |
            Sort-Object -Property @{ Expression = { $_.heat }; Descending = $true })

        & $add (Format-Line $T.techHeading @{ tech = $Labels[$tag] })
        & $add ''
        $whyText = if ($Lang -eq 'ar') { Get-P $tm 'why_ar' $tm.why } else { $tm.why }
        & $add (Format-Line $T.why @{ why = $whyText })
        & $add ''

        if ($hits.Count -eq 0) {
            & $add $T.nothing
            & $add ''
            continue
        }

        & $add (Format-Line $T.found @{ count = $hits.Count })
        & $add ''

        foreach ($i in @($hits | Select-Object -First $PerTech)) {
            $pubName = Get-P $i.publisher 'name' ''
            $who = if ($pubName) { $pubName } else { $T.unattributed }
            $tier = Get-P $i.publisher 'tier' $null
            $tierNote = ''
            if ($tier) { $tierNote = (Format-Line $T.tierNote @{ tier = $tier }) }

            # "seen by" for a floor, "first seen" only for a real observation
            $seen = ''
            if ($i.firstSeen) {
                $day = ([datetime]::Parse($i.firstSeen)).ToString('yyyy-MM-dd')
                if ((Get-P $i 'firstSeenBasis' '') -eq 'observed') {
                    $seen = (Format-Line $T.seenObserved @{ date = $day })
                }
                else {
                    $seen = (Format-Line $T.seenFloor @{ date = $day })
                }
            }

            & $add (Format-Line $T.citation @{ title = $i.title; url = $i.url; who = $who; tier = $tierNote })
            & $add (Format-Line $T.citationMeta @{
                heat = $i.heat; category = $i.category; seen = $seen
                meaning = (Get-P $i 'publishedMeaning' 'unknown')
            })
            $cited++
        }
        & $add ''
    }

    foreach ($l in $T.footer) { & $add $l }

    $path = Join-Path $OutDir ("$($Vertical.id).$Lang.md")
    [System.IO.File]::WriteAllText($path, $sb.ToString(), $utf8)
    return [pscustomobject]@{ path = $path; cited = $cited }
}

$total = 0
foreach ($v in $targets) {
    $en = Write-Brief -Vertical $v -Lang 'en' -T $template.en -Labels $label
    $ar = Write-Brief -Vertical $v -Lang 'ar' -T $template.ar -Labels $labelAr
    $total += $en.cited
    if (-not $Quiet) {
        Write-Output ("{0,-30} {1,2} technologies, {2,2} citations frozen at {3}" -f `
            $v.label, @($v.technologies_that_matter).Count, $en.cited, $stamp)
        Write-Output ("   " + $en.path)
        Write-Output ("   " + $ar.path)
    }
}
if (-not $Quiet -and $targets.Count -gt 1) {
    Write-Output ''
    Write-Output ("{0} verticals, {1} citations, all frozen at {2}" -f $targets.Count, $total, $stamp)
}
exit 0
