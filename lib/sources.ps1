# lib/sources.ps1 — JBelly Radar fetchers + deterministic ranking.
#
# Five source kinds, one function each. Adding a SOURCE needs only a new object
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
    # stripping a leading tracking parameter can leave '&' as the first separator
    if ($u -notmatch '\?' -and $u -match '&') { $u = ([regex]'&').Replace($u, '?', 1) }
    # the same paper arrives as arxiv.org/abs/ID, arxiv.org/abs/IDv2 and huggingface.co/papers/ID
    $u = $u -replace '^(https?://arxiv\.org/abs/\d{4}\.\d{4,5})v\d+$', '$1'
    $u = $u -replace '^https?://huggingface\.co/papers/(\d{4}\.\d{4,5})$', 'https://arxiv.org/abs/$1'
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

function Get-PublishedMeaning {
    # What a source's date means. Declared per source with `publishedMeaning`, or
    # derived from the kind, which is honest because each fetcher reads one field:
    # github-search reads created_at (the repository was created), hn reads
    # created_at (the story was posted), rss reads pubDate/published/updated, and
    # a release feed's entry is a release, not a post. json-api maps a field per
    # source, so its meaning cannot be guessed and must be declared.
    param($Source)
    $declared = Get-Prop $Source 'publishedMeaning' $null
    if ($declared) { return $declared }
    switch ((Get-Prop $Source 'kind' '')) {
        'github-search' { return 'created' }
        'hn'            { return 'posted' }
        'skills-sh'     { return 'none' }
        'rss'           { if ((Get-Prop $Source 'category' '') -eq 'release') { return 'released' } else { return 'posted' } }
        default         { return 'unknown' }
    }
}

function New-RadarItem {
    param(
        [string]$SourceId, [string]$SourceLabel, [string]$Category,
        [string]$Title, [string]$Url, [string]$Summary = '', [string]$Author = '',
        $Metric = $null, [string]$MetricLabel = '', $Published = $null,
        [string[]]$Tags = @(), $Spark = $null, [string]$Install = '', [string]$Key = '',
        [string]$PublishedMeaning = 'unknown'
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
        # Filled by Set-RadarMomentum from the ledger. `published` is the source's own
        # date and means a different thing in each feed; `firstSeen` is this radar's own
        # observation and is the only timestamp comparable across every source.
        # What `published` above actually MEANS for this source. It is a different
        # event in every feed - a Hacker News story was posted, a GitHub repository
        # was created, a changelog entry was released, an npm package was last
        # published - and comparing them as if they were one thing is how a routine
        # patch release gets announced as news.
        publishedMeaning = $PublishedMeaning
        firstSeen      = $null
        firstSeenBasis = $null
        daysOnRadar    = $null
        heat        = 0
        heatBasis   = ''
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
        # 'source' is owner/repo for GitHub-hosted skills and a bare domain otherwise
        $isRepo = ($repo -match '^[^/]+/[^/]+$')
        $owner = ''
        $link = "https://$repo"
        $author = ''
        if ($isRepo) { $owner = ($repo -split '/')[0]; $link = "https://github.com/$repo"; $author = $repo }
        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title $m.Groups[3].Value -Url $link `
            -Summary "Published by $repo on the skills directory." `
            -Author $author -Metric $installs -MetricLabel 'installs' `
            -Tags @('skill', $owner) -Spark $chrono -Install "npx skills add $repo" -PublishedMeaning 'none' `
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
            -Published (ConvertTo-Utc $r.created_at) -Tags $tags -PublishedMeaning (Get-PublishedMeaning $Source)
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
            -Published (ConvertTo-Utc (Get-Prop $h 'created_at' $null)) -Tags @('hn') -Install $thread -PublishedMeaning (Get-PublishedMeaning $Source)
        $items.Add($item)
    }
    return $items
}

# -- kind: rss (RSS 2.0 and Atom, so arXiv runs through the same code path) ----

