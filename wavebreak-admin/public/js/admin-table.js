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
