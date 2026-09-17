# ADR 0003 — Publisher reputation is a curated list plus GitHub's own record

**Status:** accepted · **Date:** 2026-09-17

## Context

The owner's instruction was direct: *not any repository is useful; if the
organisation is famous — Cloudflare, say — highlight it and rank it up.* Heat
alone cannot do that. A weekend project with 300 stars and a Cloudflare release
with 300 stars have the same popularity term, and the reader's time is not
equally well spent on both.

Three ways to know who published something were available.

1. **Stars and followers as a proxy.** Cheap, but it rewards age and virality,
   not standing. A meme repository outscores a platform team's SDK.
2. **A model judging "is this organisation notable".** A judgement call that
   drifts between runs, costs a call per item, and cannot be audited.
3. **A curated list of organisations with an explicit tier**, backed by a
   machine signal for organisations the list does not know.

## Decision

**Reputation is `config/publishers.json` — a reviewable list of organisations
with a tier — combined with GitHub's organisation record for repository owners
the list does not name.**

- Each entry carries `tier` (1 = global platform owner, 2 = major tech/AI
  company or foundation, 3 = notable startup or lab), the organisation's GitHub
  logins and its web domains. An item is matched by the login that owns its
  repository, by the `owner/repo` its source reports, or by the host of its
  URL (subdomains walk up to the registrable domain, so `blog.cloudflare.com`
  is Cloudflare).
- For a repository owner the list does not know, the sync asks GitHub
  (`/users/{login}`): an account of type `Organization` that is **verified** or
  has at least 2 000 followers becomes a publisher with no tier. Lookups are
  capped per sync and cached for 30 days in `data/history/orgs.json`, so the
  unauthenticated rate limit is never the reason a run fails.
- The client turns this into a score term (tier 1 → 1.0, tier 2 → 0.75,
  tier 3 → 0.5, verified-only → 0.35) that changes the **order** only in
  *For you* mode. In both modes the publisher is **highlighted**: a badge on the
  row, an outline on the blip, and a *From notable organizations* rail.

## Consequences

**Positive**

- "Famous" is a file anyone can read, argue with and extend in a pull request.
  A wrong tier is a one-line fix, not a retraining.
- Verified organisations the list has never heard of still surface, so the
  mechanism is not frozen at the day the list was written.
- Highlighting is separated from ordering. A reader who wants pure heat still
  sees who published what.

**Negative / accepted cost**

- The list is opinionated and Anglophone-tech-centric at birth. It will need
  regional additions; the sector field exists so those can be filtered later.
- News items match by domain only. A Forbes story *about* Cloudflare is not a
  Cloudflare publication and is not tagged as one; only Cloudflare's own
  channels are. That is correct, and it means news reputation needs its own
  source list of official channels, which the sources config carries.
- GitHub's `is_verified` is a domain-ownership check, not a quality check. It is
  therefore worth 0.35, not 1.0.
