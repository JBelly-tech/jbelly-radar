# lib/sources.ps1 — JBelly Radar fetchers + deterministic ranking.
#
# Four source kinds, one function each. Adding a SOURCE needs only a new object
# in config/sources.json; adding a KIND is the only thing that touches this file.
#
# No model call anywhere in this file, by design: fetch, normalise, rank, write.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Sibling modules: technology tagging and publisher reputation. Loaded here so
# every entry point (radar.ps1, scripts/sync.ps1, tests) gets the whole pipeline
# from one dot-source.
. (Join-Path $PSScriptRoot 'classify.ps1')
. (Join-Path $PSScriptRoot 'reputation.ps1')

# -- small helpers ------------------------------------------------------------

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or '' -eq "$($p.Value)") { return $Default }
    return $p.Value
}

function ConvertTo-PlainText {
    param([string]$Html, [int]$Max = 260)
    if (-not $Html) { return '' }
    $t = $Html -replace '(?s)<script.*?</script>', ' ' -replace '(?s)<style.*?</style>', ' '
    $t = $t -replace '<[^>]+>', ' '
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = ($t -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max).TrimEnd() + [char]0x2026 }
    return $t
}

function Get-StableId {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))
    $sha.Dispose()
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
}

function Get-CanonicalUrl {
    param([string]$Url)
    if (-not $Url) { return '' }
    $u = $Url.Trim()
    $u = $u -replace '[?&](utm_[^=]+|ref|ref_src|source)=[^&]*', ''
    $u = $u -replace '[?&]+$', ''
    return $u.TrimEnd('/')
}

function ConvertTo-Utc {
    param([string]$Value)
    if (-not $Value) { return $null }
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}

function Invoke-Http {
    param([string]$Url, [int]$TimeoutSec = 30, [string]$UserAgent, [hashtable]$Headers)
    $p = @{ Uri = $Url; TimeoutSec = $TimeoutSec; UseBasicParsing = $true; ErrorAction = 'Stop' }
    if ($UserAgent) { $p.UserAgent = $UserAgent }
    if ($Headers)   { $p.Headers   = $Headers }
    $resp = Invoke-WebRequest @p

    # Decode from the raw bytes. Windows PowerShell falls back to ISO-8859-1 when a
    # response omits the charset, which turns every curly quote in a feed into mojibake.
    $bytes = $resp.RawContentStream.ToArray()
    $enc = [System.Text.Encoding]::UTF8
    $ct = $resp.Headers['Content-Type']
    if ($ct -and ($ct -match 'charset=["'']?([\w-]+)')) {
        try { $enc = [System.Text.Encoding]::GetEncoding($Matches[1]) } catch { $enc = [System.Text.Encoding]::UTF8 }
    }
    return ($enc.GetString($bytes)).TrimStart([char]0xFEFF)
}

function New-RadarItem {
    param(
        [string]$SourceId, [string]$SourceLabel, [string]$Category,
        [string]$Title, [string]$Url, [string]$Summary = '', [string]$Author = '',
        $Metric = $null, [string]$MetricLabel = '', $Published = $null,
        [string[]]$Tags = @(), $Spark = $null, [string]$Install = '', [string]$Key = ''
    )
    $canon = Get-CanonicalUrl $Url
    # Identity defaults to the canonical URL. A source whose items legitimately
    # share a URL (many skills live in one repo) passes its own -Key.
    $identity = $canon
    if ($Key) { $identity = $Key }
    $pubIso = $null
    $age = $null
    if ($Published) {
        $pubIso = $Published.ToString('o')
        $age = [math]::Round(([datetime]::UtcNow - $Published).TotalDays, 2)
    }
    return [pscustomobject]@{
        id          = Get-StableId $identity
        sourceId    = $SourceId
        sourceLabel = $SourceLabel
        category    = $Category
        title       = ($Title -replace '\s+', ' ').Trim()
        url         = $canon
        summary     = $Summary
        author      = $Author
        metric      = $Metric
        metricLabel = $MetricLabel
        momentum    = $null
        published   = $pubIso
        ageDays     = $age
        heat        = 0
        tags        = @($Tags | Where-Object { $_ } | Select-Object -First 6)
        spark       = $Spark
        install     = $Install
    }
}

