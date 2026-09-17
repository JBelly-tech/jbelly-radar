/* scope.js — the radar scope. Sectors are categories, radius is heat (hot at
   the centre), blip size is log popularity, one amber ramp for heat. Positions
   are a pure function of the item, so a re-render never makes a blip jump.
   Attaches Radar.scope = { mount(el, opts), update(items, {newIds, selectedId}) }.
   Touches no DOM until mount() is called; needs nothing else on Radar. */

(function () {
  'use strict';

  var Radar = window.Radar = window.Radar || {};
  var NS = 'http://www.w3.org/2000/svg';

  // Fixed clockwise order from 12 o'clock; the sector label carries identity,
  // which is why colour is free to encode heat alone.
  var ORDER = ['skill', 'repo', 'release', 'discussion', 'news', 'research'];
  var SECTOR = Math.PI * 2 / ORDER.length;
  // Metric ceilings for blip size; a category not listed has a fixed 5 px blip
  // because its metric (points, none) is not comparable across sources.
  var CEIL = { skill: 500000, repo: 20000, discussion: 800 };
  var CAP = 400;
  var RINGS = [75, 50, 25, 0];

  // Geometry in viewBox units. The SVG scales with its container, so nothing
  // here depends on pixels; the rim leaves room for the sector labels.
  var SIZE = 520;
  var CX = SIZE / 2;
  var RIM = 226;
  var LABEL_R = RIM + 10;
  var mountSeq = 0;

  var st = {
    el: null, svg: null, blips: null, tip: null, table: null,
    opts: {}, byId: {}, items: {}, ro: null, hoverId: null
  };

  // ── pure helpers ──────────────────────────────────────────────────────────

  // FNV-1a: cheap, well spread, and stable across sessions so the same id
  // always lands on the same angle.
  function hash01(s) {
    var h = 0x811c9dc5;
    s = String(s);
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h / 4294967296;
  }

  function sectorIndex(cat) {
    var i = ORDER.indexOf(cat);
    return i < 0 ? ORDER.length - 1 : i;
  }

  function polar(angle, r) {
    // angle 0 = 12 o'clock, clockwise; SVG y grows downward
    return { x: CX + Math.sin(angle) * r, y: CX - Math.cos(angle) * r };
  }

  function position(item) {
    // 8% padding keeps blips off the sector dividers where the sector is ambiguous
    var spread = 0.08 + hash01(item.id) * 0.84;
    var angle = (sectorIndex(item.category) + spread) * SECTOR;
    var heat = clamp(Number(item.heat) || 0, 0, 100);
    return polar(angle, RIM * (1 - heat / 100));
  }

  function radius(item) {
    var ceil = CEIL[item.category];
    if (!ceil) return 5;
    var m = Math.max(0, Number(item.metric) || 0);
    return clamp(3 + 4 * Math.log10(1 + m) / Math.log10(1 + ceil), 3, 11);
  }

  function step(heat) {
    heat = Number(heat) || 0;
    return heat >= 75 ? 4 : heat >= 50 ? 3 : heat >= 25 ? 2 : 1;
  }

  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

  function num(n) {
    if (n == null || n === '') return '';
    n = Number(n);
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return String(n);
  }

  function label(cat) {
    var l = st.opts.labels || {};
    return l[cat] || cat;
  }

  function notable(item) {
    var p = item.publisher;
    return !!(p && (p.tier === 1 || p.tier === 2));
  }

  function toSet(v) {
    if (!v) return {};
    var out = {};
    if (typeof v.forEach === 'function') v.forEach(function (id) { out[id] = true; });
    return out;
  }

  // Proportional cap: each category keeps its share of the whole, and within a
  // category the hottest survive, so a flood of skills cannot push news off.
  function cap(items) {
    if (items.length <= CAP) return items.slice();
    var groups = {};
    items.forEach(function (it) { (groups[it.category] = groups[it.category] || []).push(it); });
    var cats = Object.keys(groups);
    var quota = {}, used = 0, rem = [];
    cats.forEach(function (c) {
      var exact = CAP * groups[c].length / items.length;
      quota[c] = Math.floor(exact);
      used += quota[c];
      rem.push({ c: c, frac: exact - quota[c] });
    });
    rem.sort(function (a, b) { return b.frac - a.frac; });
    for (var i = 0; used < CAP && i < rem.length; i++, used++) quota[rem[i].c]++;
    var out = [];
    cats.forEach(function (c) {
      groups[c].sort(function (a, b) { return (b.heat || 0) - (a.heat || 0); });
      out = out.concat(groups[c].slice(0, quota[c]));
    });
    return out;
  }

  // ── DOM builders ──────────────────────────────────────────────────────────

  function svgEl(name, attrs, cls) {
    var n = document.createElementNS(NS, name);
    if (cls) n.setAttribute('class', cls);
    for (var k in attrs) if (attrs[k] != null) n.setAttribute(k, attrs[k]);
    return n;
  }

  function buildChrome(svg) {
    var g = svgEl('g', null, 'scope__chrome');
    g.setAttribute('aria-hidden', 'true');

    RINGS.forEach(function (h) {
      var r = RIM * (1 - h / 100);
      g.appendChild(svgEl('circle', { cx: CX, cy: CX, r: r.toFixed(1), 'data-heat': h },
        'scope__ring' + (h === 0 ? ' scope__ring--rim' : '')));
      if (h) {
        // ring labels once, on the 12 o'clock axis, sitting just above the ring
        var t = svgEl('text', { x: CX + 4, y: (CX - r - 3).toFixed(1) }, 'scope__ring-label');
        t.textContent = String(h);
        g.appendChild(t);
      }
    });

    var defs = svgEl('defs');
    g.appendChild(defs);
    var prefix = 'scope' + (++mountSeq) + '-';

    ORDER.forEach(function (cat, i) {
      var a0 = i * SECTOR, a1 = a0 + SECTOR, p = polar(a0, RIM);
      g.appendChild(svgEl('line', { x1: CX, y1: CX, x2: p.x.toFixed(1), y2: p.y.toFixed(1) }, 'scope__divider'));

      // Labels ride an arc just outside the rim so no word can run out of the
      // viewBox. Arcs in the lower half are drawn the other way round so their
      // text still reads left to right.
      var mid = (a0 + a1) / 2;
      var flip = mid > Math.PI / 2 && mid < Math.PI * 1.5;
      var s = polar(flip ? a1 : a0, LABEL_R), e = polar(flip ? a0 : a1, LABEL_R);
      var id = prefix + cat;
      defs.appendChild(svgEl('path', {
        id: id,
        d: 'M' + s.x.toFixed(1) + ' ' + s.y.toFixed(1) + ' A' + LABEL_R + ' ' + LABEL_R + ' 0 0 ' + (flip ? 0 : 1) + ' ' +
          e.x.toFixed(1) + ' ' + e.y.toFixed(1)
      }));
      var t = svgEl('text', { 'data-cat': cat, 'dominant-baseline': flip ? 'hanging' : 'auto' }, 'scope__sector');
      var tp = svgEl('textPath', { startOffset: '50%', 'text-anchor': 'middle' });
      tp.setAttribute('href', '#' + id);
      tp.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', '#' + id);
      tp.textContent = label(cat);
      t.appendChild(tp);
      g.appendChild(t);
    });

    return g;
  }

  function buildSweep() {
    // A narrow wedge that rotates once and fades; removed on animationend so a
    // later re-render can never restart it (the sweep is a greeting, not a loop).
    var g = svgEl('g', null, 'scope__sweep');
    var a = SECTOR * 0.55, p = polar(a, RIM);
    g.appendChild(svgEl('path', {
      d: 'M' + CX + ' ' + CX + ' L' + CX + ' ' + (CX - RIM) + ' A' + RIM + ' ' + RIM + ' 0 0 1 ' +
        p.x.toFixed(1) + ' ' + p.y.toFixed(1) + ' Z'
    }, 'scope__sweep-fill'));
    g.appendChild(svgEl('line', { x1: CX, y1: CX, x2: p.x.toFixed(1), y2: p.y.toFixed(1) }, 'scope__sweep-edge'));
    g.addEventListener('animationend', function () { if (g.parentNode) g.parentNode.removeChild(g); });
    return g;
  }

  function buildTable() {
    var table = document.createElement('table');
    table.className = 'sr-only scope__table';
    var head = table.createTHead().insertRow();
    ['title', 'category', 'heat'].forEach(function (h) {
      var th = document.createElement('th');
      th.scope = 'col';
      th.textContent = h;
      head.appendChild(th);
    });
    table.appendChild(document.createElement('tbody'));
    return table;
  }

  function blipLabel(item) {
    var parts = [item.title || '', label(item.category), 'heat ' + Math.round(item.heat || 0)];
    if (item.metric != null) parts.push(num(item.metric) + (item.metricLabel ? ' ' + item.metricLabel : ''));
    if (item.publisher && item.publisher.name) parts.push(item.publisher.name);
    return parts.join(', ');
  }

  function ensureCircle(g, cls, wanted, p, r, before) {
    var c = g.querySelector('.' + cls);
    if (!wanted) { if (c) g.removeChild(c); return; }
    if (!c) {
      c = svgEl('circle', null, cls);
      g.insertBefore(c, before || g.firstChild);
    }
    c.setAttribute('cx', p.x.toFixed(2));
    c.setAttribute('cy', p.y.toFixed(2));
    c.setAttribute('r', r.toFixed(2));
  }

  function paintBlip(g, item, isNew, isSelected) {
    var p = position(item), r = radius(item);
    var dot = g.querySelector('.scope__dot');
    if (!dot) { dot = svgEl('circle', null, 'scope__dot'); g.appendChild(dot); }
    dot.setAttribute('cx', p.x.toFixed(2));
    dot.setAttribute('cy', p.y.toFixed(2));
    dot.setAttribute('r', r.toFixed(2));

    // rings sit under the dot; halo lowest, pulse directly under the dot, in
    // that order regardless of which state arrived first
    ensureCircle(g, 'scope__pulse', isNew, p, r + 3, dot);
    ensureCircle(g, 'scope__halo', isSelected, p, r + 7, null);

    g.setAttribute('data-step', step(item.heat));
    g.setAttribute('data-r', r.toFixed(2));
    g.setAttribute('aria-label', blipLabel(item));
    g.setAttribute('class', 'scope__blip' +
      (isNew ? ' scope__blip--new' : '') +
      (isSelected ? ' scope__blip--selected' : '') +
      (notable(item) ? ' scope__blip--notable' : ''));
  }

  // ── tooltip ───────────────────────────────────────────────────────────────

  function text(tag, cls, s) {
    var n = document.createElement(tag);
    n.className = cls;
    n.textContent = s;
    return n;
  }

  function showTip(item, g) {
    var tip = st.tip;
    tip.textContent = '';
    tip.appendChild(text('div', 'scope__tip-title', item.title || ''));
    var meta = [];
    if (item.publisher && item.publisher.name) meta.push(item.publisher.name);
    if (item.sourceLabel) meta.push(item.sourceLabel);
    if (meta.length) tip.appendChild(text('div', 'scope__tip-meta', meta.join(' · ')));
    var stats = 'heat ' + Math.round(item.heat || 0);
    if (item.metric != null) stats += ' · ' + num(item.metric) + (item.metricLabel ? ' ' + item.metricLabel : '');
    tip.appendChild(text('div', 'scope__tip-stats', stats));
    tip.hidden = false;
    placeTip(g);
  }

  function placeTip(g) {
    var dot = g.querySelector('.scope__dot');
    var box = st.el.getBoundingClientRect();
    var sb = st.svg.getBoundingClientRect();
    var k = sb.width / SIZE;
    var x = sb.left - box.left + Number(dot.getAttribute('cx')) * k;
    var y = sb.top - box.top + Number(dot.getAttribute('cy')) * k;
    var r = Number(dot.getAttribute('r')) * k;
    var tip = st.tip;
    var w = tip.offsetWidth, h = tip.offsetHeight, pad = 8;
    // prefer above the blip; flip below near the top edge; always stay inside
    var top = y - r - h - pad;
    if (top < pad) top = y + r + pad;
    var left = clamp(x - w / 2, pad, Math.max(pad, box.width - w - pad));
    top = clamp(top, pad, Math.max(pad, box.height - h - pad));
    tip.style.insetInlineStart = left.toFixed(0) + 'px';
    tip.style.insetBlockStart = top.toFixed(0) + 'px';
  }

  function hideTip() {
    st.tip.hidden = true;
    st.hoverId = null;
  }

  // ── events ────────────────────────────────────────────────────────────────

  function blipOf(target) {
    var n = target;
    while (n && n !== st.blips) {
      if (n.getAttribute && n.getAttribute('data-id') != null) return n;
      n = n.parentNode;
    }
    return null;
  }

  function onEnter(e) {
    var g = blipOf(e.target);
    if (!g) return;
    var id = g.getAttribute('data-id');
    if (id === st.hoverId) return;
    st.hoverId = id;
    var item = st.items[id];
    if (!item) return;
    showTip(item, g);
    if (st.opts.onHover) st.opts.onHover(item);
  }

  function onLeave(e) {
    var g = blipOf(e.target);
    if (!g) return;
    var to = e.relatedTarget && blipOf(e.relatedTarget);
    if (to === g) return;
    hideTip();
    if (st.opts.onHover) st.opts.onHover(null);
  }

  function select(g) {
    var item = st.items[g.getAttribute('data-id')];
    if (item && st.opts.onSelect) st.opts.onSelect(item);
  }

  function onClick(e) {
    var g = blipOf(e.target);
    if (g) select(g);
  }

  function onKey(e) {
    if (e.key !== 'Enter' && e.key !== ' ' && e.key !== 'Spacebar') return;
    var g = blipOf(e.target);
    if (!g) return;
    e.preventDefault();
    select(g);
  }

  function bind(layer) {
    layer.addEventListener('mouseover', onEnter);
    layer.addEventListener('mouseout', onLeave);
    layer.addEventListener('focusin', onEnter);
    layer.addEventListener('focusout', onLeave);
    layer.addEventListener('click', onClick);
    layer.addEventListener('keydown', onKey);
  }

  // ── public ────────────────────────────────────────────────────────────────

  function unmount() {
    if (st.ro) { st.ro.disconnect(); st.ro = null; }
    if (st.el) { st.el.textContent = ''; st.el.classList.remove('scope'); }
    st.el = st.svg = st.blips = st.tip = st.table = null;
    st.byId = {};
    st.items = {};
    st.opts = {};
    st.hoverId = null;
  }

  function mount(el, opts) {
    if (!el) return;
    unmount();
    st.el = el;
    st.opts = opts || {};

    el.classList.add('scope');
    if (st.opts.reducedMotion) el.classList.add('scope--still');
    // role=group, not img: img makes its children presentational, which would
    // strip the focusable blips and the sr-only table out of the a11y tree.
    el.setAttribute('role', 'group');
    el.setAttribute('aria-label', summary([]));
    el.setAttribute('data-showing', '0');
    el.setAttribute('data-total', '0');
    el.setAttribute('data-capped', 'false');

    var svg = svgEl('svg', { viewBox: '0 0 ' + SIZE + ' ' + SIZE, focusable: 'false' }, 'scope__svg');
    svg.appendChild(buildChrome(svg));
    if (!st.opts.reducedMotion) svg.appendChild(buildSweep());
    var blips = svgEl('g', null, 'scope__blips');
    svg.appendChild(blips);
    bind(blips);

    var tip = document.createElement('div');
    tip.className = 'scope__tip';
    tip.setAttribute('role', 'tooltip');
    tip.hidden = true;

    el.appendChild(svg);
    el.appendChild(tip);
    el.appendChild(buildTable());
    st.svg = svg;
    st.blips = blips;
    st.tip = tip;
    st.table = el.querySelector('.scope__table');

    // The viewBox does the scaling; the observer only keeps an open tooltip
    // glued to its blip when the container changes size.
    if (typeof ResizeObserver === 'function') {
      st.ro = new ResizeObserver(function () {
        if (st.hoverId && st.byId[st.hoverId]) placeTip(st.byId[st.hoverId]);
      });
      st.ro.observe(el);
    }
  }

  function summary(items) {
    var counts = {};
    items.forEach(function (it) { counts[it.category] = (counts[it.category] || 0) + 1; });
    var parts = ORDER.filter(function (c) { return counts[c]; })
      .map(function (c) { return counts[c] + ' ' + label(c); });
    return 'Radar scope, ' + items.length + ' signals' + (parts.length ? ': ' + parts.join(', ') : '');
  }

  function update(items, state) {
    if (!st.el) return;
    items = Array.isArray(items) ? items : [];
    state = state || {};
    var shown = cap(items);
    var newIds = toSet(state.newIds);
    var selectedId = state.selectedId == null ? null : String(state.selectedId);
    var keep = {};

    st.items = {};
    shown.forEach(function (it) {
      var id = String(it.id);
      st.items[id] = it;
      keep[id] = true;
      var g = st.byId[id];
      if (!g) {
        g = svgEl('g', { role: 'button', tabindex: '0', 'data-id': id }, 'scope__blip');
        st.byId[id] = g;
      }
      paintBlip(g, it, !!newIds[id], id === selectedId);
    });

    Object.keys(st.byId).forEach(function (id) {
      if (keep[id]) return;
      var g = st.byId[id];
      if (g.parentNode) g.parentNode.removeChild(g);
      delete st.byId[id];
    });

    // Small blips on top of big ones, so nothing is buried under a giant repo.
    // appendChild moves an existing node, which is how the z-order is set.
    shown.slice().sort(function (a, b) { return radius(b) - radius(a); }).forEach(function (it) {
      st.blips.appendChild(st.byId[String(it.id)]);
    });

    var tbody = st.table.tBodies[0];
    tbody.textContent = '';
    shown.forEach(function (it) {
      var row = tbody.insertRow();
      [it.title || '', label(it.category), String(Math.round(it.heat || 0))].forEach(function (v) {
        row.insertCell().textContent = v;
      });
    });

    st.el.setAttribute('data-showing', String(shown.length));
    st.el.setAttribute('data-total', String(items.length));
    st.el.setAttribute('data-capped', String(shown.length < items.length));
    st.el.setAttribute('aria-label', summary(shown));

    if (st.hoverId && !st.items[st.hoverId]) hideTip();
    else if (st.hoverId) placeTip(st.byId[st.hoverId]);
  }

  Radar.scope = { mount: mount, update: update, unmount: unmount, CAP: CAP };
})();
