/* main.js — boot: prefs → theme/lang → taxonomy → live data → ui.
   Nothing here decides what a payload means; ui.js does. */

(function () {
  'use strict';

  var R = window.Radar;
  var store = R.store;

  // ?theme=light&lang=ar makes a view linkable and lets a headless render check
  // both themes and both directions. The override is persisted like a click.
  var qs = new URLSearchParams(location.search);
  var qTheme = qs.get('theme'), qLang = qs.get('lang');
  if (qTheme === 'light' || qTheme === 'dark') store.set('theme', qTheme);
  if (qLang === 'ar' || qLang === 'en') store.set('lang', qLang);
  // ?profile=skip suppresses the first-visit drawer — for screenshots and automation.
  if (qs.get('profile') === 'skip') store.set('onboarded', true);

  var prefs = store.prefs();
  document.documentElement.classList.toggle('light', prefs.theme === 'light');
  R.i18n.setLang(prefs.lang);

  function loadTaxonomy() {
    if (window.RADAR_TAXONOMY) return Promise.resolve(window.RADAR_TAXONOMY);
    if (!R.live.isServed) return Promise.resolve(null);
    return fetch('../config/taxonomy.json', { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  loadTaxonomy().then(function (taxonomy) {
    R.ui.init({ taxonomy: taxonomy });

    var first = true;
    R.live.start({
      onStatus: function (status) { R.ui.onStatus(status); },
      onData: function (payload, meta) {
        R.ui.onData(payload, meta);
        if (first) {
          first = false;
          // One baseline per page load: everything on screen now is "seen";
          // what arrives later (live merges) is appended, never rotated.
          store.markVisit(payload.items.map(function (i) { return i.id; }));
          R.ui.afterFirstData();
        }
      },
      onNewItems: function (newIds, payload) { R.ui.onNewItems(newIds, payload); }
    }).catch(function (e) {
      // A fresh checkout before the first sync, or a server that is not running.
      R.ui.noData(e && e.message ? e.message : String(e));
    });
  });
})();
