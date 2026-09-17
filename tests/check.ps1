# tests/check.ps1 — the whole test suite. Deterministic, no network, no model.
#
#   powershell -ExecutionPolicy Bypass -File tests\check.ps1
#
# Exits 0 when clean, 1 with one FAIL line per finding.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fail = New-Object System.Collections.Generic.List[string]
$checks = 0

function Read-Utf8([string]$p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }

# ── 1. every PowerShell file parses ───────────────────────────────────────────

foreach ($f in Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File) {
    $checks++
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        foreach ($e in $errors) { $fail.Add("parse error: $($f.Name):$($e.Extent.StartLineNumber) $($e.Message)") }
    }
}

# ── 2. the source configuration is well formed ────────────────────────────────

$configPath = Join-Path $root 'config\sources.json'
$checks++
if (-not (Test-Path $configPath)) { $fail.Add('missing config/sources.json') }
else {
    $config = $null
    try { $config = Read-Utf8 $configPath | ConvertFrom-Json } catch { $fail.Add("config/sources.json is not valid JSON: $($_.Exception.Message)") }

    if ($config) {
        $knownKinds = @('skills-sh', 'github-search', 'hn', 'rss')
        $ids = @{}
        foreach ($s in $config.sources) {
            $checks++
            foreach ($k in 'id', 'label', 'kind', 'category') {
                if (-not $s.PSObject.Properties[$k]) { $fail.Add("source is missing '$k': $($s.id)") }
            }
            if ($s.kind -and ($knownKinds -notcontains $s.kind)) { $fail.Add("unknown kind '$($s.kind)' in source '$($s.id)' -- add a fetcher in lib/sources.ps1") }
            if ($s.id) {
                if ($ids.ContainsKey($s.id)) { $fail.Add("duplicate source id: $($s.id)") }
                $ids[$s.id] = $true
            }
            if ($s.kind -eq 'rss' -and -not $s.url) { $fail.Add("rss source without a url: $($s.id)") }
            foreach ($rx in 'requireMatch', 'excludeMatch') {
                if ($s.PSObject.Properties[$rx] -and $s.$rx) {
                    try { [void][regex]::new($s.$rx) } catch { $fail.Add("invalid $rx regex in '$($s.id)': $($_.Exception.Message)") }
                }
            }
        }

        $checks++
        foreach ($cat in $config.heat.categories.PSObject.Properties.Name) {
            $c = $config.heat.categories.$cat
            if ($c.halfLifeDays -le 0) { $fail.Add("heat.categories.$cat.halfLifeDays must be > 0") }
        }
        $w = $config.heat.weights
        $sum = [double]$w.recency + [double]$w.popularity + [double]$w.momentum
        if ([math]::Abs($sum - 1.0) -gt 0.001) { $fail.Add("heat.weights must sum to 1.0, found $sum") }

        # every category used by a source must have a heat profile
        foreach ($s in $config.sources) {
            if ($s.category -and -not $config.heat.categories.PSObject.Properties[$s.category]) {
                $fail.Add("source '$($s.id)' uses category '$($s.category)' with no entry in heat.categories")
            }
        }
    }
}

# ── 3. tokens: no raw colour outside tokens.css ───────────────────────────────

$rawColour = '(#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\()'
foreach ($f in Get-ChildItem -Path (Join-Path $root 'app') -File) {
    if ($f.Name -eq 'tokens.css') { continue }
    $checks++
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
        $n++
        # data: URIs carry the favicon's colour and cannot reference a token;
        # a fragment link (href="#feed") is not a hex colour.
        if ($line -match 'data:image/svg') { continue }
        if ($line -match 'href="#') { continue }
        if ($line -match $rawColour) {
            # rgb(... / alpha) inside a shadow token is allowed only in tokens.css
            $fail.Add("raw colour outside tokens.css: $($f.Name):${n}  $($line.Trim())")
        }
    }
}

# ── 4. the page's structural guarantees ───────────────────────────────────────

$indexPath = Join-Path $root 'app\index.html'
$checks++
if (-not (Test-Path $indexPath)) { $fail.Add('missing app/index.html') }
else {
    $html = Read-Utf8 $indexPath

    $h1 = ([regex]::Matches($html, '<h1[\s>]')).Count
    if ($h1 -ne 1) { $fail.Add("index.html must have exactly one <h1>, found $h1") }

    if ($html -notmatch 'class="skip-link"') { $fail.Add('index.html has no skip link') }
    if ($html -notmatch '\blang="') { $fail.Add('index.html has no lang attribute') }
    if ($html -notmatch '\bdir="') { $fail.Add('index.html has no dir attribute') }

    # exactly one primary action on the view
    $primaries = ([regex]::Matches($html, 'btn--primary')).Count
    if ($primaries -ne 1) { $fail.Add("index.html must have exactly one btn--primary, found $primaries") }

    # every icon-only button is labelled
    foreach ($m in [regex]::Matches($html, '<button[^>]*class="[^"]*btn--icon[^"]*"[^>]*>')) {
        if ($m.Value -notmatch 'aria-label=') { $fail.Add("icon-only button without aria-label: $($m.Value)") }
    }

    # no emoji as icons (jbelly-ui rule)
    if ($html -match '[\uD800-\uDBFF][\uDC00-\uDFFF]') { $fail.Add('index.html contains emoji -- icons must be inline SVG') }

    # no external origin: the dashboard runs offline once the data is synced
    foreach ($m in [regex]::Matches($html, '(?:src|href)="(https?:)?//[^"]+"')) {
        $fail.Add("index.html loads an external resource, which breaks offline use: $($m.Value)")
    }
}

# ── 5. generated data is not committed ────────────────────────────────────────

$checks++
$ignore = Read-Utf8 (Join-Path $root '.gitignore')
foreach ($p in 'data/trends.json', 'data/trends.js', 'data/history/') {
    if ($ignore -notmatch [regex]::Escape($p)) { $fail.Add("$p must be listed in .gitignore -- generated data is never committed") }
}

# ── report ────────────────────────────────────────────────────────────────────

if ($fail.Count -gt 0) {
    foreach ($x in $fail) { Write-Output ("FAIL " + $x) }
    Write-Output ("{0} failure(s) across {1} checks" -f $fail.Count, $checks)
    exit 1
}
Write-Output ("OK - {0} checks passed" -f $checks)
exit 0
