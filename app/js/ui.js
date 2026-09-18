/* ui.js — everything that writes DOM except the scope. Consumes Radar.i18n,
   Radar.icons, Radar.store, Radar.rank, Radar.live and Radar.scope exactly as
   docs/ARCHITECTURE.md describes them. main.js boots it. */

(function () {
  'use strict';

  var R = window.Radar;
  var store = R.store;
  var I = R.icons;
  var t = function (k) { return R.i18n.t(k); };
  var fmt = function (k, v) { return R.i18n.format(k, v); };

  var CATS = ['all', 'skill', 'repo', 'release', 'news', 'discussion', 'research'];
  var CAT_ORDER = { skill: 0, repo: 1, release: 2, discussion: 3, news: 4, research: 5 };

  var state = {
    data: null,
    taxonomy: null,
    cat: 'all',
    q: '',
    range: 30,
    sort: 'auto',
    tech: {},          // tag -> true (active technology filters)
    selectedId: null,
    liveNew: {},       // ids that arrived through a live merge this session
    status: null,
    busy: false,
    error: null,
    scopeMounted: false,
    dwell: null        // { item, at }
  };

  var $ = function (id) { return document.getElementById(id); };
  var undoToast = null;     // one restorable hide at a time (store keeps one candidate)
  var drawerTimer = null;
  var lastAnnounced = '';

  // ── helpers ──────────────────────────────────────────────────────────────

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function num(n) {
    if (n == null) return '';
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return String(n);
  }

  function ago(days) {
    if (days == null) return '';
    var a = t('ago');
    if (days < 1 / 24) return Math.max(1, Math.round(days * 1440)) + a.m;
    if (days < 1) return Math.round(days * 24) + a.h;
    return Math.round(days) + a.d;
  }

  function step(heat) { heat = Number(heat) || 0; return heat >= 75 ? 4 : heat >= 50 ? 3 : heat >= 25 ? 2 : 1; }

  function prefs() { return store.prefs(); }

  // Arabic labels live in the taxonomy as label_ar / why_ar; English is the fallback.
  function ar() { return R.i18n.lang === 'ar'; }
  function techLabel(tag) {
    var tx = state.taxonomy && state.taxonomy.technologies;
    if (tx) for (var i = 0; i < tx.length; i++) if (tx[i].tag === tag) return (ar() && tx[i].label_ar) || tx[i].label;
    return tag;
  }
  function verticalLabel(v) { return (ar() && v.label_ar) || v.label; }
  function whyText(m) { return (ar() && m.why_ar) || m.why; }

  function verticalById(id) {
    var vs = state.taxonomy && state.taxonomy.verticals;
    if (vs) for (var i = 0; i < vs.length; i++) if (vs[i].id === id) return vs[i];
    return null;
  }

  function isNew(id) { return !!state.liveNew[id] || store.isNew(id); }

  function newIdSet() {
    var s = {};
    if (!state.data) return s;
    state.data.items.forEach(function (it) { if (isNew(it.id)) s[it.id] = true; });
    return s;
  }

  function rankCtx() {
    var p = prefs();
    return { mode: p.mode, profile: p.profile, affinity: store.affinity(), taxonomy: state.taxonomy };
  }

  function tierBadge(item) {
    if (!item.publisher) return '';
    var tier = item.publisher.tier;
    var label = tier === 1 ? t('tier1') : tier === 2 ? t('tier2') : tier === 3 ? t('tier3') : t('verified');
    return '<span class="badge badge--tier" title="' + esc(label) + '">' + I.badgeCheck + esc(item.publisher.name) + '</span>';
  }

  function whyLines(why) {
    return why.map(function (w) {
      if (w.key === 'publisher') return esc(w.value) + (w.tier ? ' · ' + esc(t('tier' + w.tier)) : ' · ' + esc(t('verified')));
      if (w.key === 'matches') return esc(fmt('matches', { list: (w.value || []).map(techLabel).join(', ') }));
      if (w.key === 'source-affinity') return esc(fmt('sourceAffinity', { source: w.value }));
      if (w.key === 'explore') return esc(t('explore'));
      return '';
    }).filter(Boolean);
  }

  function sparkline(values, w, h) {
    var v = (values || []).filter(function (x) { return typeof x === 'number' && isFinite(x); });
    if (v.length < 2) return '';
    var min = Math.min.apply(null, v), max = Math.max.apply(null, v);
    var span = (max - min) || 1;
    var stepX = w / (v.length - 1);
    var pts = v.map(function (y, i) {
      return (i * stepX).toFixed(1) + ',' + (h - 2 - ((y - min) / span) * (h - 4)).toFixed(1);
    });
    var rising = v[v.length - 1] >= v[0];
    var stroke = rising ? 'var(--success)' : 'var(--muted-foreground)';
    return '<svg viewBox="0 0 ' + w + ' ' + h + '" width="100%" height="100%" preserveAspectRatio="none" aria-hidden="true">' +
      '<polyline fill="none" stroke="' + stroke + '" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" points="' + pts.join(' ') + '"/></svg>';
  }

  function momentumBadge(m) {
    if (m == null) return '';
    var up = m >= 0;
    var cls = Math.abs(m) < 3 ? 'badge--outline' : (up ? 'badge--success' : 'badge--destructive');
    return '<span class="badge ' + cls + '">' + (up ? I.up : I.down) + (up ? '+' : '') + m.toFixed(0) + '%</span>';
  }

  // ── filtering + ordering ─────────────────────────────────────────────────

  function activeTech() { return Object.keys(state.tech); }

  function visible() {
    if (!state.data) return [];
    var q = state.q.trim().toLowerCase();
    var p = prefs();
    var tech = activeTech();
    var out = state.data.items.filter(function (it) {
      if (store.isHidden(it.id)) return false;
      if (state.cat !== 'all' && it.category !== state.cat) return false;
      if (state.range > 0 && it.ageDays != null && it.ageDays > state.range) return false;
      if (p.profile.orgsOnly && !it.publisher) return false;
      if (tech.length) {
        var itemTech = it.tech || [];
        var hit = false;
        for (var i = 0; i < tech.length; i++) if (itemTech.indexOf(tech[i]) !== -1) { hit = true; break; }
        if (!hit) return false;
      }
      if (q) {
        var hay = (it.title + ' ' + it.summary + ' ' + it.sourceLabel + ' ' + it.author + ' ' +
          (it.tags || []).join(' ') + ' ' + (it.tech || []).join(' ') + ' ' + (it.publisher ? it.publisher.name : '')).toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });

    if (state.sort === 'auto') {
      // For you: the personal score; Everything: heat. Both through rank.order
      // so ties break identically and hidden items are already gone.
      return R.rank.order(out, rankCtx());
    }
    var by = {
      new: function (a, b) { return (a.ageDays == null ? 1e9 : a.ageDays) - (b.ageDays == null ? 1e9 : b.ageDays); },
      momentum: function (a, b) { return (b.momentum == null ? -1e9 : b.momentum) - (a.momentum == null ? -1e9 : a.momentum); },
      metric: function (a, b) { return (b.metric || 0) - (a.metric || 0); }
    };
    return out.slice().sort(by[state.sort] || by.new);
  }

  // ── sidebar ──────────────────────────────────────────────────────────────

  function renderNav() {
    var counts = { all: 0 };
    if (state.data) {
      state.data.items.forEach(function (it) {
        if (store.isHidden(it.id)) return;
        counts.all++;
        counts[it.category] = (counts[it.category] || 0) + 1;
      });
    }
    $('catNav').innerHTML = CATS.filter(function (c) { return c === 'all' || counts[c]; }).map(function (c) {
      return '<button class="nav__item" type="button" data-cat="' + c + '" aria-current="' + (state.cat === c) + '">' +
        (I[c] || I.all) + '<span>' + esc(t(c)) + '</span><span class="nav__count">' + (counts[c] || 0) + '</span></button>';
    }).join('');
  }

  function renderTechChips() {
    var el = $('techChips');
    if (!state.data || !state.taxonomy) { el.innerHTML = ''; return; }
    var counts = {};
    state.data.items.forEach(function (it) { (it.tech || []).forEach(function (tg) { counts[tg] = (counts[tg] || 0) + 1; }); });
    var rows = state.taxonomy.technologies
      .filter(function (tx) { return counts[tx.tag]; })
      .sort(function (a, b) { return counts[b.tag] - counts[a.tag]; })
      .slice(0, 18);
    el.innerHTML = rows.map(function (tx) {
      return '<button class="chip chip--sm" type="button" data-tech="' + esc(tx.tag) + '" aria-pressed="' + !!state.tech[tx.tag] + '">' +
        esc(techLabel(tx.tag)) + '<span class="chip__n">' + counts[tx.tag] + '</span></button>';
    }).join('');
  }

  function renderHealth() {
    var el = $('healthList');
    if (!state.data) { el.innerHTML = ''; return; }
    el.innerHTML = state.data.sources.map(function (s) {
      var title = s.status === 'failed' || s.status === 'stale' ? s.message : s.status + ' · ' + s.ms + 'ms';
      var tail = s.status === 'ok'
        ? '<span class="health__n">' + s.count + '</span>'
        : '<span class="health__status">' + esc(t('st-' + s.status)) + (s.status === 'stale' ? ' ' + s.count : '') + '</span>';
      return '<div class="health__row" title="' + esc(title) + '">' +
        '<span class="health__dot health__dot--' + esc(s.status) + '" aria-hidden="true"></span>' +
        '<span class="health__name">' + esc(s.label) + '</span>' + tail + '</div>';
    }).join('');
  }

  // ── header + live bar ────────────────────────────────────────────────────

  function renderMode() {
    var mode = prefs().mode;
    Array.prototype.forEach.call($('modeToggle').querySelectorAll('[data-mode]'), function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-mode') === mode));
    });
    var sortEl = $('sort');
    var opt = sortEl.options[0];
    opt.textContent = mode === 'foryou' ? t('sHeat').replace(/:.*$/, ': ' + t('forYou').toLowerCase()) : t('sHeat');
  }

  function announce(key) {
    if (key === lastAnnounced) return;
    lastAnnounced = key;
    var a = $('announcer');
    if (a) a.textContent = t(key);
  }

  function renderLive() {
    var bar = $('livebar'), text = $('liveText'), track = $('liveTrack'), fill = $('liveFill'), right = $('liveRight');
    var s = state.status;
    if (s && s.state === 'offline') announce('offline');
    else if (s && s.state === 'syncing') announce('syncingSources');
    else if (s && state.data) announce('syncedT');
    bar.classList.remove('livebar--syncing', 'livebar--offline');
    track.hidden = true;
    right.innerHTML = '';

    if (!R.live.isServed) {
      text.textContent = t('never').replace(/.*/, state.data ? (t('generated') + ' ' + sinceGenerated()) : t('never'));
      return;
    }
    if (s && s.state === 'offline') {
      bar.classList.add('livebar--offline');
      text.textContent = t('offline');
      return;
    }
    if (s && s.state === 'syncing') {
      bar.classList.add('livebar--syncing');
      var done = s.done || 0, total = s.total || 0;
      text.textContent = fmt('syncing', { done: done, total: total, current: s.current || '' });
      track.hidden = false;
      fill.style.width = (total ? Math.round(100 * done / total) : 5) + '%';
      return;
    }
    text.textContent = t('live') + ' · ' + t('generated') + ' ' + sinceGenerated();
    if (s && s.everyMinutes) right.innerHTML = '<span>' + I.radar + '</span><span>' + s.everyMinutes + 'm</span>';
  }

  function sinceGenerated() {
    if (!state.data) return t('never');
    var mins = Math.max(0, Math.round((Date.now() - new Date(state.data.generatedAt).getTime()) / 60000));
    return mins < 1 ? '<1m' : ago(mins / 1440);
  }

  function renderSubtitle() {
    var p = $('subtitle');
    if (!state.data) { p.textContent = t('never'); return; }
    p.textContent = t('generated') + ' ' + sinceGenerated() + ' · ' + state.data.counts.total + ' · ' + state.data.durationMs + 'ms';

    var chips = [];
    var newCount = Object.keys(newIdSet()).length;
    if (newCount) chips.push('<button class="chip chip--count" type="button" data-act="filter-new">' + I.radar + esc(fmt('newSignals', { n: newCount })) + '</button>');
    if (state.cat !== 'all') chips.push('<button class="chip" type="button" data-act="clear-cat">' + esc(t(state.cat)) + I.x + '</button>');
    activeTech().forEach(function (tg) { chips.push('<button class="chip" type="button" data-tech="' + esc(tg) + '" aria-pressed="true">' + esc(techLabel(tg)) + I.x + '</button>'); });
    if (state.q) chips.push('<button class="chip" type="button" data-act="clear-q">"' + esc(state.q) + '"' + I.x + '</button>');
    if (prefs().profile.orgsOnly) chips.push('<button class="chip" type="button" data-act="profile">' + I.badgeCheck + esc(t('profileOrgs')) + '</button>');
    $('activeChips').innerHTML = chips.join('');
  }

  // ── KPIs, scope, rail ────────────────────────────────────────────────────

  function renderKpis() {
    var d = state.data;
    if (!d) { $('kpis').innerHTML = ''; return; }
    var items = d.items;
    var hot = items.filter(function (i) { return i.heat >= 70; }).length;
    var notable = items.filter(function (i) { return i.publisher; }).length;
    var newCount = Object.keys(newIdSet()).length;
    var live = d.sources.filter(function (s) { return s.status === 'ok'; }).length;
    var failed = d.sources.filter(function (s) { return s.status === 'failed'; }).length;

    var perDay = [0, 0, 0, 0, 0, 0, 0];
    items.forEach(function (i) { if (i.ageDays != null && i.ageDays >= 0 && i.ageDays < 7) perDay[6 - Math.floor(i.ageDays)]++; });
    var buckets = [0, 0, 0, 0, 0];
    items.forEach(function (i) { buckets[Math.min(4, Math.floor(i.heat / 20))]++; });

    var cards = [
      { label: t('kTotal'), value: items.length, spark: perDay, cap: t('cDay'), badge: '<span class="badge badge--outline">' + d.sources.length + ' ' + esc(t('srcBadge')) + '</span>' },
      { label: t('kHot'), value: hot, spark: buckets, cap: t('cHeat'), badge: '<span class="badge badge--primary">' + esc(t('heat')) + ' 70+</span>' },
      { label: t('newSince'), value: newCount, badge: '<span class="badge badge--new">' + I.radar + esc(t('newBadge')) + '</span>' },
      { label: t('notable'), value: notable, badge: failed ? '<span class="badge badge--destructive">' + I.error + failed + '</span>' : '<span class="badge badge--success">' + I.ok + live + '/' + d.sources.length + '</span>' }
    ];
    $('kpis').innerHTML = cards.map(function (c) {
      return '<section class="card"><div class="kpi">' +
        '<div class="kpi__top"><span class="kpi__label">' + esc(c.label) + '</span>' + c.badge + '</div>' +
        '<div class="kpi__value">' + esc(c.value) + '</div>' +
        (c.spark ? '<div class="kpi__foot"><div class="kpi__spark">' + sparkline(c.spark, 100, 28) + '</div><span class="kpi__cap">' + esc(c.cap) + '</span></div>' : '') +
        '</div></section>';
    }).join('');
  }

  function scopeLabels() {
    return { skill: t('skill'), repo: t('repo'), release: t('release'), discussion: t('discussion'), news: t('news'), research: t('research') };
  }

  function reducedMotion() {
    return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  }

  function mountScope(still) {
    var el = $('scope');
    if (!el) return;
    R.scope.mount(el, {
      labels: scopeLabels(),
      reducedMotion: still || reducedMotion(),
      onSelect: function (item) { selectItem(item.id, true); },
      onHover: function (item) { highlightRow(item ? item.id : null); }
    });
    state.scopeMounted = true;
    $('scopeLegend').innerHTML =
      '<span><span class="scope-legend__ramp"><i></i><i></i><i></i><i></i></span> ' + esc(t('heat')) + '</span>' +
      '<span><span class="scope-legend__dot"></span> ' + esc(t('notable')) + '</span>' +
      '<span><span class="scope-legend__new"></span> ' + esc(t('newSince')) + '</span>';
  }

  function renderScope(rows) {
    if (!state.scopeMounted) return;
    var known = rows.filter(function (i) { return CAT_ORDER[i.category] != null; });
    R.scope.update(known, { newIds: newIdSet(), selectedId: state.selectedId });
    var el = $('scope');
    var showing = el.getAttribute('data-showing') || known.length, total = el.getAttribute('data-total') || known.length;
    $('scopeCount').textContent = el.getAttribute('data-capped') === 'true' ? fmt('scopeShowing', { n: showing, total: total }) : String(known.length);
  }

  function renderRail() {
    var el = $('rail'), card = $('notableCard');
    if (!state.data) { el.innerHTML = ''; return; }
    var rows = state.data.items
      .filter(function (i) { return i.publisher && !store.isHidden(i.id); })
      .sort(function (a, b) { return R.rank.reputationOf(b) - R.rank.reputationOf(a) || b.heat - a.heat; })
      .slice(0, 14);
    $('notableCount').textContent = rows.length;
    card.hidden = rows.length === 0;
    el.innerHTML = rows.map(function (it) {
      return '<article class="rail__card" data-id="' + esc(it.id) + '">' +
        '<div class="rail__org">' + I.badgeCheck + esc(it.publisher.name) + (it.publisher.tier ? ' <span class="badge badge--outline badge--sm">T' + it.publisher.tier + '</span>' : '') + '</div>' +
        '<div class="rail__title"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" data-open="' + esc(it.id) + '">' + esc(it.title) + '</a></div>' +
        '<div class="rail__meta"><span>' + esc(t(it.category)) + (it.ageDays != null ? ' · ' + esc(ago(it.ageDays)) : '') + '</span><span>' + esc(t('heat')) + ' ' + it.heat + '</span></div>' +
      '</article>';
    }).join('');
  }

  // ── feed ─────────────────────────────────────────────────────────────────

  function renderFeed() {
    var el = $('feed');

    if (state.error && !state.data) {
      el.innerHTML = '<div class="state"><span class="state__icon state__icon--error">' + I.error + '</span>' +
        '<h3>' + esc(t('errTitle')) + '</h3><p>' + esc(t('errText')) + '</p>' +
        '<button class="btn btn--outline" type="button" data-act="retry">' + esc(t('refresh')) + '</button></div>';
      $('feedCount').textContent = '0';
      return;
    }
    if (!state.data) {
      el.innerHTML = new Array(6).join('x').split('x').map(function () {
        return '<div class="skel-row"><div class="skeleton"></div><div>' +
          '<div class="skeleton" style="height:12px;width:58%"></div>' +
          '<div class="skeleton" style="height:10px;width:82%;margin-top:8px"></div>' +
          '<div class="skeleton" style="height:9px;width:34%;margin-top:8px"></div></div>' +
          '<div class="skeleton" style="height:22px"></div></div>';
      }).join('');
      $('feedCount').textContent = '…';
      return;
    }

    var rows = visible();
    $('feedCount').textContent = rows.length;
    renderScope(rows);

    if (!rows.length) {
      el.innerHTML = '<div class="state"><span class="state__icon">' + I.empty + '</span>' +
        '<h3>' + esc(t('emptyTitle')) + '</h3><p>' + esc(t('emptyText')) + '</p>' +
        '<button class="btn btn--outline" type="button" data-act="clear">' + esc(t('clear')) + '</button></div>';
      return;
    }

    var ctx = rankCtx();
    var foryou = ctx.mode === 'foryou' && state.sort === 'auto';
    var newSet = newIdSet();
    var html = [];
    var dividerDone = false;

    rows.slice(0, 150).forEach(function (it, idx) {
      var isNewRow = !!newSet[it.id];
      if (!dividerDone && !isNewRow && idx > 0 && state.sort === 'new' && Object.keys(newSet).length) {
        html.push('<div class="divider-new">' + esc(t('newSince')) + '</div>');
        dividerDone = true;
      }
      var meta = [esc(it.sourceLabel)];
      if (it.ageDays != null) meta.push(esc(ago(it.ageDays)));
      if (it.author && it.category !== 'news' && !it.publisher) meta.push(esc(it.author));
      // a release feed's title is often just a version string; say whose release it is
      var title = it.title;
      if (it.category === 'release' && /^(v?\d|release\b|@|rust-v|\d{4}\.\d)/i.test(title)) {
        title = (it.publisher ? it.publisher.name : it.sourceLabel.split(' · ')[0]) + ' · ' + title;
      }
      var chips = (it.tech || []).slice(0, 4).map(function (tg) {
        return '<button class="chip chip--sm" type="button" data-tech="' + esc(tg) + '" aria-pressed="' + !!state.tech[tg] + '">' + esc(techLabel(tg)) + '</button>';
      }).join('');
      var why = foryou ? whyLines(R.rank.score(it, ctx).why) : [];
      var saved = store.isSaved(it.id);

      html.push('<article class="item' + (isNewRow ? ' is-new' : '') + (state.selectedId === it.id ? ' is-selected' : '') + '" data-id="' + esc(it.id) + '" data-step="' + step(it.heat) + '">' +
        '<div class="item__heat" title="heat ' + it.heat + '"><i style="--h:' + it.heat + '%"></i></div>' +
        '<div class="item__main">' +
          '<div class="item__title-row">' +
            '<h3 class="item__title"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" data-open="' + esc(it.id) + '">' + esc(title) + '</a></h3>' +
            tierBadge(it) +
            (isNewRow ? '<span class="badge badge--new badge--sm">' + esc(t('newBadge')) + '</span>' : '') +
          '</div>' +
          (it.summary ? '<p class="item__summary">' + esc(it.summary) + '</p>' : '') +
          '<div class="item__meta">' + meta.join('<span class="item__sep">·</span>') + '</div>' +
          (chips ? '<div class="item__chips">' + chips + '</div>' : '') +
        '</div>' +
        '<div class="item__side">' +
          (it.metric != null ? '<span class="item__metric">' + num(it.metric) + '<small>' + esc(it.metricLabel) + '</small></span>' : '') +
          momentumBadge(it.momentum) +
          '<div class="item__actions">' +
            (why.length ? '<span class="why"><button class="btn btn--ghost btn--icon" type="button" data-why="' + esc(it.id) + '" aria-label="' + esc(t('whyRanked')) + '" aria-expanded="false">' + I.info + '</button>' +
              '<div class="why__pop" hidden><strong>' + esc(t('whyRanked')) + '</strong><ul>' + why.map(function (l) { return '<li>' + l + '</li>'; }).join('') + '</ul></div></span>' : '') +
            '<button class="btn btn--ghost btn--icon" type="button" data-save="' + esc(it.id) + '" aria-label="' + esc(saved ? t('unsave') : t('save')) + '" aria-pressed="' + saved + '">' + (saved ? I.bookmarkFilled : I.bookmark) + '</button>' +
            '<button class="btn btn--ghost btn--icon" type="button" data-hide="' + esc(it.id) + '" aria-label="' + esc(t('hide')) + '">' + I.eyeOff + '</button>' +
            (it.install && it.install.indexOf('npx') === 0 ? '<button class="btn btn--ghost btn--icon" type="button" data-copy="' + esc(it.install) + '" aria-label="' + esc(t('copyInstall')) + '" title="' + esc(it.install) + '">' + I.copy + '</button>' : '') +
            '<a class="btn btn--ghost btn--icon" href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" aria-label="' + esc(t('openLink')) + '" data-open="' + esc(it.id) + '">' + I.link + '</a>' +
          '</div>' +
        '</div>' +
      '</article>');
    });
    el.innerHTML = html.join('');
  }

  // ── right column ─────────────────────────────────────────────────────────

  function renderMovers() {
    var el = $('movers');
    if (!state.data) { el.innerHTML = ''; return; }
    var rows = state.data.items
      .filter(function (i) { return i.momentum != null && i.momentum > 0 && !store.isHidden(i.id); })
      .sort(function (a, b) { return b.momentum - a.momentum; })
      .slice(0, 7);
    if (!rows.length) {
      el.innerHTML = '<div class="state" style="padding:28px 20px"><span class="state__icon">' + I.empty + '</span><p>' + esc(t('noMovers')) + '</p></div>';
      return;
    }
    el.innerHTML = rows.map(function (it, i) {
      return '<div class="mover">' +
        '<span class="mover__rank">' + (i + 1) + '</span>' +
        '<div class="mover__body">' +
          '<div class="mover__name"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" data-open="' + esc(it.id) + '">' + esc(it.title) + '</a></div>' +
          '<div class="mover__sub">' + num(it.metric) + ' ' + esc(it.metricLabel) + ' · ' + esc(it.sourceLabel) + '</div>' +
        '</div>' +
        (it.spark ? '<div class="mover__spark">' + sparkline(it.spark, 56, 20) + '</div>' : '') +
        momentumBadge(it.momentum) +
      '</div>';
    }).join('');
  }

  function renderSaved() {
    var el = $('savedList');
    var ids = store.saved();
    var byId = {};
    if (state.data) state.data.items.forEach(function (i) { byId[i.id] = i; });
    var rows = ids.map(function (id) { return byId[id]; }).filter(Boolean).slice(0, 8);
    $('savedCount').textContent = rows.length;
    if (!rows.length) {
      el.innerHTML = '<div class="state" style="padding:24px 20px"><span class="state__icon">' + I.bookmark + '</span><p>' + esc(t('save')) + ' · ' + esc(t('saved')) + '</p></div>';
      return;
    }
    el.innerHTML = rows.map(function (it) {
      return '<div class="mover">' +
        '<div class="mover__body">' +
          '<div class="mover__name"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" data-open="' + esc(it.id) + '">' + esc(it.title) + '</a></div>' +
          '<div class="mover__sub">' + esc(it.sourceLabel) + (it.ageDays != null ? ' · ' + esc(ago(it.ageDays)) : '') + '</div>' +
        '</div>' +
        '<button class="btn btn--ghost btn--icon" type="button" data-save="' + esc(it.id) + '" aria-label="' + esc(t('unsave')) + '" aria-pressed="true">' + I.bookmarkFilled + '</button>' +
      '</div>';
    }).join('');
  }

  function renderMix() {
    var el = $('mix');
    if (!state.data) { el.innerHTML = ''; return; }
    var counts = {};
    state.data.items.forEach(function (i) { counts[i.sourceLabel] = (counts[i.sourceLabel] || 0) + 1; });
    var rows = Object.keys(counts).map(function (k) { return { name: k, n: counts[k] }; })
      .sort(function (a, b) { return b.n - a.n; }).slice(0, 8);
    var max = rows.length ? rows[0].n : 1;
    el.innerHTML = rows.map(function (r) {
      return '<div><div class="bar__top"><span class="bar__name">' + esc(r.name) + '</span><span class="bar__n">' + r.n + '</span></div>' +
        '<div class="bar__track"><div class="bar__fill" style="width:' + ((r.n / max) * 100).toFixed(1) + '%"></div></div></div>';
    }).join('');
  }

  function renderAdvice() {
    var card = $('adviceCard'), el = $('advice'), title = $('adviceTitle');
    var verticals = prefs().profile.verticals || [];
    if (!state.taxonomy || !verticals.length) {
      title.textContent = t('profileTitle');
      el.innerHTML = '<div class="state" style="padding:24px 20px"><span class="state__icon">' + I.briefcase + '</span>' +
        '<p>' + esc(t('profileBusiness')) + '</p><button class="btn btn--outline" type="button" data-act="profile">' + esc(t('profileTitle')) + '</button></div>';
      return;
    }
    var counts = {};
    if (state.data) state.data.items.forEach(function (i) { (i.tech || []).forEach(function (tg) { counts[tg] = (counts[tg] || 0) + 1; }); });
    var v = verticalById(verticals[0]);
    if (!v) { card.hidden = true; return; }
    card.hidden = false;
    title.textContent = fmt('advice', { vertical: verticalLabel(v) });
    el.innerHTML = v.technologies_that_matter.slice(0, 6).map(function (m, i) {
      return '<div class="advice__row">' +
        '<span class="advice__rank">' + (i + 1) + '</span>' +
        '<div>' +
          '<button class="chip chip--sm" type="button" data-tech="' + esc(m.tag) + '" aria-pressed="' + !!state.tech[m.tag] + '">' + esc(techLabel(m.tag)) + '<span class="chip__n">' + (counts[m.tag] || 0) + '</span></button>' +
          '<div class="advice__why">' + esc(whyText(m)) + '</div>' +
        '</div>' +
      '</div>';
    }).join('');
  }

  // ── profile drawer ───────────────────────────────────────────────────────

  var draft = null;

  function openDrawer() {
    if (!state.taxonomy) { toast('err', t('profileTitle'), t('offline')); return; }
    if (!$('profileDrawer').hidden) return;
    clearTimeout(drawerTimer);
    var p = prefs().profile;
    draft = { verticals: p.verticals.slice(), tech: p.tech.slice(), orgsOnly: !!p.orgsOnly };
    renderDrawer();
    // aria-modal promises the rest is inert; make it so (Edge/Chrome support inert)
    var shell = document.querySelector('.shell');
    if (shell) shell.inert = true;
    $('profileDrawer').hidden = false;
    $('drawerBackdrop').classList.add('is-open');
    requestAnimationFrame(function () { $('profileDrawer').classList.add('is-open'); });
    $('drawerClose').focus();
  }

  function closeDrawer() {
    var d = $('profileDrawer');
    if (d.hidden) return;
    d.classList.remove('is-open');
    $('drawerBackdrop').classList.remove('is-open');
    var shell = document.querySelector('.shell');
    if (shell) shell.inert = false;
    clearTimeout(drawerTimer);
    drawerTimer = setTimeout(function () { d.hidden = true; }, 260);
    $('profileBtn').focus();
  }

  // Tab wraps inside the open dialog (inert covers pointer and reader, not the
  // browser's own tab order in every engine).
  function wrapFocus(e) {
    var d = $('profileDrawer');
    var f = d.querySelectorAll('button, input, [tabindex]:not([tabindex="-1"])');
    if (!f.length) return;
    var first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  function renderDrawer() {
    var tx = state.taxonomy;
    $('profileVerticals').innerHTML = tx.verticals.map(function (v) {
      return '<button class="chip" type="button" data-dv="' + esc(v.id) + '" aria-pressed="' + (draft.verticals.indexOf(v.id) !== -1) + '">' + I.briefcase + esc(verticalLabel(v)) + '</button>';
    }).join('');
    $('profileTech').innerHTML = tx.technologies.map(function (x) {
      return '<button class="chip" type="button" data-dt="' + esc(x.tag) + '" aria-pressed="' + (draft.tech.indexOf(x.tag) !== -1) + '">' + esc((ar() && x.label_ar) || x.label) + '</button>';
    }).join('');
    $('profileOrgs').checked = draft.orgsOnly;
  }

  function toggleIn(arr, v) { var i = arr.indexOf(v); if (i === -1) arr.push(v); else arr.splice(i, 1); }

  // ── interaction ──────────────────────────────────────────────────────────

  function selectItem(id, scroll) {
    state.selectedId = id;
    renderFeed();
    if (scroll) {
      var row = document.querySelector('.item[data-id="' + id + '"]');
      if (row) { row.scrollIntoView({ block: 'center', behavior: reducedMotion() ? 'auto' : 'smooth' }); }
    }
  }

  function highlightRow(id) {
    Array.prototype.forEach.call(document.querySelectorAll('.item.is-hover'), function (r) { r.classList.remove('is-hover'); });
    if (id) { var row = document.querySelector('.item[data-id="' + id + '"]'); if (row) row.classList.add('is-hover'); }
  }

  function itemById(id) {
    if (!state.data) return null;
    for (var i = 0; i < state.data.items.length; i++) if (state.data.items[i].id === id) return state.data.items[i];
    return null;
  }

  function toast(kind, title, body, action) {
    var el = document.createElement('div');
    el.className = 'toast toast--' + kind;
    el.innerHTML = (kind === 'err' ? I.error : I.ok) + '<div><strong>' + esc(title) + '</strong><span>' + esc(body || '') + '</span></div>' +
      (action ? '<button class="btn btn--outline" type="button" data-toast-act="' + esc(action.key) + '" style="margin-inline-start:auto">' + esc(action.label) + '</button>' : '');
    $('toasts').appendChild(el);
    if (action) el.querySelector('[data-toast-act]').addEventListener('click', function () { action.run(); el.remove(); });
    setTimeout(function () { el.remove(); }, action ? 9000 : 4200);
    return el;
  }

  // Re-rendering replaces the element that had focus; put focus back on its twin.
  function refocus(selector, fallback) {
    var again = selector && document.querySelector(selector);
    if (again) { again.focus(); return; }
    if (fallback) fallback.focus();
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(function () { toast('ok', t('copied'), text); });
    }
    toast('err', t('copied'), text);
    return Promise.resolve();
  }

  function sync() {
    if (state.busy) return;
    if (!R.live.isServed) { toast('err', t('failT'), t('errText')); return; }
    state.busy = true;
    $('refreshBtn').disabled = true;
    $('refreshBtn').classList.add('is-busy');
    toast('ok', t('syncingSources'), '');
    R.live.sync().then(function () {
      // progress arrives through onStatus; completion through onData
    }).catch(function (e) {
      toast('err', t('failT'), e && e.message ? e.message : String(e));
    }).then(function () {
      state.busy = false;
      $('refreshBtn').disabled = false;
      $('refreshBtn').classList.remove('is-busy');
    });
  }

  function bind() {
    $('catNav').addEventListener('click', function (e) {
      var b = e.target.closest('[data-cat]');
      if (!b) return;
      state.cat = b.getAttribute('data-cat');
      renderNav(); renderFeed(); renderSubtitle();
      closeSidebar();
    });

    var timer = null;
    $('q').addEventListener('input', function (e) {
      clearTimeout(timer);
      var v = e.target.value;
      timer = setTimeout(function () { state.q = v; renderFeed(); renderSubtitle(); }, 120);
    });

    $('range').addEventListener('change', function (e) { state.range = parseInt(e.target.value, 10); renderFeed(); });
    $('sort').addEventListener('change', function (e) { state.sort = e.target.value; renderFeed(); });
    $('refreshBtn').addEventListener('click', sync);
    $('profileBtn').addEventListener('click', openDrawer);
    $('drawerClose').addEventListener('click', closeDrawer);
    $('drawerBackdrop').addEventListener('click', closeDrawer);
    $('profileSkip').addEventListener('click', function () { store.set('onboarded', true); closeDrawer(); });
    $('profileApply').addEventListener('click', function () {
      store.set('profile', draft);
      store.set('onboarded', true);
      if (draft.verticals.length || draft.tech.length) store.set('mode', 'foryou');
      closeDrawer();
      renderAll();
    });
    $('profileOrgs').addEventListener('change', function (e) { if (draft) draft.orgsOnly = e.target.checked; });

    $('modeToggle').addEventListener('click', function (e) {
      var b = e.target.closest('[data-mode]');
      if (!b) return;
      store.set('mode', b.getAttribute('data-mode'));
      renderMode(); renderFeed(); renderSubtitle();
    });

    $('themeBtn').addEventListener('click', function () {
      var next = prefs().theme === 'dark' ? 'light' : 'dark';
      store.set('theme', next);
      document.documentElement.classList.toggle('light', next === 'light');
    });

    $('langBtn').addEventListener('click', function () {
      var next = R.i18n.lang === 'ar' ? 'en' : 'ar';
      store.set('lang', next);
      R.i18n.setLang(next);
      $('langBtn').title = next === 'ar' ? 'English' : 'العربية';
      // sector labels are baked into the SVG at mount; re-mount without the sweep
      mountScope(true);
      renderAll();
    });

    document.addEventListener('click', function (e) {
      var el;
      if ((el = e.target.closest('[data-copy]'))) { copyText(el.getAttribute('data-copy')); return; }
      if ((el = e.target.closest('[data-open]'))) { var it = itemById(el.getAttribute('data-open')); if (it) store.open(it); return; }
      if ((el = e.target.closest('[data-save]'))) {
        var s = itemById(el.getAttribute('data-save'));
        if (!s) return;
        if (store.isSaved(s.id)) store.unsave(s); else store.save(s);
        renderFeed(); renderSaved();
        refocus('[data-save="' + s.id + '"]', $('feed'));
        return;
      }
      if ((el = e.target.closest('[data-hide]'))) {
        var h = itemById(el.getAttribute('data-hide'));
        if (!h) return;
        if (undoToast) { undoToast.remove(); undoToast = null; }
        store.hide(h);
        renderAll();
        undoToast = toast('ok', t('hide'), h.title, { key: 'undo', label: t('undo'), run: function () { store.unhide(h.id); undoToast = null; renderAll(); } });
        var undoBtn = undoToast.querySelector('[data-toast-act]');
        if (undoBtn) undoBtn.focus();
        return;
      }
      if ((el = e.target.closest('[data-why]'))) {
        var pop = el.parentNode.querySelector('.why__pop');
        var open = pop.hidden;
        closeWhy();
        pop.hidden = !open;
        el.setAttribute('aria-expanded', String(open));
        return;
      }
      if ((el = e.target.closest('[data-tech]'))) {
        var tg = el.getAttribute('data-tech');
        var inSidebar = !!el.closest('#techChips');
        if (state.tech[tg]) delete state.tech[tg]; else state.tech[tg] = true;
        renderTechChips(); renderFeed(); renderSubtitle(); renderAdvice();
        refocus((inSidebar ? '#techChips ' : '') + '[data-tech="' + tg + '"]', $('feed'));
        return;
      }
      if ((el = e.target.closest('[data-dv]'))) { toggleIn(draft.verticals, el.getAttribute('data-dv')); renderDrawer(); return; }
      if ((el = e.target.closest('[data-dt]'))) { toggleIn(draft.tech, el.getAttribute('data-dt')); renderDrawer(); return; }
      if ((el = e.target.closest('[data-act]'))) {
        var act = el.getAttribute('data-act');
        if (act === 'clear') { state.q = ''; state.cat = 'all'; state.range = 0; state.tech = {}; $('q').value = ''; $('range').value = '0'; renderAll(); }
        if (act === 'clear-cat') { state.cat = 'all'; renderNav(); renderFeed(); renderSubtitle(); }
        if (act === 'clear-q') { state.q = ''; $('q').value = ''; renderFeed(); renderSubtitle(); }
        if (act === 'filter-new') { state.sort = 'new'; $('sort').value = 'new'; renderFeed(); }
        if (act === 'retry') sync();
        if (act === 'profile') openDrawer();
        return;
      }
      if (!e.target.closest('.why')) closeWhy();
    });

    // dwell: a row the pointer rests on for 8 s counts as read (store gates the threshold)
    $('feed').addEventListener('mouseover', function (e) {
      var row = e.target.closest('.item');
      if (!row || (state.dwell && state.dwell.id === row.getAttribute('data-id'))) return;
      endDwell();
      state.dwell = { id: row.getAttribute('data-id'), at: Date.now() };
    });
    $('feed').addEventListener('mouseleave', endDwell);

    document.addEventListener('keydown', function (e) {
      var tag = document.activeElement ? document.activeElement.tagName : '';
      var typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); $('q').focus(); $('q').select(); return; }
      if (e.key === 'Escape') {
        if (!$('profileDrawer').hidden) { closeDrawer(); return; }
        closeWhy();
        if (document.activeElement === $('q') && $('q').value) { $('q').value = ''; state.q = ''; renderFeed(); renderSubtitle(); }
        closeSidebar();
        return;
      }
      if (!$('profileDrawer').hidden) { if (e.key === 'Tab') wrapFocus(e); return; }
      if (typing) return;
      if (e.key === '/') { e.preventDefault(); $('q').focus(); return; }
      if (e.key.toLowerCase() === 'r' && !e.ctrlKey && !e.metaKey) sync();
      if (e.key.toLowerCase() === 'f') { store.set('mode', prefs().mode === 'foryou' ? 'all' : 'foryou'); renderMode(); renderFeed(); renderSubtitle(); }
      if (e.key.toLowerCase() === 'p') openDrawer();
    });

    $('menuBtn').addEventListener('click', function () {
      $('sidebar').classList.add('is-open');
      $('backdrop').classList.add('is-open');
      $('sidebarClose').focus();
    });
    $('sidebarClose').addEventListener('click', closeSidebar);
    $('backdrop').addEventListener('click', closeSidebar);

    var mq = window.matchMedia('(max-width: 900px)');
    var syncMenuBtn = function () { $('menuBtn').style.display = mq.matches ? 'inline-flex' : 'none'; };
    if (mq.addEventListener) mq.addEventListener('change', syncMenuBtn); else mq.addListener(syncMenuBtn);
    syncMenuBtn();

    // the subtitle's "Xm ago" should not freeze
    setInterval(function () { if (state.data) { renderSubtitle(); renderLive(); } }, 60000);
  }

  function endDwell() {
    if (!state.dwell) return;
    var it = itemById(state.dwell.id);
    if (it) store.dwell(it, (Date.now() - state.dwell.at) / 1000);
    state.dwell = null;
  }

  function closeWhy() {
    Array.prototype.forEach.call(document.querySelectorAll('.why__pop'), function (p) { p.hidden = true; });
    Array.prototype.forEach.call(document.querySelectorAll('[data-why]'), function (b) { b.setAttribute('aria-expanded', 'false'); });
  }

  function closeSidebar() {
    $('sidebar').classList.remove('is-open');
    $('backdrop').classList.remove('is-open');
  }

  function renderAll() {
    renderNav(); renderTechChips(); renderHealth(); renderMode(); renderLive();
    renderKpis(); renderRail(); renderFeed(); renderMovers(); renderSaved(); renderMix(); renderAdvice(); renderSubtitle();
  }

  // ── public surface (called by main.js and live handlers) ─────────────────

  R.ui = {
    init: function (opts) {
      state.taxonomy = opts && opts.taxonomy ? opts.taxonomy : null;
      state.range = parseInt($('range').value, 10) || 0;
      state.sort = $('sort').value || 'auto';
      bind();
      mountScope(false);
      renderAll();
    },
    onStatus: function (status) {
      state.status = status;
      renderLive();
    },
    onData: function (payload, meta) {
      state.data = payload;
      state.error = null;
      if (meta && meta.previous && meta.newIds) {
        meta.newIds.forEach(function (id) { state.liveNew[id] = true; });
        if (meta.newIds.length) store.markVisit(meta.newIds, true);
      }
      renderAll();
    },
    onNewItems: function (newIds) {
      if (newIds && newIds.length) toast('ok', fmt('newSignals', { n: newIds.length }), t('newSince'));
    },
    afterFirstData: function () {
      // the visit baseline was just written; recompute "new" badges against it
      renderAll();
      if (!store.get('onboarded') && state.taxonomy) openDrawer();
    },
    noData: function (message) {
      state.error = message || 'no data';
      renderAll();
    },
    state: state
  };
})();