function Get-RssItems {
    param($Source, $Defaults)
    $max = [int](Get-Prop $Source 'maxItems' (Get-Prop $Defaults 'maxItems' 25))
    $ua  = Get-Prop $Source 'userAgent' (Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0')
    $raw = Invoke-Http -Url $Source.url -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent $ua
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
            -Summary $desc -Author $author -Published $pub -Tags $cats -PublishedMeaning (Get-PublishedMeaning $Source)
        $items.Add($item)
    }
    # A changelog feed can carry a thousand entries and not every feed is
    # newest-first; sort by date (undated last) before taking the cap.
    $sorted = @($items | Sort-Object -Property @{ Expression = { if ($_.published) { $_.published } else { '' } }; Descending = $true })
    return @($sorted | Select-Object -First $max)
}

# -- kind: json-api -----------------------------------------------------------
# A public JSON endpoint plus a field map in config. Paths are dot-separated;
# a segment in [brackets] may itself contain dots ("_meta.[io.x/official].at");
# "a|b" tries a then b; a numeric segment indexes an array. Nothing here knows
# any particular API, so a new JSON source is configuration only.

function Get-JsonPath {
    param($Object, [string]$Path)
    if ($null -eq $Object -or -not $Path) { return $null }
    foreach ($alt in ($Path -split '\|')) {
        $cur = $Object
        $ok = $true
        foreach ($seg in [regex]::Matches($alt.Trim(), '\[[^\]]+\]|[^.]+')) {
            $name = $seg.Value.Trim('[', ']')
            if ($null -eq $cur) { $ok = $false; break }
            if ($cur -is [System.Array] -or $cur -is [System.Collections.IList]) {
                $idx = 0
                if ([int]::TryParse($name, [ref]$idx) -and $idx -lt $cur.Count) { $cur = $cur[$idx] } else { $ok = $false; break }
            }
            elseif ($cur.PSObject -and $cur.PSObject.Properties[$name]) { $cur = $cur.PSObject.Properties[$name].Value }
            else { $ok = $false; break }
        }
        if ($ok -and $null -ne $cur -and "$cur" -ne '') { return $cur }
    }
    return $null
}

function Get-JsonApiItems {
    param($Source, $Defaults)
    $max = [int](Get-Prop $Source 'maxItems' (Get-Prop $Defaults 'maxItems' 25))
    $ua  = Get-Prop $Source 'userAgent' (Get-Prop $Defaults 'userAgent' 'jbelly-radar/1.0')
    $raw = Invoke-Http -Url $Source.url -TimeoutSec (Get-Prop $Defaults 'timeoutSec' 30) -UserAgent $ua -Headers @{ 'Accept' = 'application/json' }
    $data = $raw | ConvertFrom-Json
    $itemPath = Get-Prop $Source 'itemPath' ''
    $list = $data
    if ($itemPath) { $list = Get-JsonPath -Object $data -Path $itemPath }
    $map = $Source.map
    $prefix = Get-Prop $map 'urlPrefix' ''
    $split = Get-Prop $map 'authorSplit' ''

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($list)) {
        $title = Get-JsonPath -Object $row -Path (Get-Prop $map 'title' 'title')
        $url   = Get-JsonPath -Object $row -Path (Get-Prop $map 'url' 'url')
        if (-not $title -or -not $url) { continue }
        $url = "$url"
        if ($prefix -and $url -notmatch '^https?://') { $url = $prefix + $url }
        $summary = Get-JsonPath -Object $row -Path (Get-Prop $map 'summary' 'description')
        $author  = Get-JsonPath -Object $row -Path (Get-Prop $map 'author' 'author')
        if ($author -and $split) { $author = ("$author" -split [regex]::Escape($split))[0] }
        $metric  = Get-JsonPath -Object $row -Path (Get-Prop $map 'metric' '')
        $pubRaw  = Get-JsonPath -Object $row -Path (Get-Prop $map 'published' '')
        $tagsRaw = Get-JsonPath -Object $row -Path (Get-Prop $map 'tags' '')
        $tags = @()
        if ($tagsRaw -is [string]) { $tags = @($tagsRaw -split ',\s*') } elseif ($tagsRaw) { $tags = @($tagsRaw | ForEach-Object { "$_" }) }
        $metricVal = $null
        if ($null -ne $metric -and "$metric" -match '^\d+(\.\d+)?$') { $metricVal = [int64][double]$metric }

        $item = New-RadarItem -SourceId $Source.id -SourceLabel $Source.label -Category $Source.category `
            -Title (ConvertTo-PlainText "$title" 180) -Url $url `
            -Summary (ConvertTo-PlainText "$summary") -Author "$author" `
            -Metric $metricVal -MetricLabel (Get-Prop $map 'metricLabel' '') `
            -Published (ConvertTo-Utc "$pubRaw") -Tags $tags -PublishedMeaning (Get-PublishedMeaning $Source)
        $items.Add($item)
    }
    $sorted = @($items | Sort-Object -Property @{ Expression = { if ($null -ne $_.metric) { [double]$_.metric } else { -1 } }; Descending = $true })
    if ((Get-Prop $map 'order' 'metric') -eq 'published') {
        $sorted = @($items | Sort-Object -Property @{ Expression = { if ($_.published) { $_.published } else { '' } }; Descending = $true })
    }
    return @($sorted | Select-Object -First $max)
}

