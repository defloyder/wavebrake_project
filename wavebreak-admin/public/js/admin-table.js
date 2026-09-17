// Generic sort + search for any .adm-table-wrap[data-enhance].
// No framework, no server round-trip — admin datasets here are small
// (dozens to low hundreds of rows), so client-side is plenty and keeps
// every page's markup dumb (a plain <table>, nothing bespoke to wire up).
(() => {
  function enhanceTable(wrap) {
    const table = wrap.querySelector('table.adm-table');
    if (!table) return;
    const tbody = table.querySelector('tbody');
    const headers = Array.from(table.querySelectorAll('thead th'));
    const rows = Array.from(tbody.querySelectorAll('tr[data-row]'));
    if (!rows.length) return;

    const toolbar = wrap.previousElementSibling?.classList?.contains('adm-table-toolbar')
      ? wrap.previousElementSibling
      : null;
    const searchInput = toolbar?.querySelector('[data-table-search]');
    const countEl = toolbar?.querySelector('[data-table-count]');

    let sortCol = null;
    let sortDir = 1;

    function applyFilter() {
      const q = (searchInput?.value || '').trim().toLowerCase();
      let visible = 0;
      rows.forEach((row) => {
        const hay = row.getAttribute('data-search') || row.textContent;
        const match = !q || hay.toLowerCase().includes(q);
        row.hidden = !match;
        if (match) visible += 1;
      });
      if (countEl) countEl.textContent = `${visible} / ${rows.length}`;
    }

    function applySort() {
      if (sortCol === null) return;
      const sorted = [...rows].sort((a, b) => {
        const av = a.children[sortCol]?.getAttribute('data-sort') ?? a.children[sortCol]?.textContent.trim() ?? '';
        const bv = b.children[sortCol]?.getAttribute('data-sort') ?? b.children[sortCol]?.textContent.trim() ?? '';
        const an = Number(av);
        const bn = Number(bv);
        const bothNumeric = av !== '' && bv !== '' && !Number.isNaN(an) && !Number.isNaN(bn);
        const cmp = bothNumeric ? an - bn : av.localeCompare(bv, undefined, { sensitivity: 'base' });
        return cmp * sortDir;
      });
      sorted.forEach((row) => tbody.appendChild(row));
    }

    headers.forEach((th, i) => {
      if (th.dataset.sortable === 'false') return;
      th.classList.add('is-sortable');
      th.addEventListener('click', () => {
        if (sortCol === i) {
          sortDir *= -1;
        } else {
          sortCol = i;
          sortDir = 1;
        }
        headers.forEach((h) => h.classList.remove('sort-asc', 'sort-desc'));
        th.classList.add(sortDir === 1 ? 'sort-asc' : 'sort-desc');
        applySort();
      });
    });

    searchInput?.addEventListener('input', applyFilter);
    applyFilter();
  }

  document.querySelectorAll('.adm-table-wrap[data-enhance]').forEach(enhanceTable);
})();

// Traffic pipeline health chip, polled on every admin page (it lives in
// the shared header, not a specific view) — a node agent that's stopped
// reporting usage produces no error anywhere else, so this is the only
// place that would ever say so.
(() => {
  const chip = document.getElementById('traffic-health-chip');
  const text = document.getElementById('traffic-health-text');
  if (!chip || !text) return;

  async function check() {
    try {
      const res = await fetch('/traffic/health', { headers: { Accept: 'application/json' } });
      if (!res.ok) return; // 401 mid-session etc. — next poll retries, don't flap the badge on a blip
      const data = await res.json();
      chip.hidden = false;
      if (data.stale) {
        chip.classList.remove('alive');
        chip.classList.add('dead');
        const mins = data.seconds_since ? Math.round(data.seconds_since / 60) : null;
        text.textContent = mins === null
          ? 'Трафик: нет данных ни разу'
          : `Трафик: не поступает ${mins} мин`;
      } else {
        chip.classList.remove('dead');
        chip.classList.add('alive');
        text.textContent = 'Трафик: поступает';
      }
    } catch (e) { /* transient — next poll retries */ }
  }

  check();
  setInterval(check, 30000);
})();

