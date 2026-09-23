# Release readiness

**Reviewed 2026-09-24, against the working tree at `91725ec` plus uncommitted
changes.** A pre-publication audit: what blocks a public release, what would make
a stranger adopt this rather than star it, and where the project claims more than
it delivers.

Verdict up front: **the engineering is release-grade; the product story and one
scoring rule are not.** Nothing here is embarrassing — there is no dead code, no
TODO, no stub, no abandoned experiment. What blocks a release is (1) a personal
email address on every commit in the history, (2) a systematic bias in the
matcher's verdict that makes it wrong in a way a stranger cannot see, and (3) a
date field that says something it cannot support. Only (1) is urgent in the sense
that publishing first makes it unfixable.

---

## 1. Blockers

Do these before the repository goes public.

| # | Blocker | Where |
|---|---------|-------|
| B0 | **Every commit in the history carries a personal email address.** `git log --format='%ae' \| sort -u` returns exactly one value — a personal Gmail address — across all 25 commits. The author *name* is already `JBelly`, so the file-level sweep and the commit log look clean; the email does not appear until the repository is public, at which point it is on every commit page and in every `.patch`. `git config --local user.email` is set to the same value, so the next commit adds another. | repository history; `.git/config` |
| B1 | ~~`<org>` placeholders~~ — **done.** All repository URLs now read `github.com/jbelly-tech/…`. The one that mattered most is the user agent: it goes out to 54 source operators on every sync and is this project's only identification to them, so it must resolve to a real page **before** the first sync from a published clone. | `config/sources.json:9`, `config/brief-template.json:48,90`, `LICENSE-DATA:39`, `CONTRIBUTING.md:57`, `README.md` |
| B2 | ~~Corrupted skills.sh regex~~ — **resolved during this review.** A path-separator sweep (`\` → `/`) had briefly turned `\\"source\\":` into `\\"source//":`, a pattern that can never match, which would have silently zeroed the `skills-sh` fetcher — the source of 600 of the catalogue's 800 skills. It has since been reverted. Recorded because the failure mode is invisible: a broken fetcher reports `ok` with a low count, not an error. See §6. | `lib/sources.ps1:190` |
| B3 | **The hero screenshot predates the current build.** `docs/screenshot-dark.png` is dated 2026-09-18 and shows a `79624ms` sync duration in the UI, Reddit still enabled, and no operator console. It is the first thing a visitor sees and it contradicts the README. | `docs/screenshot-*.png` |
| B4 | **Decide what `content/` publishes.** `content/briefs/` and `content/matches/` are gitignored, so a stranger clones the repo and finds the briefs feature invisible. `LICENSE-DATA` meanwhile licenses `content/**` under CC BY 4.0, which licenses a directory that does not exist in the repository. Either commit one dated example of each, or drop `content/**` from the licence. | `.gitignore:27,34`, `LICENSE-DATA:24` |

---

## 2. Improvements, ranked by value to a stranger

### I1 — The usage floor compares stars against installs, and it decides the verdict

**What.** `match-plan.ps1` calls a candidate *strong* when it matched in a title
or a tech tag **and** is "backed": it has a curated publisher tier, or its
`metric` clears the median of its pool. The median is computed per **kind**
(`skill`, `mcp`) — but within a kind the metric is not one unit.

Measured against the current ledger:

| Pool | Unit | n | Median for that unit | Pooled floor actually applied |
|---|---|---:|---:|---:|
| skill | installs (skills.sh) | 600 | 151,752 | **82,554** |
| skill | stars (GitHub) | 198 | 918 | **82,554** |
| mcp | weekly downloads (npm) | 217 | 16,735 | **8,233** |
| mcp | uses (registries) | 47 | 8,243 | **8,233** |
| mcp | stars (GitHub) | 92 | 74 | **8,233** |
| mcp | none at all | 86 | — | unreachable |

Consequence: **2 of 198 star-measured skills and 1 of 92 star-measured MCP
servers can ever be called strong** on usage. Every other GitHub-sourced
candidate — 287 rows — can only reach "covered" through a curated publisher tier,
i.e. only if it belongs to one of the 150 organisations on the list. A GitHub
project is structurally excluded from the verdict.

It is visible in the example run. The `search` requirement returns **thin**, with
the sentence *"nothing with a known publisher or usage above the catalogue median
for its kind"*, over two candidates at 1,167 and 1,332 stars — both comfortably
above the star median of 918. The sentence is true and the comparison is
meaningless.

**Why it matters.** This is the headline feature. The whole argument for the
ledger is that a record answers "does something cover this" better than a
leaderboard does; if the verdict is decided by which registry happened to report
the number, the record is not doing the work. And the CHANGELOG already
identifies the exact failure mode one level up ("skills and MCP servers are three
orders of magnitude apart, so one hardcoded number would call every MCP server
weak") — the same argument applies inside each pool and was not carried through.

**Cost.** Small. Key the median by `(kind, metricLabel)` instead of `kind`, fall
back to the pooled median when a label has too few rows to have a median, and
print the floor per unit in the header line. Maybe 20 lines in
`scripts/match-plan.ps1`, plus the two report templates.

**Risk.** Verdicts will move — some `thin` requirements become `covered`. That is
the point, but it means any brief or match report already published becomes
inconsistent with a re-run. Bump the report's own version line so the two are
distinguishable. Also: a unit with very few rows (`reactions`, n=1) gets a
meaningless median; the fallback has to be explicit, not emergent.

---

### I2 — `firstSeen: observed` is claiming something it cannot support

**What.** `firstSeenBasis` distinguishes `observed` ("this radar watched the item
arrive") from `snapshot-floor` ("it was already there when the record began").
The distinction is good and it is honestly documented. But on 2026-09-23 the
`catalogueMax` change raised the fetch depth, and **1,255 rows — 42% of the
ledger — entered with today's date and basis `observed`**, including items that
plainly predate it.

The example match report prints the result: *`supabase-postgres-best-practices`
— 414,075 installs · first seen 2026-09-23*. A skill with 414,000 installs did
not first appear yesterday. What actually happened is that it entered the radar's
fetch window yesterday.

**Why it matters.** "First seen" is one of exactly two facts the match report
carries per candidate (the other is usage), and it is the fact that is supposed
to prove the catalogue is worth more than a search. A reader who knows the
ecosystem will spot one of these and stop trusting the rest — which is the
correct response, and fatal for a tool whose pitch is "from a record rather than
a guess".

**Cost.** Two options. Cheap: add a third basis — `window-entry` — set when a row
first appears in a sync where its source's fetch cap was raised, and render it as
"entered the record on". Cheaper still and nearly as good: treat any `observed`
date equal to the first sync after a `catalogueMax` change as a floor, once, by
hand, via `backfill-ledger.ps1` which already only ever moves dates earlier.
Either way the rendering strings in both templates need a third case.

**Risk.** Retroactively relabelling is itself a claim. Whatever is chosen should
be recorded as an ADR, because it is a change to what the record means — and the
project's own rule (ADR 0002) is that a number that cannot be measured is
dropped, not guessed.

---

### I3 — There is no way to try this without installing something and waiting 40 seconds

**What.** `scripts/pack-demo.ps1` already builds a frozen, double-clickable
bundle that runs from `file://` with no server and no network. It is the single
best adoption asset in the repository and it is invisible: `dist/` is gitignored,
no release has been cut, and the README mentions it only in a command list.

**Why it matters.** The audience is developers choosing tools, and the first
question they ask of an unfamiliar repository is "what does it look like",
not "how do I install it". Today the funnel is: read the README → install or
locate PowerShell → clone → wait through a sync → decide. With a demo attached to
a GitHub release it is: read the README → click → see the product → decide. That
is the difference between a star and an adoption, and it matters more now that
the port has removed the Windows barrier, because the remaining barrier is
entirely "I have not seen it yet".

**Cost.** One `pack-demo.ps1` run and one GitHub release, plus a link at the top
of the README. An hour, including checking that nothing personal is in the
frozen snapshot.

**Risk.** A frozen demo rots — the bundle already says so in its own README, in
the page, and in the script's header, so the honesty is handled. Re-cut it with
each tagged release or it becomes a dated screenshot with extra steps.

---

### I4 — The ledger is committed but the snapshots that repair it are not

**What.** `data/ledger.json` is committed, deliberately and correctly: it is the
one artefact a re-run cannot rebuild. `data/history/` is gitignored.
`scripts/backfill-ledger.ps1` repairs the ledger *from* `data/history/`, and its
own header calls it "the recovery path — a lost ledger can be rebuilt from the
snapshots". On a fresh clone there are no snapshots, so the recovery path does
not exist, and the 298 anonymous rows can never be named by anyone but the
original maintainer.

**Why it matters.** It is the difference between publishing a dataset and
publishing a copy of a dataset. A contributor who wants to improve the record has
no way to; the licence says CC BY 4.0 and "adapt this material", but the material
needed to adapt it is not there.

**Cost.** Two honest options. (a) Commit the dated snapshots — seven files, and
they compress well, but the repository grows monthly forever. (b) Keep them out
and correct the two places that imply otherwise: the `backfill-ledger.ps1` header
and the recovery claim. (b) is nearly free and is probably right; (a) is a real
decision that deserves an ADR.

**Risk.** Committing snapshots means committing third-party summaries and titles
at scale, daily, forever. That is a different licensing and volume question from
committing the ledger once.

---

### I5 — Nothing checks that the documentation matches the configuration

**What.** `tests/check.ps1` runs 300 static checks and validates all three config
files rigorously. It does not check a single documentation claim. The record
shows why that matters: v0.3.0's changelog entry is *"The README claimed 55
sources, listed Reddit as live, said a sync takes 90 seconds"*. At the time of
this review the README still said a sync takes 12 seconds in one paragraph and
~90 seconds in another, and `docs/ARCHITECTURE.md` still said ~90 s — five days
after the concurrency change that made both wrong.

**Why it matters.** This is the project's own Class-D argument: a deterministic
check is free and a human re-reading the README is not. The same defect has now
been found and fixed twice by hand. It will be found a third time by a stranger,
and a wrong number in a README is the cheapest possible reason to distrust a tool
that sells itself on not guessing.

**Cost.** A sixth section in `tests/check.ps1`, maybe 40 lines. Assert that the
enabled-source count in `config/sources.json` appears in `README.md`; that no
source with `enabled: false` is listed in the README's live source table; that
every `kind` named in the README's kind table has a fetcher; that the heat
weights in the README's table equal `config/sources.json`'s. Everything needed is
already parsed by the suite.

**Risk.** A brittle check that fails on prose rewording is worse than none. Keep
the assertions numeric and structural — counts, ids, weights — never sentences.

---

### I6 — `docs/ARCHITECTURE.md` no longer describes the architecture

**What.** It is titled "architecture (v2)", says "kept current", and until this
review documented neither the ledger, the display/fetch cap split, the operator
console, `brief.ps1`, nor `match-plan.ps1` — i.e. everything 0.3.0 and the
catalogue work added. This review added the ledger contract and the cap split and
corrected the sync timing; the scripts and the console are still undocumented.

**Why it matters.** Its own rule is "a module that needs something not written
here is a change to this file first". A contract document that has silently
stopped being a contract is worse than no contract, because contributors will
trust it.

**Cost.** An hour. Two short sections (the scripts, the console) and retitling
away from "v2", which now means nothing to a reader who arrives at 0.3.x.

**Risk.** None.

---

### I7 — The GitHub token is called optional and is not, quite

**What.** The README lists `GITHUB_TOKEN` under "optional, for a higher rate
limit". Unauthenticated, GitHub allows 10 search requests per minute and 60 core
API calls per hour. This project makes 5 search requests per sync and up to 20
organisation lookups per sync, re-syncing every 20 minutes by default. The
evidence is already in the repository: **76 of 578 entries in
`data/history/orgs.json` carry a 403**, on the maintainer's own machine.

**Why it matters.** A first-time user without a token gets a radar whose
publisher attribution silently degrades, and the failure shows up as items simply
not being marked notable — which looks like the tier list being thin rather than
the API refusing. The README now says this; the product does not.

**Cost.** Small and worth doing in the product, not the docs: surface the
rate-limit state on the source-health panel and in the operator console, the way
a stale source is surfaced. The cache already records `error` and `ttlHours`, so
the data exists.

**Risk.** None.

---

### I8 — Over-built relative to value: the brief generator

**What.** `scripts/brief.ps1` plus `config/brief-template.json` plus the 85
hand-written bilingual justifications in `config/taxonomy.json` is the largest
single body of work in the repository. It produces 38 Markdown files per run that
are gitignored, unlinked, and — on the evidence of `content/briefs/` — generated
once, on 2026-09-22, and not since.

This is not a suggestion to delete it. The 85 justifications are genuinely the
thing the CC BY licence is protecting, and they are also what makes the *vertical
filter on the dashboard* work, which is a live feature. But the brief **document**
is a publishing workflow with no publication attached, and it carries real
ongoing cost: every taxonomy change is now a bilingual editorial change.

**Why it matters for a release.** A stranger reading the README sees four
deliverables of apparently equal standing; one of them produces output they will
never see. Either show it (one committed example brief, linked from the README) or
present it for what it is — a script that turns the taxonomy into a document,
available if you want it.

**Cost.** Near zero, either direction. It is a framing decision.

**Risk.** Committing an example brief means committing frozen third-party titles
and links under the project's name, dated. That is exactly what the brief is
designed to do, so the risk is the intended behaviour — but it should be a
conscious first publication, not a side effect.

---

## 3. Sweep: anything that reads as a test, demo or experiment

The repository is unusually clean. There is no dead code, no commented-out block
in `app/js/` or `lib/`, no `TODO`, `FIXME`, `HACK` or `XXX` anywhere, no stub
file, and no orphan. Every `test`/`example`/`demo` string found is legitimate:
`Test-Path`/`Test-Word` cmdlet names, `example.com` in a documentation snippet,
`config/build.example.json` which is a deliberate worked example, and
`scripts/pack-demo.ps1` which is a shipped feature.

What the sweep did turn up:

| File:line | Finding | Recommendation | Status |
|---|---|---|---|
| `lib/sources.ps1` (working tree) | skills.sh regex corrupted by a `\`→`/` sweep: `\\"source//":` | Revert that one pattern. Blocks the source entirely. | **owner — engine code** |
| `radar.ps1:13` | Comment says "~55 sources are being read"; 54 are enabled | Say 54, or better, drop the number from a comment that will drift | owner — engine code |
| `docs/screenshot-*.png` | Dated 2026-09-18; UI shows `79624ms`, Reddit live, no ops console | Re-shoot all three after the next sync | owner |
| `README.md` "Running it" block | Commands are still written Windows-style (`.\radar.ps1`, `powershell -File scripts\…`) although the engine now targets PowerShell 7. A macOS or Linux reader has to translate them | Rewrite as `./radar.ps1`, `./scripts/sync.ps1`, and say "cron or Task Scheduler". An edit to this block was blocked by a tooling permission during this review and was left alone rather than worked around | owner |
| `docs/ARCHITECTURE.md:69` | "the ~90 s a sync takes" — wrong since the 0.3.0 concurrency change | Fixed: now states 8-way parallelism and the measured 24–38 s | **fixed** |
| `docs/ARCHITECTURE.md` | No ledger contract, no `maxItems`/`catalogueMax` split | Added both as a documented data shape | **fixed** |
| `README.md:43` vs `:227` | Claimed 12 s in one paragraph and ~90 s, sequential fetching, in another. Neither matches any observed run | Rewritten; now states the measured 24–38 s range once | **fixed** |
| `.github/ISSUE_TEMPLATE/source-request.md:15` | "the 19 current sources" — stale since v0.1.0 | Fixed: 54 | **fixed** |
| `.github/ISSUE_TEMPLATE/source-request.md:12` | Category list omitted `release`, which has existed since v0.2.0 | Fixed | **fixed** |
| `app/ops/index.html:160-172` | "Demand signal — Not collected", a deliberately empty card | **Leave it.** It states what is not collected and why, and refuses a default that would need consent. It is the most trustworthy thing on the page. | no action |
| `config/build.example.json` (`search`) | The semantic-search requirement uses `mode: build`, so MCP servers — the obvious coverage for it — are never considered, and it is the one requirement that comes back `thin` | Change the example to `mode: both`. It is a worked example; it should demonstrate the mode that fits | owner |
| `config/sources.json:190,510` | Two `$note` entries on disabled sources | **Leave them.** Correct, load-bearing, and the honest way to ship a source that says no | no action |
| `data/history/orgs.json` | 76 of 578 cached lookups hold a 403 | See I7 | owner |

---

## 4. Personal-identity sweep

**Tracked files — all fixed** (personal account → `<org>` placeholder):

| File | Was |
|---|---|
| `README.md:3,37,213` | CI badge, clone URL, `jbelly-ui` link |
| `config/sources.json:9` | `defaults.userAgent`, sent to every source on every fetch |
| `config/brief-template.json:48,90` | EN and AR brief footers |
| `LICENSE-DATA:39` | the CC BY attribution line |
| `CONTRIBUTING.md:57` | `jbelly-ui` link |

`git grep -i mohammadJohar` over tracked files now returns nothing. Both JSON
files re-parse and the Arabic strings are byte-identical apart from the URL.

**Generated, gitignored, not published** — reported for completeness, no action
needed, but do not commit them as-is:

- `content/briefs/2026-09-22/*.{en,ar}.md` — 38 files, each footer carries the
  personal URL. They will regenerate clean from the fixed template.
- `content/matches/*` — regenerate from `config/match-template.json`, which never
  carried a URL.
- `data/ledger.json` **is committed** and was checked: it holds third-party
  titles, URLs and authors only. No personal identifier.

**The history itself — B0, and the only finding here that files cannot show.**
`LICENSE` and `LICENSE-DATA` are copyright "JBelly" and `git config user.name`
is `JBelly`, so everything visible reads as the brand. But:

```
$ git log --format='%ae %an' | sort -u
mohammadasadjohar@gmail.com JBelly
```

All 25 commits carry a personal Gmail address in the author field, and
`.git/config` still sets it locally, so the next commit adds a twenty-sixth.
Publishing exposes it on every commit page, in the API, and in every generated
`.patch`. This is the owner's call to fix and it is destructive, so nothing was
changed here. The order that works:

1. `git config --local user.email` → a noreply or organisation address, **first**,
   so no further commits inherit it.
2. Rewrite the existing 25 authors (`git filter-repo --mailmap`, or a fresh
   squashed initial commit if the granular history is not worth keeping).
3. Only then push to the organisation.

Doing (3) before (1) and (2) cannot be undone — GitHub keeps orphaned commits
reachable by SHA, and forks and mirrors keep them regardless.

---

## 5. Where the docs and the code disagree

Everything in this list is now either fixed or listed above; it is collected here
because the pattern matters more than the items.

1. **Sync duration** — claimed 12 s and 90 s in the same README, 90 s in
   `ARCHITECTURE.md`, 79,624 ms in the screenshot. Measured from the project's own
   dated snapshots: 64 s, 64 s, 94 s, 72 s, 67 s, 30 s, 24 s on 17–23 September,
   and 38 s on the most recent live run. The concurrency change is real and
   dramatic; the numbers published for it were not.
2. **Source count** — README said "54 (56 configured)"; config agrees. This one
   was already correct, and it was wrong two releases ago. Nothing prevents it
   regressing again (I5).
3. **Catalogue size** — the `[Unreleased]` changelog says 2,656 items / 800 skills
   / 441 MCP servers. A live run reports 2,666 / 800 / 443 and is growing daily.
   Any fixed number in prose is stale on arrival; the README now shows the
   matcher's own output instead and says it grows.
4. **`ARCHITECTURE.md` "kept current"** — it was not (I6).
5. **`backfill-ledger.ps1` "the recovery path"** — not on a fresh clone (I4).
6. **Platform** — the README said Windows PowerShell 5.1 while the working tree
   was already running on both runtimes. Corrected, and deliberately kept short
   of claiming macOS and Linux work, because they have not been run there (§6).

---

## 6. Notes for the PowerShell 7 / cross-platform port

The port is **in progress in a parallel session**, not planned. Nothing here was
edited by this review. What is already done, verified by reading the working
tree:

- `radar.ps1:36-40` — the child sync process now inherits the running
  interpreter's own executable path, falling back to `pwsh`. The hardcoded
  `powershell.exe` is gone.
- `radar.ps1:42-53` — `Open-InBrowser` branches Windows / `open` / `xdg-open`,
  and swallows its own failure so a missing opener cannot take the server down.
- `radar.ps1:94-97` — `-ExecutionPolicy` is passed only on Windows, because
  `pwsh` on Linux and macOS rejects it outright rather than ignoring it. That is
  the right call and an easy one to miss.
- `tests/run-harness.ps1:51-66` — browser discovery now covers the macOS
  `.app` bundles, `/usr/bin/google-chrome*` and bare names on `PATH`.
- Path separators converted to `/` throughout.

What still needs to be true before the README's claim is worth anything:

- **CI runs on one platform.** `.github/workflows/ci.yml` is `windows-latest`
  only and invokes `powershell` (5.1) explicitly. Until the suite and the
  harness run on `ubuntu-latest` and `macos-latest`, cross-platform is a claim,
  not a property — and it is the cheapest possible verification, because the
  static suite needs no browser and no network. Add the matrix before the
  release, not after. The README currently says macOS and Linux are unverified;
  CI is what lets that sentence be deleted.
- **Regex literals are not paths.** The `\` → `/` sweep is right in direction and
  briefly corrupted the skills.sh extraction pattern (B2). Worth a one-time
  `git diff` review of every changed line that contains a backslash but is not a
  `Join-Path` argument. The failure mode is the dangerous kind: a fetcher that
  matches nothing reports `ok` with a low count, not an error.
- **The ISO-8859-1 workaround** (`lib/sources.ps1:75-80`) decodes response bytes
  by hand because Windows PowerShell falls back to Latin-1 on a missing charset.
  PowerShell 7 does not. It has to stay correct under both, and the source most
  likely to expose a regression is the Arabic-free one — a mis-decode shows up
  as a mangled title in a French or German feed, not as an error.
- **The runspace concurrency** (`lib/sources.ps1:~798`) is hand-rolled *because*
  5.1 has no `ForEach-Object -Parallel`. Do not rewrite it to `-Parallel` while
  5.1 is still supported; it is the one place where "runs on both" costs real
  complexity, and the current code already works.
- **Keep the ASCII-only script rule even though its reason expires.**
  `scripts/brief.ps1` and `scripts/match-plan.ps1` keep every user-visible string
  in JSON because "Windows PowerShell reads .ps1 as ANSI". Under 7 that
  constraint is gone, but the design — editorial wording in config, not in code —
  was right for reasons that have nothing to do with encoding. Removing it
  because it is now possible would be a regression.
- **`config/*.json` and `app/**`** are platform-neutral. The client is plain
  scripts with no build step and needs no porting.
- `radar.ps1:13` — the header comment still says "~55 sources are being read".
  54 are enabled. Worth dropping the number rather than correcting it; a count in
  a comment drifts by design.
