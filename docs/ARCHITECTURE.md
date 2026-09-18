# JBelly Radar — architecture (v2)

> **Status: v2 shipped (2026-09-18).** This document is the contract v2 was
> built against and is kept current: every module
> below names its file, its public surface and the shape it consumes. A module
> that needs something not written here is a change to this file first.

## What v2 adds, and why

| Owner goal | Mechanism | Where |
|---|---|---|
| "Not any repo is useful — highlight famous organizations" | **Publisher reputation**: a curated tier list (`config/publishers.json`) plus live GitHub org signals; a `reputation` term in the score; a *From notable organizations* rail | `lib/reputation.ps1`, `js/rank.js`, `js/ui.js` |
| "Filter by technology and by business" | **Deterministic taxonomy**: keyword rules tag every item with technologies; business verticals map to the technologies that matter for them, with one-line advice | `config/taxonomy.json`, `lib/classify.ps1`, `js/store.js` (profile) |
| "Order by user behaviour and experience" | **Client-side personalization**: clicks, saves, hides and dwell become decayed tag/source affinities; a *For you* mode re-ranks with an explainable score; *Everything* mode keeps pure heat | `js/store.js`, `js/rank.js` |
| "Dynamic, not static" | **Live server**: background sync process, `data/status.json` progress, `/api/status` polling; the page merges new items in place and marks *new since your last visit*; a **radar scope** visual where items are blips | `radar.ps1`, `js/live.js`, `js/scope.js` |
| "Sources people actually go to" | Research-verified official channels of major vendors, community hubs and directories, each fetched live before being admitted | `config/sources.json`, `docs/research/` |

Everything remains deterministic and keyless. There is still no model call in
the sync path; where a model *could* add value (a one-line "why it matters"
per item) it is an optional, cached, opt-in enrichment — never the ranking.

## Data shape (the contract)

`data/trends.json` — written by `Invoke-RadarSync`, read by every client module.

```jsonc
{
  "generatedAt": "2026-09-17T20:41:28Z",
  "durationMs": 31240,
  "counts": { "total": 512, "skill": 155, "repo": 90, "news": 160, "discussion": 60, "research": 32, "release": 15, "notable": 264 },
  "sources": [ { "id": "techcrunch-ai", "label": "TechCrunch · AI", "category": "news", "status": "ok|empty|stale|failed|disabled", "count": 20, "message": "", "ms": 333 } ],
  "publishers": { "cloudflare": { "name": "Cloudflare", "tier": 1, "sector": "cloud" } },   // only publishers seen this run
  "items": [
    {
      "id": "3f9c…",                     // stable: sha1 of canonical url, or of the source's own key
      "sourceId": "gh-mcp-servers", "sourceLabel": "GitHub · new MCP servers",
      "category": "skill|repo|news|discussion|research|release",
      "title": "…", "url": "https://…", "summary": "…", "author": "cloudflare",
      "metric": 1420, "metricLabel": "stars|installs|points|", "momentum": 38.2,   // momentum may be null
      "published": "2026-09-16T…", "ageDays": 1.3,                                  // both may be null
      "heat": 81,                                                                   // 0..100, server-side
      "tags": ["mcp-server","typescript"],                                          // raw source tags, ≤ 6
      "tech": ["mcp","agents","typescript"],                                        // taxonomy tags, ≤ 5, deterministic
      "publisher": { "key": "cloudflare", "name": "Cloudflare", "tier": 1, "verified": true }, // or null
      "spark": [ … ],                                                               // optional weekly series
      "install": "npx skills add owner/repo"                                        // optional
    }
  ]
}
```

New in v2: `publisher`, `tech`, the `release` category, the `publishers` map.
Everything else is unchanged from v1, so the v1 page keeps rendering v2 data.

`data/status.json` — written after every source during a sync:

```jsonc
{ "state": "syncing|idle", "startedAt": "…", "updatedAt": "…", "done": 13, "total": 27,
  "current": "Ars Technica · Technology", "generatedAt": "…", "sources": [ …health rows so far… ] }
```

`/api/status` returns it with `dataAt` (mtime of `trends.json`), `everyMinutes`
and `serverTime` added. `POST /api/sync` returns `202 {started: bool, status}`.

## Server (`radar.ps1`)

- Serves the project folder on `http://localhost:8477/`, static files only, path-confined.
- Sync runs in a **child PowerShell process** (`scripts/sync.ps1 -Quiet`), so the
  listener keeps answering during the ~90 s a sync takes. One sync at a time,
  across processes: `data/sync.lock` holds the pid of the running sync.
- Sync fires: at start when the cache is older than `-StaleMinutes`; every
  `-Every` minutes (default 20) while running; on `POST /api/sync`.
- Writes are atomic (temp file + rename), so a poll never reads a torn file.

## Ranking

Two layers, deliberately separate.

**Server — heat** (unchanged from v1, [ADR 0002](adr/0002-momentum-is-measured.md)):
`0.40 recency + 0.35 popularity + 0.25 momentum`, per-category half-lives and ceilings.

**Client — personal score** (`js/rank.js`), only in *For you* mode:

```
score = 0.45·heat/100
      + 0.20·reputation      // tier 1 → 1.0, tier 2 → 0.75, tier 3 → 0.5, verified org only → 0.35, else 0
      + 0.20·relevance       // 0..1: overlap of item.tech with the profile's technologies,
                             //       where the profile = chosen tech chips ∪ the chosen verticals' "technologies that matter"
      + 0.15·affinity        // 0..1 with 0.5 neutral: decayed sum of learned weights over item.tech, tags and sourceId
      + explore              // +0.04 for items whose tech the user has never interacted with, so the feed can surprise
```

