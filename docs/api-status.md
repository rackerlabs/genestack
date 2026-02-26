<meta http-equiv="refresh" content="420">
<div id="rax-flex-banner"></div>

<script>
(function () {
  // raw.githubusercontent.com serves the actual file content with CORS open
  var JSON_URL = 'https://raw.githubusercontent.com/rackerlabs/genestack/master/docs/flex-status.json';

  var STATUS_STYLE = {
    operational: { bg: '#2e7d32', border: '#69f0ae', label: '✅ Operational'              },
    maintenance: { bg: '#1a237e', border: '#448aff', label: '🔧 Maintenance In Progress'  },
    degraded:    { bg: '#e65100', border: '#ff9100', label: '🟠 Degraded Performance'      },
    outage:      { bg: '#7f0000', border: '#ff1744', label: '🔴 Active Outage'             },
  };
  var DEFAULT_STYLE = { bg: '#b71c1c', border: '#ff5252', label: '⚠️ Active Event' };

  function getStyle(event) {
    // Use current_status to pick the colour, fall back to default
    var key = (event.current_status || '').toLowerCase();
    return STATUS_STYLE[key] || DEFAULT_STYLE;
  }

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

    if (detail.length > 400) detail = detail.slice(0, 397) + '…';

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
        (end   ? ' &nbsp;·&nbsp; End: ' + end : '') +
      '</div>' +
      (detail ? '<div style="margin-top:10px;font-size:0.9em;background:rgba(0,0,0,0.2);padding:8px 12px;border-radius:4px;">' + detail + '</div>' : '') +
      '<div style="margin-top:12px;font-size:0.82em;">' +
        '<a href="' + link + '" target="_blank" rel="noopener" style="color:#fff;opacity:0.85;text-decoration:underline;">' +
          'View full details on Rackspace Status →' +
        '</a>' +
      '</div>' +
    '</div>';
  }

  fetch(JSON_URL + '?_=' + Date.now())
    .then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    })
    .then(function (data) {
      var banner = document.getElementById('rax-flex-banner');
      if (!banner) return;
      if (data.active_event) {
        banner.innerHTML = buildBanner(data.active_event, data.current_status);
      }
    })
    .catch(function (e) {
      console.warn('[rax-status] Could not load status:', e);
    });
})();
</script>

# Rackspace OpenStack Flex

Clouds Without Borders. Rackspace OpenStack Private Goes __Public__.

## Power Innovation Worldwide with One OpenStack Platform

![Rackspace OpenStack Software](assets/images/cloud-anywhere.png){ align=left : style="width:100%;max-width:500px" }

The ability to scale across geographies, meet strict data sovereignty requirements, and maintain rigorous security
is paramount. With Rackspace, you can tap into any of our available regions, all running on a unified OpenStack
platform—so you stay agile, compliant, and equipped to evolve in a fast-paced world.

And it doesn’t stop there. Our incredible team of experts is committed to delivering Fanatical support every step
of the way, ensuring you have the guidance and confidence to take your technology stack further than ever before.

[Create a new account](https://cart.rackspace.com/cloud) or [reach out](https://www.rackspace.com/cloud/openstack/private).
When you’re ready to shape the future of your organization, we’ll be here, ready to help you build an extraordinary
platform on our open ecosystem.

<br clear="left">

## Rackspace Solutions

<div class="grid cards" markdown>

- :material-ab-testing:{ .lg } __Game Changing Solutions__

    Tap into unprecedented scalability expertise, including over one billion server hours managing
    and scaling OpenStack clouds for many of the world’s largest and most recognized companies.

- :material-account-wrench:{ .xl .middle } - __A Partner in your Success__

    Rackspace solutions deliver the capability, scalability and reliability of an enterprise-grade
    cloud platform at a fraction of the cost, enabling you to focus on innovation rather than
    infrastructure.

- :material-amplifier:{ .xl .middle } __Rackspace Cloud Solutions__

    Grow profitably with predictable cloud costs

- :material-api:{ .lg } __Simple Solutions__

    At Rackspace, our industry-leading performance drives up your ROI.

</div>
