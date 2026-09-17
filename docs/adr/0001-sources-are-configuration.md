# ADR 0001 — Sources are configuration, ranking is code, neither is a model

**Status:** accepted · **Date:** 2026-09-17

## Context

The radar has to cover sources that do not resemble each other: a leaderboard
rendered into a web page, two JSON APIs, and a dozen feeds in two XML dialects.
Its usefulness depends on how easily a new one can be added, because the
interesting source next month is not the interesting source today.

Three shapes were available.

1. **One fetcher per source.** Honest, and unmaintainable at twenty sources —
   twenty places for the same bug.
2. **A model reads each source and returns structured items.** Handles any shape
   with no code. It also costs a model call per source per sync, and it is
   non-deterministic: the same page can yield different items on two runs, which
   destroys momentum, which is the point of the product.
3. **A small set of fetchers by transport, with everything source-specific in
   configuration.**

## Decision

**Sources live in `config/sources.json`. Transports live in `lib/sources.ps1`.
No model is called anywhere in the pipeline.**

- A source is an object: `id`, `label`, `kind`, `category`, plus the keys that
  kind accepts. Adding one is a JSON edit.
- There are four kinds — `skills-sh`, `github-search`, `hn`, `rss` — chosen by
  transport, not by site. `rss` parses RSS 2.0 and Atom through one XPath pass,
  so an arXiv API query is an `rss` source with no extra code.
- Filtering that would otherwise justify a special fetcher is configuration too:
  `requireMatch` and `excludeMatch` are regexes over title and summary, which is
  what a broad section feed needs to drop its puzzles and horoscopes.
- Ranking runs once over every item after fetching, never inside a fetcher.

## Consequences

**Positive**

- A new feed is a pull request with no code in it, reviewable in a minute.
- Every source gets identical normalisation, deduplication and ranking, so a bug
  is fixed once.
- A sync costs nothing but bandwidth, so it can run on a schedule without a
  budget conversation.
- Runs are reproducible, which is what makes measured momentum possible
  ([ADR 0002](0002-momentum-is-measured.md)).

**Negative / accepted cost**

- A source whose shape no kind can read needs a new kind. That is deliberate:
  the alternative is a configuration language that grows until it is a worse
  programming language.
- One source — the agent-skills leaderboard — has no API and is read out of its
  server-rendered payload. It will break when that page changes. It is isolated
  in its own fetcher, reports zero items when it breaks, and never fails the run.
- The regex filters are a blunt instrument. They are visible in the config, which
  is the point: a surprising omission is one `grep` away from an explanation.