// Shared by every traffic chart: builds a Chart.js line chart from the
// already-loaded N-day history and wires a Сегодня/7 дней/30 дней toggle
// that just re-slices the same array client-side — the 30-day fetch
// already has everything a shorter range needs, so no extra request.
window.admInitRangeChart = function admInitRangeChart(canvasId, raw, buildDataset) {
  const el = document.getElementById(canvasId);
  if (!el || !window.Chart || !raw.length) return null;

  const axisOptions = {
    responsive: true,
    maintainAspectRatio: false,
    scales: {
      x: { ticks: { color: 'rgba(230,242,247,.55)' }, grid: { color: 'rgba(230,242,247,.06)' } },
      y: { ticks: { color: 'rgba(230,242,247,.55)' }, grid: { color: 'rgba(230,242,247,.06)' }, beginAtZero: true },
    },
  };

  const slice = (days) => raw.slice(Math.max(0, raw.length - days));
  const labelsFor = (rows) => rows.map((r) => new Date(r.date).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit' }));

  const initial = buildDataset(slice(30));
  const chart = new Chart(el, {
    type: 'line',
    data: { labels: labelsFor(slice(30)), datasets: initial.datasets },
    options: { ...axisOptions, plugins: initial.plugins || { legend: { display: false } } },
  });

  const toggle = document.querySelector(`.adm-range-toggle[data-range-for="${canvasId}"]`);
  toggle?.querySelectorAll('button[data-range]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const days = Number(btn.dataset.range);
      const rows = slice(days);
      const built = buildDataset(rows);
      chart.data.labels = labelsFor(rows);
      chart.data.datasets = built.datasets;
      chart.update();
      toggle.querySelectorAll('button').forEach((b) => b.classList.toggle('is-active', b === btn));
    });
  });

  return chart;
};

// Live traffic widget: polls /traffic/live every few seconds and plots the
// delta since the previous poll — a rolling window, not history, so it
// answers "is anything moving right now" rather than "what happened
// today". Pause just stops the timer; the chart keeps whatever it already
// drew, and Resume picks back up from a fresh baseline (no gap-filling —
// simpler, and the gap itself is honest: nothing was sampled then).
window.admInitLiveTraffic = function admInitLiveTraffic(canvasId, btnId) {
  const el = document.getElementById(canvasId);
  const btn = document.getElementById(btnId);
  if (!el || !window.Chart) return null;

  const maxPoints = 40;
  const labels = [];
  const data = [];
  let lastTotal = null;
  let timer = null;
  let running = false;
  const pauseIcon = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M9 6v12M15 6v12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
  const playIcon = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m8 5 11 7-11 7V5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>';

  function setButtonState(label, icon) {
    if (!btn) return;
    btn.innerHTML = icon;
    btn.setAttribute('aria-label', label);
    btn.setAttribute('title', label);
  }

  const chart = new Chart(el, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'MB / интервал',
        data,
        borderColor: '#00D6FF',
        backgroundColor: 'rgba(0,214,255,.12)',
        fill: true,
        tension: .3,
        pointRadius: 2,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: 'rgba(230,242,247,.55)', maxRotation: 0 }, grid: { color: 'rgba(230,242,247,.06)' } },
        y: { ticks: { color: 'rgba(230,242,247,.55)' }, grid: { color: 'rgba(230,242,247,.06)' }, beginAtZero: true },
      },
    },
  });

  async function poll() {
    try {
      const res = await fetch('/traffic/live', { headers: { Accept: 'application/json' } });
      if (!res.ok) return;
      const json = await res.json();
      const total = json.total_bytes || 0;
      if (lastTotal !== null) {
        const deltaMB = Math.max(0, total - lastTotal) / 1048576;
        labels.push(new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
        data.push(Number(deltaMB.toFixed(3)));
        if (labels.length > maxPoints) { labels.shift(); data.shift(); }
        chart.update();
      }
      lastTotal = total;
    } catch (e) { /* transient network hiccup — next poll retries */ }
  }

  function start() {
    running = true;
    setButtonState('Пауза', pauseIcon);
    lastTotal = null; // fresh baseline so resuming doesn't show a fake spike for the paused gap
    poll();
    timer = setInterval(poll, 4000);
  }

  function stop() {
    running = false;
    setButtonState('Продолжить', playIcon);
    if (timer) clearInterval(timer);
  }

  btn?.addEventListener('click', () => (running ? stop() : start()));
  start();

  return { chart, start, stop };
};