# -- kind: skills-sh ----------------------------------------------------------
# The Agent Skills Directory publishes no API. The leaderboard ships inside the
# server-rendered payload; this reads that payload. It is the one brittle source
# in the set: if the shape changes, the source reports zero items and the rest of
# the sync is unaffected.

function Get-SkillsShItems {
    param($Source, $Defaults)
    $ua   = Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0'
    $html = Invoke-Http -Url (Get-Prop $Source 'url' 'https://www.skills.sh/') -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent $ua
    $pattern = '\\"source\\":\\"([^"\\]+)\\",\\"skillId\\":\\"([^"\\]+)\\",\\"name\\":\\"([^"\\]+)\\",\\"installs\\":(\d+),\\"weeklyInstalls\\":\[([0-9,\s]*)\]'
    $newestFirst = ((Get-Prop $Source 'weeklyOrder' 'newest-first') -eq 'newest-first')
    $max = [int](Get-Prop $Source 'maxItems' 120)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($html, $pattern)) {
        $repo     = $m.Groups[1].Value
        $installs = [int64]$m.Groups[4].Value
        $weeks    = @()
        if ($m.Groups[5].Value.Trim()) { $weeks = @($m.Groups[5].Value -split ',' | ForEach-Object { [int64]$_.Trim() }) }
        $chrono = $weeks
        if ($newestFirst -and $weeks.Count -gt 1) { $chrono = @($weeks[($weeks.Count - 1)..0]) }
        $owner = ($repo -split '/')[0]
        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title $m.Groups[3].Value -Url "https://github.com/$repo" `
            -Summary "Published by $repo on the skills directory." `
            -Author $repo -Metric $installs -MetricLabel 'installs' `
            -Tags @('skill', $owner) -Spark $chrono -Install "npx skills add $repo" `
            -Key "skills.sh/$repo#$($m.Groups[2].Value)"
        $items.Add($item)
        if ($items.Count -ge $max) { break }
    }
    return $items
}

# -- kind: github-search ------------------------------------------------------
# Unauthenticated: 10 search requests/minute. Set GITHUB_TOKEN (or GH_TOKEN) to raise it.

