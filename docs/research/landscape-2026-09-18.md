# Does this already exist? — landscape study, 2026-09-18

**Question.** Is there a product, open-source project, newsletter or site that
does what JBelly Radar does: aggregate many public sources into one ranked view
of what is moving in AI tooling, weight it by who published it, filter it by
technology and business vertical, order it by the reader's own behaviour — and
run locally, without an API key or a model call?

**Method.** Five parallel research passes (prior art, reputation signals, public
sources, personalisation methods, taxonomy), 26 products examined, 40 candidate
sources fetched live before being admitted, one completeness critique over the
whole. Every claim below carries the URL it came from.

## Verdict

**The exact concept does not exist.** Every axis has prior art; no product
combines them, and none runs local, keyless and model-free.

| Axis | Who does it | How | What they lack |
|---|---|---|---|
| Multi-source keyless aggregation with local history and measured velocity | [trend-pulse](https://github.com/claude-world/trend-pulse) (MIT, Python, 20 sources, SQLite), [TrendRadar](https://github.com/sansan0/TrendRadar) (GPL-3.0, Python, Chinese platforms + RSS) | per-source normalised scores, velocity from own snapshots, lifecycle labels | no organisation weighting, no vertical filter, no per-reader ordering |
| Organisation reputation | [Glama](https://glama.ai/mcp/servers) "official", [PulseMCP](https://www.pulsemcp.com/servers) official / reference / community icons, [skills.sh /official](https://www.skills.sh/), Hugging Face org pages, [Techmeme Leaderboard](https://news.techmeme.com/071001/techmeme-leaderboard) | a **badge** — except Techmeme's *Presence* (share of headline space) and Product Hunt's reputation-weighted votes | nobody uses it as a **rank input** across sources |
| Business-vertical filtering | [Feedly Market Intelligence](https://feedly.com/ai) (paid), [Exploding Topics](https://explodingtopics.com/) categories (paid), Glama category counts | industry facets over news or over MCP servers only | not keyless, not across repos + skills + news + research |
| Behaviour-personalised ordering | [daily.dev](https://docs.daily.dev/feeds/) feed v3, [Feedly Leo](https://feedly.com/ai) with "why chosen" labels | server-side learning from clicks / upvotes / feedback | needs an account and a server; not explainable term by term |
| "Which MCP / skill would help *this* business" | blog posts ("MCP servers by industry") | prose | no ranked, filterable tool |

The differentiation JBelly Radar owns is therefore not any single feature but the
combination, done deterministically: **provenance as a ranking term** from a
reviewable tier list plus GitHub's own organisation record ([ADR 0003](../adr/0003-publisher-reputation.md)),
**a personal score computed in the browser** from an explicit profile and
decayed behaviour ([ADR 0004](../adr/0004-personal-score-is-client-side.md)),
and **advice per vertical** from a taxonomy file — none of it a model, all of
it a file someone can read and argue with.

## The 26 products, and what was taken from each

| Product | Kind | Ranks by | Taken into the radar |
|---|---|---|---|
| [ThoughtWorks Technology Radar](https://www.thoughtworks.com/radar/faq) | site | editorial board, twice a year | the **radar scope** metaphor — rings and sectors; "blip moved since last edition" → *new since your last visit* |
| [GitHub Trending](https://github.com/trending) | site | undocumented star velocity | nothing directly; it is opaque and single-source |
| [OSS Insight](https://ossinsight.io/blog/introducing-trending-page) | product | stated deterministic velocity | "same inputs, same outputs" as a product promise |
| [Trendshift](https://trendshift.io/) | site | daily momentum + social mentions; paid *Featured* | per-item history (first seen, days on radar) — the metric baselines in `data/history/` |
| [star-history.com](https://www.star-history.com/) | site | stars gained in a window | sparkline from our own snapshots |
| [Product Hunt](https://www.producthunt.com/) | product | reputation-weighted votes, fixed daily cohort | the idea that a signal from a reputable source counts more |
| [daily.dev](https://docs.daily.dev/feeds/) | product | learns from clicks and upvotes, server-side | *For you / Everything* as explicit views; hides apply in both views, only the ordering is personal |
| [Feedly AI (Leo)](https://feedly.com/ai) | product | pre-trained models, "why chosen" labels | *Why this is here* on every personalised row |
| [Hacker News](http://www.righto.com/2013/11/how-hacker-news-ranking-really-works.html) | site | `(P−1)/(T+2)^1.8` with penalties | the decay family behind *heat*; HN itself is a source |
| [Hugging Face Trending](https://huggingface.co/papers/trending) | site | upvotes + recency; undisclosed `trendingScore` | trending models and daily papers as keyless sources; organisation as a navigation axis |
| [alphaXiv](https://www.alphaxiv.org/) | product | views / comments / recency | institution tags for research (future) |
| [Glama](https://glama.ai/mcp/servers) | product | usage, stars, recent stars, letter grades | *official publisher* as a rank input, not only a badge |
| [mcp.so](https://mcp.so/) | site | featured (editorial), installs, stars | category names as a seed for the technology taxonomy |
| [Smithery](https://smithery.ai/) | product | usage counts, verified badge | its registry is a source (`useCount` as popularity) |
| [PulseMCP](https://www.pulsemcp.com/servers) | site | recommended / recent / popular by window | three-tier provenance rendered on every card |
| [Official MCP Registry](https://github.com/modelcontextprotocol/registry) | oss | none — a registry | a source; reverse-DNS namespaces are cryptographic proof of who published |
| [skills.sh](https://www.skills.sh/) | site | installs; 24h trending; hot | already a source; the 8-week series bootstraps momentum |
| [awesome lists via ecosyste.ms](https://awesome.ecosyste.ms/) | oss | stars; inclusion is a human PR | "listed in a high-star awesome list" as a future curation signal |
| [best-of-generator](https://github.com/best-of-lists/best-of-generator) | oss | additive, log-scaled project rank | the shape of an explainable additive score |
| [Techmeme Leaderboard](https://news.techmeme.com/150520/author-leaderboards) | site | *Presence* and *Leadership* over 30 days | a data-derived reputation to complement the hand list (future) |
| [Changelog Nightly](https://github.com/thechangelog/nightly) | newsletter | GH Archive star events, first-timers vs repeat | novelty flag from our own history (future) |
| [TLDR AI / Ben's Bites / AlphaSignal](https://alphasignal.ai/about) | newsletter | editorial or learned | the *Today* digest format readers already trust (future) |
| [TrendRadar](https://github.com/sansan0/TrendRadar) | oss | rank × frequency × hotness weights, keyword DSL | cross-source frequency as a signal; `requireMatch` / `excludeMatch` filters in config |
| [trend-pulse](https://github.com/claude-world/trend-pulse) | oss | 5-dimension score, velocity, lifecycle labels | lifecycle labels (emerging / peak / declining) from momentum sign (future); extra keyless sources |
| [Exploding Topics](https://explodingtopics.com/) | product | search-volume growth, human curation | business-vertical categories as a seed for the taxonomy |
| [GitNews](https://git.news/) | site | undisclosed merge of three feeds | confirms demand for a merged repo feed |

## Sources people actually go to — what was admitted

The owner's rule was *only the sources people actually go to*. 40 candidates
were fetched live; 37 were admitted, 3 were not (a Bluesky profile feed, a
YouTube channel feed, and an undated 445-model list that would only add noise).
Admitted, by kind:

- **Official channels of the organisations in the tier list** — Cloudflare blog
  and developer changelog, OpenAI news, Google AI blog and DeepMind, GitHub blog
  and changelog, AWS machine-learning blog and *What's new*, Meta engineering,
  NVIDIA technical blog, Microsoft .NET and VS Code, Vercel changelog, Stripe,
  Supabase, Docker, Mistral; release feeds for Claude Code, the Claude platform,
  `openai/codex`, `vercel/ai`, `cloudflare/agents`, `modelcontextprotocol/servers`;
  Cursor's changelog.
- **Community** — Reddit (r/LocalLLaMA, r/ClaudeAI, r/mcp, r/MachineLearning),
  Lobsters, dev.to top AI, Simon Willison's weblog, Product Hunt AI launches.
- **Registries and models** — the official MCP registry, Smithery, npm packages
  tagged `mcp`, Hugging Face trending models and daily papers, arXiv cs.CL.

Together with the original 19 this is **56 sources**; a sync reads them in about
90 seconds in the background and reports each one's health on the page.

## Reputation signals that are actually free

| Signal | Endpoint / method | Keyless | Reliability |
|---|---|---|---|
| Organisation vs user | `GET /users/{login}` → `type` | yes, 60/h | exact |
| Verified organisation | `GET /users/{login}` → `is_verified` (domain-ownership check) | yes | exact, but a domain check, not a quality check |
| Followers, public repos | same record | yes | exact |
| Official MCP publisher | reverse-DNS namespace in the official registry | yes | cryptographic |
| Curated tier | `config/publishers.json` | — | a judgement, reviewable |

Hence [ADR 0003](../adr/0003-publisher-reputation.md): tier list first, GitHub's
record for the rest, cached 30 days, capped per sync.

## What the critique changed

The completeness critic over all five passes produced 17 gaps and 16
corrections; the ones that changed the build:

- **Hosting platforms are not publishers.** With `github.com` in GitHub's domain
  list, every repository by an unknown owner would have become "GitHub, tier 2".
  `platformHosts` in `config/publishers.json` now names the hosts where only the
  path owner counts.
- **Keyword false positives.** Bare `cursor`, `codex`, `inference`, `eval`,
  `monitoring`, `gpu`, `checkout`, `cargo` were retired or qualified; six tags
  (`evals`, `observability`, `hardware`, `rust`, `prompting`, `reasoning`) match
  the **title only**, because those words appear in every abstract.
- **Release feeds title their entries with version strings.** Rows now read
  *Anthropic · v2.1.274*.
- **Stale-while-error.** A source that answers 429 keeps its previous items and
  is shown as *stale*, not dropped.
- **Notable individuals** exist as an opt-in tier 3 (`person: true`) — the owner
  asked for organisations, so people are few and never above tier 3.

Deferred, recorded here so they are not forgotten: parallel fetching (a
RunspacePool) once the source count passes ~80; cross-source clustering of the
same story; lifecycle labels; a data-derived *presence* weight from our own
ranking history; exposing the radar as a read-only MCP server.
