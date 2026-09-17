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
