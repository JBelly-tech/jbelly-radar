# JBelly Radar

[![ci](https://github.com/mohammadJohar/jbelly-radar/actions/workflows/ci.yml/badge.svg)](https://github.com/mohammadJohar/jbelly-radar/actions/workflows/ci.yml) · MIT · Windows PowerShell 5.1+ · no dependencies, no build step, no API key

**A local trend radar for people who build with AI.** One command syncs 19
sources — the agent-skills leaderboard, GitHub, Hacker News, Forbes, TechCrunch,
WIRED, The Verge, Ars Technica, MIT News, Hugging Face, arXiv — ranks everything
with one explainable formula, and serves a dashboard on `localhost`.

It answers one question: **what changed since yesterday, and how much does it
matter.**

![JBelly Radar, dark](docs/screenshot-dark.png)

## Why

Trend-watching for AI tooling is a tab problem. The skill directory, GitHub
search, three news sites and Hacker News each hold a piece, none of them rank
against each other, and none of them tell you what moved.

JBelly Radar normalises all of them into one item shape, scores each item with a
formula you can read in twelve lines, and keeps its own history so *momentum* is
a measured delta rather than a number somebody else's API asserts.

- **No API key.** Every source is public. A GitHub token is optional and only
  raises a rate limit.
- **No model call.** Fetch, normalise, rank, write — all deterministic. Running
  it costs nothing per run.
- **Nothing leaves the machine.** The dashboard binds to `localhost`, the data
  lives in `data/`, and no request carries anything but a static query from
  `config/sources.json`.

## Install

```powershell
git clone https://github.com/mohammadJohar/jbelly-radar.git
cd jbelly-radar
.\radar.ps1
```

That is the whole install. `radar.ps1` syncs if the cached data is stale, starts
a local server and opens the dashboard.

Optional, for a higher GitHub rate limit (60 → 5000 requests/hour):

```powershell
$env:GITHUB_TOKEN = 'ghp_...'     # a token with no scopes is enough
```

## Use

```powershell
.\radar.ps1                  # sync if data is older than 30 minutes, serve, open
.\radar.ps1 -Sync            # always sync first
.\radar.ps1 -NoSync          # serve the cache, do not touch the network
.\radar.ps1 -Port 9000       # different port
.\radar.ps1 -NoOpen          # do not launch a browser

powershell -File scripts\sync.ps1   # headless sync, for Task Scheduler
powershell -File tests\check.ps1    # the test suite
```

In the dashboard: `Ctrl`/`⌘` + `K` or `/` focuses search, `r` re-syncs, `Esc`
clears. The globe button switches between English and Arabic (the interface
flips to RTL); the moon button switches theme. Both are remembered, and
`?theme=light&lang=ar` makes any view a link.

### Scheduled sync

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\jbelly-radar\scripts\sync.ps1" -Quiet'
$trigger = New-ScheduledTaskTrigger -Daily -At 8am
Register-ScheduledTask -TaskName 'JBelly Radar sync' -Action $action -Trigger $trigger
```

## How ranking works

Every item gets a **heat** between 0 and 100 from three parts. There is no model
in this path and no hidden weighting — the numbers are in
[`config/sources.json`](config/sources.json).

| Part | Weight | Meaning |
|------|--------|---------|
| **recency** | 0.40 | `exp(-ln2 × ageDays / halfLifeDays)`. News halves every 3 days, discussion every 5, research every 7, skills every 14, repositories every 21. |
| **popularity** | 0.35 | `log10(1 + metric) / log10(1 + ceiling)`, so the first thousand stars count for far more than the twentieth. |
| **momentum** | 0.25 | Change in the metric per week, measured between two of *our own* snapshots. |

**Momentum is measured, not asserted.** Each sync stores a metric baseline in
`data/history/`, and a baseline is only replaced once it is more than 12 hours
old (`heat.minBaselineHours`). Two syncs minutes apart therefore report *no*
momentum rather than an invented number. Until a baseline matures, a
source-supplied weekly series is used to bootstrap it, and momentum is left
empty when there is neither.

The heat meter on the start edge of each row is that number, and the feed is
sorted by it.

## Sources

19 out of the box, in five categories.

| Category | Sources |
|----------|---------|
| **skill** | the agent-skills leaderboard, plus GitHub repositories tagged `claude-skill` and `agent-skills` created in the last 120 / 180 days |
| **repo** | new `mcp-server` repositories, rising `ai` repositories, actively pushed agent frameworks |
| **discussion** | Hacker News on AI agents, coding agents, vibe coding and Claude Code, above a per-topic point threshold |
| **news** | Forbes Innovation, TechCrunch AI, WIRED AI, The Verge AI, Ars Technica, Hugging Face, MIT News — plus VentureBeat AI, shipped disabled because it answers 429 to every request from a residential IP |
| **research** | arXiv `cs.AI`, newest first |

A failed source is reported in the sidebar and never fails the run.

### Adding a source

Add an object to `config/sources.json`. No code changes, as long as `kind` is
one of the four that exist:

```jsonc
{
  "id": "my-feed",
  "label": "My feed",
  "kind": "rss",              // skills-sh | github-search | hn | rss
  "category": "news",         // must exist in heat.categories
  "enabled": true,
  "url": "https://example.com/feed.xml",
  "maxItems": 15,
  "excludeMatch": "(?i)(sponsored|webinar)",   // optional regex, title + summary
  "requireMatch": "(?i)\\b(ai|agent|llm)\\b"   // optional regex
}
```

| `kind` | Reads | Extra keys |
|--------|-------|------------|
| `rss` | RSS 2.0 and Atom, so an arXiv API query works through the same path | `url` |
| `github-search` | the GitHub repository search API | `query`, `sort`, `createdWithinDays`, `pushedWithinDays` |
| `hn` | the Hacker News Algolia API | `query`, `minPoints`, `withinDays` |
| `skills-sh` | the agent-skills leaderboard | `url`, `weeklyOrder` |

A **new kind** is the only thing that touches code: one function in
[`lib/sources.ps1`](lib/sources.ps1) and one line in its `switch`. `tests\check.ps1`
fails on a `kind` with no fetcher, so the two cannot drift apart.

## Layout

```
jbelly-radar/
├─ radar.ps1              entry point: sync when stale, serve on localhost, open
├─ config/sources.json    the source list and the ranking weights — the expandable surface
├─ lib/sources.ps1        four fetchers, normalisation, momentum, heat
├─ scripts/sync.ps1       headless sync, for a scheduled task
├─ app/                   the dashboard: index.html, tokens.css, app.css, app.js
├─ design/personality.md  the design decisions this product owns
├─ data/                  generated — trends.json, trends.js, history/ (git-ignored)
├─ tests/check.ps1        parser, config, token and structure checks
└─ docs/adr/              one numbered file per architectural decision
```

**`data/` is never committed.** It is a cache; `scripts\sync.ps1` reproduces it.

## Design

The interface is built with [`jbelly-ui`](https://github.com/mohammadJohar/jbelly-ui),
the house UI system: semantic colour tokens, no raw palette values outside
`app/tokens.css`, exact control sizes, four states per async region, full
keyboard support, light and dark, LTR and RTL. The choices specific to this
product — signal amber on cool slate, dark by default, the heat meter as the
signature element — are recorded in [`design/personality.md`](design/personality.md).

No CDN, no web font, no build step. The dashboard is three files and works from
`file://` once the data exists.

## Licence

MIT — see [LICENSE](LICENSE).
