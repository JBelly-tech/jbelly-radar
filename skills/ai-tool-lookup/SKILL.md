---
name: ai-tool-lookup
license: MIT
description: "Check whether an agent skill or an MCP server already exists for a requirement, from a dated record of 2,700+ items across 54 public sources instead of a web search. Use before choosing a skill, MCP server, library or tool for a task, and when asked what is new in AI tooling. Reports what exists and how much use it has, never whether it is good."
---

# ai-tool-lookup

Answers one question: **does something already cover this, and does anyone
actually use it?**

Not from a search engine and not from a leaderboard. From a record — every item
[JBelly Radar](https://github.com/JBelly-tech/jbelly-radar) has seen across 54
public sources, with the date it first saw each one.

## Why this exists

Ask a search engine "is there a skill for X" and you get what is popular this
week. When the answer is *no*, you cannot tell which *no* it is:

- nothing exists → build it
- it exists but is not in this week's top ten → you are about to write it twice

Those read identically and lead to opposite decisions. A record can tell them
apart; a ranking cannot.

## Use it when

- You are about to pick a skill, an MCP server, a library or a tool for a task
- Someone asks whether something exists for a given job
- You are asked what is new, or what shipped recently, in AI tooling
- You are writing an architecture and want to know which parts are already covered

**Do not use it for** general web search, for documentation, or to decide
whether a tool is any good. It reports existence and usage. Quality is a
judgement it does not make and does not pretend to.

## How

One command. It needs Node — which you already have if this skill was installed
with `npx` — and nothing else.

```bash
node skills/ai-tool-lookup/scripts/lookup.mjs "<what you need>"
```

Useful flags:

```bash
--kind skill      only agent skills          (they help whoever WRITES the code)
--kind mcp        only MCP servers           (they help the code while it RUNS)
--top 10          how many to show           (default 5)
--json            machine-readable output
--fresh           ignore the local cache and re-fetch
```

**Pick the kind deliberately.** A skill and an MCP server solve different
problems, and searching one pool for the other's problem returns noise that
reads like an answer. If you are asking "how do I build X well", that is
`--kind skill`. If you are asking "how does the running product talk to X",
that is `--kind mcp`.

## Reading the answer

Each result gives the name, the publisher, the usage figure **with its unit**,
the date the radar first saw it, and the install command where there is one.

Three things the output does that matter:

- **A number always carries its unit.** 414,075 installs and 414,075 weekly
  downloads are not the same claim, so a figure with no recorded unit is not
  printed as one.
- **"first seen" vs "on the radar by".** The first means the radar watched the
  item arrive. The second is a lower bound — it was already there when the
  record began. They are never conflated.
- **A word that matches a quarter of the pool is dropped and named.** Searching
  MCP servers for "mcp" matches all of them and ranks nothing; the tool says so
  instead of returning a confident list of noise.

If nothing matches, that is a real finding — but a bounded one. The record holds
what the radar has seen, and a few hundred of its rows are dates with no title
(seen between snapshots). The tool prints how stale the index is and how many
rows it could not name, so you can weigh the answer instead of trusting it.

## What it does not do

- No model call, in this skill or anywhere in the radar. The matching is
  arithmetic you can read in `scripts/lookup.mjs`.
- No account, no API key, no telemetry. It fetches one public JSON file and
  caches it in your temp directory.
- No ranking by quality, and no recommendation. Read the source before you
  install anything it shows you.

## Getting the whole thing

This skill is the lookup. The radar that builds the record — the live dashboard,
the plan matcher, the per-industry briefs — runs locally with no dependencies:

```bash
git clone https://github.com/JBelly-tech/jbelly-radar.git
cd jbelly-radar && pwsh ./radar.ps1
```

Demo, nothing to install: <https://jbelly-tech.github.io/jbelly-radar/>
