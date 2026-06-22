(function () {
  var JSON_URL = 'https://raw.githubusercontent.com/rackerlabs/genestack/main/docs/flex-status.json';

  var STATUS_STYLE = {
    operational: { bg: '#2e7d32', border: '#69f0ae', label: '✅ Operational'             },
    maintenance: { bg: '#1a237e', border: '#448aff', label: '🔧 Maintenance In Progress' },
    degraded:    { bg: '#e65100', border: '#ff9100', label: '🟠 Degraded Performance'     },
    outage:      { bg: '#7f0000', border: '#ff1744', label: '🔴 Active Outage'            },
  };
  var DEFAULT_STYLE = { bg: '#b71c1c', border: '#ff5252', label: '⚠️ Active Event' };

  function esc(s) {
    return String(s || '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function buildBanner(event, currentStatus) {
    var s      = STATUS_STYLE[(currentStatus && currentStatus.status) || ''] || DEFAULT_STYLE;
    var title  = esc(event.title   || 'OpenStack Flex Event');
    var detail = esc(event.details || '');
    var start  = esc(event.begin_display || event.begin_value || '');
    var end    = esc(event.end_display   || event.end_value   || '');
    var link   = esc(event.link || 'https://rackspace.service-now.com/system_status?id=service_status&service=85be01de87aaee104b7afc45dabb35b8');

    if (detail.length > 400) detail = detail.slice(0, 397) + '\u2026';

    return '<div style="' +
        'background:' + s.bg + ';color:#fff;' +
        'border-left:5px solid ' + s.border + ';' +
        'padding:14px 18px;border-radius:0 6px 6px 0;' +
        'margin-bottom:20px;font-family:inherit;">' +
      '<div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:6px;">' +
        '<strong style="font-size:1.05em;">' + s.label + ' — OpenStack Flex</strong>' +
      '</div>' +
      '<div style="margin-top:8px;font-size:1em;font-weight:600;">' + title + '</div>' +
      '<div style="margin-top:4px;font-size:0.82em;opacity:0.85;">' +
        (start ? 'Start: ' + start : '') +
        (end   ? ' &nbsp;&middot;&nbsp; End: ' + end : '') +
      '</div>' +
      (detail ? '<div style="margin-top:10px;font-size:0.9em;background:rgba(0,0,0,0.2);padding:8px 12px;border-radius:4px;">' + detail + '</div>' : '') +
      '<div style="margin-top:12px;font-size:0.82em;">' +
        '<a href="' + link + '" target="_blank" rel="noopener" style="color:#fff;opacity:0.85;text-decoration:underline;">' +
          'View full details on Rackspace Status \u2192' +
        '</a>' +
      '</div>' +
    '</div>';
  }

  function injectBanner(event, currentStatus) {
    var wrapper = document.createElement('div');
    wrapper.id = 'rax-flex-banner';
    wrapper.innerHTML = buildBanner(event, currentStatus);

    // MkDocs Material — insert before the article/content area
    var target =
      document.querySelector('article.md-content__inner') ||
      document.querySelector('.md-content__inner') ||
      document.querySelector('article') ||
      document.querySelector('.md-content') ||
      document.querySelector('main');

    if (target) {
      target.insertAdjacentElement('afterbegin', wrapper);
    }
  }

  function loadBanner() {
    // Avoid injecting twice on pages that already have the div
    if (document.getElementById('rax-flex-banner')) return;

    fetch(JSON_URL + '?_=' + Date.now())
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        if (data.active_event) {
          injectBanner(data.active_event, data.current_status);
        }
      })
      .catch(function (e) {
        console.warn('[rax-status] Could not load status:', e);
      });
  }

  // MkDocs Material uses instant navigation (SPA-style) —
  // re-run on every page transition, not just initial load
  if (typeof document$ !== 'undefined') {
    document$.subscribe(loadBanner);
  } else {
    document.addEventListener('DOMContentLoaded', loadBanner);
  }

})();
