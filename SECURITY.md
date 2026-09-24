# Security

## Reporting a vulnerability

Use **[Report a vulnerability](https://github.com/JBelly-tech/jbelly-radar/security/advisories/new)**
under this repository's Security tab. That reaches the maintainer privately.
Please do not open a public issue for anything exploitable.

Expect a first reply within a week. If a fix is warranted it ships in the next
release with the finding credited, unless you would rather not be.

## What this program does, so you can judge the risk yourself

JBelly Radar runs entirely on your machine. It has no account, no API key, no
telemetry and no backend. But it is not inert, and two of its behaviours are
worth understanding before you run it.

**It fetches 54 public URLs and parses what they return.** The list is in
`config/sources.json` and nothing outside it is ever contacted. Responses are
HTML, RSS and JSON from other people's servers, which means the content is
untrusted input by definition. It is parsed for fields, never executed, and no
fetched value is used to build a file path or a command line.

The one place a hostile response reaches your screen is the dashboard, which
renders titles and summaries from those sources. Text is escaped before it is
inserted; the item URL is rendered as a link. A source that started returning
malicious content could therefore put a link in front of you — the same risk as
any feed reader — but not run code in the page.

**It writes files under `data/` and `content/`.** Every write is to a path the
program computes itself, and each one goes to a temporary file that is then
renamed, so an interrupted run cannot leave a half-written file behind.

**The server is localhost-only.** `radar.ps1` binds `http://localhost:8477/` and
nothing else. It is not reachable from your network. It serves files from the
repository directory and exposes three endpoints — `/api/data`, `/api/status`
and `POST /api/sync`. Anything already able to reach localhost on your machine
can trigger a sync; nothing else can.

**`GITHUB_TOKEN` is optional.** If you set it, it raises GitHub's rate limit for
two sources. It is read from your environment, sent only to `api.github.com`,
and never written to any file the program produces. Not setting it costs you
nothing but a lower rate limit.

## What would count as a vulnerability here

- Anything that makes fetched content execute, on your machine or in the page
- A path traversal through a source's response, a config value, or a URL
  requested from the local server
- The local server reachable from outside localhost
- A token, an absolute path, or anything else private appearing in committed
  output or in a generated brief, match report or demo bundle
- A crafted `config/*.json` or plan file causing command execution

## What does not

- A source going down, rate-limiting, or returning junk. Sources are third
  parties; a failed source is reported and the run continues by design.
- Anything requiring an attacker to already control your machine or your files.
