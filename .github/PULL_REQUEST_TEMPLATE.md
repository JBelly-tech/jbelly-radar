## What this changes

<!-- One or two sentences. -->

## Type

- [ ] New source (configuration only)
- [ ] New source kind (touches `lib/sources.ps1`)
- [ ] Ranking change
- [ ] Dashboard / design
- [ ] Fix
- [ ] Docs

## Checks

- [ ] `powershell -File tests\check.ps1` prints `OK`
- [ ] For a change under `app/js/`: `tests\run-harness.ps1` passes against a running `radar.ps1`
- [ ] For a new source: category chosen, item count noted, rate-limiting noted
- [ ] For a design change: `design/personality.md` updated in this commit
- [ ] For a ranking change: the README's *How ranking works* table still matches
      `config/sources.json`

## Notes

<!-- Anything a reviewer would otherwise have to ask. -->