# -- ranking: deterministic, explainable, no model ----------------------------

function Set-RadarHeat {
    param($Items, $HeatConfig)
    $w = $HeatConfig.weights
    foreach ($it in $Items) {
        # an item kept from an earlier run (stale-while-error) carries that run's
        # ageDays; recompute so it keeps cooling
        if ($it.published) {
            $p = ConvertTo-Utc "$($it.published)"
            if ($p) { $it.ageDays = [math]::Round(([datetime]::UtcNow - $p).TotalDays, 2) }
        }
        $cat = Get-Prop $HeatConfig.categories $it.category $null
        $halfLife = [double](Get-Prop $cat 'halfLifeDays' 7)
        $ceiling  = [double](Get-Prop $cat 'metricCeiling' 1)

        # A missing signal is not a mid-range signal. Substituting 0.5 for a term we
        # cannot measure does not express uncertainty, it manufactures a number and
        # then hides it inside a total: with metricCeiling = 1 and no momentum, the
        # old code scored every news and release item as 0.4*recency + 0.30, which is
        # age wearing the word "heat". A term we cannot measure is DROPPED and the
        # remaining weights are renormalised, so heat always means "of what we could
        # actually measure here", and heatBasis says which terms those were.
        $num = 0.0
        $den = 0.0
        $totalW = [double]$w.recency + [double]$w.popularity + [double]$w.momentum
        $basis = New-Object System.Collections.Generic.List[string]

        # recency — prefer the source's own date; fall back to the day this radar
        # first saw the item, which is an observation we made rather than a guess
        $age = $null
        $ageFrom = ''
        if ($null -ne $it.ageDays) { $age = [math]::Max([double]$it.ageDays, 0); $ageFrom = 'published' }
        elseif ($null -ne $it.daysOnRadar) { $age = [math]::Max([double]$it.daysOnRadar, 0); $ageFrom = 'firstSeen' }
        if ($null -ne $age) {
            $recency = [math]::Exp(-[math]::Log(2) * $age / $halfLife)
            $num += [double]$w.recency * $recency; $den += [double]$w.recency
            $basis.Add('recency:' + $ageFrom)
        }

        # popularity — only where the category declares a real ceiling to scale against
        if ($ceiling -gt 1 -and $null -ne $it.metric) {
            $popularity = [math]::Min(1.0, [math]::Log10(1 + [double]$it.metric) / [math]::Log10(1 + $ceiling))
            $num += [double]$w.popularity * $popularity; $den += [double]$w.popularity
            $basis.Add('popularity')
        }
        elseif ($null -ne $it.publisher) {
            # A news item or a release carries no star count, so popularity cannot be
            # measured at all — but WHO published it is a quality signal we already
            # resolved, and it is the only one these categories have. Without it a
            # routine alpha tag from an unknown account scores the same as a major
            # release, because freshness would be the only term in the sum.
            $tier = [int](Get-Prop $it.publisher 'tier' 0)
            $rep = $null
            if ($tier -eq 1) { $rep = 1.0 }
            elseif ($tier -eq 2) { $rep = 0.75 }
            elseif ($tier -eq 3) { $rep = 0.5 }
            elseif ((Get-Prop $it.publisher 'verified' $false) -eq $true) { $rep = 0.35 }
            if ($null -ne $rep) {
                $num += [double]$w.popularity * $rep; $den += [double]$w.popularity
                $basis.Add('reputation')
            }
        }

        # momentum — measured against a baseline, or absent. Never copied from another term.
        if ($null -ne $it.momentum) {
            $momentumNorm = [math]::Max(0.0, [math]::Min(1.0, 0.5 + ([double]$it.momentum / 200.0)))
            $num += [double]$w.momentum * $momentumNorm; $den += [double]$w.momentum
            $basis.Add('momentum')
        }

        if ($den -gt 0) {
            $score = $num / $den

            # Renormalising alone makes every category internally honest and then
            # makes them incomparable: an item with one measurable term scores full
            # marks on that one term, so a routine alpha tag published an hour ago
            # ties with a major release carrying stars and momentum. Confidence is
            # how much of the total weight we could actually measure, and it scales
            # the result, so more evidence can outrank less. confidenceFloor is what
            # a single-signal item keeps; at 1.0 the discount is off entirely.
            $floor = [double](Get-Prop $HeatConfig 'confidenceFloor' 0.7)
            $confidence = $floor + ((1.0 - $floor) * ($den / $totalW))
            $score = $score * $confidence
            $basis.Add('conf:' + [math]::Round($confidence, 2))
        }
        else {
            # nothing measurable at all: say so rather than inventing a middle
            $score = 0.0
            $basis.Add('none')
        }
        $it.heat = [int][math]::Round(100 * [math]::Max(0.0, [math]::Min(1.0, $score)))
        $it.heatBasis = ($basis -join '+')
    }
}