function Get-GitHubItems {
    param($Source, $Defaults)
    $q = Get-Prop $Source 'query' ''
    $createdDays = Get-Prop $Source 'createdWithinDays' $null
    $pushedDays  = Get-Prop $Source 'pushedWithinDays' $null
    if ($createdDays) { $q = $q + ' created:>' + ([datetime]::UtcNow.AddDays(-[int]$createdDays)).ToString('yyyy-MM-dd') }
    if ($pushedDays)  { $q = $q + ' pushed:>'  + ([datetime]::UtcNow.AddDays(-[int]$pushedDays)).ToString('yyyy-MM-dd') }

    $max = [int](Get-Prop $Source 'maxItems' (Get-Prop $Defaults 'maxItems' 25))
    $url = 'https://api.github.com/search/repositories?q=' + [uri]::EscapeDataString($q.Trim()) +
           '&sort=' + (Get-Prop $Source 'sort' 'stars') + '&order=desc&per_page=' + [math]::Min($max, 50)

    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $token = $null
    if ($env:GITHUB_TOKEN) { $token = $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $token = $env:GH_TOKEN }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $json = Invoke-Http -Url $url -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent (Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0') -Headers $headers
    $data = $json | ConvertFrom-Json

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($r in $data.items) {
        $tags = @()
        $topics = Get-Prop $r 'topics' @()
        if ($topics) { $tags += @($topics) }
        $lang = Get-Prop $r 'language' $null
        if ($lang) { $tags += $lang }

        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title $r.full_name -Url $r.html_url -Summary (ConvertTo-PlainText (Get-Prop $r 'description' '')) `
            -Author (Get-Prop $r.owner 'login' '') -Metric ([int64]$r.stargazers_count) -MetricLabel 'stars' `
            -Published (ConvertTo-Utc $r.created_at) -Tags $tags
        $items.Add($item)
        if ($items.Count -ge $max) { break }
    }
    return $items
}

# -- kind: hn -----------------------------------------------------------------

function Get-HnItems {
    param($Source, $Defaults)
    $max    = [int](Get-Prop $Source 'maxItems' (Get-Prop $Defaults 'maxItems' 25))
    $since  = [int64]([datetimeoffset]::UtcNow.AddDays(-[int](Get-Prop $Source 'withinDays' 30)).ToUnixTimeSeconds())
    $points = [int](Get-Prop $Source 'minPoints' 50)
    $filters = "points>$points,created_at_i>$since"
    $url = 'https://hn.algolia.com/api/v1/search?query=' + [uri]::EscapeDataString((Get-Prop $Source 'query' '')) +
           '&tags=story&numericFilters=' + [uri]::EscapeDataString($filters) + '&hitsPerPage=' + $max

    $data = (Invoke-Http -Url $url -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent (Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0')) | ConvertFrom-Json
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($h in $data.hits) {
        $thread = "https://news.ycombinator.com/item?id=$($h.objectID)"
        $link = Get-Prop $h 'url' $thread
        $pts  = [int](Get-Prop $h 'points' 0)
        $cmts = [int](Get-Prop $h 'num_comments' 0)
        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title (Get-Prop $h 'title' '(untitled)') -Url $link `
            -Summary "$pts points, $cmts comments on Hacker News." `
            -Author (Get-Prop $h 'author' '') -Metric ([int64]$pts) -MetricLabel 'points' `
            -Published (ConvertTo-Utc (Get-Prop $h 'created_at' $null)) -Tags @('hn') -Install $thread
        $items.Add($item)
    }
    return $items
}

# -- kind: rss (RSS 2.0 and Atom, so arXiv runs through the same code path) ----

function Get-RssItems {
    param($Source, $Defaults)
    $max = [int](Get-Prop $Source 'maxItems' (Get-Prop $Defaults 'maxItems' 25))
    $raw = Invoke-Http -Url $Source.url -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent (Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0')
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $false
    $xml.LoadXml(($raw -replace '^[\s﻿]*<\?xml[^>]*\?>', '<?xml version="1.0" encoding="utf-8"?>'))

    $nodes = @($xml.SelectNodes('//*[local-name()="item"] | //*[local-name()="entry"]'))
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($n in $nodes) {
        $titleNode = $n.SelectSingleNode('*[local-name()="title"]')
        if (-not $titleNode) { continue }

        $linkNode = $n.SelectSingleNode('*[local-name()="link"][@rel="alternate"]')
        if (-not $linkNode) { $linkNode = $n.SelectSingleNode('*[local-name()="link"]') }
        if (-not $linkNode) { continue }
        $link = $linkNode.InnerText
        if ($linkNode.Attributes -and $linkNode.Attributes['href']) { $link = $linkNode.Attributes['href'].Value }
        if (-not $link) { continue }

        $descNode = $n.SelectSingleNode('*[local-name()="description"]')
        if (-not $descNode) { $descNode = $n.SelectSingleNode('*[local-name()="summary"]') }
        if (-not $descNode) { $descNode = $n.SelectSingleNode('*[local-name()="content"]') }
        $desc = ''
        if ($descNode) { $desc = ConvertTo-PlainText $descNode.InnerText }

        $dateNode = $n.SelectSingleNode('*[local-name()="pubDate"]')
        if (-not $dateNode) { $dateNode = $n.SelectSingleNode('*[local-name()="published"]') }
        if (-not $dateNode) { $dateNode = $n.SelectSingleNode('*[local-name()="updated"]') }
        if (-not $dateNode) { $dateNode = $n.SelectSingleNode('*[local-name()="date"]') }
        $pub = $null
        if ($dateNode) { $pub = ConvertTo-Utc $dateNode.InnerText }

        $authorNode = $n.SelectSingleNode('*[local-name()="creator"]')
        if (-not $authorNode) { $authorNode = $n.SelectSingleNode('*[local-name()="author"]/*[local-name()="name"]') }
        $author = ''
        if ($authorNode) { $author = ConvertTo-PlainText $authorNode.InnerText 60 }

        $cats = @()
        foreach ($c in @($n.SelectNodes('*[local-name()="category"]'))) {
            if ($c.Attributes -and $c.Attributes['term']) { $cats += $c.Attributes['term'].Value } else { $cats += $c.InnerText }
        }

        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title (ConvertTo-PlainText $titleNode.InnerText 180) -Url $link.Trim() `
            -Summary $desc -Author $author -Published $pub -Tags $cats
        $items.Add($item)
        if ($items.Count -ge $max) { break }
    }
    return $items
}

# -- ranking: deterministic, explainable, no model ----------------------------

function Set-RadarHeat {
    param($Items, $HeatConfig)
    $w = $HeatConfig.weights
    foreach ($it in $Items) {
        $cat = Get-Prop $HeatConfig.categories $it.category $null
        $halfLife = [double](Get-Prop $cat 'halfLifeDays' 7)
        $ceiling  = [double](Get-Prop $cat 'metricCeiling' 1)

        $age = $halfLife
        if ($null -ne $it.ageDays) { $age = [math]::Max([double]$it.ageDays, 0) }
        $recency = [math]::Exp(-[math]::Log(2) * $age / $halfLife)

        $popularity = 0.5
        if ($ceiling -gt 1 -and $null -ne $it.metric) {
            $popularity = [math]::Min(1.0, [math]::Log10(1 + [double]$it.metric) / [math]::Log10(1 + $ceiling))
        }

        $momentumNorm = $popularity
        if ($null -ne $it.momentum) {
            $momentumNorm = [math]::Max(0.0, [math]::Min(1.0, 0.5 + ([double]$it.momentum / 200.0)))
        }

        $score = ([double]$w.recency * $recency) + ([double]$w.popularity * $popularity) + ([double]$w.momentum * $momentumNorm)
        $it.heat = [int][math]::Round(100 * [math]::Max(0.0, [math]::Min(1.0, $score)))
    }
}

# Momentum comes from OUR OWN snapshots first -- an unambiguous delta between two
# syncs -- and falls back to a source-supplied weekly series on the first run.
function Set-RadarMomentum {
    param($Items, [string]$HistoryPath, [double]$MinBaselineHours = 12)
    $prev = @{}
    if (Test-Path $HistoryPath) {
        try {
            $loaded = (Get-Content -Raw -Encoding UTF8 $HistoryPath | ConvertFrom-Json)
            foreach ($p in $loaded.PSObject.Properties) { $prev[$p.Name] = $p.Value }
        } catch { $prev = @{} }
    }
    $now = [datetime]::UtcNow
    $next = [ordered]@{}

    # A baseline is only replaced once it is older than this. Without it, two syncs
    # minutes apart would divide a near-zero delta by a near-zero interval and report
    # invented momentum.
    $minBaselineDays = $MinBaselineHours / 24.0

    foreach ($it in $Items) {
        $measured = $false

        if ($null -ne $it.metric -and $prev.ContainsKey($it.id)) {
            $old = $prev[$it.id]
            $oldAt = (ConvertTo-Utc $old.at)
            if ($oldAt) {
                $elapsed = ($now - $oldAt).TotalDays
                if ($elapsed -ge $minBaselineDays) {
                    $base = [double]$old.metric
                    if ($base -lt 1.0) { $base = 1.0 }
                    $weekly = (([double]$it.metric - [double]$old.metric) / $base) * (7.0 / $elapsed) * 100.0
                    $it.momentum = [math]::Round([math]::Max(-200.0, [math]::Min(200.0, $weekly)), 1)
                    $measured = $true
                    $next[$it.id] = [pscustomobject]@{ metric = $it.metric; at = $now.ToString('o') }
                }
                else {
                    # too young to measure against: carry the baseline forward untouched
                    $next[$it.id] = $old
                }
            }
        }
        elseif ($null -ne $it.metric) {
            $next[$it.id] = [pscustomobject]@{ metric = $it.metric; at = $now.ToString('o') }
        }

        if (-not $measured -and $it.spark -and @($it.spark).Count -ge 4) {
            $s = @($it.spark)
            $last = [double]$s[$s.Count - 1]
            $baseline = ($s[0..($s.Count - 2)] | Measure-Object -Average).Average
            if ($baseline -gt 0) {
                $it.momentum = [math]::Round([math]::Max(-200.0, [math]::Min(200.0, (($last - $baseline) / $baseline) * 100.0)), 1)
            }
        }
    }

    $dir = Split-Path -Parent $HistoryPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($next | ConvertTo-Json -Depth 4) | Set-Content -Path $HistoryPath -Encoding UTF8
}

# -- the sync itself ----------------------------------------------------------

# data/status.json is the live progress file: the dashboard polls it while a
# sync runs, so the user sees "12 of 27 sources, reading TechCrunch" instead of a
# spinner. Written after every source; cheap, atomic via rename.
function Write-RadarStatus {
    param([string]$Path, [string]$State, [datetime]$StartedAt, [int]$Done, [int]$Total, [string]$Current, $Sources, [string]$GeneratedAt = '')
    if (-not $Path) { return }
    # Windows PowerShell 5.1 throws "Argument types do not match" on @() over an
    # empty generic List inside a hashtable literal; copy through the pipeline.
    $sourceList = @()
    if ($Sources) { $sourceList = @($Sources | ForEach-Object { $_ }) }
    $obj = [pscustomobject]@{
        state       = $State
        startedAt   = $StartedAt.ToString('o')
        updatedAt   = [datetime]::UtcNow.ToString('o')
        done        = $Done
        total       = $Total
        current     = $Current
        generatedAt = $GeneratedAt
        sources     = $sourceList
    }
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 5 -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $Path -Force
}

function Invoke-RadarSync {
    param([string]$Root, [switch]$Quiet)

    $config = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'config\sources.json') | ConvertFrom-Json
    $all = New-Object System.Collections.Generic.List[object]
    $health = New-Object System.Collections.Generic.List[object]
    $started = [datetime]::UtcNow

    $dataDir = Join-Path $Root 'data'
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    $statusPath = Join-Path $dataDir 'status.json'
    $enabled = @($config.sources | Where-Object { Get-Prop $_ 'enabled' $true })
    $done = 0
    Write-RadarStatus -Path $statusPath -State 'syncing' -StartedAt $started -Done 0 -Total $enabled.Count -Current '' -Sources @()

    foreach ($src in $config.sources) {
        if (-not (Get-Prop $src 'enabled' $true)) {
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = 'disabled'; count = 0; message = 'disabled in config'; ms = 0 })
            continue
        }
        Write-RadarStatus -Path $statusPath -State 'syncing' -StartedAt $started -Done $done -Total $enabled.Count -Current $src.label -Sources $health
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $fetched = $null
            switch ($src.kind) {
                'skills-sh'     { $fetched = Get-SkillsShItems -Source $src -Defaults $config.defaults }
                'github-search' { $fetched = Get-GitHubItems   -Source $src -Defaults $config.defaults }
                'hn'            { $fetched = Get-HnItems       -Source $src -Defaults $config.defaults }
                'rss'           { $fetched = Get-RssItems      -Source $src -Defaults $config.defaults }
                default         { throw "unknown source kind '$($src.kind)' -- add a fetcher in lib/sources.ps1" }
            }
            $sw.Stop()
            # Optional per-source regex gates. A broad feed (a whole "Innovation"
            # section) carries puzzles and horoscopes next to the technology it is
            # here for; these keep the filtering in config, not in a fetcher.
            $requireMatch = Get-Prop $src 'requireMatch' $null
            $excludeMatch = Get-Prop $src 'excludeMatch' $null
            if ($requireMatch) { $fetched = @($fetched | Where-Object { ("$($_.title) $($_.summary)") -match $requireMatch }) }
            if ($excludeMatch) { $fetched = @($fetched | Where-Object { ("$($_.title) $($_.summary)") -notmatch $excludeMatch }) }

            $n = @($fetched).Count
            foreach ($f in $fetched) { $all.Add($f) }
            $status = 'empty'
            if ($n -gt 0) { $status = 'ok' }
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = $status; count = $n; message = ''; ms = [int]$sw.ElapsedMilliseconds })
            if (-not $Quiet) {
                $colour = 'DarkGray'
                if ($n -eq 0) { $colour = 'DarkYellow' }
                Write-Host ("  {0,-22} {1,4} items {2,6} ms" -f $src.id, $n, $sw.ElapsedMilliseconds) -ForegroundColor $colour
            }
        }
        catch {
            $sw.Stop()
            $msg = $_.Exception.Message
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = 'failed'; count = 0; message = $msg; ms = [int]$sw.ElapsedMilliseconds })
            if (-not $Quiet) { Write-Host ("  {0,-22} FAILED  {1}" -f $src.id, $msg) -ForegroundColor DarkRed }
        }
        $done++
    }

    # dedupe by canonical URL: first source wins, so order in config is priority order
    $seen = @{}
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($it in $all) {
        if (-not $it.url -or $seen.ContainsKey($it.id)) { continue }
        $seen[$it.id] = $true
        $items.Add($it)
    }

    # classify → resolve publishers → momentum → heat (docs/ARCHITECTURE.md)
    $taxonomyPath = Join-Path $Root 'config\taxonomy.json'
    $taxonomy = $null
    if (Test-Path $taxonomyPath) { $taxonomy = Get-Content -Raw -Encoding UTF8 $taxonomyPath | ConvertFrom-Json }
    Set-RadarTech -Items $items -Taxonomy $taxonomy

    $publishersPath = Join-Path $Root 'config\publishers.json'
    $publishers = [pscustomobject]@{ publishers = @() }
    if (Test-Path $publishersPath) { $publishers = Get-Content -Raw -Encoding UTF8 $publishersPath | ConvertFrom-Json }
    Set-RadarPublishers -Items $items -Publishers $publishers -CachePath (Join-Path $Root 'data\history\orgs.json') -MaxLookups (Get-Prop $config.defaults 'orgLookupsPerSync' 20) -Quiet:$Quiet

    Set-RadarMomentum -Items $items -HistoryPath (Join-Path $Root 'data\history\metrics.json') -MinBaselineHours (Get-Prop $config.heat 'minBaselineHours' 12)
    Set-RadarHeat -Items $items -HeatConfig $config.heat

    $sorted = @($items | Sort-Object -Property @{ Expression = { $_.heat }; Descending = $true }, @{ Expression = { $_.ageDays }; Descending = $false })

    # publishers seen this run, so the client can render names and tiers without the whole list
    $seenPublishers = [ordered]@{}
    foreach ($it in $sorted) {
        if ($it.publisher -and -not $seenPublishers.Contains($it.publisher.key)) {
            $seenPublishers[$it.publisher.key] = [pscustomobject]@{ name = $it.publisher.name; tier = $it.publisher.tier; sector = $it.publisher.sector; verified = $it.publisher.verified }
        }
    }

    $payload = [pscustomobject]@{
        generatedAt = $started.ToString('o')
        durationMs  = [int]([datetime]::UtcNow - $started).TotalMilliseconds
        counts      = [pscustomobject]@{
            total      = $sorted.Count
            skill      = @($sorted | Where-Object { $_.category -eq 'skill' }).Count
            repo       = @($sorted | Where-Object { $_.category -eq 'repo' }).Count
            news       = @($sorted | Where-Object { $_.category -eq 'news' }).Count
            discussion = @($sorted | Where-Object { $_.category -eq 'discussion' }).Count
            research   = @($sorted | Where-Object { $_.category -eq 'research' }).Count
            release    = @($sorted | Where-Object { $_.category -eq 'release' }).Count
            notable    = @($sorted | Where-Object { $_.publisher }).Count
        }
        sources    = $health
        publishers = [pscustomobject]$seenPublishers
        items      = $sorted
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $json = $payload | ConvertTo-Json -Depth 8 -Compress
    # Write to a temp file and rename, so a reader never sees a half-written file.
    $tmp = Join-Path $dataDir 'trends.json.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, $utf8)
    Move-Item -Path $tmp -Destination (Join-Path $dataDir 'trends.json') -Force
    # trends.js exists so app/index.html also works when opened straight from disk
    # (file://), where fetch() of a local JSON file is blocked by the browser.
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'trends.js'), "window.RADAR_DATA = $json;", $utf8)
    if ($taxonomy) {
        [System.IO.File]::WriteAllText((Join-Path $dataDir 'taxonomy.js'), "window.RADAR_TAXONOMY = " + ($taxonomy | ConvertTo-Json -Depth 6 -Compress) + ";", $utf8)
    }
    [System.IO.File]::WriteAllText((Join-Path $Root ('data\history\' + $started.ToString('yyyy-MM-dd') + '.json')), $json, $utf8)

    Write-RadarStatus -Path $statusPath -State 'idle' -StartedAt $started -Done $done -Total $enabled.Count -Current '' -Sources $health -GeneratedAt $payload.generatedAt

    return $payload
}
