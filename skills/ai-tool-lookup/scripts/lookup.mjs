#!/usr/bin/env node
//
// lookup.mjs — does an agent skill or an MCP server already cover this?
//
//   node lookup.mjs "postgres migrations"
//   node lookup.mjs "stripe billing" --kind mcp --top 8
//   node lookup.mjs "pdf table extraction" --json
//
// Fetches the published index from JBelly Radar, matches locally, prints a
// short answer. No model call, no account, no telemetry — one public JSON file
// and a cache in your temp directory.
//
// Node's standard library only, on purpose: a skill that needs `npm install`
// to answer a question is a skill nobody runs twice.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const INDEX_URL =
  'https://raw.githubusercontent.com/JBelly-tech/jbelly-radar/main/data/index.json';
const CACHE_DIR = join(tmpdir(), 'jbelly-radar');
const CACHE_FILE = join(CACHE_DIR, 'index.json');
const CACHE_HOURS = 12;
const SCHEMA = 1;

// ── arguments ────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};
const has = (name) => argv.includes(`--${name}`);

const query = argv.filter((a) => !a.startsWith('--') && argv[argv.indexOf(a) - 1] !== '--kind' && argv[argv.indexOf(a) - 1] !== '--top').join(' ').trim();
const kind = (flag('kind', 'any') || 'any').toLowerCase();
const top = Math.max(1, parseInt(flag('top', '5'), 10) || 5);
const asJson = has('json');
const fresh = has('fresh');

if (!query) {
  console.log('usage: node lookup.mjs "<what you need>" [--kind skill|mcp|any] [--top N] [--json] [--fresh]');
  process.exit(1);
}
if (!['any', 'skill', 'mcp'].includes(kind)) {
  console.log(`--kind must be skill, mcp or any (got "${kind}")`);
  process.exit(1);
}

// ── the index ────────────────────────────────────────────────────────────────

async function loadIndex() {
  if (!fresh) {
    try {
      const raw = await readFile(CACHE_FILE, 'utf8');
      const doc = JSON.parse(raw);
      const ageH = (Date.now() - Date.parse(doc.builtAt)) / 3.6e6;
      // The cache is reused on its own age, not the file's mtime: the point is
      // how old the DATA is, and a re-download of an unchanged file does not
      // make it newer.
      if (ageH < CACHE_HOURS) return { doc, cached: true };
    } catch { /* no cache, or unreadable — fetch */ }
  }
  let res;
  try {
    res = await fetch(INDEX_URL, { headers: { 'User-Agent': 'ai-tool-lookup' } });
  } catch (e) {
    const stale = await readFile(CACHE_FILE, 'utf8').catch(() => null);
    if (stale) return { doc: JSON.parse(stale), cached: true, offline: true };
    throw new Error(`could not reach the index and no cache to fall back on: ${e.message}`);
  }
  if (!res.ok) throw new Error(`the index answered HTTP ${res.status}`);
  const doc = await res.json();
  await mkdir(CACHE_DIR, { recursive: true });
  await writeFile(CACHE_FILE, JSON.stringify(doc), 'utf8');
  return { doc, cached: false };
}

// ── matching ─────────────────────────────────────────────────────────────────

