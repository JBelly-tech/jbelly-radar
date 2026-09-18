# lib/reputation.ps1 — who published this, and how much does that count.
#
# Two signals, combined:
#   1. config/publishers.json — a curated list of organisations with a tier
#      (1 = global platform owner, 2 = major tech/AI company or foundation,
#      3 = notable startup or lab), their GitHub logins and their web domains.
#      Curated on purpose: "famous" is a judgement, and a judgement belongs in a
#      reviewable file, not in a formula.
#   2. GitHub's own organisation record — is_verified, followers, public_repos —
#      for repository publishers the list does not know. Looked up live, at most
#      -MaxLookups per sync, cached in data/history/orgs.json for 30 days, so an
#      unlisted-but-verified organisation is still recognised. Dynamic where the
#      list is static.
#
# Result: item.publisher = { key, name, tier, verified, followers } or $null.

function Get-HostName {
    param([string]$Url)
    try {
        $u = [uri]$Url
        $h = $u.Host.ToLowerInvariant()
        if ($h.StartsWith('www.')) { $h = $h.Substring(4) }
        return $h
    } catch { return '' }
}

function Get-GitHubOwner {
    param([string]$Url)
    try {
        $u = [uri]$Url
        if ($u.Host -notmatch '(^|\.)github\.com$') { return '' }
        $segs = $u.AbsolutePath.Trim('/').Split('/')
        if ($segs.Count -ge 1 -and $segs[0]) { return $segs[0].ToLowerInvariant() }
    } catch { }
    return ''
}

function New-PublisherIndex {
    param($Publishers)
    $byLogin  = @{}
    $byDomain = @{}
    $byKey    = @{}
    foreach ($p in @($Publishers.publishers)) {
        $byKey[$p.key] = $p
        foreach ($l in @($p.github))  { if ($l) { $byLogin[$l.ToLowerInvariant()] = $p } }
        foreach ($d in @($p.domains)) { if ($d) { $byDomain[$d.ToLowerInvariant()] = $p } }
    }
    return [pscustomobject]@{ byLogin = $byLogin; byDomain = $byDomain; byKey = $byKey }
}

# Walk up the host: blog.cloudflare.com → cloudflare.com → (stop at the registrable domain).
function Find-DomainPublisher {
    param([string]$HostName, $Index)
    if (-not $HostName) { return $null }
    $parts = $HostName.Split('.')
    for ($i = 0; $i -le $parts.Count - 2; $i++) {
        $candidate = ($parts[$i..($parts.Count - 1)] -join '.')
        if ($Index.byDomain.ContainsKey($candidate)) { return $Index.byDomain[$candidate] }
    }
    return $null
}

function Get-OrgCache {
    param([string]$Path)
    $cache = @{}
    if (Test-Path $Path) {
        try {
            $loaded = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
            foreach ($p in $loaded.PSObject.Properties) { $cache[$p.Name] = $p.Value }
        } catch { $cache = @{} }
    }
    return $cache
}

