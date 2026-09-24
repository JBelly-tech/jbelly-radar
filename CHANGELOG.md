# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [0.4.0-beta] — 2026-09-24

**First public release, and it is a beta.** Everything here works and is
tested — 302 static checks, 333 browser assertions, CI green on Linux and
Windows — but it has been used in earnest by one person, on one operating
system. The two places most likely to bite first are the macOS code paths,
which CI cannot reach, and the plan matcher, which is the newest code and the
only part that makes a judgement rather than a measurement. Treat its verdicts
as a shortlist, not an answer, and please say where it is wrong.

The published demo runs on **committed sample data and does not update**. A
demo that re-synced would run forever on the maintainer's account and point 54
other people's servers at a page shown to strangers; a frozen sample shows the
same shape and costs nobody anything after the day it was taken.

The ledger becomes a catalogue: it remembers what an item was, not only that it
was.

### Added

- **Identity on every ledger row** — `title`, `url`, `summary`, `sourceId`,
  `category`, `tech`, `install`, `author` and a flattened `publisherName` /
  `publisherTier`. `data/trends.json` holds one sync and every source is capped,
  so "is there a skill for X" asked against it answers *not in today's top N*
  while sounding like *does not exist* — the worst available failure for a
  question used to choose a technology. The ledger keeps every row it has ever
  written, so the same question asked there is answered from everything the
  radar has ever seen: **1,555 named rows against 750 in the current sync.**
- **`backfill-ledger.ps1` restores identity too**, from the dated snapshots,
  which are full `trends.json` dumps and still hold it: **805 rows named**, 160
  first-seen dates lowered. 308 rows stay anonymous and are reported as such —
  they were seen between daily snapshots, so no snapshot ever recorded them.
  Identity is only ever filled in, never overwritten: a live sync is fresher
  than any snapshot. Re-running changes nothing (verified).

- **Catalogue depth, separate from display depth.** `maxItems` was capping both
  what the dashboard ranks (right) and what is fetched (wrong — it threw away the
  answer before anything could ask). `catalogueMax` is now the fetch cap and
  `maxItems` the display cap. Nothing needed an extra request: skills.sh already
  ships ~600 matches in the page that 120 were read from, and the three registries
  were each asked for 50 and kept 20–25.

  | | dashboard | catalogue |
  |---|---|---|
  | all items | 752 (was 750) | **2,656** (was 1,555) |
  | skills | 155 | **800** (was 158) |
  | MCP servers | 54 | **441** (was 91) |

- **`scripts/match-plan.ps1`** answers, per requirement in a build plan: is there
  already a skill or an MCP server that covers this. `mode` picks the pool —
  `build` searches skills, `runtime` searches MCP servers — because the two solve
  different problems and mixing them is noise. Alternatives are only raised for a
  requirement the architect marked `open`. Deterministic: no model, no network.
- **`config/build.example.json`** is the plan format by example, and
  **`config/match-template.json`** holds every word the matcher writes, in English
  and Arabic.
- **Keyword discrimination.** A keyword matching more than a quarter of its pool
  is dropped and named in the report. Measured: `mode: runtime` already narrows to
  MCP servers, so the keyword `mcp` matched all 440, every candidate scored
  identically, and the report announced "covered" with a random server on top.
- **`metricLabel` on ledger rows** — 414,075 installs and 414,075 weekly downloads
  are not the same claim.

### Fixed

- **The browser harness ran on a flag Edge no longer honours.** `--dump-dom`
  produces empty output in Edge 153 — exit 0, no stderr, every headless mode, a
  clean profile — while `--screenshot` still renders. The runner now reads the
  page over the DevTools protocol, which returns the harness's own text with no
  HTML to un-escape, and polls until it prints `DONE` instead of waiting a fixed
  8 s. All 333 assertions pass again.
- **The harness leaked browsers.** Edge's launcher hands off and exits, so killing
  what was started killed nothing: five harnesses left 78 processes behind and the
  next run failed with nothing to report but silence. It now sweeps by
  `--user-data-dir`, unique per run, so it can never touch the browser the person
  running the tests has open.
