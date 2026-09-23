# scripts/pack-demo.ps1 - bundle a self-contained demo that opens by double-click.
#
# The dashboard already runs from file:// - app/index.html loads data/trends.js and
# data/taxonomy.js instead of fetching, when the protocol is file:. This copies the
# page, its assets and a frozen snapshot of the data into one zip, so somebody can
# see the radar without installing PowerShell, running a sync or trusting a server.
#
#   pwsh -File scripts/pack-demo.ps1
#   pwsh -File scripts/pack-demo.ps1 -OutFile D:\somewhere\radar-demo.zip
#
# The snapshot is frozen at pack time. It is a demo, not a live radar: it shows
# what the radar looked like on one date and does not update. The bundle says so,
# in the page and in its own README, so nobody mistakes a still for a feed.
#
# Deterministic, no network, no model call.

[CmdletBinding()]
param(
    [string]$OutFile = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root 'data'

foreach ($needed in @('trends.js', 'taxonomy.js')) {
    if (-not (Test-Path (Join-Path $dataDir $needed))) {
        Write-Output "missing data/$needed - run a sync first (pwsh -File scripts/sync.ps1)"
        exit 1
    }
}

$trends = Get-Content -Raw -Encoding UTF8 (Join-Path $dataDir 'trends.json') | ConvertFrom-Json
$stamp = ([datetime]::Parse($trends.generatedAt)).ToUniversalTime().ToString('yyyy-MM-dd')
$okSources = @($trends.sources | Where-Object { $_.status -eq 'ok' }).Count

if (-not $OutFile) { $OutFile = Join-Path $root ("dist/jbelly-radar-demo-$stamp.zip") }
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# stage in a temp tree, so the zip has exactly the paths the page expects
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('radar-demo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

try {
    Copy-Item -Path (Join-Path $root 'app') -Destination (Join-Path $stage 'app') -Recurse -Force
    # the operator console reads /api/*, which does not exist on file:// - leave it out
    # rather than ship a page that can only show its own error state
    $ops = Join-Path $stage 'app/ops'
    if (Test-Path $ops) { Remove-Item -LiteralPath $ops -Recurse -Force }

    New-Item -ItemType Directory -Path (Join-Path $stage 'data') -Force | Out-Null
    Copy-Item (Join-Path $dataDir 'trends.js') (Join-Path $stage 'data/trends.js') -Force
    Copy-Item (Join-Path $dataDir 'taxonomy.js') (Join-Path $stage 'data/taxonomy.js') -Force

    Copy-Item (Join-Path $root 'LICENSE') (Join-Path $stage 'LICENSE') -Force
    Copy-Item (Join-Path $root 'LICENSE-DATA') (Join-Path $stage 'LICENSE-DATA') -Force

    $readme = @"
JBelly Radar - offline demo
===========================

Open app\index.html in a browser. Nothing to install, no server, no account,
no network: every byte it needs is in this folder.

  items      $($trends.counts.total)
  sources    $okSources public sources, all fetched live
  snapshot   $stamp

WHAT THIS IS NOT
----------------
A frozen snapshot, not a live radar. The dates, the heat scores and the "new
since your last visit" marks are all as they stood on $stamp and will not
change. The real thing re-syncs in the background every 20 minutes; a full sync
takes about 12 seconds.

The operator console is not included: it reads the running server's API, so on
a file:// page it could only show its own error state.

WHAT WORKS HERE
---------------
Filtering by technology and by business vertical, the radar scope, the row
detail with its written reason, saving and hiding, English and Arabic with full
right-to-left, and light and dark. Personalisation is stored in this browser
only, exactly as in the real thing, and is never transmitted.

TO RUN THE REAL ONE
-------------------
Needs Windows PowerShell 5.1, which ships with Windows. No other dependency.

  git clone <the repository>
  cd jbelly-radar
  .\radar.ps1

LICENCE
-------
Software under MIT (LICENSE). The curated content and the observation record
under CC BY 4.0 (LICENSE-DATA) - free to use, including commercially, with
credit to JBelly Radar.
"@
    [System.IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($false)))

    if (Test-Path $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $OutFile)
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

$size = [math]::Round((Get-Item $OutFile).Length / 1KB)
if (-not $Quiet) {
    Write-Output ("demo packed: {0} items, {1} sources, snapshot {2}" -f $trends.counts.total, $okSources, $stamp)
    Write-Output ("  {0}  ({1} KB)" -f $OutFile, $size)
}
exit 0
