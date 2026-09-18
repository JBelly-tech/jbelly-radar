# JBelly Radar

[![ci](https://github.com/mohammadJohar/jbelly-radar/actions/workflows/ci.yml/badge.svg)](https://github.com/mohammadJohar/jbelly-radar/actions/workflows/ci.yml) · MIT · Windows PowerShell 5.1+ · no dependencies, no build step, no API key, no model call

**A live, local trend radar for people who build with AI.** It reads 56 public
sources — the official channels of Cloudflare, OpenAI, Anthropic, Google, GitHub,
AWS, Meta, NVIDIA, Microsoft, Vercel, Stripe and others, the agent-skills
leaderboard, the MCP registries, Hacking News, Reddit, Lobsters, dev.to, Product
Hunt, Hugging Face, arXiv and the tech press — ranks everything with one
explainable score, **highlights what notable organisations published**, and
re-orders the feed around *your* business, *your* technologies and what you
actually open.

It answers one question: **what changed since yesterday, and how much does it
matter to me.**

![JBelly Radar](docs/screenshot-dark.png)

## What makes it different

Every part of this exists somewhere ([the landscape study](docs/research/landscape-2026-09-18.md)
looked at 26 products); nothing combines them, and nothing runs like this:

| | |
|---|---|
| **Notable organisations rank up** | A reviewable tier list of 149 organisations (Cloudflare, Google, Anthropic … down to notable labs) plus GitHub's own *verified organisation* record for anyone not on it. A Cloudflare release and a weekend project with the same stars are not treated the same. [ADR 0003](docs/adr/0003-publisher-reputation.md) |
| **Filter by technology and by business** | 46 technology tags assigned by deterministic keyword rules; 19 business verticals, each mapped to the technologies that matter for it, with one line of *why* — shown as advice, in English or Arabic. |
| **Ordered by what you do** | Opens, saves, hides and dwell become decayed affinities in your browser. *For you* re-ranks with a score you can read term by term ("Cloudflare · tier 1 · matches mcp, agents · you open Hacker News often"); *Everything* stays pure heat. Nothing leaves the machine. [ADR 0004](docs/adr/0004-personal-score-is-client-side.md) |
| **Live, not static** | The server re-syncs in the background, the page follows progress source by source, new signals merge in place and are marked *new since your last visit*. |
| **The radar scope** | Every signal is a blip: sector = kind, distance from centre = heat, size = popularity, one amber ramp, a pulse for what is new, an outline for notable organisations. Keyboard reachable, with a screen-reader table. |
| **Deterministic** | Fetch, normalise, classify, attribute, rank, write. No model anywhere in the path, so the same inputs give the same radar, and a sync costs nothing. |

## Install

```powershell
git clone https://github.com/mohammadJohar/jbelly-radar.git
cd jbelly-radar
.\radar.ps1
```

That is the whole install. `radar.ps1` starts a background sync, serves the
dashboard on `localhost` and opens it. The first sync takes about 90 seconds;
the page shows which source it is on.

Optional, for a higher GitHub rate limit (60 → 5 000 requests/hour):

```powershell
$env:GITHUB_TOKEN = 'ghp_...'     # a token with no scopes is enough
```

## Use

```powershell
.\radar.ps1                  # sync if data is older than 30 minutes, serve, open; re-sync every 20 min
.\radar.ps1 -Sync            # sync first, whatever the cache age
.\radar.ps1 -NoSync          # serve the cache, never touch the network
.\radar.ps1 -Every 10        # background re-sync interval in minutes (0 = off)
.\radar.ps1 -Port 9000       # different port
.\radar.ps1 -NoOpen          # do not launch a browser

powershell -File scripts\sync.ps1        # headless sync, for Task Scheduler
powershell -File tests\check.ps1         # the static test suite
powershell -File tests\run-harness.ps1   # the browser harnesses (needs radar.ps1 running)
```

**On the page.** *Tune your radar* asks for your business and the technologies
you follow (30 seconds, skippable). *For you* / *Everything* switches the
ordering. Chips in the sidebar filter by technology; the sidebar also shows
every source's health. Each row can be saved, hidden (with undo), or asked
*why this is here*. The globe switches English ⇄ Arabic (full RTL), the moon
switches theme, and `?theme=light&lang=ar` makes any view a link.

Keyboard: `/` or `Ctrl K` search · `f` For you / Everything · `p` profile ·
`r` re-sync · `Esc` closes.

### Scheduled sync

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\jbelly-radar\scripts\sync.ps1" -Quiet'
$trigger = New-ScheduledTaskTrigger -Daily -At 8am
Register-ScheduledTask -TaskName 'JBelly Radar sync' -Action $action -Trigger $trigger
```

## How ranking works

Two layers, deliberately separate.

**Heat** (server, identical for every reader) — 0..100 from three parts; the
numbers are in [`config/sources.json`](config/sources.json):

| Part | Weight | Meaning |
|------|--------|---------|
| **recency** | 0.40 | `exp(-ln2 × ageDays / halfLifeDays)`. News halves every 3 days, releases and discussion every 5, research every 7, skills every 14, repositories every 21. |
| **popularity** | 0.35 | `log10(1 + metric) / log10(1 + ceiling)` — the first thousand stars count for far more than the twentieth. |
| **momentum** | 0.25 | Change in the metric per week, **measured between two of our own snapshots** — a baseline is only replaced once it is 12 hours old, so two syncs minutes apart report no momentum rather than an invented one. [ADR 0002](docs/adr/0002-momentum-is-measured.md) |

**Personal score** (browser, *For you* only):

```
score = 0.45·heat + 0.20·reputation + 0.20·relevance + 0.15·affinity + explore
```

`reputation` is the publisher tier (1 → 1.0, 2 → 0.75, 3 → 0.5, verified-only →
0.35). `relevance` is how much the item's technologies overlap your profile —
your chips plus the technologies that matter for your vertical. `affinity` is
the decayed sum of your opens (+1), saves (+2), hides (−2) and dwell (+0.5),
14-day half-life. `explore` adds a little for technologies you have never
touched, so the feed can still surprise you. Every row can show its terms.

## Sources

56, in six kinds of signal. All public, none needing a key; each one was
fetched live before being admitted, and a failing source keeps its last items
and is shown as *stale* rather than disappearing.

| Kind | Sources |
|------|---------|
| **skill** | the agent-skills leaderboard; GitHub repositories tagged `claude-skill` / `agent-skills` |
| **repo** | the official MCP registry, Smithery, npm packages tagged `mcp`, Hugging Face trending models, new MCP servers and rising AI repositories on GitHub, agent frameworks |
| **release** | changelogs and release feeds of Claude Code and the Claude platform, `openai/codex`, `vercel/ai`, `cloudflare/agents`, `modelcontextprotocol/servers`, Cloudflare, GitHub, Vercel, AWS, VS Code, Cursor; Product Hunt AI launches |
| **news** | Cloudflare, OpenAI, Google AI and DeepMind, GitHub, AWS ML, Meta engineering, NVIDIA, Microsoft .NET, Stripe, Supabase, Docker, Mistral, Hugging Face, MIT News, Simon Willison; Forbes, TechCrunch, WIRED, The Verge, Ars Technica |
| **discussion** | Hacker News (AI agents, coding agents, vibe coding, Claude Code), Reddit (LocalLLaMA, ClaudeAI, mcp, MachineLearning), Lobsters, dev.to |
| **research** | arXiv cs.AI and cs.CL, Hugging Face daily papers |

### Adding a source

Add an object to `config/sources.json`. No code, as long as `kind` is one of the
five that exist:

```jsonc
{
  "id": "my-feed",
  "label": "My feed",
  "kind": "rss",                       // skills-sh | github-search | hn | rss | json-api
  "category": "news",                  // skill | repo | release | news | discussion | research
  "enabled": true,
  "url": "https://example.com/feed.xml",
  "maxItems": 15,
  "excludeMatch": "(?i)(sponsored|webinar)",   // optional regex over title + summary
  "requireMatch": "(?i)\\b(ai|agent|llm)\\b"   // optional regex
}
```

| `kind` | Reads | Keys |
|--------|-------|------|
| `rss` | RSS 2.0 and Atom (so GitHub release feeds and arXiv work through the same path) | `url`, optional `userAgent` |
| `json-api` | any public JSON endpoint, with a field map: `itemPath`, `map.title`, `map.url`, `map.summary`, `map.author`, `map.metric`, `map.published`, `map.tags`, `urlPrefix`, `authorSplit`; paths are dot-separated, `a\|b` tries alternatives, `[bracketed]` segments may contain dots | `url`, `itemPath`, `map` |
| `github-search` | the GitHub repository search API | `query`, `sort`, `createdWithinDays`, `pushedWithinDays` |
| `hn` | the Hacker News Algolia API | `query`, `minPoints`, `withinDays` |
| `skills-sh` | the agent-skills leaderboard | `url`, `weeklyOrder` |

A **new kind** is the only thing that touches code: one function in
[`lib/sources.ps1`](lib/sources.ps1) and one line in its `switch`. The test
suite fails on a `kind` with no fetcher.

### Adding an organisation or a technology

- **Organisation** — one object in [`config/publishers.json`](config/publishers.json):
  `key`, `name`, `tier` (1–3), `sector`, GitHub `github` logins, web `domains`.
  Subdomains match automatically; hosts in `platformHosts` (github.com,
  huggingface.co, …) never match by domain, only by the path owner.
- **Technology** — one object in [`config/taxonomy.json`](config/taxonomy.json):
  `tag`, `label`, `label_ar`, lowercase `keywords` (no regex characters),
  optional `"scope": "title"` for words that are honest in a headline but appear
  in every abstract. A **vertical** lists its `technologies_that_matter` with a
  `why` / `why_ar` for each.

The suite validates all three files: duplicate ids, logins or domains claimed
twice, regexes that do not compile, keywords with regex characters, verticals
naming unknown technologies.

## Layout

```
jbelly-radar/
├─ radar.ps1               entry: background sync, localhost server, /api/status, /api/sync
├─ scripts/sync.ps1        headless sync (the same function the server runs)
├─ config/
│  ├─ sources.json         56 sources, filters, heat weights and half-lives
│  ├─ publishers.json      149 organisations with tiers, logins and domains
│  └─ taxonomy.json        46 technologies, 19 business verticals, advice in EN + AR
├─ lib/
│  ├─ sources.ps1          five fetchers, normalisation, dedupe, momentum, heat, status file
│  ├─ classify.ps1         technology tagging
│  └─ reputation.ps1       publisher resolution + GitHub organisation cache
├─ app/
│  ├─ index.html · tokens.css · app.css · radar.css
│  └─ js/  i18n · icons · store · rank · live · scope · ui · main
├─ tests/
│  ├─ check.ps1            parser, config, token and page-structure checks (static)
│  ├─ run-harness.ps1      runs every browser harness headlessly against the server
│  └─ harness/*.html       one harness per client module (326 assertions)
├─ docs/
│  ├─ ARCHITECTURE.md      the contract every module is built against
│  ├─ adr/                 decisions 0001–0004
│  └─ research/            the landscape study
└─ data/                   generated, git-ignored: trends.json, status.json, history/
```

## Design

The interface is built with [`jbelly-ui`](https://github.com/mohammadJohar/jbelly-ui),
the house UI system: semantic colour tokens, no raw palette values outside
`app/tokens.css`, exact control sizes, four states per async region, full
keyboard support, light and dark, LTR and RTL. The product's own choices —
signal amber on cool slate, dark by default, the heat meter and the scope as
signature elements — are in [`design/personality.md`](design/personality.md).
The charts follow one rule from the data-viz method: **a single magnitude gets a
single hue** — heat is one amber ramp everywhere, never a rainbow.

No CDN, no web font, no build step, no framework. The dashboard works from
`file://` once the data exists.

## Known limits

- Sources are fetched one after another; a full sync is ~90 s. Parallel fetching
  is the next step if the source count passes ~80.
- The same story can arrive from several sources (Hacker News and TechCrunch,
  say) and appears once per URL, not once per story. Clustering is deferred.
- The organisation list is Anglophone-tech-centric at birth. Pull requests that
  add regional organisations are welcome; a tier is a one-line change.

## Licence

MIT — see [LICENSE](LICENSE).
