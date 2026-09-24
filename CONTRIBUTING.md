# Contributing

Issues and pull requests are welcome. The project is small on purpose; these
notes keep it that way.

## Before you open a pull request

```powershell
powershell -ExecutionPolicy Bypass -File tests\check.ps1
```

It must print `OK - n checks passed`. For a change under `app/js/`, also start
`.\radar.ps1 -NoOpen -NoSync` and run `powershell -File tests\run-harness.ps1`.
CI runs both, plus PSScriptAnalyzer at severity *Error*, on Windows.

## Adding a source

Most contributions are a new source, and a source is **configuration, not code**.
Add an object to `config/sources.json` and run the suite. The README's *Adding a
source* section lists the keys each `kind` accepts.

Include in the pull request:

- the source's category and why it belongs there,
- roughly how many items it returns, and
- whether it rate-limits (a source that returns 429 regularly should say so in a
  `$note` key).

## Adding a source kind

Only when no existing kind can read the source. It is one function in
`lib/sources.ps1` returning `New-RadarItem` objects, plus one line in the
`switch` inside `Invoke-RadarSync`, plus the kind's name in the `$knownKinds`
list in `tests/check.ps1`. Keep the fetcher free of ranking logic — heat and
momentum are computed once, for every source, afterwards.

## Rules the suite enforces

- **No raw colour outside `app/tokens.css`.** Components reference token roles.
  Re-branding is one edit, and dark mode costs nothing.
- **No external resource in `app/index.html`.** No CDN, no web font. The
  dashboard has to work offline once the data is synced.
- **One `<h1>`, one primary button, an `aria-label` on every icon-only button,
  a skip link.**
- **Generated data stays out of git.** `data/` is a cache.

## Style

- Windows PowerShell 5.1 compatible — no `pwsh`-only syntax, no `??`, no `?:`,
  no `&&` chaining.
- Comments explain *why*, not *what*. A comment that restates the line is noise.
- No dependencies. If something needs a package, it probably needs a discussion
  first.

## Design changes

The interface follows [`jbelly-ui`](https://github.com/JBelly-tech/jbelly-ui).
A visual change that alters the product's identity — palette, shape, density,
motion, the signature element — updates `design/personality.md` in the same
commit.