# Momentum comes from OUR OWN snapshots first -- an unambiguous delta between two
# syncs -- and falls back to a source-supplied weekly series on the first run.
# The ledger. One entry per item id, carried across every sync, holding:
#   title/url/summary       what the item IS, so a row outlives the item's stay
#   sourceId/category/tech  where it came from and what it is about
#   install/author          how to get it and who ships it (skills carry both)
#   publisherName/Tier      flattened from the publisher object: a matcher ranks by
#                           tier and prints the name, and reads nothing else
#   firstSeen  the first sync that ever recorded this id. NEVER overwritten.
#   lastSeen   the most recent sync that saw it, so a disappearance is visible.
#   metric/at  the momentum baseline and when it was taken (metric-bearing items only)
#   momentum   the last measured value, so it survives a sync too young to re-measure
#
# The identity fields are what make this a catalogue rather than a momentum cache.
# data/trends.json holds one sync and every source is capped, so "is there a skill
# for X" asked against it answers "not in today's top N" while sounding like "does
# not exist" -- the worst available failure for a question someone uses to choose a
# technology. The ledger keeps every row it has ever written, so the same question
# asked here is answered from everything the radar has ever seen. Identity is
# refreshed on every sighting, because a title or a summary can be edited upstream.
#
# firstSeen is the only field here that cannot be reconstructed later: a source's own
# "published" date means different things per source (posted, uploaded, last released),
# so the date this radar first saw something is the one honest, comparable timestamp,
# and it exists only if it was written down at the time. Every sync that runs without
# it is a day of record that cannot be recovered.
#
# Every item gets an entry, not only those carrying a numeric metric, which is what
# makes "what is new since" and "how long has this been around" answerable at all.
function Set-RadarMomentum {
    param($Items, [string]$HistoryPath, [double]$MinBaselineHours = 12)
    $prev = @{}
    if (Test-Path $HistoryPath) {
        try {
            # -Encoding UTF8 on Get-Content handles a BOM written by older runs
            $loaded = (Get-Content -Raw -Encoding UTF8 $HistoryPath | ConvertFrom-Json)
            foreach ($p in $loaded.PSObject.Properties) { $prev[$p.Name] = $p.Value }
        } catch { $prev = @{} }
    }
    $now = [datetime]::UtcNow
    $nowIso = $now.ToString('o')
    $next = [ordered]@{}

    # A baseline is only replaced once it is older than this. Without it, two syncs
    # minutes apart would divide a near-zero delta by a near-zero interval and report
    # invented momentum.
    $minBaselineDays = $MinBaselineHours / 24.0

    foreach ($it in $Items) {
        $measured = $false
        $old = $null
        if ($prev.ContainsKey($it.id)) { $old = $prev[$it.id] }

        # baseline fields, decided by the branches below; $null means "carry nothing"
        $baseMetric = $null; $baseAt = $null; $baseMomentum = $null

        if ($null -ne $it.metric -and $null -ne $old) {
            $oldAt = (ConvertTo-Utc $old.at)
            if ($oldAt) {
                $elapsed = ($now - $oldAt).TotalDays
                if ($elapsed -ge $minBaselineDays) {
                    $base = [double]$old.metric
                    if ($base -lt 1.0) { $base = 1.0 }
                    $weekly = (([double]$it.metric - [double]$old.metric) / $base) * (7.0 / $elapsed) * 100.0
                    $it.momentum = [math]::Round([math]::Max(-200.0, [math]::Min(200.0, $weekly)), 1)
                    $measured = $true
                    $baseMetric = $it.metric; $baseAt = $nowIso; $baseMomentum = $it.momentum
                }
                else {
                    # too young to measure against: carry the baseline forward untouched,
                    # and keep the last measured value so it survives until the next one
                    $baseMetric = Get-Prop $old 'metric' $null
                    $baseAt = Get-Prop $old 'at' $null
                    $prevMomentum = Get-Prop $old 'momentum' $null
                    if ($null -ne $prevMomentum) {
                        $it.momentum = [double]$prevMomentum; $measured = $true; $baseMomentum = $prevMomentum
                    }
                }
            }
            else {
                # an unreadable baseline timestamp: start a fresh one rather than drop it
                $baseMetric = $it.metric; $baseAt = $nowIso
            }
        }
        elseif ($null -ne $it.metric) {
            $baseMetric = $it.metric; $baseAt = $nowIso
        }
        elseif ($null -ne $old) {
            # no metric now, but keep whatever baseline we already held
            $baseMetric = Get-Prop $old 'metric' $null
            $baseAt = Get-Prop $old 'at' $null
            $baseMomentum = Get-Prop $old 'momentum' $null
        }

        # firstSeen: what we already recorded, else the oldest timestamp we can prove
        # we saw this item at (its carried baseline), else this sync.
        #
        # firstSeenBasis says which of two different claims the date is making:
        #   observed       this sync saw the item arrive, and the one before did not.
        #                  A real first sighting.
        #   snapshot-floor the earliest record we hold. The item may well be older;
        #                  this is a lower bound, not a birth date.
        # Every consumer must render a floor as "seen by" and never as "first
        # appeared". The distinction is free to record now and impossible to
        # reconstruct later, and publishing a floor as a birth date is exactly the
        # kind of quiet inaccuracy a dated record exists to prevent.
        $firstSeen = $null
        $firstSeenBasis = $null
        if ($null -ne $old) {
            $firstSeen = Get-Prop $old 'firstSeen' $null
            $firstSeenBasis = Get-Prop $old 'firstSeenBasis' $null
            if (-not $firstSeen) {
                # a pre-ledger row: its baseline timestamp proves we saw it then, but
                # says nothing about when it actually arrived
                $firstSeen = Get-Prop $old 'at' $null
                $firstSeenBasis = 'snapshot-floor'
            }
        }
        if (-not $firstSeen) { $firstSeen = $nowIso; $firstSeenBasis = 'observed' }
        if (-not $firstSeenBasis) { $firstSeenBasis = 'snapshot-floor' }

        # identity first, so `head` on the file shows what a row is before when it was
        $entry = [ordered]@{ title = $it.title; url = $it.url }
        if ($it.summary) { $entry['summary'] = $it.summary }
        $entry['sourceId'] = $it.sourceId
        $entry['category'] = $it.category
        if ($it.tech -and @($it.tech).Count -gt 0) { $entry['tech'] = @($it.tech) }
        if ($it.install) { $entry['install'] = $it.install }
        if ($it.author) { $entry['author'] = $it.author }
        if ($it.publisher) {
            $pubName = Get-Prop $it.publisher 'name' $null
            $pubTier = Get-Prop $it.publisher 'tier' $null
            if ($pubName) { $entry['publisherName'] = $pubName }
            if ($pubTier) { $entry['publisherTier'] = $pubTier }
        }
        $entry['firstSeen'] = $firstSeen
        $entry['firstSeenBasis'] = $firstSeenBasis
        $entry['lastSeen'] = $nowIso
        if ($null -ne $baseMetric) { $entry['metric'] = $baseMetric; $entry['at'] = $baseAt }
        if ($null -ne $baseMomentum) { $entry['momentum'] = $baseMomentum }
        $next[$it.id] = [pscustomobject]$entry

        # publish it on the item so the dashboard, an MCP tool and a brief can all
        # answer "how long has this been on the radar" from the artifact alone
        $it.firstSeen = $firstSeen
        $it.firstSeenBasis = $firstSeenBasis
        $seenAt = (ConvertTo-Utc $firstSeen)
        if ($seenAt) { $it.daysOnRadar = [math]::Round(($now - $seenAt).TotalDays, 2) }

        if (-not $measured -and $it.spark -and @($it.spark).Count -ge 4) {
            $s = @($it.spark)
            $last = [double]$s[$s.Count - 1]
            $baseline = ($s[0..($s.Count - 2)] | Measure-Object -Average).Average
            if ($baseline -gt 0) {
                $it.momentum = [math]::Round([math]::Max(-200.0, [math]::Min(200.0, (($last - $baseline) / $baseline) * 100.0)), 1)
            }
        }
    }

    # Entries for items not seen this sync are KEPT: the ledger is the record of what
    # the radar has ever seen, and dropping a row would erase its firstSeen forever.
    # A row written before the ledger existed is brought up to shape on the way past,
    # so every row answers "when did we first see this" the same way.
    foreach ($k in $prev.Keys) {
        if ($next.Contains($k)) { continue }
        $row = $prev[$k]
        $rowSeen = Get-Prop $row 'firstSeen' $null
        $rowBasis = Get-Prop $row 'firstSeenBasis' $null
        if (-not $rowSeen -or -not $rowBasis) {
            # Anything we cannot prove we watched arrive is a floor, not a birth date.
            if (-not $rowSeen) { $rowSeen = (Get-Prop $row 'at' $nowIso) }
            $carried = [ordered]@{}
            foreach ($f in @('title', 'url', 'summary', 'sourceId', 'category', 'tech',
                             'install', 'author', 'publisherName', 'publisherTier')) {
                $v = Get-Prop $row $f $null
                if ($null -ne $v) { $carried[$f] = $v }
            }
            $carried['firstSeen'] = $rowSeen
            $carried['firstSeenBasis'] = 'snapshot-floor'
            $carried['lastSeen'] = (Get-Prop $row 'lastSeen' (Get-Prop $row 'at' $nowIso))
            foreach ($f in @('metric', 'at', 'momentum')) {
                $v = Get-Prop $row $f $null
                if ($null -ne $v) { $carried[$f] = $v }
            }
            $row = [pscustomobject]$carried
        }
        $next[$k] = $row
    }

    $dir = Split-Path -Parent $HistoryPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = $HistoryPath + '.tmp'
    # depth 6: root -> row -> tech array -> string, with headroom. PowerShell's depth
    # counting silently truncates to "System.Object[]" rather than failing, so this is
    # set above what the shape needs on purpose.
    [System.IO.File]::WriteAllText($tmp, ($next | ConvertTo-Json -Depth 6 -Compress), (New-Object System.Text.UTF8Encoding($false)))
    Move-FileWithRetry -From $tmp -To $HistoryPath
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
    Move-FileWithRetry -From $tmp -To $Path
}

