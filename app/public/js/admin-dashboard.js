function admSwitchView(mode) {
    var mapEl = document.getElementById('adm-view-map');
    var listEl = document.getElementById('adm-view-list');
    var btnMap = document.getElementById('btn-map');
    var btnList = document.getElementById('btn-list');
    if (!mapEl) return;

    if (mode === 'map') {
        mapEl.style.display = '';
        if (listEl) listEl.style.display = 'none';
        if (btnMap) btnMap.classList.add('active');
        if (btnList) btnList.classList.remove('active');
        if (window._leafletMap) window._leafletMap.invalidateSize();
    } else {
        mapEl.style.display = 'none';
        if (listEl) listEl.style.display = '';
        if (btnMap) btnMap.classList.remove('active');
        if (btnList) btnList.classList.add('active');
    }
}

function admNodeCode(node) {
    var chip = node && node.name
        ? document.querySelector('.node-chip[data-node-name="' + node.name + '"]')
        : null;

    if (chip && chip.dataset.nodeCode) return chip.dataset.nodeCode;

    return ((node && (node.name || node.ip)) || 'NODE')
        .toString()
        .replace(/[^a-z0-9а-яё]+/ig, '-')
        .replace(/^-|-$/g, '') || 'NODE';
}

function admNodeGeo(node, index) {
    var rawText = [
        node && node.name,
        node && node.ip,
        node && node.city,
        node && node.country
    ].join(' ').toLowerCase();
    var tokens = rawText.split(/[^a-zа-яё0-9]+/i).filter(Boolean);
    var hasToken = function(values) {
        return values.some(function(value) { return tokens.indexOf(value) !== -1; });
    };

    if (node && node.lat && node.lng) {
        return {
            lat: Number(node.lat),
            lng: Number(node.lng),
            label: [node.country, node.city].filter(Boolean).join(' ') || node.name
        };
    }

    if (hasToken(['de', 'ger', 'germany', 'deu', 'fra', 'frankfurt'])) {
        return { lat: 50.1109, lng: 8.6821, label: 'Germany - Frankfurt' };
    }
    if (hasToken(['moscow', 'москва', 'msk', 'ru', 'russia', 'россия'])) {
        return { lat: 55.76, lng: 37.62, label: 'Russia - Moscow' };
    }
    if (hasToken(['nl', 'netherlands', 'ams', 'amsterdam'])) {
        return { lat: 52.37, lng: 4.90, label: 'Netherlands - Amsterdam' };
    }
    if (hasToken(['uk', 'gb', 'london', 'united', 'kingdom'])) {
        return { lat: 51.51, lng: -0.13, label: 'United Kingdom - London' };
    }
    if (hasToken(['fi', 'fin', 'finland', 'helsinki'])) {
        return { lat: 60.17, lng: 24.94, label: 'Finland - Helsinki' };
    }
    if (hasToken(['tr', 'turkey', 'istanbul'])) {
        return { lat: 41.01, lng: 28.97, label: 'Turkey - Istanbul' };
    }

    return {
        lat: 50 + (index * 2),
        lng: 10 + (index * 6),
        label: node && node.name ? node.name : 'Node'
    };
}

function admNodePopup(label, node) {
    var alive = node && node.status === 'alive';
    var color = alive ? '#4ade80' : '#f87171';
    var load = node ? node.load_percent + '% load' : 'No data';
    var latency = node && node.latency ? node.latency + ' ms' : '-';
    var status = alive ? 'ONLINE' : 'OFFLINE';

    return '<div style="font-family:Inter,sans-serif;font-size:12px;color:#e6ebf3;'
        + 'background:#0f1825;border-radius:8px;padding:10px 14px;min-width:160px">'
        + '<strong style="font-size:13px;display:block;margin-bottom:6px">' + label + '</strong>'
        + '<span style="color:' + color + ';font-weight:600">' + status + '</span>'
        + ' &middot; ' + load
        + '<br><span style="color:#7a8699;font-size:11px">Latency: ' + latency + '</span>'
        + '</div>';
}

function admMarkerIcon(color) {
    return L.divIcon({
        className: '',
        html: '<div class="adm-marker-wrap">'
            + '<div class="adm-marker-ring" style="border-color:' + color + '"></div>'
            + '<div class="adm-marker-dot" style="background:' + color + ';box-shadow:0 0 6px ' + color + '"></div>'
            + '</div>',
        iconSize: [14, 14],
        iconAnchor: [7, 7],
    });
}

function admEnsureMarker(node, index) {
    if (!window.L || !window._leafletMap || !node) return null;
    if (!window._leafletMarkers) window._leafletMarkers = {};

    var code = admNodeCode(node);
    if (window._leafletMarkers[code]) return window._leafletMarkers[code];

    var geo = admNodeGeo(node, index || 1);
    var color = node.status === 'alive' ? '#4ade80' : '#f87171';
    var marker = L.marker([geo.lat, geo.lng], { icon: admMarkerIcon(color) })
        .addTo(window._leafletMap)
        .on('click', function() { admFocusNode(code); })
        .bindPopup(admNodePopup(geo.label || node.name, node), { className: 'leaflet-dark-popup', closeButton: false });

    window._leafletMarkers[code] = marker;
    return marker;
}