const words = (s) =>
  String(s || '')
    .toLowerCase()
    .split(/[^a-z0-9+#.]+/i)
    .filter((w) => w.length > 1);

// Word-boundary match. Built per keyword rather than per row: the same regex is
// tested against thousands of rows.
const matcher = (kw) => {
  const esc = kw.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^a-z0-9])${esc}([^a-z0-9]|$)`, 'i');
};

function pool(items) {
  if (kind === 'skill') return items.filter((r) => r.c === 'skill');
  if (kind === 'mcp') return items.filter((r) => r.c !== 'skill' && (r.k || []).includes('mcp'));
  return items;
}

// A keyword matching more than a quarter of the pool is not evidence, it is the
// pool. Searching MCP servers for "mcp" matches every one of them, every
// candidate scores identically, the ranking falls through to raw usage, and the
// answer is a confident list of noise. Such a word is dropped and named.
function discriminating(rows, kws) {
  const limit = Math.max(2, Math.floor(rows.length * 0.25));
  const keep = [], broad = [];
  for (const kw of kws) {
    const re = matcher(kw);
    let n = 0;
    for (const r of rows) {
      if (re.test(r.t) || re.test(r.s || '') || (r.k || []).some((t) => re.test(t))) n++;
      if (n > limit) break;
    }
    (n > limit ? broad : keep).push(kw);
  }
  return { keep, broad };
}

function score(rows, kws) {
  const res = [];
  const tests = kws.map((kw) => [kw, matcher(kw)]);
  for (const r of rows) {
    let s = 0, sharp = false;
    const hits = [];
    const tech = (r.k || []).join(' ');
    for (const [kw, re] of tests) {
      if (re.test(r.t) || re.test(tech)) { s += 3; sharp = true; hits.push(kw); }
      else if (re.test(r.s || '') || re.test(r.p || '') || re.test(r.a || '')) { s += 1; hits.push(kw); }
    }
    if (s > 0) res.push({ r, s, sharp, hits: [...new Set(hits)] });
  }
  // match quality, then a known publisher, then usage
  res.sort((a, b) =>
    b.s - a.s ||
    (a.r.pt || 9) - (b.r.pt || 9) ||
    (b.r.n || -1) - (a.r.n || -1));
  return res;
}

// ── output ───────────────────────────────────────────────────────────────────

const fmt = (n) => Number(n).toLocaleString('en-US');

function render(doc, found, sel, meta) {
  const lines = [];
  const c = doc.counts || {};
  const built = String(doc.builtAt || '').replace('T', ' ').replace('Z', ' UTC');

  if (found.length === 0) {
    lines.push(`Nothing in the record matches "${query}"${kind !== 'any' ? ` among ${kind === 'skill' ? 'agent skills' : 'MCP servers'}` : ''}.`);
  } else {
    lines.push(`${found.length} match${found.length === 1 ? '' : 'es'} for "${query}"${kind !== 'any' ? ` among ${kind === 'skill' ? 'agent skills' : 'MCP servers'}` : ''}. Strongest first:`);
    lines.push('');
    for (const m of found.slice(0, top)) {
      const r = m.r;
      const who = r.p || r.a || 'no named publisher';
      // a figure only appears WITH its unit; the index does not carry one without
      const usage = r.n != null && r.nu ? `${fmt(r.n)} ${r.nu}` : 'no usage figure recorded';
      // "first seen" is an observation; anything else is a lower bound
      const seen = r.f ? (r.fo ? `first seen ${r.f}` : `on the radar by ${r.f}`) : '';
      lines.push(`  ${r.t}`);
      lines.push(`    ${who} · ${usage}${seen ? ` · ${seen}` : ''}`);
      lines.push(`    ${r.u}`);
      if (r.i) lines.push(`    ${r.i}`);
      if (m.hits.length) lines.push(`    matched: ${m.hits.join(', ')}`);
      lines.push('');
    }
  }

  if (sel.broad.length) {
    lines.push(`Ignored as too broad for this pool — each matches over a quarter of it: ${sel.broad.join(', ')}.`);
    lines.push('A word that matches everything ranks nothing.');
    lines.push('');
  }

  lines.push(`Record: ${fmt(c.items || 0)} items (${fmt(c.skills || 0)} skills, ${fmt(c.mcp || 0)} MCP servers), built ${built}${meta.offline ? ' — OFFLINE, served from cache' : ''}.`);
  if (c.anonymous) {
    lines.push(`${fmt(c.anonymous)} further rows are a date with no title and could not be searched, so "nothing matches" is a bounded claim.`);
  }
  lines.push('This reports what exists and how much use it has. Not whether it is good — read the source before installing anything.');
  return lines.join('\n');
}

// ── run ──────────────────────────────────────────────────────────────────────

try {
  const { doc, cached, offline } = await loadIndex();
  if (doc.schema !== SCHEMA) {
    console.log(`This index is schema ${doc.schema}; this lookup understands ${SCHEMA}. Update the skill rather than trusting a file it may misread.`);
    process.exit(1);
  }
  const rows = pool(doc.items || []);
  const sel = discriminating(rows, words(query));
  const found = sel.keep.length ? score(rows, sel.keep) : [];
  const out = render(doc, found, sel, { cached, offline });

  if (asJson) {
    console.log(JSON.stringify({
      query, kind,
      builtAt: doc.builtAt,
      counts: doc.counts,
      ignoredKeywords: sel.broad,
      matches: found.slice(0, top).map((m) => ({
        title: m.r.t, url: m.r.u, category: m.r.c,
        publisher: m.r.p || m.r.a || null,
        usage: m.r.n != null && m.r.nu ? { value: m.r.n, unit: m.r.nu } : null,
        firstSeen: m.r.f || null, firstSeenObserved: !!m.r.fo,
        install: m.r.i || null, matched: m.hits,
      })),
    }, null, 2));
  } else {
    console.log(out);
  }
} catch (e) {
  console.log(`lookup failed: ${e.message}`);
  process.exit(1);
}
