/* icons.js — JBelly Radar inline icon set.
   Lucide-style: 24 viewBox, stroke 2, currentColor, so an icon inherits the
   colour of its text and needs no token of its own. v1 ICON map moved here
   unchanged; v2 names added below it. */

(function () {
  'use strict';

  var open = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';

  var icons = {
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
    ok:         '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="m8.5 12.5 2.5 2.5 4.5-5"/></svg>',

    // v2
    release:        open + '<path d="M12 3v11"/><path d="m8 10 4 4 4-4"/><path d="M4 17v2a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-2"/></svg>',
    bookmark:       open + '<path d="M6 4h12v17l-6-4-6 4Z"/></svg>',
    bookmarkFilled: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4h12v17l-6-4-6 4Z"/></svg>',
    eyeOff:         open + '<path d="M3 3l18 18"/><path d="M10.6 5.2A10 10 0 0 1 12 5c5 0 8.5 4 9.6 7a13 13 0 0 1-2.4 3.5"/><path d="M6.6 6.6C4.4 8 3 10 2.4 12c1.1 3 4.6 7 9.6 7 1.6 0 3-.4 4.3-1.1"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg>',
    undo:           open + '<path d="M4 8h10a5 5 0 0 1 0 10H9"/><path d="m8 4-4 4 4 4"/></svg>',
    badgeCheck:     open + '<path d="M12 2.5 14.6 4.4l3.2-.3.9 3.1 2.7 1.8-1.3 3 1.3 3-2.7 1.8-.9 3.1-3.2-.3L12 21.5l-2.6-1.9-3.2.3-.9-3.1L2.6 15l1.3-3-1.3-3 2.7-1.8.9-3.1 3.2.3Z"/><path d="m8.5 12 2.5 2.5 4.5-5"/></svg>',
    building:       open + '<rect x="4" y="3" width="16" height="18" rx="1"/><path d="M9 21v-4h6v4"/><path d="M8 7h2M14 7h2M8 11h2M14 11h2M8 15h2M14 15h2"/></svg>',
    radar:          open + '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5"/><path d="M12 12 18.4 5.6"/><path d="M12 12v.01"/></svg>',
    filter:         open + '<path d="M3 5h18l-7 8v6l-4 2v-8Z"/></svg>',
    x:              open + '<path d="M6 6l12 12M18 6 6 18"/></svg>',
    info:           open + '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.5v.01"/></svg>',
    chevronDown:    open + '<path d="m6 9 6 6 6-6"/></svg>',
    tag:            open + '<path d="M3 3h8l10 10-8 8L3 11Z"/><path d="M7.5 7.5v.01"/></svg>',
    briefcase:      open + '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M3 13h18"/></svg>'
  };

  // Same glyph as `link`; the v2 name reads better at call sites.
  icons.externalLink = icons.link;

  window.Radar = window.Radar || {};
  window.Radar.icons = icons;
})();
