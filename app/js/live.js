/* live.js — JBelly Radar live layer.
   Owns the conversation with radar.ps1: load data, poll /api/status, reload
   when the data file changes, diff ids so "new since you looked" is exact.
   Never writes DOM; ui.js/main.js decide what a status or a payload means. */

(function () {
  'use strict';

  window.Radar = window.Radar || {};

  // Overridable so the harness can run the whole state machine in milliseconds.
  var intervals = { fast: 1500, idle: 45000, offline: 60000 };

  var handlers = {};
  var timer = null;
  var running = false;
  var session = 0;          // bumped by stop(); async work from an older session is discarded
  var last = null;          // last status object seen (or the synthetic offline one)
  var payload = null;       // last loaded trends.json
  var loadedStamp = null;   // status.dataAt at the moment payload was loaded
  var failures = 0;
  var offline = false;
  var reloading = false;
  // `served` means "an API answers behind this page" -- which is NOT the same
  // as "the protocol is http". A published snapshot (GitHub Pages, or any other
  // static host) is served over http and has no API at all, and without this
  // distinction such a page polls /api/status forever, fails three times, and
  // tells the visitor the server is unreachable. It is not unreachable; it was
  // never there. A static page says so by setting window.RADAR_STATIC before
  // this script runs. file:// needs no flag: it can never be served.
  var served = location.protocol.indexOf('http') === 0 && !window.RADAR_STATIC;

  // Paths are relative to app/ by contract, but the harness loads this file from
  // tests/harness/. Anchoring on the script's own URL (app/js/live.js -> root)
  // gives the same result from both places without a config knob.
  var root = (function () {
    var s = document.currentScript && document.currentScript.src;
    var m = s && /^(.*\/)app\/js\/[^\/]*$/.exec(s);
    return m ? m[1] : '../';
  })();

  function emit(name) {
    var fn = handlers[name];
    if (typeof fn !== 'function') return;
    try { fn.apply(null, Array.prototype.slice.call(arguments, 1)); }
    catch (e) { /* a broken listener must not stop the poll loop */ }
  }

  // Read window.fetch at call time so a test can swap it after load. Wrapped in
  // a promise so a fetch that throws synchronously still surfaces as a rejection.
  function getJson(url, opts) {
    return new Promise(function (resolve) { resolve(window.fetch(url, opts)); })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      });
  }

  function bust(url) { return url + (url.indexOf('?') === -1 ? '?' : '&') + 't=' + Date.now(); }

  function stampOf(status) { return (status && (status.dataAt || status.generatedAt)) || null; }

  function idSet(p) {
    var set = {};
    ((p && p.items) || []).forEach(function (it) { if (it && it.id != null) set[it.id] = true; });
    return set;
  }

  function loadData(stamp) {
    if (reloading) return Promise.resolve(null);
    reloading = true;
    var s = session;
    return getJson(bust(root + 'data/trends.json'), { cache: 'no-store' })
      .then(function (next) {
        if (s !== session) return null;   // stop()/start() happened while the request was in flight
        var prev = payload;
        payload = next;
        loadedStamp = stamp || null;
        var before = idSet(prev);
        var newIds = Object.keys(idSet(next)).filter(function (id) { return !before[id]; });
        emit('onData', next, { previous: prev, newIds: newIds, stamp: loadedStamp });
        if (prev) emit('onNewItems', newIds, next);
        return next;
      })
      .then(function (next) { if (s === session) reloading = false; return next; },
            function (e) { if (s === session) reloading = false; throw e; });
  }

  function clearTimer() {
    if (timer) { clearTimeout(timer); timer = null; }
  }

  function schedule(ms) {
    clearTimer();
    if (!running || document.hidden) return;
    timer = setTimeout(poll, ms);
  }

  // Read through the public object so a test may replace it, not only mutate it.
  function iv() { return window.Radar.live._intervals || intervals; }

  function nextInterval() {
    if (offline) return iv().offline;
    return last && last.state === 'syncing' ? iv().fast : iv().idle;
  }

  function changed(status) {
    var stamp = stampOf(status);
    if (!payload) return true;
    // First status after a load: the payload carries generatedAt but not the
    // file mtime, so compare on generatedAt once, then trust dataAt.
    if (loadedStamp === null) {
      if (status.generatedAt && payload.generatedAt && status.generatedAt !== payload.generatedAt) return true;
      loadedStamp = stamp;
      return false;
    }
    return stamp !== loadedStamp;
  }

  function poll() {
    clearTimer();
    if (!running) return;
    var s = session;
    return getJson(bust(root + 'api/status'), { cache: 'no-store' })
      .then(function (status) {
        if (s !== session) return;
        failures = 0;
        offline = false;      // recovery is silent: the next real status speaks for itself
        last = status;
        emit('onStatus', status);
        var p = changed(status) ? loadData(stampOf(status)).catch(function () { /* next poll retries */ }) : Promise.resolve();
        return p.then(function () { if (s === session) schedule(nextInterval()); });
      })
      .catch(function (e) {
        if (s !== session) return;
        failures += 1;
        if (failures >= 3 && !offline) {
          offline = true;
          last = { state: 'offline', error: e && e.message ? e.message : String(e) };
          emit('onStatus', last);
        }
        schedule(nextInterval());
      });
  }

  function onVisibility() {
    if (!running) return;
    if (document.hidden) clearTimer();
    else poll();
  }

  function start(h) {
    stop();
    handlers = h || {};
    running = true;
    var s = session;
    // A restart is a fresh session: the first payload must not be diffed
    // against whatever an earlier start() had loaded.
    payload = null; loadedStamp = null; last = null;
    failures = 0; offline = false; reloading = false;
    if (!served) {
      // Opened from disk: no API, no polling; the embedded snapshot is all there is.
      if (window.RADAR_DATA) {
        payload = window.RADAR_DATA;
        emit('onData', payload, { previous: null, newIds: [], stamp: null });
      }
      return Promise.resolve(payload);
    }
    document.addEventListener('visibilitychange', onVisibility);
    return loadData(null)
      .then(function (p) { if (s === session) poll(); return p; },
            function (e) { if (s === session) poll(); throw e; });
  }

  function stop() {
    session += 1;
    running = false;
    handlers = {};
    clearTimer();
    document.removeEventListener('visibilitychange', onVisibility);
  }

  function sync() {
    if (!served) return Promise.reject(new Error('Not served: open through radar.ps1 to sync'));
    var s = session;
    return getJson(root + 'api/sync', { method: 'POST', cache: 'no-store' })
      .then(function (res) {
        var status = res && res.status;
        if (status && s === session) {
          last = status;
          emit('onStatus', status);
        }
        // Whether we started it or someone else did, the fast poll shows progress.
        if (running && s === session && (res.started || (status && status.state === 'syncing'))) schedule(iv().fast);
        return { started: !!(res && res.started), status: status || null };
      });
  }

  function status() { return last; }

  window.Radar.live = {
    isServed: served,
    start: start,
    stop: stop,
    sync: sync,
    status: status,
    _intervals: intervals
  };
})();