- **npm claimed a false author.** Its search API returns
  `publisher.username = "GitHub Actions"` for every CI-published package and
  carries no author field, so every npm row was attributed to a build robot. The
  mapping is gone; those rows are unattributed, which is true.

### Known limits

- Three registries report far more than is read: Smithery 17,033 servers, npm
  74,790 packages keyworded `mcp`. Neither is paged. Depth beyond one response is
  not obviously worth it — most of that npm tail is abandoned scaffolds, and a
  catalogue full of them answers "is there an MCP for X" worse, not better. The
  measurement to make first is whether any real `no coverage` result is an
  artefact of depth.
- 302 ledger rows are still anonymous: seen between daily snapshots, so no
  snapshot ever recorded them. The matcher counts and reports them, because "no
  coverage" from a partly anonymous catalogue is a weaker claim than it looks.

## [0.3.0] — 2026-09-22

The radar starts keeping a record, and stops reporting numbers it cannot support.

### Added

- **A ledger.** `data/ledger.json` records, per item, the first sync that ever saw
  it, the last one that did, and the momentum baseline. It is the only artefact a
  re-run cannot reproduce, so unlike everything else under `data/` it is
  committed. 1,239 rows.
- **`scripts/backfill-ledger.ps1`** recovers first-seen from the dated snapshots
  the radar had been writing and nobody was reading: 594 dates corrected, 463
  items restored. It only ever moves a date earlier, so re-running is a no-op.
- **`firstSeenBasis`** on every row and item — `observed` when this radar watched
  the item arrive, `snapshot-floor` when it was already there when the record
  began. A floor is shown as *seen by*, never as *first appeared*.
- **`publishedMeaning`** per source: `posted`, `created`, `released`, `updated`,
  `indexed`, `none`. One field had been carrying six different events.
- **An operator console** at `/app/ops/` — source health, signal coverage, what
  heat was computed from, and arrivals by day. Every card says what to do when it
  goes red. A fourth section is deliberately empty and says so.
- **`scripts/brief.ps1`** writes a dated, bilingual brief per business vertical,
  joining the hand-written judgement in the taxonomy to what the radar saw, with
  citations frozen at write time. All 19 verticals, both languages.
- **`scripts/pack-demo.ps1`** bundles a demo that opens by double-click — no
  install, no server, no network, no account.
- **Source saturation**: every health row carries `fetched`, `cap` and
  `saturated`. 49 of 54 working sources return at their cap.
- **`LICENSE-DATA`**: the curated content and the observation record move to
  CC BY 4.0. The software stays MIT.

### Changed

- **Sources are fetched concurrently.** A full sync went from 85.9 s to 12 s.
  Verified identical against the sequential path: 748 items both ways, and zero
  items where a different source won the URL.
- **Heat stops guessing.** A term that cannot be measured is dropped and the
  remaining weights renormalised, instead of substituting 0.5. Where popularity
  cannot be measured, the publisher's tier stands in. A confidence factor scales
  the result by how much was measurable. Every item carries `heatBasis`.
- An item with no published date ages from `firstSeen` rather than being assumed
  to be exactly one half-life old.
- `radar.ps1` resolves any directory to its index, so adding a page no longer
  means editing the server.

### Fixed

- **Heat was a relabelled age for 43% of the corpus.** news, research and release
  declare `metricCeiling: 1`, so popularity fell to a constant and momentum was
  copied from it; those categories scored `0.4·recency + 0.30`, locked in 30..70.
- The Reddit source shipped with a browser user agent. Measured: Reddit answers
  429 to the spoof and 200 to an honest one, and its `robots.txt` disallows
  generic clients either way. It now ships disabled, with a note saying why.
- The README claimed 55 sources, listed Reddit as live, said a sync takes 90
  seconds, and described heat as three terms always present.
- `config/publishers.json` claimed an opt-in for the four listed individuals that
  was never obtained.

## [0.2.0] — 2026-09-18

The radar becomes live, personal and organisation-aware.

### Added

