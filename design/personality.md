# JBelly Radar — personality

The `jbelly-ui` foundation (token roles, shell, control sizes, behaviours) is
shared with every JBelly product. This file records what is **not** shared.

## Design read

| Field | Value |
|-------|-------|
| **kind** | dashboard — a local monitoring console over external feeds |
| **audience** | one developer, opens it daily for a few minutes, keyboard-first, desktop 1440px |
| **vibe** | instrument · signal · unfussy |
| **system** | preset `theme-graphite`, four dials changed |

## The eight dials

| Dial | Value | Changed from graphite? |
|------|-------|------------------------|
| **Type pairing** | Inter for text and display (house default), `--font-mono` for every meta line | no |
| **Palette** | **signal amber** `oklch(74% 0.15 68)` on cool-slate neutrals, **dark is the default mode** | **yes** — graphite ships signal green on a light page |
| **Shape** | `--radius: 0.375rem` | **yes** — graphite is 0.25rem; 0.25 read as unfinished at this density |
| **Density** | compact — 28/32px controls, 40px rows | no |
| **Surface** | flat-bordered, hairline + `shadow-xs`, no nested cards | no |
| **Motion** | micro (150ms colour/opacity) **plus one signature moment**: heat meters sweep from zero on first paint | **yes** — graphite is "still" |
| **Signature element** | the **heat meter** — a 3px bar on the start edge of every row, length and colour encoding the item's heat — plus a monospace meta line (`source · age · metric`) | **yes** — replaces graphite's dotted separators |
| **Data colours** | amber `68` · cyan `210` · violet `300` · slate `250`, all at equal lightness | derived |

## Why

The screen answers one question — *what changed since yesterday, and how much
does it matter* — for a reader who is scanning, not studying. So the ranking is
the interface: heat decides order, the meter shows it without a number being
read, and everything else (chrome, labels, borders) stays quiet enough that a
row of amber is the only thing that pulls the eye.

Amber over green because green already means "healthy" in the source-health
panel on the same screen; one colour cannot carry two meanings.

## Anti-defaults refused

`blue-600` primary · untouched zinc greys · `rounded-2xl shadow-lg` everywhere ·
purple/blue gradients and gradient text · glassmorphism · icon-in-a-rounded-square
on every card · uniform padding with no hierarchy · `Sparkles` / `Zap` icons ·
emoji as icons · "Elevate / Seamless / Powerful" copy.
