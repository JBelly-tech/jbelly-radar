/* app.js — JBelly Radar dashboard.
   Reads data/trends.json (served) or window.RADAR_DATA (file://). Renders,
   filters and sorts client-side; the ranking itself is computed by the sync,
   so the page never has to be trusted with it. */

(function () {
  'use strict';

  var ICON = {
    all:        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.2"/></svg>',
    skill:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="m12 3 2.5 5.5L20 11l-5.5 2.5L12 19l-2.5-5.5L4 11l5.5-2.5Z"/></svg>',
    repo:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v16H6.5A2.5 2.5 0 0 0 4 20.5Z"/><path d="M4 17.5h16"/></svg>',
    news:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 5h13v14H5a1 1 0 0 1-1-1Z"/><path d="M17 8h3v9a2 2 0 0 1-3 1.7"/><path d="M7 9h7M7 13h7"/></svg>',
    discussion: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12Z"/></svg>',
    research:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 3v6l-5 8a2 2 0 0 0 1.7 3h12.6a2 2 0 0 0 1.7-3l-5-8V3"/><path d="M8 3h8M7.5 14h9"/></svg>',
    up:         '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 15l6-6 6 6"/></svg>',
    down:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>',
    link:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>',
    copy:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/></svg>',
    empty:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
    error:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16.5v.01"/></svg>',
    ok:         '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="m8.5 12.5 2.5 2.5 4.5-5"/></svg>'
  };

  var I18N = {
    en: {
      skip: 'Skip to results', tagline: 'trend radar', signals: 'Signals', sourceHealth: 'Source health',
      searchLabel: 'Search signals', searchPh: 'Search title, source, tag…', refresh: 'Refresh',
      title: 'Trend radar', feed: 'Signals', movers: 'Top movers', weekly: 'weekly', mix: 'Signal mix',
      r24: 'Last 24 hours', r7: 'Last 7 days', r30: 'Last 30 days', rAll: 'All time',
      sHeat: 'Sort: heat', sNew: 'Sort: newest', sMom: 'Sort: momentum', sMetric: 'Sort: popularity',
      all: 'Everything', skill: 'Skills', repo: 'Repositories', news: 'News', discussion: 'Discussion', research: 'Research',
      kTotal: 'Signals tracked', kHot: 'Hot right now', kFresh: 'New in 24h', kSources: 'Sources live',
      emptyTitle: 'Nothing matches', emptyText: 'Widen the time range or clear the search. The data itself is fine — this is a filter, not a failure.',
      clear: 'Clear filters', errTitle: 'No data yet', errText: 'Run a sync to fill the radar. From the project folder: powershell -File scripts\\sync.ps1',
      syncing: 'Syncing sources…', syncedT: 'Sync complete', syncedB: '{n} signals from {s} sources',
      failT: 'Sync failed', copied: 'Install command copied', noMovers: 'Momentum appears once two syncs are at least 12 hours apart.',
      cDay: 'per day, 7d', cHeat: 'heat spread',
      ago: { m: 'm ago', h: 'h ago', d: 'd ago' }, generated: 'last sync', never: 'never synced'
    },
    ar: {
      skip: 'تخطَّ إلى النتائج', tagline: 'رادار الترندات', signals: 'الإشارات', sourceHealth: 'حالة المصادر',
      searchLabel: 'بحث في الإشارات', searchPh: 'ابحث بالعنوان أو المصدر أو الوسم…', refresh: 'تحديث',
      title: 'رادار الترندات', feed: 'الإشارات', movers: 'الأكثر صعوداً', weekly: 'أسبوعي', mix: 'توزيع الإشارات',
      r24: 'آخر ٢٤ ساعة', r7: 'آخر ٧ أيام', r30: 'آخر ٣٠ يوم', rAll: 'كل الفترات',
      sHeat: 'ترتيب: الحرارة', sNew: 'ترتيب: الأحدث', sMom: 'ترتيب: الاندفاع', sMetric: 'ترتيب: الشعبية',
      all: 'الكل', skill: 'سكيلز', repo: 'مستودعات', news: 'أخبار', discussion: 'نقاشات', research: 'أبحاث',
      kTotal: 'إشارات مرصودة', kHot: 'ساخن الآن', kFresh: 'جديد خلال ٢٤ ساعة', kSources: 'مصادر شغّالة',
      emptyTitle: 'ما في نتائج مطابقة', emptyText: 'وسّع الفترة الزمنية أو امسح البحث. البيانات سليمة — هاي فلترة مش عطل.',
      clear: 'مسح الفلاتر', errTitle: 'ما في بيانات بعد', errText: 'شغّل سيرك لتعبئة الرادار. من مجلد المشروع: powershell -File scripts\\sync.ps1',
      syncing: 'عم يزامن المصادر…', syncedT: 'خلص التزامن', syncedB: '{n} إشارة من {s} مصدر',
      failT: 'فشل التزامن', copied: 'تم نسخ أمر التنصيب', noMovers: 'الاندفاع بيظهر لما يصير بين سيركين ١٢ ساعة عالأقل.',
      cDay: 'يومياً، ٧ أيام', cHeat: 'توزّع الحرارة',
      ago: { m: ' د', h: ' س', d: ' ي' }, generated: 'آخر تزامن', never: 'ما تزامن بعد'
    }
  };

  var CATS = ['all', 'skill', 'repo', 'news', 'discussion', 'research'];

  var state = {
    data: null,
    cat: 'all',
    q: '',
    range: 30,
    sort: 'heat',
    lang: localStorage.getItem('radar.lang') || 'en',
    theme: localStorage.getItem('radar.theme') || 'dark',
    busy: false,
    error: null
  };

  var $ = function (id) { return document.getElementById(id); };
  var t = function (k) { return (I18N[state.lang] && I18N[state.lang][k]) || I18N.en[k] || k; };

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

  // heat tone: one hue ramp, never a rainbow
  function tone(heat) {
    if (heat >= 75) return 'var(--data-1)';
    if (heat >= 55) return 'var(--data-2)';
    if (heat >= 35) return 'var(--data-3)';
    return 'var(--data-4)';
  }

  function sparkline(values, w, h) {
    var v = (values || []).filter(function (x) { return typeof x === 'number'; });
    if (v.length < 2) return '';
    var min = Math.min.apply(null, v), max = Math.max.apply(null, v);
    var span = (max - min) || 1;
    var step = w / (v.length - 1);
    var pts = v.map(function (y, i) {
      return (i * step).toFixed(1) + ',' + (h - 2 - ((y - min) / span) * (h - 4)).toFixed(1);
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
    return '<span class="badge ' + cls + '">' + (up ? ICON.up : ICON.down) + (up ? '+' : '') + m.toFixed(0) + '%</span>';
  }

  // ── filtering ──────────────────────────────────────────────────────────────

  function visible() {
    if (!state.data) return [];
    var q = state.q.trim().toLowerCase();
    var out = state.data.items.filter(function (it) {
      if (state.cat !== 'all' && it.category !== state.cat) return false;
      if (state.range > 0 && it.ageDays != null && it.ageDays > state.range) return false;
      if (q) {
        var hay = (it.title + ' ' + it.summary + ' ' + it.sourceLabel + ' ' + it.author + ' ' + (it.tags || []).join(' ')).toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });
    var by = {
      heat: function (a, b) { return b.heat - a.heat; },
      new: function (a, b) { return (a.ageDays == null ? 1e9 : a.ageDays) - (b.ageDays == null ? 1e9 : b.ageDays); },
      momentum: function (a, b) { return (b.momentum == null ? -1e9 : b.momentum) - (a.momentum == null ? -1e9 : a.momentum); },
      metric: function (a, b) { return (b.metric || 0) - (a.metric || 0); }
    };
    return out.sort(by[state.sort] || by.heat);
  }

  // ── rendering ──────────────────────────────────────────────────────────────

  function renderNav() {
    var counts = { all: 0 };
    if (state.data) {
      counts.all = state.data.items.length;
      state.data.items.forEach(function (it) { counts[it.category] = (counts[it.category] || 0) + 1; });
    }
    $('catNav').innerHTML = CATS.map(function (c) {
      return '<button class="nav__item" type="button" data-cat="' + c + '" aria-current="' + (state.cat === c) + '">' +
        ICON[c] + '<span>' + esc(t(c)) + '</span><span class="nav__count">' + (counts[c] || 0) + '</span></button>';
    }).join('');
  }

  function renderHealth() {
    var el = $('healthList');
    if (!state.data) { el.innerHTML = ''; return; }
    el.innerHTML = state.data.sources.map(function (s) {
      var title = s.status === 'failed' ? s.message : s.status + ' · ' + s.ms + 'ms';
      return '<div class="health__row" title="' + esc(title) + '">' +
        '<span class="health__dot health__dot--' + esc(s.status) + '"></span>' +
        '<span class="health__name">' + esc(s.label) + '</span>' +
        '<span class="health__n">' + (s.status === 'failed' ? '!' : s.count) + '</span></div>';
    }).join('');
  }

  function renderKpis() {
    var d = state.data;
    if (!d) { $('kpis').innerHTML = ''; return; }
    var items = d.items;
    var hot = items.filter(function (i) { return i.heat >= 70; });
    var fresh = items.filter(function (i) { return i.ageDays != null && i.ageDays <= 1; });
    var live = d.sources.filter(function (s) { return s.status === 'ok'; }).length;
    var failed = d.sources.filter(function (s) { return s.status === 'failed'; }).length;

    // Both sparklines carry a real distribution and say which one, so neither is
    // decoration: publication volume per day, and how heat is spread.
    var perDay = [0, 0, 0, 0, 0, 0, 0];
    items.forEach(function (i) {
      if (i.ageDays == null || i.ageDays >= 7) return;
      perDay[6 - Math.floor(i.ageDays)]++;
    });
    var buckets = [0, 0, 0, 0, 0];
    items.forEach(function (i) { buckets[Math.min(4, Math.floor(i.heat / 20))]++; });

    var cards = [
      { label: t('kTotal'), value: items.length, spark: perDay, cap: t('cDay'), badge: '<span class="badge badge--outline">' + d.sources.length + ' src</span>' },
      { label: t('kHot'), value: hot.length, spark: buckets, cap: t('cHeat'), badge: '<span class="badge badge--primary">heat 70+</span>' },
      { label: t('kFresh'), value: fresh.length, spark: null, badge: '<span class="badge badge--info">24h</span>' },
      {
        label: t('kSources'), value: live + '/' + d.sources.length, spark: null,
        badge: failed ? '<span class="badge badge--destructive">' + ICON.error + failed + '</span>'
                      : '<span class="badge badge--success">' + ICON.ok + 'ok</span>'
      }
    ];

    $('kpis').innerHTML = cards.map(function (c) {
      return '<section class="card"><div class="kpi">' +
        '<div class="kpi__top"><span class="kpi__label">' + esc(c.label) + '</span>' + c.badge + '</div>' +
        '<div class="kpi__value">' + esc(c.value) + '</div>' +
        (c.spark ? '<div class="kpi__foot"><div class="kpi__spark">' + sparkline(c.spark, 100, 28) + '</div><span class="kpi__cap">' + esc(c.cap) + '</span></div>' : '') +
        '</div></section>';
    }).join('');
  }

  function renderFeed() {
    var el = $('feed');

    if (state.busy) {
      el.innerHTML = new Array(5).join('x').split('x').map(function () {
        return '<div class="skel-row"><div class="skeleton"></div><div>' +
          '<div class="skeleton" style="height:12px;width:58%"></div>' +
          '<div class="skeleton" style="height:10px;width:82%;margin-top:8px"></div>' +
          '<div class="skeleton" style="height:9px;width:34%;margin-top:8px"></div></div>' +
          '<div class="skeleton" style="height:22px"></div></div>';
      }).join('');
      $('feedCount').textContent = '…';
      return;
    }

    if (state.error) {
      el.innerHTML = '<div class="state"><span class="state__icon state__icon--error">' + ICON.error + '</span>' +
        '<h3>' + esc(t('errTitle')) + '</h3><p>' + esc(state.error) + '</p>' +
        '<button class="btn btn--outline" type="button" data-act="retry">' + esc(t('refresh')) + '</button></div>';
      $('feedCount').textContent = '0';
      return;
    }

    var rows = visible();
    $('feedCount').textContent = rows.length;

    if (!rows.length) {
      el.innerHTML = '<div class="state"><span class="state__icon">' + ICON.empty + '</span>' +
        '<h3>' + esc(t('emptyTitle')) + '</h3><p>' + esc(t('emptyText')) + '</p>' +
        '<button class="btn btn--outline" type="button" data-act="clear">' + esc(t('clear')) + '</button></div>';
      return;
    }

    el.innerHTML = rows.slice(0, 120).map(function (it) {
      var meta = [esc(it.sourceLabel)];
      if (it.ageDays != null) meta.push(esc(ago(it.ageDays)));
      if (it.author && it.category !== 'news') meta.push(esc(it.author));
      var tags = (it.tags || []).slice(0, 3).filter(function (x) { return x && x.length < 22; });

      return '<article class="item">' +
        '<div class="item__heat" title="heat ' + it.heat + '"><i style="--h:' + it.heat + '%;--tone:' + tone(it.heat) + '"></i></div>' +
        '<div class="item__main">' +
          '<h3 class="item__title"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer">' + esc(it.title) + '</a></h3>' +
          (it.summary ? '<p class="item__summary">' + esc(it.summary) + '</p>' : '') +
          '<div class="item__meta">' +
            meta.join('<span class="item__sep">·</span>') +
            (tags.length ? '<span class="item__sep">·</span>' + tags.map(function (x) { return '<span>#' + esc(x) + '</span>'; }).join('') : '') +
          '</div>' +
        '</div>' +
        '<div class="item__side">' +
          (it.metric != null ? '<span class="item__metric">' + num(it.metric) + '<small>' + esc(it.metricLabel) + '</small></span>' : '') +
          momentumBadge(it.momentum) +
          '<div class="item__actions">' +
            (it.install && it.install.indexOf('npx') === 0
              ? '<button class="btn btn--ghost btn--icon" type="button" data-copy="' + esc(it.install) + '" aria-label="Copy install command" title="' + esc(it.install) + '">' + ICON.copy + '</button>'
              : '') +
            '<a class="btn btn--ghost btn--icon" href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" aria-label="Open source">' + ICON.link + '</a>' +
          '</div>' +
        '</div>' +
      '</article>';
    }).join('');
  }

  function renderMovers() {
    var el = $('movers');
    if (!state.data) { el.innerHTML = ''; return; }
    var rows = state.data.items
      .filter(function (i) { return i.momentum != null && i.momentum > 0; })
      .sort(function (a, b) { return b.momentum - a.momentum; })
      .slice(0, 7);

    if (!rows.length) {
      el.innerHTML = '<div class="state" style="padding:32px 20px"><span class="state__icon">' + ICON.empty + '</span>' +
        '<p>' + esc(t('noMovers')) + '</p></div>';
      return;
    }

    el.innerHTML = rows.map(function (it, i) {
      return '<div class="mover">' +
        '<span class="mover__rank">' + (i + 1) + '</span>' +
        '<div class="mover__body">' +
          '<div class="mover__name"><a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer">' + esc(it.title) + '</a></div>' +
          '<div class="mover__sub">' + num(it.metric) + ' ' + esc(it.metricLabel) + ' · ' + esc(it.sourceLabel) + '</div>' +
        '</div>' +
        (it.spark ? '<div class="mover__spark">' + sparkline(it.spark, 56, 20) + '</div>' : '') +
        momentumBadge(it.momentum) +
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
    var hues = ['var(--data-1)', 'var(--data-2)', 'var(--data-3)', 'var(--data-4)'];

    el.innerHTML = rows.map(function (r, i) {
      return '<div><div class="bar__top"><span class="bar__name">' + esc(r.name) + '</span><span class="bar__n">' + r.n + '</span></div>' +
        '<div class="bar__track"><div class="bar__fill" style="width:' + ((r.n / max) * 100).toFixed(1) + '%;--tone:' + hues[i % 4] + '"></div></div></div>';
    }).join('');
  }

  function renderSubtitle() {
    var p = $('subtitle');
    if (!state.data) { p.textContent = t('never'); return; }
    var d = new Date(state.data.generatedAt);
    var mins = Math.max(0, Math.round((Date.now() - d.getTime()) / 60000));
    p.textContent = t('generated') + ' ' + (mins < 1 ? '<1m' : ago(mins / 1440)) +
      ' · ' + state.data.counts.total + ' · ' + state.data.durationMs + 'ms';

    var chip = $('filterChip');
    if (state.cat !== 'all' || state.q) {
      chip.hidden = false;
      chip.textContent = t(state.cat) + (state.q ? ' · "' + state.q + '"' : '');
    } else { chip.hidden = true; }
  }

  function renderAll() {
    renderNav(); renderHealth(); renderKpis(); renderFeed(); renderMovers(); renderMix(); renderSubtitle();
  }

  // ── i18n + theme ───────────────────────────────────────────────────────────

  function applyLang() {
    var html = document.documentElement;
    html.lang = state.lang;
    html.dir = state.lang === 'ar' ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-i18n]').forEach(function (el) { el.textContent = t(el.getAttribute('data-i18n')); });
    document.querySelectorAll('[data-i18n-ph]').forEach(function (el) { el.placeholder = t(el.getAttribute('data-i18n-ph')); });
    $('langBtn').title = state.lang === 'ar' ? 'English' : 'العربية';
    localStorage.setItem('radar.lang', state.lang);
  }

  function applyTheme() {
    document.documentElement.classList.toggle('light', state.theme === 'light');
    localStorage.setItem('radar.theme', state.theme);
  }

  function toast(kind, title, body) {
    var el = document.createElement('div');
    el.className = 'toast toast--' + kind;
    el.innerHTML = (kind === 'err' ? ICON.error : ICON.ok) + '<div><strong>' + esc(title) + '</strong><span>' + esc(body || '') + '</span></div>';
    $('toasts').appendChild(el);
    setTimeout(function () { el.remove(); }, 4200);
  }

  // ── data ───────────────────────────────────────────────────────────────────

  function adopt(payload) {
    state.data = payload;
    state.error = null;
    renderAll();
  }

  function load() {
    return fetch('../data/trends.json?t=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(adopt);
  }

  function sync() {
    if (state.busy) return;
    state.busy = true;
    $('refreshBtn').disabled = true;
    $('refreshBtn').classList.add('is-busy');
    renderFeed();
    toast('ok', t('syncing'), '');

    fetch('../api/sync', { method: 'POST' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (payload) {
        state.busy = false;
        adopt(payload);
        var live = payload.sources.filter(function (s) { return s.status === 'ok'; }).length;
        toast('ok', t('syncedT'), t('syncedB').replace('{n}', payload.counts.total).replace('{s}', live));
      })
      .catch(function (e) {
        state.busy = false;
        // Opened from disk rather than through radar.ps1: no sync endpoint exists.
        toast('err', t('failT'), e.message + ' — run scripts\\sync.ps1');
        renderFeed();
      })
      .then(function () {
        $('refreshBtn').disabled = false;
        $('refreshBtn').classList.remove('is-busy');
      });
  }

  // ── events ─────────────────────────────────────────────────────────────────

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
    $('themeBtn').addEventListener('click', function () { state.theme = state.theme === 'dark' ? 'light' : 'dark'; applyTheme(); });
    $('langBtn').addEventListener('click', function () { state.lang = state.lang === 'ar' ? 'en' : 'ar'; applyLang(); renderAll(); });

    document.addEventListener('click', function (e) {
      var copy = e.target.closest('[data-copy]');
      if (copy) {
        navigator.clipboard.writeText(copy.getAttribute('data-copy')).then(function () { toast('ok', t('copied'), copy.getAttribute('data-copy')); });
        return;
      }
      var act = e.target.closest('[data-act]');
      if (!act) return;
      if (act.getAttribute('data-act') === 'clear') {
        state.q = ''; state.cat = 'all'; state.range = 0;
        $('q').value = ''; $('range').value = '0';
        renderAll();
      }
      if (act.getAttribute('data-act') === 'retry') sync();
    });

    document.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); $('q').focus(); $('q').select(); return; }
      if (e.key === '/' && document.activeElement.tagName !== 'INPUT') { e.preventDefault(); $('q').focus(); return; }
      if (e.key === 'Escape') {
        if (document.activeElement === $('q') && $('q').value) { $('q').value = ''; state.q = ''; renderFeed(); renderSubtitle(); }
        closeSidebar();
        return;
      }
      if (e.key.toLowerCase() === 'r' && !e.ctrlKey && !e.metaKey && document.activeElement.tagName !== 'INPUT') sync();
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
    mq.addEventListener ? mq.addEventListener('change', syncMenuBtn) : mq.addListener(syncMenuBtn);
    syncMenuBtn();
  }

  function closeSidebar() {
    $('sidebar').classList.remove('is-open');
    $('backdrop').classList.remove('is-open');
  }

  // ── boot ───────────────────────────────────────────────────────────────────

  // ?theme=light&lang=ar overrides the stored preference — makes a given view
  // linkable, and lets a headless render check both themes and both directions.
  var qs = new URLSearchParams(location.search);
  if (qs.get('theme') === 'light' || qs.get('theme') === 'dark') state.theme = qs.get('theme');
  if (qs.get('lang') === 'ar' || qs.get('lang') === 'en') state.lang = qs.get('lang');

  applyTheme();
  applyLang();
  bind();

  if (window.RADAR_DATA) { adopt(window.RADAR_DATA); }
  else { state.error = t('errText'); renderAll(); }

  // Served by radar.ps1: prefer the live file, and sync on open when it is stale.
  if (location.protocol.indexOf('http') === 0) {
    load().then(function () {
      var age = (Date.now() - new Date(state.data.generatedAt).getTime()) / 60000;
      if (age > 30) sync();
    }).catch(function () { /* window.RADAR_DATA already rendered */ });
  }
})();