# Move-Item over a file another process is reading fails on Windows; the server
# reads these files between polls. Retry a few times, then fall back to a copy so
# a progress-file hiccup can never abort a fetch.
function Move-FileWithRetry {
    param([string]$From, [string]$To, [int]$Attempts = 6)
    for ($i = 1; $i -le $Attempts; $i++) {
        try { Move-Item -Path $From -Destination $To -Force -ErrorAction Stop; return }
        catch { Start-Sleep -Milliseconds (50 * $i) }
    }
    try { Copy-Item -Path $From -Destination $To -Force -ErrorAction Stop; Remove-Item -Path $From -Force -ErrorAction SilentlyContinue }
    catch { }
}

function Invoke-RadarSync {
    param([string]$Root, [switch]$Quiet)

    $config = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'config\sources.json') | ConvertFrom-Json
    $all = New-Object System.Collections.Generic.List[object]
    $health = New-Object System.Collections.Generic.List[object]
    $started = [datetime]::UtcNow

    $dataDir = Join-Path $Root 'data'
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

    # One sync at a time, across processes: a scheduled task and the server must
    # not write the same files together. A stale lock (dead pid) is taken over.
    $lockPath = Join-Path $dataDir 'sync.lock'
    $lock = $null
    try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read) }
    catch {
        $ownerPid = 0
        try { $ownerPid = [int](Get-Content -Raw $lockPath -ErrorAction Stop) } catch { }
        $alive = $false
        if ($ownerPid -gt 0) { $alive = [bool](Get-Process -Id $ownerPid -ErrorAction SilentlyContinue) }
        if ($alive) { throw "another sync is running (pid $ownerPid)" }
        Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
        $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    }
    $pidBytes = [System.Text.Encoding]::ASCII.GetBytes("$PID")
    $lock.Write($pidBytes, 0, $pidBytes.Length); $lock.Flush()
    try {
    $statusPath = Join-Path $dataDir 'status.json'
    $enabled = @($config.sources | Where-Object { Get-Prop $_ 'enabled' $true })
    $done = 0
    # the previous run, for stale-while-error retention
    $previous = $null
    $prevPath = Join-Path $dataDir 'trends.json'
    if (Test-Path $prevPath) { try { $previous = Get-Content -Raw -Encoding UTF8 $prevPath | ConvertFrom-Json } catch { $previous = $null } }
    Write-RadarStatus -Path $statusPath -State 'syncing' -StartedAt $started -Done 0 -Total $enabled.Count -Current '' -Sources @()

    # Fetching is 96% of a sync and every source waits on a different host, so the
    # sources are fetched CONCURRENTLY. Windows PowerShell 5.1 has no
    # ForEach-Object -Parallel, so this is a runspace pool: each worker dot-sources
    # this file and calls one fetcher.
    #
    # Two invariants survive the change:
    #   * results are merged in CONFIG ORDER, not completion order, because dedupe
    #     is first-wins and config order is therefore priority order
    #   * every per-source field - status, count, ms, message - means exactly what
    #     it meant sequentially, and ms is still that source's own elapsed time
    $maxParallel = [int](Get-Prop $config.defaults 'parallelFetches' 8)
    if ($maxParallel -lt 1) { $maxParallel = 1 }
    # .NET caps outbound connections per host at 2 by default, which would serialise
    # the several sources that share a host (GitHub, Hugging Face).
    if ([Net.ServicePointManager]::DefaultConnectionLimit -lt ($maxParallel * 4)) {
        [Net.ServicePointManager]::DefaultConnectionLimit = $maxParallel * 4
    }

    $libPath = Join-Path $Root 'lib\sources.ps1'
    $worker = {
        param($LibPath, $Source, $Defaults)
        . $LibPath
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $fetched = $null
            switch ($Source.kind) {
                'skills-sh'     { $fetched = Get-SkillsShItems -Source $Source -Defaults $Defaults }
                'github-search' { $fetched = Get-GitHubItems   -Source $Source -Defaults $Defaults }
                'hn'            { $fetched = Get-HnItems       -Source $Source -Defaults $Defaults }
                'rss'           { $fetched = Get-RssItems      -Source $Source -Defaults $Defaults }
                'json-api'      { $fetched = Get-JsonApiItems  -Source $Source -Defaults $Defaults }
                default         { throw ("unknown source kind '" + $Source.kind + "' -- add a fetcher in lib/sources.ps1") }
            }
            $sw.Stop()
            return [pscustomobject]@{ ok = $true; items = @($fetched); ms = [int]$sw.ElapsedMilliseconds; error = '' }
        }
        catch {
            $sw.Stop()
            return [pscustomobject]@{ ok = $false; items = @(); ms = [int]$sw.ElapsedMilliseconds; error = $_.Exception.Message }
        }
    }

    # Measured: preloading the library through InitialSessionState.StartupScripts
    # serialises runspace creation and doubled the sync (31 s -> 60 s). Each job
    # dot-sourcing the file is the faster arrangement, counter-intuitive as it looks.
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxParallel)
    $pool.ApartmentState = 'MTA'
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]
    $result = @{}
    try {
        foreach ($src in $config.sources) {
            if (-not (Get-Prop $src 'enabled' $true)) { continue }
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker).AddArgument($libPath).AddArgument($src).AddArgument($config.defaults)
            $jobs.Add([pscustomobject]@{ src = $src; ps = $ps; handle = $ps.BeginInvoke() })
        }

        # report progress while they run; the listener polls status.json meanwhile
        $lastWrite = [datetime]::UtcNow.AddSeconds(-10)
        while ($true) {
            $finished = @($jobs | Where-Object { $_.handle.IsCompleted }).Count
            if (([datetime]::UtcNow - $lastWrite).TotalMilliseconds -ge 500 -or $finished -eq $jobs.Count) {
                $current = ''
                $running = @($jobs | Where-Object { -not $_.handle.IsCompleted })
                if ($running.Count -gt 0) { $current = $running[0].src.label }
                try { Write-RadarStatus -Path $statusPath -State 'syncing' -StartedAt $started -Done $finished -Total $enabled.Count -Current $current -Sources $health } catch { }
                $lastWrite = [datetime]::UtcNow
            }
            if ($finished -eq $jobs.Count) { break }
            Start-Sleep -Milliseconds 120
        }
    }
    finally {
        foreach ($j in $jobs) {
            $r = $null
            try { $r = @($j.ps.EndInvoke($j.handle)) | Select-Object -First 1 } catch { $r = $null }
            if ($null -eq $r) {
                $r = [pscustomobject]@{ ok = $false; items = @(); ms = 0; error = 'worker produced no result' }
            }
            $result[$j.src.id] = $r
            $j.ps.Dispose()
        }
        $pool.Close(); $pool.Dispose()
    }

    # merge in CONFIG ORDER: dedupe is first-wins, so this is the priority order
    foreach ($src in $config.sources) {
        if (-not (Get-Prop $src 'enabled' $true)) {
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = 'disabled'; count = 0; fetched = 0; cap = 0; saturated = $false; message = 'disabled in config'; ms = 0 })
            continue
        }
        $r = $result[$src.id]
        if ($r.ok) {
            $fetched = @($r.items)
            $raw = $fetched.Count
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
            # A source that returned exactly its configured maxItems did not run out
            # of material, it ran out of permission. Without this flag every count in
            # the radar is partly a reading of config/sources.json rather than of the
            # world, and nobody can tell which. `fetched` is the count BEFORE the
            # regex gates, so saturation means the cap bit, not that a filter did.
            $cap = [int](Get-Prop $src 'maxItems' (Get-Prop $config.defaults 'maxItems' 25))
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = $status; count = $n; fetched = $raw; cap = $cap; saturated = ($raw -ge $cap); message = ''; ms = $r.ms })
            if (-not $Quiet) {
                $colour = 'DarkGray'
                if ($n -eq 0) { $colour = 'DarkYellow' }
                Write-Host ("  {0,-22} {1,4} items {2,6} ms" -f $src.id, $n, $r.ms) -ForegroundColor $colour
            }
        }
        else {
            # Stale-while-error: a feed that answers 429 once must not vanish from
            # the radar for a whole cycle. Its items from the previous run are kept
            # and the source is reported as stale, not failed, when there were any.
            $kept = @()
            if ($previous -and $previous.items) { $kept = @($previous.items | Where-Object { $_.sourceId -eq $src.id }) }
            foreach ($k in $kept) { $all.Add($k) }
            $status = 'failed'
            if ($kept.Count -gt 0) { $status = 'stale' }
            $health.Add([pscustomobject]@{ id = $src.id; label = $src.label; category = $src.category; status = $status; count = $kept.Count; fetched = 0; cap = [int](Get-Prop $src 'maxItems' (Get-Prop $config.defaults 'maxItems' 25)); saturated = $false; message = $r.error; ms = $r.ms })
            if (-not $Quiet) { Write-Host ("  {0,-22} {1}  {2}" -f $src.id, $status.ToUpper(), $r.error) -ForegroundColor DarkRed }
        }
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

    Set-RadarMomentum -Items $items -HistoryPath (Join-Path $Root 'data\ledger.json') -MinBaselineHours (Get-Prop $config.heat 'minBaselineHours' 12)
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
    Move-FileWithRetry -From $tmp -To (Join-Path $dataDir 'trends.json')
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
    finally {
        if ($lock) { $lock.Close(); Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue }
    }
}