function Save-OrgCache {
    param([string]$Path, $Cache)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $ordered = [ordered]@{}
    foreach ($k in ($Cache.Keys | Sort-Object)) { $ordered[$k] = $Cache[$k] }
    [System.IO.File]::WriteAllText($Path, ($ordered | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-GitHubOrgRecord {
    param([string]$Login, [int]$TimeoutSec = 15)
    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $token = $null
    if ($env:GITHUB_TOKEN) { $token = $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $token = $env:GH_TOKEN }
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    try {
        # /orgs carries is_verified; /users does not. Try the organisation record
        # first and fall back to the user record for personal accounts.
        $r = $null
        try { $r = Invoke-RestMethod -Uri "https://api.github.com/orgs/$Login" -Headers $headers -TimeoutSec $TimeoutSec -UserAgent 'jbelly-radar/1.0' -ErrorAction Stop }
        catch {
            $status = 0
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if ($status -ne 404) { throw }
            $r = Invoke-RestMethod -Uri "https://api.github.com/users/$Login" -Headers $headers -TimeoutSec $TimeoutSec -UserAgent 'jbelly-radar/1.0' -ErrorAction Stop
        }
        return [pscustomobject]@{
            login       = $Login
            type        = "$($r.type)"                                   # User | Organization
            verified    = [bool](Get-Prop $r 'is_verified' $false)
            followers   = [int](Get-Prop $r 'followers' 0)
            publicRepos = [int](Get-Prop $r 'public_repos' 0)
            name        = "$(Get-Prop $r 'name' $Login)"
            checkedAt   = [datetime]::UtcNow.ToString('o')
        }
    }
    catch {
        # A 404 (renamed / deleted) is worth remembering for a week; a 403 (rate
        # limit) or a network error only for an hour, or the miss would hide a real
        # organisation for a month.
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        $ttlHours = 1
        if ($status -eq 404) { $ttlHours = 24 * 7 }
        return [pscustomobject]@{ login = $Login; type = ''; verified = $false; followers = 0; publicRepos = 0; name = $Login; checkedAt = [datetime]::UtcNow.ToString('o'); error = $_.Exception.Message; ttlHours = $ttlHours }
    }
}

function Set-RadarPublishers {
    param($Items, $Publishers, [string]$CachePath, [int]$MaxLookups = 20, [int]$CacheDays = 30, [switch]$Quiet)

    $index = New-PublisherIndex -Publishers $Publishers
    $cache = Get-OrgCache -Path $CachePath
    $lookups = 0
    $seenThisRun = @{}
    $now = [datetime]::UtcNow

    foreach ($it in $Items) {
        $pub = $null
        $owner = Get-GitHubOwner -Url $it.url
        if (-not $owner -and $it.author -and ($it.author -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')) {
            $owner = ($it.author -split '/')[0].ToLowerInvariant()   # skills.sh items carry owner/repo as author
        }

        # 1. curated list, by login then by domain. On a hosting platform the host
        #    says nothing about the author: github.com/someone is not GitHub's work,
        #    huggingface.co/someone is not Hugging Face's. There the path owner is
        #    the only signal, and only an exact login match counts.
        $entry = $null
        $hostName = Get-HostName -Url $it.url
        $isPlatform = $false
        foreach ($ph in @($Publishers.platformHosts)) { if ($hostName -eq $ph -or $hostName.EndsWith('.' + $ph)) { $isPlatform = $true; break } }
        if (-not $owner -and $isPlatform) {
            try { $segs = ([uri]$it.url).AbsolutePath.Trim('/').Split('/'); if ($segs.Count -ge 2 -and $segs[0]) { $owner = $segs[0].ToLowerInvariant() } } catch { }
        }
        # a registry that links every entry to its own repository is not the author
        foreach ($own in @($Publishers.registryRepos)) { if ($it.url -match ('^https?://github\.com/' + [regex]::Escape($own) + '(/|$)')) { $owner = '' } }
        if ($owner -and $index.byLogin.ContainsKey($owner)) { $entry = $index.byLogin[$owner] }
        if (-not $entry -and -not $isPlatform) { $entry = Find-DomainPublisher -HostName $hostName -Index $index }
        if ($entry) {
            $pub = [pscustomobject]@{ key = $entry.key; name = $entry.name; tier = [int]$entry.tier; sector = "$(Get-Prop $entry 'sector' '')"; verified = $true; followers = $null }
        }
        # 2. GitHub's record for an unlisted repository owner (GitHub URLs only —
        #    a Hugging Face namespace is not a GitHub login)
        elseif ($owner -and (Get-GitHubOwner -Url $it.url)) {
            $rec = $null
            if ($cache.ContainsKey($owner)) {
                $rec = $cache[$owner]
                $ageHours = ($now - (ConvertTo-Utc $rec.checkedAt)).TotalHours
                $ttl = [double]$CacheDays * 24
                $recTtl = Get-Prop $rec 'ttlHours' $null
                if ($null -ne $recTtl) { $ttl = [double]$recTtl }
                if ($ageHours -gt $ttl) { $rec = $null }
            }
            if (-not $rec -and $lookups -lt $MaxLookups -and -not $seenThisRun.ContainsKey($owner)) {
                $seenThisRun[$owner] = $true
                $rec = Get-GitHubOrgRecord -Login $owner
                $cache[$owner] = $rec
                $lookups++
            }
            if ($rec -and $rec.type -eq 'Organization' -and ($rec.verified -or $rec.followers -ge 2000)) {
                $pub = [pscustomobject]@{ key = $owner; name = $rec.name; tier = $null; sector = ''; verified = [bool]$rec.verified; followers = [int]$rec.followers }
            }
        }

        $it | Add-Member -NotePropertyName 'publisher' -NotePropertyValue $pub -Force
    }

    if ($lookups -gt 0) { Save-OrgCache -Path $CachePath -Cache $cache }
    if (-not $Quiet -and $lookups -gt 0) { Write-Host ("  {0} GitHub org lookups (cached for {1} days)" -f $lookups, $CacheDays) -ForegroundColor DarkGray }
}
