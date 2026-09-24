/* i18n.js — JBelly Radar dictionaries and language switch.
   Extracted from v1 app.js unchanged, plus the v2 keys. Attaches to
   window.Radar.i18n only; the DOM is touched by setLang(), never at load. */

(function () {
  'use strict';

  var dict = {
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
      // v1's toast text lives under a new name: `syncing` is now the live progress line.
      syncingSources: 'Syncing sources…', syncedT: 'Sync complete', syncedB: '{n} signals from {s} sources',
      failT: 'Sync failed', copied: 'Install command copied', noMovers: 'Momentum appears once two syncs are at least 12 hours apart.',
      cDay: 'per day, 7d', cHeat: 'heat spread',
      ago: { m: 'm ago', h: 'h ago', d: 'd ago' }, generated: 'last sync', never: 'never synced',

      // v2
      forYou: 'For you', everything: 'Everything', notable: 'From notable organisations',
      tier1: 'Tier 1', tier2: 'Tier 2', tier3: 'Notable', verified: 'Verified org',
      newSince: 'New since your last visit', saved: 'Saved', save: 'Save', unsave: 'Unsave',
      hide: 'Not interested', undo: 'Undo', whyRanked: 'Why this is here',
      matches: 'matches {list}', sourceAffinity: 'you open {source} often', explore: 'new area for you',
      profileTitle: 'Tune your radar', profileBusiness: 'Your business', profileTech: 'Technologies you follow',
      profileOrgs: 'Only notable organisations', profileSave: 'Apply', profileSkip: 'Skip for now',
      scope: 'Radar scope', scopeShowing: 'showing {n} of {total}',
      syncing: 'Syncing {done} of {total} — {current}', newSignals: '{n} new signals', live: 'live',
      offline: 'server unreachable — showing cached data', advice: 'Why it matters for {vertical}',
      release: 'Releases', tech: 'Technology', allTech: 'All technologies', openMenu: 'Open menu', closeMenu: 'Close menu', close: 'Close', switchLang: 'Switch language', switchTheme: 'Switch theme', timeRange: 'Time range', sortBy: 'Sort by', categories: 'Categories', techFilters: 'Technology filters', feedMode: 'Feed mode', summary: 'Summary', openLink: 'Open link', copyInstall: 'Copy install command', newBadge: 'new', srcBadge: 'src', heat: 'heat', 'st-failed': 'failed', 'st-stale': 'stale', 'st-empty': 'empty', 'st-disabled': 'off'
    },
    ar: {
      skip: 'تخطَّ إلى النتائج', tagline: 'رادار الترندات', signals: 'الإشارات', sourceHealth: 'حالة المصادر',
      searchLabel: 'بحث في الإشارات', searchPh: 'ابحث بالعنوان أو المصدر أو الوسم…', refresh: 'تحديث',
      title: 'رادار الترندات', feed: 'الإشارات', movers: 'الأكثر صعودًا', weekly: 'أسبوعي', mix: 'توزيع الإشارات',
      r24: 'آخر ٢٤ ساعة', r7: 'آخر ٧ أيام', r30: 'آخر ٣٠ يوم', rAll: 'كل الفترات',
      sHeat: 'ترتيب: الحرارة', sNew: 'ترتيب: الأحدث', sMom: 'ترتيب: الزخم', sMetric: 'ترتيب: الشعبية',
      all: 'الكل', skill: 'سكيلز', repo: 'مستودعات', news: 'أخبار', discussion: 'نقاشات', research: 'أبحاث',
      kTotal: 'إشارات مرصودة', kHot: 'ساخن الآن', kFresh: 'جديد خلال ٢٤ ساعة', kSources: 'مصادر شغّالة',
      emptyTitle: 'ما في نتائج مطابقة', emptyText: 'وسّع الفترة الزمنية أو امسح البحث. البيانات سليمة — هاي فلترة مش عطل.',
      clear: 'مسح الفلاتر', errTitle: 'ما في بيانات بعد', errText: 'شغّل مزامنة لتعبئة الرادار. من مجلد المشروع: powershell -File scripts\\sync.ps1',
      syncingSources: 'عم يزامن المصادر…', syncedT: 'خلص التزامن', syncedB: '{n} إشارة من {s} مصدر',
      failT: 'فشل التزامن', copied: 'تم نسخ أمر التنصيب', noMovers: 'الزخم بيظهر لما يصير بين مزامنتين ١٢ ساعة عالأقل.',
      cDay: 'يوميًا، ٧ أيام', cHeat: 'توزّع الحرارة',
      ago: { m: ' د', h: ' س', d: ' ي' }, generated: 'آخر تزامن', never: 'ما تزامن بعد',

      // v2
      forYou: 'إلك', everything: 'الكل', notable: 'من شركات معروفة',
      tier1: 'الفئة الأولى', tier2: 'الفئة الثانية', tier3: 'معروف', verified: 'منظمة موثّقة',
      newSince: 'جديد من آخر زيارة', saved: 'المحفوظ', save: 'احفظ', unsave: 'شيل من المحفوظ',
      hide: 'ما بهمّني', undo: 'تراجع', whyRanked: 'ليش هون',
      matches: 'بيطابق {list}', sourceAffinity: 'بتفتح {source} كتير', explore: 'مجال جديد إلك',
      profileTitle: 'ظبّط رادارك', profileBusiness: 'شغلك', profileTech: 'التقنيات اللي بتتابعها',
      profileOrgs: 'بس الشركات المعروفة', profileSave: 'طبّق', profileSkip: 'بعدين',
      scope: 'شاشة الرادار', scopeShowing: 'معروض {n} من {total}',
      syncing: 'عم يزامن {done} من {total} — {current}', newSignals: '{n} إشارة جديدة', live: 'مباشر',
      offline: 'السيرفر مش موصول — معروض آخر نسخة', advice: 'ليش بيهمّ {vertical}',
      release: 'إصدارات', tech: 'التقنية', allTech: 'كل التقنيات', openMenu: 'افتح القائمة', closeMenu: 'سكّر القائمة', close: 'إغلاق', switchLang: 'غيّر اللغة', switchTheme: 'غيّر المظهر', timeRange: 'الفترة الزمنية', sortBy: 'الترتيب', categories: 'الفئات', techFilters: 'فلاتر التقنية', feedMode: 'وضع العرض', summary: 'الملخّص', openLink: 'افتح الرابط', copyInstall: 'انسخ أمر التنصيب', newBadge: 'جديد', srcBadge: 'مصدر', heat: 'حرارة', 'st-failed': 'فشل', 'st-stale': 'قديم', 'st-empty': 'فاضي', 'st-disabled': 'مطفي'
    }
  };

  var KEY = 'radar.lang';

  // Own-property lookup only: 'constructor', 'toString', '__proto__' … are
  // neither languages nor keys, but a plain `obj[k]` finds them on the prototype.
  function has(obj, k) { return Object.prototype.hasOwnProperty.call(obj, k); }

  function stored() {
    // Storage may be disabled or throw in private mode: default to English.
    try { var v = localStorage.getItem(KEY); return v === 'ar' || v === 'en' ? v : 'en'; }
    catch (e) { return 'en'; }
  }

  var i18n = {
    dict: dict,
    lang: stored(),

    t: function (key) {
      var d = has(dict, i18n.lang) ? dict[i18n.lang] : dict.en;
      return (has(d, key) && d[key]) || (has(dict.en, key) && dict.en[key]) || key;
    },

    // Replaces {name} tokens; a token with no matching var is left in place so
    // a missing value is visible rather than silently blank.
    format: function (key, vars) {
      var s = i18n.t(key);
      if (typeof s !== 'string') return s;
      return s.replace(/\{(\w+)\}/g, function (m, name) {
        return vars && vars[name] != null ? String(vars[name]) : m;
      });
    },

    setLang: function (lang) {
      i18n.lang = has(dict, lang) ? lang : 'en';
      var html = document.documentElement;
      html.lang = i18n.lang;
      html.dir = i18n.lang === 'ar' ? 'rtl' : 'ltr';
      document.querySelectorAll('[data-i18n]').forEach(function (el) { el.textContent = i18n.t(el.getAttribute('data-i18n')); });
      document.querySelectorAll('[data-i18n-ph]').forEach(function (el) { el.placeholder = i18n.t(el.getAttribute('data-i18n-ph')); });
      Array.prototype.forEach.call(document.querySelectorAll('[data-i18n-aria]'), function (el) { el.setAttribute('aria-label', i18n.t(el.getAttribute('data-i18n-aria'))); });
      try { localStorage.setItem(KEY, i18n.lang); } catch (e) { /* preference is per-session then */ }
      return i18n.lang;
    }
  };

  window.Radar = window.Radar || {};
  window.Radar.i18n = i18n;
})();
