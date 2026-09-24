# scripts/build-pages.ps1 - stage the public demo for a static host.
#
# Produces a directory that can be served by GitHub Pages, or by anything else
# that serves files, showing the real dashboard over a frozen snapshot.
#
#   pwsh -File scripts/build-pages.ps1
#   pwsh -File scripts/build-pages.ps1 -OutDir /tmp/site
#
# The layout deliberately MIRRORS the repository: app/ stays at app/ and data/
# stays at data/, with a redirect at the root. Flattening them would change
# every relative path, and app/js/live.js works out where the data lives from
# its own script URL -- so a flattened demo would be a different page that only
# looked like this one. The point of a demo is that it is the same page.
#
# What makes it static rather than live is one flag. window.RADAR_STATIC tells
# app/index.html to load the .js snapshots instead of fetching, and tells
# live.js not to poll an API that is not there. Without it the page would ask
# /api/status forever and eventually tell the visitor the server is
# unreachable, which would be false: it was never there.
#
# Deterministic, no network of its own. Run a sync first; this only stages.

[CmdletBinding()]
param(
    [string]$OutDir = '',
    [switch]$Sample,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist/site' }

# -Sample builds from the committed snapshot in data/sample/ instead of from a
# live sync. That is what the published demo uses, on purpose:
#
#   a demo that re-syncs runs on the OWNER'S account forever -- their Actions,
#   their name in the user agent, their machine asking 54 other people's servers
#   for data every single day, to show strangers a page. The point of the demo is
#   that someone sees the shape and then runs it themselves. A frozen sample does
#   that exactly as well, costs nobody anything after the day it was taken, and
#   is more honest besides: it cannot pretend to be live.
$dataDir = Join-Path $root 'data'
if ($Sample) { $dataDir = Join-Path $root 'data/sample' }

foreach ($needed in @('trends.js', 'taxonomy.js')) {
    if (-not (Test-Path (Join-Path $dataDir $needed))) {
        if ($Sample) { Write-Output "missing data/sample/$needed" }
        else { Write-Output "missing data/$needed - run a sync first (pwsh -File scripts/sync.ps1)" }
        exit 1
    }
}

# The sample ships only the .js files. They are the same payload as trends.json
# wrapped in one assignment, so the counts are read back out of the wrapper
# rather than committing a second 634 KB copy of the same bytes.
$trendsPath = Join-Path $dataDir 'trends.json'
if (Test-Path $trendsPath) {
    $trends = Get-Content -Raw -Encoding UTF8 $trendsPath | ConvertFrom-Json
}
else {
    $wrapped = Get-Content -Raw -Encoding UTF8 (Join-Path $dataDir 'trends.js')
    $trends = ($wrapped -replace '^\s*window\.RADAR_DATA\s*=\s*', '').TrimEnd() -replace ';$', '' | ConvertFrom-Json
}
$stamp = ([datetime]::Parse($trends.generatedAt)).ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$okSources = @($trends.sources | Where-Object { $_.status -eq 'ok' }).Count

if (Test-Path $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

Copy-Item -Path (Join-Path $root 'app') -Destination (Join-Path $OutDir 'app') -Recurse -Force

# The operator console reads /api/*, which does not exist on a static host, so it
# would have nothing to show but its own error state. Left out rather than shipped
# broken.
$ops = Join-Path $OutDir 'app/ops'
if (Test-Path $ops) { Remove-Item -LiteralPath $ops -Recurse -Force }

New-Item -ItemType Directory -Path (Join-Path $OutDir 'data') -Force | Out-Null
Copy-Item (Join-Path $dataDir 'trends.js') (Join-Path $OutDir 'data/trends.js') -Force
Copy-Item (Join-Path $dataDir 'taxonomy.js') (Join-Path $OutDir 'data/taxonomy.js') -Force

# -- the one edit that makes it static ----------------------------------------
# Anchored on the comment that introduces the block which reads the flag, so if
# that block is ever rewritten this fails loudly here instead of silently
# shipping a page that polls an API it will never reach.
$indexPath = Join-Path $OutDir 'app/index.html'
$html = [System.IO.File]::ReadAllText($indexPath)
$anchor = '<script>' + "`n" + '  // No API behind this page'
if ($html -notmatch [regex]::Escape('// No API behind this page')) {
    Write-Output 'app/index.html no longer has the static-snapshot block this build depends on'
    exit 1
}
$flag = @'
<script>
  /* Built by scripts/build-pages.ps1. This page is a published snapshot: there
     is no radar.ps1 behind it, so it reads the bundled data and does not poll. */
  window.RADAR_STATIC = true;
</script>
'@
$html = $html.Replace($anchor, $flag + $anchor)

# A visitor must be told this is a snapshot without having to infer it from
# stale numbers. It uses the page's own tokens, so it follows light, dark and RTL.
$banner = @"
<div class="demo-note" dir="auto">
  <span><strong>Beta &middot; sample data</strong> &middot; $($trends.counts.total) signals from $okSources sources, collected once on $stamp UTC. This page does not update &mdash; it is here to show the shape.</span>
  <a href="https://github.com/JBelly-tech/jbelly-radar">Run it yourself for a live radar &rarr;</a>
</div>
<style>
  .demo-note {
    display: flex; flex-wrap: wrap; gap: .5rem 1rem; align-items: center; justify-content: center;
    padding: .5rem 1rem; font-size: 12px; line-height: 1.5;
    background: var(--muted); color: var(--muted-foreground);
    border-bottom: 1px solid var(--border);
  }
  .demo-note a { color: var(--primary); text-decoration: none; font-weight: 500; }
  .demo-note a:hover { text-decoration: underline; }
</style>
"@
if ($html -notmatch '<body[^>]*>') {
    Write-Output 'app/index.html has no <body> tag to place the snapshot notice after'
    exit 1
}
$html = [regex]::Replace($html, '(<body[^>]*>)', ('$1' + "`n" + $banner), 1)
[System.IO.File]::WriteAllText($indexPath, $html, $utf8)

# -- the root redirect --------------------------------------------------------
# Pages serves / and the dashboard lives at /app/. A redirect keeps the layout
# identical to the repository while still landing a visitor on the page.
$redirect = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>JBelly Radar</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="0; url=app/">
<link rel="canonical" href="app/">
</head>
<body>
<p>Loading the radar. <a href="app/">Continue &rarr;</a></p>
</body>
</html>
'@
[System.IO.File]::WriteAllText((Join-Path $OutDir 'index.html'), $redirect, $utf8)

# Pages runs Jekyll unless told not to, and Jekyll ignores files and folders
# whose names begin with an underscore. Nothing here starts with one today, but
# a build that silently drops a file later is a bad way to find that out.
[System.IO.File]::WriteAllText((Join-Path $OutDir '.nojekyll'), '', $utf8)

$files = @(Get-ChildItem -Path $OutDir -Recurse -File)
$bytes = ($files | Measure-Object -Property Length -Sum).Sum
if (-not $Quiet) {
    Write-Output ("staged {0} files, {1:N0} KB, into {2}" -f $files.Count, ($bytes / 1KB), $OutDir)
    Write-Output ("  snapshot: {0} signals from {1} sources, {2} UTC" -f $trends.counts.total, $okSources, $stamp)
}
exit 0
