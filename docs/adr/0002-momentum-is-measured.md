# ADR 0002 — Momentum is measured from our own snapshots

**Status:** accepted · **Date:** 2026-09-17

## Context

"Trending" is the product's reason to exist, and it is the number that is
easiest to fake. Three ways to produce it were available.

1. **Take the source's own trend number.** Not every source has one, they are
   not comparable, and their definitions are undocumented. The skills
   leaderboard ships an eight-element weekly series whose direction — newest
   first or oldest first — is not stated anywhere.
2. **Compute it from the difference between consecutive syncs.** Unambiguous and
   comparable across sources, because it is one definition applied to
   everything.
3. **Ask a model which items look like they are trending.** A judgement where an
   arithmetic answer exists.

Option 2 has a failure mode that showed up immediately in testing: normalising a
delta to a weekly rate divides by the elapsed time, so two syncs fifteen minutes
apart multiply a rounding-level change by 28 and report ±200%. The first build
did exactly that and produced a leaderboard of noise.

## Decision

**Momentum is the change in an item's metric between two of our own snapshots,
normalised to a week, and a snapshot is only replaced once it is older than
`heat.minBaselineHours` (12).**

- `data/ledger.json` holds one row per item: `firstSeen` with its basis, `lastSeen`,
  and, for items carrying a metric, the momentum baseline and its timestamp.
  It is **committed**, unlike everything else under `data/`: it is the only
  artefact in the project that a fresh `sync.ps1` cannot reproduce.
- On each sync, an item whose baseline is younger than the threshold carries that
  baseline forward untouched and reports **no** momentum.
- Once the baseline matures, momentum is computed, and only then is the baseline
  replaced.
- Where no baseline has matured yet and the source ships a weekly series, that
  series bootstraps the value so the first run is not empty. Its assumed
  direction is the `weeklyOrder` key, because the source does not document it.
- Where there is neither, momentum is empty, and heat falls back to the item's
  popularity rather than penalising it.

## Consequences

**Positive**

- The number means one thing across every source, and it is arithmetic anyone
  can check against the two snapshots that produced it.
- Running the sync more often improves freshness without corrupting momentum,
  so the schedule is a free choice.
- "No data yet" is representable. The *Top movers* panel says so in words rather
  than showing a ranking built from nothing.

**Negative / accepted cost**

- Momentum is weakest on a new installation, which is when the user is most
  curious. The bootstrap series softens this for skills only; other categories
  wait a day.
- Baselines are local. Deleting `data/history/` resets momentum, and two
  machines will disagree until both have run for a day. This is the honest
  consequence of measuring rather than asserting.
- An item that changes identity — a repository rename, a retitled article —
  starts a new baseline and loses its history.
