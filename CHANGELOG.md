# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

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
