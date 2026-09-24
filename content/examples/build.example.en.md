# Example: a small B2B SaaS with an AI assistant: what the radar already covers

**2026-09-24** · JBelly Radar · matched against 2762 catalogued items (803 skills, 468 MCP servers)

Each requirement below comes from the build section of the architecture, not
from the radar. The radar only answers one question about it: is there already
something that covers this, and is it worth anything.

Nothing here is a recommendation. A match means something exists and how much
use it has, never that it is good. Read the source before you install it.

## Covered

### auth - Email and Google sign-in, team invitations, role checks on every endpoint

**Chosen:** Supabase Auth

7 candidate(s) in the catalogue. The strongest:

- **[supabase-postgres-best-practices](https://github.com/supabase/agent-skills)** - Supabase
  <br>414,075 installs · on the radar by 2026-09-23 - supabase
  <br>`npx skills add supabase/agent-skills`
- **[supabase](https://github.com/supabase/agent-skills)** - Supabase
  <br>289,444 installs · on the radar by 2026-09-23 - supabase
  <br>`npx skills add supabase/agent-skills`
- **[convex-setup-auth](https://github.com/get-convex/agent-skills)** - Convex
  <br>94,104 installs · on the radar by 2026-09-23 - auth
  <br>`npx skills add get-convex/agent-skills`

_Marked `open`. It came back covered, so the alternatives were not raised._

### payments - Subscriptions, metered usage billing, invoices

**Chosen:** Stripe

12 candidate(s) in the catalogue. The strongest:

- **[stripe-best-practices](https://github.com/stripe/ai)** - Stripe
  <br>88,170 installs · on the radar by 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`
- **[upgrade-stripe](https://github.com/stripe/ai)** - Stripe
  <br>67,710 installs · on the radar by 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`
- **[stripe-projects](https://github.com/stripe/ai)** - Stripe
  <br>65,065 installs · on the radar by 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`

_Marked `firm`, so this is reported and not reopened._

### assistant - An in-product assistant that reads the customer's own data and acts on it

**Chosen:** MCP server over our own API

178 candidate(s) in the catalogue. The strongest:

- **[@typia/mcp](https://www.npmjs.com/package/@typia/mcp)** - no named publisher
  <br>14,815 weekly downloads · on the radar by 2026-09-23 - model context protocol, tool
- **[activeing123/mcptoon](https://github.com/activeing123/mcptoon)** - activeing123
  <br>203 stars · on the radar by 2026-09-17 - agent, tool
- **[INo-xious/stockbit-mcp](https://github.com/INo-xious/stockbit-mcp)** - INo-xious
  <br>43 stars · on the radar by 2026-09-23 - model context protocol, agent

_Ignored as too broad for this pool (each matched over a quarter of it): mcp, agents. A keyword that matches everything ranks nothing._

_Marked `firm`, so this is reported and not reopened._

### observability - Trace every assistant call: latency, tokens, cost per customer

**Chosen:** OpenTelemetry + a hosted backend

15 candidate(s) in the catalogue. The strongest:

- **[@hasna/logs](https://www.npmjs.com/package/@hasna/logs)** - no named publisher
  <br>1,342 weekly downloads · first seen 2026-09-23 - monitoring, logs
- **[google-agents-cli-observability](https://github.com/google/agents-cli)** - Google
  <br>328,249 installs · on the radar by 2026-09-23 - observability
  <br>`npx skills add google/agents-cli`
- **[azure-observability](https://github.com/microsoft/azure-skills)** - Microsoft
  <br>98,331 installs · on the radar by 2026-09-23 - observability
  <br>`npx skills add microsoft/azure-skills`

_Marked `open`. It came back covered, so the alternatives were not raised._

### search - Semantic search across the customer's uploaded documents

**Chosen:** pgvector on the existing Postgres

3 candidate(s) in the catalogue. The strongest:

- **[yuezhiai/jonex](https://github.com/yuezhiai/jonex)** - yuezhiai
  <br>1,167 stars · on the radar by 2026-09-23 - rag
- **[axoviq-ai/synthadoc](https://github.com/axoviq-ai/synthadoc)** - axoviq-ai
  <br>1,332 stars · on the radar by 2026-09-23 - rag
- **[001TMF/harness-forge](https://github.com/001TMF/harness-forge)** - 001TMF
  <br>80 stars · on the radar by 2026-09-23 - retrieval

_Marked `open`. It came back covered, so the alternatives were not raised._

### pdf-extraction - Pull tables out of supplier PDFs and normalise them

**Chosen:** undecided

8 candidate(s) in the catalogue. The strongest:

- **[pdf](https://github.com/anthropics/skills)** - Anthropic
  <br>200,352 installs · on the radar by 2026-09-23 - pdf
  <br>`npx skills add anthropics/skills`
- **[nexu-io/open-design](https://github.com/nexu-io/open-design)** - nexu-io
  <br>97,822 stars · on the radar by 2026-09-17 - pdf
- **[virgiliojr94/book-to-skill](https://github.com/virgiliojr94/book-to-skill)** - virgiliojr94
  <br>32,142 stars · on the radar by 2026-09-17 - pdf

_Marked `open`. It came back covered, so the alternatives were not raised._

## Not the radar's business

### invoicing-ledger - Double-entry bookkeeping for the finance team's export

_Marked `manual`: built by hand, so no skill or MCP server applies._


---

## How to read this

**Covered** means at least one candidate matched in its title or its technology
tag AND has either a known publisher or usage above the median for its kind in
this catalogue. The median is computed at run time from the catalogue itself, so
it moves as the catalogue does and is never a number frozen into a script.

**Thin** means candidates matched but none cleared that bar. Treat it as *maybe*,
and go read the source.

**No coverage** is the only finding that should move a decision, and only for a
requirement marked `open`. A requirement marked `firm` was decided before the
radar was asked; reopening it every time something new ships is how a project
never ships.

This was matched against the **ledger**, which holds every item the radar has
ever seen, not against the current feed, which holds one sync with every source
capped. Asked against the feed, "no coverage" would often mean "not in today's
top N" - which reads identically and is wrong.

The match is deterministic: keywords against titles, technology tags, summaries
and authors. No model, no network. The same plan and the same catalogue give the
same report.
A keyword matching more than a quarter of the pool it searches is dropped and
named, because it cannot separate anything from anything.


*JBelly Radar · CC BY 4.0*