- **Publisher reputation** — `config/publishers.json`, 146 organisations in
  three tiers with GitHub logins and web domains; live GitHub organisation
  lookup (verified / followers) for owners not on the list, cached 30 days;
  `platformHosts` so a hosting platform is never mistaken for the author.
  Notable individuals as an opt-in tier 3. ADR 0003.
- **Technology tagging** — `config/taxonomy.json`, 46 technologies matched by
  deterministic keyword rules (`scope: title` for words that appear in every
  abstract); 19 business verticals, each mapped to the technologies that matter
  with one line of advice, in English and Arabic.
- **Personal score, client-side** — `For you` mode: heat + reputation +
  relevance to the profile + decayed behavioural affinity + an exploration
  term, with a *why this is here* explanation on every row; `Everything` keeps
  pure heat. Profile drawer (business, technologies, notable-only), saved and
  hidden lists with undo, export/import. ADR 0004.
- **Live server** — sync runs in a child process; `data/status.json` is
  written after every source; `/api/status` and `/api/sync`; automatic re-sync
  every `-Every` minutes; the page polls, merges new items in place and marks
  *new since your last visit*.
- **The radar scope** — SVG: sector = category, radius = heat, size = log
  popularity, one amber ramp, pulse for new items, outline for notable
  organisations, keyboard-reachable blips, screen-reader table, a single sweep
  on mount.
- **37 new sources** (56 total): official blogs and changelogs of Cloudflare,
  OpenAI, Anthropic, Google, GitHub, AWS, Meta, NVIDIA, Microsoft, Vercel,
  Stripe, Supabase, Docker, Mistral, Cursor; release feeds for Claude Code,
  `openai/codex`, `vercel/ai`, `cloudflare/agents`, MCP servers; Reddit,
  Lobsters, dev.to, Simon Willison, Product Hunt; the official MCP registry,
  Smithery, npm `mcp` packages, Hugging Face trending models and daily papers,
  arXiv cs.CL. Each fetched live before admission.
- **`json-api` source kind** with a config-side field map; per-source
  `userAgent`; newest-first capping for thousand-entry changelog feeds;
  stale-while-error retention (a source that fails keeps its last items and is
  shown as *stale*).
- **Client modules** under `app/js/`, with browser harnesses for i18n/icons,
  store, rank, live and scope (333 assertions) and `tests/run-harness.ps1` to
  run them headlessly.
- `docs/ARCHITECTURE.md` (the module contract), ADR 0003 and 0004, and the
  landscape study in `docs/research/`.

### Changed

- The heat meter and the signal-mix bars use one sequential hue; v1's four-hue
  ramp and rotating bar colours are retired (a single magnitude, a single hue).
- Release rows read *Publisher · version* instead of a bare version string.
- The static suite now validates the three config files (294 checks).

## [0.1.0] — 2026-09-17

First release.

### Added

- **Four source kinds** — `skills-sh`, `github-search`, `hn`, `rss` (RSS 2.0 and
  Atom, so an arXiv API query runs through the same path).
- **19 configured sources** across five categories: skill, repo, discussion,
  news, research. Adding a source is a JSON object; adding a kind is one
  function.
- **Deterministic ranking** — heat from recency, popularity and momentum, with
  the weights and per-category half-lives in `config/sources.json`.
- **Measured momentum** — metric baselines in `data/history/`, replaced only
  once older than `heat.minBaselineHours` (12), so two syncs minutes apart
  report no momentum rather than an invented one.
- **`radar.ps1`** — syncs when the cache is stale, serves the dashboard on
  `localhost`, opens the browser, and exposes `POST /api/sync` behind the
  dashboard's Refresh button.
- **`scripts/sync.ps1`** — headless sync for a scheduled task. A failed source
  is reported, never fatal.
- **Dashboard** — built on `jbelly-ui`: category filter, search, time range,
  four sort orders, top movers, signal mix, per-source health, keyboard
  shortcuts, light and dark, English and Arabic with RTL.
- **`tests/check.ps1`** — PowerShell parse check, source-config validation,
  token lint, page-structure checks, and a guard that generated data stays out
  of git.