`rank.score()` returns `{score, parts, why[]}`; `why` is rendered in the row's
tooltip ("Cloudflare · tier 1 · matches mcp, agents · you open Hacker News often")
so the order is never a black box. *Everything* mode sorts by heat only.
Reputation is **highlighted in both modes** (badge + rail); it only changes the
*order* in *For you*.

**Behaviour store** (`js/store.js`, localStorage, every access in try/catch):

| Event | Weight | Applied to |
|---|---|---|
| open link | +1.0 | item.tech, item.tags, item.sourceId |
| save | +2.0 | same |
| hide / "less like this" | −2.0 | same |
| dwell ≥ 8 s on an expanded row | +0.5 | same |

Weights decay with a 14-day half-life; `affinity()` returns the decayed map.
`markVisit()` records the ids on screen so *new since your last visit* is a diff,
not a timestamp guess.

## Client modules (`app/js/`)

Plain scripts (no `type="module"`, so `file://` keeps working), loaded in this
order, each attaching to `window.Radar`. **One file, one owner.**

| File | Exposes | Depends on |
|---|---|---|
| `i18n.js` | `Radar.i18n = { t(key), format(key, vars), lang, setLang(lang), dict }` — EN/AR dictionaries, `data-i18n` walker; `t('ago')` returns the `{m,h,d}` suffix object | — |
| `icons.js` | `Radar.icons[name]` — inline Lucide-style SVG strings | — |
| `store.js` | `Radar.store` — prefs (`theme`, `lang`, `mode`, `profile{verticals[],tech[],orgsOnly}`), behaviour events, `affinity()`, `saved()`, `isSaved/isHidden/isNew`, `markVisit(ids)`, `lastVisit` | — |
| `rank.js` | `Radar.rank = { score(item, ctx), order(items, ctx), reputationOf(item) }`; `ctx = { mode, profile, affinity, taxonomy }` | store (read-only) |
| `live.js` | `Radar.live = { start({onStatus, onData, onNewItems}), sync(), isServed }` — status polling (1.5 s while syncing, 45 s idle), data reload on `dataAt` change, id-diff for new items | — |
| `scope.js` | `Radar.scope = { mount(el, opts), update(items, {newIds, selectedId}), unmount() }` — the radar scope (SVG): sectors = category, radius = heat (hot at centre), blip size = log popularity, **one sequential hue** for heat via `data-step` 1–4 → `--heat-1..4`, pulse for new, tooltip + click; the container becomes `role="group"` with a `sr-only` table; `data-showing` / `data-total` / `data-capped` report the 400-blip cap; labels are baked in at mount, so a language change re-mounts with `reducedMotion: true` | — |
| `ui.js` | `Radar.ui = { init(), renderAll(), renderFeed(), … }` — everything that writes DOM except the scope | all above |
| `main.js` | boot: prefs → theme/lang → data → live.start → ui.init | all |

Rendering rules carried over from v1 (jbelly-ui): one primary action per view,
four states per async region, no raw colour outside `tokens.css`, logical
properties only, Lucide-style inline SVG, no emoji.

## Data-viz rules (from the `dataviz` method)

- The scope is a **positional** encoding: angle = category sector, radius = heat.
  Colour is therefore **one sequential hue** (amber, light → dark by heat), never
  one hue per category — five categorical hues on an all-pairs form fail the
  colour-vision checks, and the sector label already carries identity.
- The **heat meter** on rows uses the same sequential ramp (v1's four-hue ramp
  was a rainbow for a single magnitude and is retired).
- **Signal mix** bars use one hue; v1 cycled four (colour by rank is retired).
- Status colours (ok / empty / failed) always ship with a dot **and** a label.
- Every chart has a hover layer and a table view (the feed list *is* the table).

## Server modules (`lib/`)

| File | Adds |
|---|---|
| `sources.ps1` | fetchers, normalisation, momentum, heat, status file (v1 + status) |
| `reputation.ps1` | `Set-RadarPublishers(items, publishers, cachePath, maxLookups)` → matches the repository owner login, the `owner/repo` a source reports, or the URL host against `config/publishers.json` (never the host on a `platformHosts` entry); for unlisted repository owners asks GitHub `/orgs/{login}` (then `/users`) for `is_verified` / followers, capped at `defaults.orgLookupsPerSync` (20) per sync, `GITHUB_TOKEN` optional to raise the rate limit; caches in `data/history/orgs.json` (30 days, 7 days for a 404, 1 hour for a rate-limit miss) |
| `classify.ps1` | `Set-RadarTech(items, taxonomy)` → `item.tech` from keyword rules over title + summary + tags (word-boundary, lowercase, no regex characters in config) |

`Invoke-RadarSync` order: fetch → dedupe → **classify → resolve publishers** →
momentum → heat → write.

## Configuration surfaces (no code to extend)

| File | Holds |
|---|---|
| `config/sources.json` | sources, filters, heat weights |
| `config/publishers.json` | `{ key, name, tier, sector, github: [logins], domains: [hosts] }` |
| `config/taxonomy.json` | `technologies: [{tag,label,label_ar,keywords[],scope?}]` (`scope: "title"` for words honest in a headline but present in every abstract), `verticals: [{id,label,label_ar,keywords[],technologies_that_matter:[{tag,why,why_ar}]}]` |

The test suite validates all three: unknown kinds, duplicate ids, regexes that do
not compile, taxonomy keywords containing regex characters, verticals naming a
tag that does not exist, publisher logins duplicated across entries.
