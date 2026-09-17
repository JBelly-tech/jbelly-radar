# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

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
