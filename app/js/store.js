/* store.js — JBelly Radar behaviour store.
   Prefs, learned affinities, saved/hidden ids and visit diffs, all under
   localStorage keys prefixed "radar.". Every storage access is wrapped, and an
   in-memory copy is kept, so the page keeps working when storage is empty,
   throws (private mode, quota) or is simply absent. Nothing here touches the
   DOM; ui.js owns rendering. */

(function () {
  'use strict';

  window.Radar = window.Radar || {};

  var PREFIX = 'radar.';
  var HALF_LIFE_MS = 14 * 24 * 3600 * 1000;
  var PRUNE_BELOW = 0.05;
  var CAP = 400;
  var UNDO_MS = 10000;

  // Contract weights. Each event touches item.tech, item.tags and item.sourceId
  // so the feed learns both what the user reads and where they read it.
  var WEIGHT = { open: 1.0, save: 2.0, hide: -2.0, unhide: 2.0, unsave: -2.0, dwell: 0.5 };

  var DEFAULTS = {
    theme: 'dark',
    lang: 'en',
    mode: 'foryou',
    profile: { verticals: [], tech: [], orgsOnly: false }
  };
  var ENUM = { theme: ['dark', 'light'], lang: ['en', 'ar'], mode: ['foryou', 'all'] };

  // v1 wrote theme and lang as bare strings; everything else is JSON.
  var RAW = { theme: true, lang: true };

  // The memory layer is the source of truth for the session. Storage is only
  // where it is persisted, and a failing store must not lose in-session state.
  var mem = {};
  var lastHide = null;

  function now() {
    var fn = api._now;
    return typeof fn === 'function' ? fn() : Date.now();
  }

  function read(key) {
    if (Object.prototype.hasOwnProperty.call(mem, key)) return mem[key];
    var v = null;
    try {
      var s = window.localStorage.getItem(PREFIX + key);
      if (s != null) v = RAW[key] ? s : JSON.parse(s);
    } catch (e) { v = null; }
    mem[key] = v;
    return v;
  }

  function write(key, val) {
    mem[key] = val;
    try {
      if (val == null) window.localStorage.removeItem(PREFIX + key);
      else window.localStorage.setItem(PREFIX + key, RAW[key] ? String(val) : JSON.stringify(val));
    } catch (e) { /* storage unavailable: memory copy still serves the session */ }
  }

  function clone(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }

  // ── prefs ──────────────────────────────────────────────────────────────────

  function normProfile(p) {
    p = p && typeof p === 'object' ? p : {};
    var list = function (a) { return Array.isArray(a) ? a.filter(function (x) { return typeof x === 'string'; }) : []; };
    return { verticals: list(p.verticals), tech: list(p.tech), orgsOnly: !!p.orgsOnly };
  }

  function get(key, def) {
    var v = read(key);
    if (v == null) return def !== undefined ? def : clone(DEFAULTS[key]);
    if (ENUM[key] && ENUM[key].indexOf(v) === -1) return def !== undefined ? def : DEFAULTS[key];
    if (key === 'profile') return normProfile(v);
    return v;
  }

  function set(key, val) {
    if (ENUM[key] && ENUM[key].indexOf(val) === -1) return get(key);
    if (key === 'profile') val = normProfile(val);
    write(key, val);
    return val;
  }

  function prefs(patch) {
    if (patch && typeof patch === 'object') {
      Object.keys(DEFAULTS).forEach(function (k) { if (k in patch) set(k, patch[k]); });
    }
    return { theme: get('theme'), lang: get('lang'), mode: get('mode'), profile: get('profile') };
  }

  // ── affinity ───────────────────────────────────────────────────────────────

  function decayed(w, at, t) {
    var age = t - at;
    if (!(age > 0)) return w;
    return w * Math.pow(0.5, age / HALF_LIFE_MS);
  }

  function loadAff() {
    var a = read('affinity');
    if (!a || typeof a !== 'object') a = {};
    return {
      tag: a.tag && typeof a.tag === 'object' ? a.tag : {},
      source: a.source && typeof a.source === 'object' ? a.source : {}
    };
  }

  // Bring every entry to time t, drop the noise, and keep storage bounded by
  // evicting the weakest entries once the cap is exceeded.
  function settle(a, t) {
    var all = [];
    ['tag', 'source'].forEach(function (kind) {
      var out = {};
      Object.keys(a[kind]).forEach(function (name) {
        var e = a[kind][name];
        if (!e || typeof e.w !== 'number') return;
        var w = decayed(e.w, typeof e.at === 'number' ? e.at : t, t);
        if (Math.abs(w) < PRUNE_BELOW) return;
        out[name] = { w: w, at: t };
        all.push({ kind: kind, name: name, abs: Math.abs(w) });
      });
      a[kind] = out;
    });
    if (all.length > CAP) {
      all.sort(function (x, y) { return x.abs - y.abs; });
      all.slice(0, all.length - CAP).forEach(function (e) { delete a[e.kind][e.name]; });
    }
    return a;
  }

  function bump(map, name, delta, t) {
    if (!name || typeof name !== 'string') return;
    var e = map[name];
    var w = e && typeof e.w === 'number' ? decayed(e.w, typeof e.at === 'number' ? e.at : t, t) : 0;
    map[name] = { w: w + delta, at: t };
  }

  function apply(item, delta) {
    if (!item || typeof item !== 'object') return;
    var t = now();
    var a = loadAff();
    [].concat(item.tech || [], item.tags || []).forEach(function (n) {
      if (n != null) bump(a.tag, String(n).toLowerCase(), delta, t);
    });
    if (item.sourceId) bump(a.source, String(item.sourceId), delta, t);
    write('affinity', settle(a, t));
  }

  function size(a) { return Object.keys(a.tag).length + Object.keys(a.source).length; }

  function affinity() {
    var raw = loadAff();
    var before = size(raw);
    var a = settle(raw, now());
    // Persist only when pruning removed something; a read must not otherwise
    // churn storage on every render.
    if (size(a) !== before) write('affinity', a);
    var flat = function (m) {
      var o = {};
      Object.keys(m).forEach(function (k) { o[k] = m[k].w; });
      return o;
    };
    return { tag: flat(a.tag), source: flat(a.source) };
  }

  // ── lists (saved / hidden) ─────────────────────────────────────────────────

  function idOf(x) { return x && typeof x === 'object' ? x.id : x; }

  function list(key) {
    var v = read(key);
    return Array.isArray(v) ? v.filter(function (x) { return typeof x === 'string'; }) : [];
  }

  function without(arr, id) { return arr.filter(function (x) { return x !== id; }); }

  function open(item) { apply(item, WEIGHT.open); }

  function save(item) {
    var id = idOf(item);
    if (!id || isSaved(id)) return;
    write('saved', [id].concat(without(list('saved'), id)));
    apply(item, WEIGHT.save);
  }

  function unsave(item) {
    var id = idOf(item);
    if (!id || !isSaved(id)) return;
    write('saved', without(list('saved'), id));
    apply(item, WEIGHT.unsave);
  }

  function hide(item) {
    var id = idOf(item);
    // A no-op hide must not arm undo: there is no weight to give back.
    if (!id || isHidden(id)) return;
    write('hidden', [id].concat(list('hidden')));
    apply(item, WEIGHT.hide);
    // Keep the item so undo can reverse the affinity change, not just the id.
    lastHide = { id: id, at: now(), item: typeof item === 'object' ? item : null };
  }

  // The undo candidate lives UNDO_MS; past that the hide is committed and an
  // unhide is a plain list edit, not an undo.
  function undoCandidate() {
    if (lastHide && now() - lastHide.at > UNDO_MS) lastHide = null;
    return lastHide;
  }

  function unhide(id) {
    id = idOf(id);
    if (!id || !isHidden(id)) return;
    write('hidden', without(list('hidden'), id));
    var c = undoCandidate();
    if (c && c.id === id) {
      if (c.item) apply(c.item, WEIGHT.unhide);
      lastHide = null;
    }
  }

  function lastHidden() {
    var c = undoCandidate();
    return c ? { id: c.id, at: c.at, item: c.item } : null;
  }

  // Dwell is only meaningful past the contract's threshold; anything shorter
  // is a scroll-past, not reading.
  function dwell(item, seconds) {
    if (!(seconds >= 8)) return;
    apply(item, WEIGHT.dwell);
  }

  function saved() { return list('saved'); }
  function hidden() { return list('hidden'); }
  function isSaved(id) { return list('saved').indexOf(idOf(id)) !== -1; }
  function isHidden(id) { return list('hidden').indexOf(idOf(id)) !== -1; }

  // ── visits ─────────────────────────────────────────────────────────────────

  function visitOf(key) {
    var v = read(key);
    if (!v || typeof v !== 'object' || !Array.isArray(v.ids)) return null;
    return v;
  }

  // Each call rotates: the set on screen becomes "this visit", the previous one
  // becomes the baseline for isNew. `append` merges into the current visit
  // instead (items arriving via live.js mid-session), so they still read as new.
  function markVisit(ids, append) {
    var clean = (Array.isArray(ids) ? ids : []).map(idOf).filter(function (x) { return typeof x === 'string'; });
    var cur = visitOf('visit');
    if (append && cur) {
      var seen = {};
      cur.ids.forEach(function (x) { seen[x] = true; });
      clean.forEach(function (x) { if (!seen[x]) { cur.ids.push(x); seen[x] = true; } });
      write('visit', cur);
      return;
    }
    if (cur) write('lastVisit', cur);
    write('visit', { ids: clean, at: now() });
  }

  function isNew(id) {
    var last = visitOf('lastVisit');
    if (!last) return false;
    return last.ids.indexOf(idOf(id)) === -1;
  }

  // The previous visit as recorded: the baseline isNew() diffs against.
  function lastVisit() {
    var last = visitOf('lastVisit');
    if (!last) return null;
    return { ids: last.ids.slice(), at: typeof last.at === 'number' ? last.at : null };
  }

  function lastVisitAt() {
    var last = lastVisit();
    return last ? last.at : null;
  }

  // ── backup ─────────────────────────────────────────────────────────────────

  var KEYS = ['theme', 'lang', 'mode', 'profile', 'affinity', 'saved', 'hidden', 'visit', 'lastVisit'];

  function exportAll() {
    var out = { version: 2, exportedAt: now(), data: {} };
    KEYS.forEach(function (k) {
      var v = read(k);
      if (v != null) out.data[k] = v;
    });
    return JSON.stringify(out);
  }

  function importAll(json) {
    var obj;
    try { obj = typeof json === 'string' ? JSON.parse(json) : json; } catch (e) { return false; }
    if (!obj || typeof obj !== 'object') return false;
    var data = obj.data && typeof obj.data === 'object' ? obj.data : obj;
    var any = false;
    KEYS.forEach(function (k) {
      if (!(k in data)) return;
      if (ENUM[k]) { set(k, data[k]); any = true; return; }
      write(k, k === 'profile' ? normProfile(data[k]) : data[k]);
      any = true;
    });
    return any;
  }

  function reset() {
    KEYS.forEach(function (k) { write(k, null); });
    // Sweep any other radar.* key (older versions, stray writes) so a reset
    // really is a clean slate.
    try {
      var ls = window.localStorage, stray = [];
      for (var i = 0; i < ls.length; i++) {
        var k = ls.key(i);
        if (k && k.indexOf(PREFIX) === 0) stray.push(k);
      }
      stray.forEach(function (k) { ls.removeItem(k); });
    } catch (e) { /* storage unavailable: nothing persisted to sweep */ }
    lastHide = null;
    mem = {};
  }

  var api = {
    prefs: prefs, get: get, set: set,
    open: open, save: save, unsave: unsave, hide: hide, unhide: unhide, dwell: dwell,
    affinity: affinity,
    saved: saved, isSaved: isSaved, hidden: hidden, isHidden: isHidden, lastHidden: lastHidden,
    markVisit: markVisit, isNew: isNew, lastVisit: lastVisit, lastVisitAt: lastVisitAt,
    'export': exportAll, 'import': importAll, reset: reset,
    _now: null,
    _keys: KEYS.slice(),
    _halfLifeMs: HALF_LIFE_MS
  };

  window.Radar.store = api;
})();
