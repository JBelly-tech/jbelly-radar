/* rank.js — personal score (Radar.rank).
   Pure: no DOM, no clock, no randomness, no storage. ui.js decides what to
   hide and how to word the "why"; this file only says how much and why.
   Contract: docs/ARCHITECTURE.md → Ranking → Client — personal score. */

(function () {
  'use strict';

  var Radar = window.Radar = window.Radar || {};

  // Weights sum to 1 without explore, so a perfect item lands at 1.04 and is
  // clamped — the bonus is meant to reorder near-ties, not to dominate.
  var W = { heat: 0.45, reputation: 0.20, relevance: 0.20, affinity: 0.15 };
  var EXPLORE = 0.04;
  var TIER = { 1: 1, 2: 0.75, 3: 0.5 };
  var VERIFIED_ONLY = 0.35;

  // A source affinity below one full "open" is too faint to claim the user
  // goes there often, so the tooltip stays quiet until then.
  var SOURCE_WHY_MIN = 1;

  function list(x) { return Array.isArray(x) ? x : []; }
  function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

  function heatOf(item) {
    var h = Number(item.heat);
    return isFinite(h) ? clamp01(h / 100) : 0;
  }

  function reputationOf(item) {
    var p = item && item.publisher;
    if (!p || typeof p !== 'object') return 0;
    var tier = TIER[Number(p.tier)];
    if (tier != null) return tier;
    return p.verified ? VERIFIED_ONLY : 0;
  }

  // Profile → { tag: weight }. First-listed tags weigh more (1/(1+i)); a tag
  // reachable from several places keeps its strongest weight, never the sum,
  // so picking a vertical does not double-count a chip the user also chose.
  function profileWeights(profile, taxonomy) {
    var out = {};
    var add = function (tag, i) {
      if (!tag) return;
      var w = 1 / (1 + i);
      if (out[tag] == null || out[tag] < w) out[tag] = w;
    };
    list(profile && profile.tech).forEach(add);

    var chosen = list(profile && profile.verticals);
    var verticals = list(taxonomy && taxonomy.verticals);
    verticals.forEach(function (v) {
      if (!v || chosen.indexOf(v.id) === -1) return;
      list(v.technologies_that_matter).forEach(function (m, i) { add(m && m.tag, i); });
    });
    return out;
  }

  function relevanceOf(tech, weights) {
    var total = 0, hit = 0, matched = [];
    Object.keys(weights).forEach(function (tag) {
      total += weights[tag];
      if (tech.indexOf(tag) !== -1) { hit += weights[tag]; matched.push(tag); }
    });
    matched.sort(function (a, b) { return weights[b] - weights[a]; });
    return { value: total > 0 ? hit / total : 0, matched: matched, empty: total === 0 };
  }

  function affinityOf(item, aff) {
    var tagAff = (aff && aff.tag) || {};
    var srcAff = (aff && aff.source) || {};
    var seen = {};
    var sum = 0;
    // tech and tags overlap on purpose in the data; count each key once.
    list(item.tech).concat(list(item.tags)).forEach(function (k) {
      if (seen[k]) return;
      seen[k] = true;
      var v = Number(tagAff[k]);
      if (isFinite(v)) sum += v;
    });
    var src = Number(srcAff[item.sourceId]);
    if (isFinite(src)) sum += src;
    return { value: 0.5 + Math.tanh(sum / 3) / 2, source: isFinite(src) ? src : 0 };
  }

  // "New area": the user has never touched any of the item's technologies.
  // An untagged item is not an area, so it earns nothing.
  function isUnexplored(tech, aff) {
    var tagAff = (aff && aff.tag) || {};
    if (!tech.length) return false;
    for (var i = 0; i < tech.length; i++) {
      if (Object.prototype.hasOwnProperty.call(tagAff, tech[i])) return false;
    }
    return true;
  }

  function score(item, ctx) {
    item = item || {};
    ctx = ctx || {};
    var profile = ctx.profile || {};
    var tech = list(item.tech);

    var heat = heatOf(item);
    var reputation = reputationOf(item);
    var weights = profileWeights(profile, ctx.taxonomy);
    var rel = relevanceOf(tech, weights);
    var aff = affinityOf(item, ctx.affinity);
    // Contract: the bonus depends only on interaction history, not on the profile.
    var explore = isUnexplored(tech, ctx.affinity) ? EXPLORE : 0;

    var parts = { heat: heat, reputation: reputation, relevance: rel.value, affinity: aff.value, explore: explore };

    if (ctx.mode === 'all') return { score: heat, parts: parts, why: [] };

    var value = W.heat * heat + W.reputation * reputation + W.affinity * aff.value;
    if (rel.empty) {
      // No profile: drop the relevance term and rescale, so nobody is
      // penalised 0.20 for not having filled in their interests.
      value = value / (1 - W.relevance);
    } else {
      value += W.relevance * rel.value;
    }
    value += explore;

    var why = [];
    if (reputation > 0) {
      why.push({ key: 'publisher', value: item.publisher.name || item.publisher.key || '', tier: TIER[Number(item.publisher.tier)] != null ? Number(item.publisher.tier) : null });
    }
    if (rel.matched.length) why.push({ key: 'matches', value: rel.matched });
    if (aff.source >= SOURCE_WHY_MIN) why.push({ key: 'source-affinity', value: item.sourceLabel || item.sourceId || '' });
    if (explore > 0) why.push({ key: 'explore' });

    return { score: clamp01(value), parts: parts, why: why };
  }

  function order(items, ctx) {
    var rows = list(items).map(function (it, i) {
      var s = score(it, ctx);
      return { item: it, score: s.score, heat: it && isFinite(Number(it.heat)) ? Number(it.heat) : 0, age: it && it.ageDays != null ? Number(it.ageDays) : Infinity, i: i };
    });
    rows.sort(function (a, b) {
      return (b.score - a.score) || (b.heat - a.heat) || (a.age - b.age) || (a.i - b.i);
    });
    return rows.map(function (r) { return r.item; });
  }

  Radar.rank = { score: score, order: order, reputationOf: reputationOf };
})();