function admFocusNode(code) {
    document.querySelectorAll('.node-chip').forEach(function(chip) {
        chip.style.outline = chip.dataset.nodeCode === code
            ? '2px solid rgba(107,147,192,.85)'
            : '';
    });

    admSwitchView('map');

    if (window._leafletMarkers && window._leafletMarkers[code]) {
        var marker = window._leafletMarkers[code];
        window._leafletMap.setView(marker.getLatLng(), 5, { animate: true });
        setTimeout(function() { marker.openPopup(); }, 350);
    }
}

function admInitMap(nodeData) {
    if (!window.L || !document.getElementById('node-map')) return;

    var lmap = L.map('node-map', {
        center: [54, 18],
        zoom: 3,
        zoomControl: false,
        attributionControl: false,
        scrollWheelZoom: false,
    });

    window._leafletMap = lmap;
    window._leafletMarkers = {};

    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        maxZoom: 19,
    }).addTo(lmap);

    (nodeData || []).forEach(function(item, index) {
        if (!item) return;
        var node = item.node || {
            name: item.label,
            status: 'dead',
            load_percent: 0,
            latency: null,
            lat: item.lat,
            lng: item.lng
        };
        node.lat = node.lat || item.lat;
        node.lng = node.lng || item.lng;
        var marker = admEnsureMarker(node, index + 1);
        if (marker && item.label) {
            marker.setPopupContent(admNodePopup(item.label, node));
        }
    });
}

function admInitChart(labels, data) {
    var ctx = document.getElementById('ordersStatusChart');
    if (!ctx || !window.Chart) return;

    var colors = { paid: '#4ade80', pending: '#fbbf24', cancelled: '#f87171', failed: '#f87171' };
    var bgColors = labels.map(function(label) { return colors[label] || '#4f7eb5'; });

    new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: bgColors,
                borderWidth: 2,
                borderColor: '#080d16',
                hoverOffset: 6,
            }]
        },
        options: {
            cutout: '68%',
            plugins: {
                legend: { labels: { color: '#e6ebf3', font: { family: 'Inter', size: 12 }, padding: 14 } }
            },
            maintainAspectRatio: false,
        }
    });
}

function admApplyHealth(data) {
    if (!data || !data.nodes) return;

    var aliveEl = document.getElementById('hb-alive');
    var loadEl = document.getElementById('hb-avg-load');
    if (aliveEl) aliveEl.textContent = data.alive_nodes + '/' + data.total_nodes;
    if (loadEl) loadEl.textContent = data.avg_load_percent + '%';

    var visibleNames = {};
    var visibleCodes = {};
    data.nodes.forEach(function(node, index) {
        visibleNames[node.name] = true;
        visibleCodes[admNodeCode(node)] = true;
    });

    document.querySelectorAll('.node-chip').forEach(function(chip) {
        if (!visibleNames[chip.dataset.nodeName]) {
            chip.remove();
        }
    });

    if (window._leafletMarkers && window._leafletMap) {
        Object.keys(window._leafletMarkers).forEach(function(code) {
            if (!visibleCodes[code]) {
                window._leafletMap.removeLayer(window._leafletMarkers[code]);
                delete window._leafletMarkers[code];
            }
        });
    }

    data.nodes.forEach(function(node, index) {
        var chip = document.querySelector('.node-chip[data-node-name="' + node.name + '"]');
        if (chip) {
            var alive = node.status === 'alive';
            chip.className = 'node-chip ' + (alive ? 'alive' : 'dead');
            var loadSpan = chip.querySelector('.hb-load');
            var latencySpan = chip.querySelector('.hb-latency');
            if (loadSpan) loadSpan.textContent = node.load_percent + '%';
            if (latencySpan) latencySpan.textContent = node.latency ? node.latency + 'ms' : '';
        }

        var marker = admEnsureMarker(node, index + 1);
        if (!marker) return;

        var color = node.status === 'alive' ? '#4ade80' : '#f87171';
        var el = marker.getElement();
        if (el) {
            var dot = el.querySelector('.adm-marker-dot');
            var ring = el.querySelector('.adm-marker-ring');
            if (dot) {
                dot.style.background = color;
                dot.style.boxShadow = '0 0 6px ' + color;
            }
            if (ring) {
                ring.style.borderColor = color;
            }
        }

        var geo = admNodeGeo(node, index + 1);
        marker.setLatLng([geo.lat, geo.lng]);
        marker.setPopupContent(admNodePopup(geo.label || node.name, node));
    });
}

function admStartPolling(healthUrl) {
    if (!healthUrl) return;

    var poll = function() {
        fetch(healthUrl, { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
            .then(function(response) { return response.ok ? response.json() : null; })
            .then(function(data) { if (data) admApplyHealth(data); })
            .catch(function() {});
    };

    poll();
    setInterval(poll, 15000);
}
