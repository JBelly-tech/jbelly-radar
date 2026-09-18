# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [0.2.0] — 2026-09-18

The radar becomes live, personal and organisation-aware.

### Added

- **Publisher reputation** — `config/publishers.json`, 149 organisations in
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
- **Client modules** under `app/js/` with a browser harness each (326
  assertions) and `tests/run-harness.ps1` to run them headlessly.
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
