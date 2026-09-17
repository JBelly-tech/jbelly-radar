# ADR 0004 — The personal score is computed in the browser, from behaviour that never leaves it

**Status:** accepted · **Date:** 2026-09-17

## Context

The owner wants the feed ordered by *user behaviour and user experience*, and
filtered by the technologies and the business the user cares about. The product
is a local tool that may be published for anyone to run; it has no accounts and
no server-side user store, and adding one would change what the product is.

## Decision

**Heat stays a server-side, user-independent fact. Everything personal — the
interest profile, the behaviour signals and the score they produce — lives in
the browser's `localStorage` and is computed on the page.**

- The profile is chosen technologies, chosen business verticals and an
  *only notable organisations* switch. A vertical expands to the technologies
  that matter for it (`config/taxonomy.json`), so a restaurant owner who has
  never heard of MCP still sees the MCP servers that would take reservations.
- Behaviour is four events — open, save, hide, dwell — each adding a weight to
  the item's technologies, tags and source, decaying with a 14-day half-life.
- The score is one explicit line:
  `0.45·heat + 0.20·reputation + 0.20·relevance + 0.15·affinity + explore`,
  and every row can show its terms as words ("Cloudflare · tier 1 · matches
  mcp, agents · you open Hacker News often").
- *Everything* mode ignores the profile and the behaviour entirely and sorts
  by heat. The user is never locked inside the personalised view.
- No cookie, no account, no telemetry. `export()` and `import()` exist so the
  profile can move between machines by hand.

## Alternatives considered

| Option | Why not |
|---|---|
| Server-side user profiles | Requires identity, storage and a privacy story; turns a tool into a service. |
| A model ranking "what this user would like" | Opaque, non-deterministic, costs a call per view, and the user cannot correct it. |
| Collaborative filtering across users | Needs the users to be in one place. They are not. |

## Consequences

**Positive**

- Personalisation ships with zero infrastructure and zero data risk.
- The ranking is explainable term by term, and a user who disagrees can flip
  a chip, hide a source, or leave *For you* altogether.
- The exploration term keeps a small stream of unfamiliar technologies in the
  feed, so the profile cannot narrow into a bubble unnoticed.

**Negative / accepted cost**

- The profile is per browser. A second machine starts cold unless the user
  exports it.
- Cold start is real: until a few interactions exist, *For you* is mostly heat
  plus reputation plus the declared profile. That is stated in the interface
  rather than hidden.
- `localStorage` can be cleared by the browser; the store treats every read as
  possibly empty and the page renders correctly without it.
