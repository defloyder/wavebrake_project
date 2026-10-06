// Shared admin UI behaviour: modals, AJAX forms and the plan editor.
// Plain DOM, no framework — markup opts in through data-* attributes.
(() => {
  const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content || '';

  // ---- Modals -----------------------------------------------------------
  // [data-modal] backdrops open with admModal.open(id) or [data-modal-open],
  // close on [data-modal-close], a click on the backdrop or Escape.
  const modal = {
    open(id) {
      const el = document.getElementById(id);
      if (!el) return null;
      el.classList.add('open');
      document.body.classList.add('adm-modal-open');
      const focusable = el.querySelector('input:not([type=hidden]), select, textarea, button:not([data-modal-close])');
      setTimeout(() => focusable?.focus(), 30);
      return el;
    },
    close(el) {
      if (typeof el === 'string') el = document.getElementById(el);
      if (!el || !el.classList.contains('open')) return;
      el.classList.remove('open');
      if (!document.querySelector('[data-modal].open')) document.body.classList.remove('adm-modal-open');
      el.dispatchEvent(new CustomEvent('adm:modal-closed'));
    },
  };
  window.admModal = modal;

  document.addEventListener('click', (event) => {
    const opener = event.target.closest('[data-modal-open]');
    if (opener) {
      modal.open(opener.dataset.modalOpen);
      return;
    }
    const closer = event.target.closest('[data-modal-close]');
    if (closer) {
      modal.close(closer.closest('[data-modal]'));
      return;
    }
    if (event.target.matches('[data-modal]')) modal.close(event.target);
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    const open = [...document.querySelectorAll('[data-modal].open')].pop();
    if (open) modal.close(open);
  });

  // ---- Request helper ---------------------------------------------------
  window.admRequest = async (url, options = {}) => {
    const response = await fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      ...options,
      headers: { 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': csrf(), Accept: 'text/html, application/json', ...(options.headers || {}) },
    });
    const type = response.headers.get('content-type') || '';
    const payload = type.includes('application/json') ? await response.json().catch(() => ({})) : await response.text();
    if (!response.ok) {
      const validation = payload && payload.errors ? Object.values(payload.errors).flat().join('\n') : '';
      const error = new Error(validation || (payload && payload.message) || 'Не удалось выполнить действие.');
      error.status = response.status;
      throw error;
    }
    return payload;
  };

  // ---- AJAX forms -------------------------------------------------------
  // form[data-ajax-form]: submit as JSON-expecting request, show errors in
  // [data-form-error], reload the page on success.
  document.addEventListener('submit', async (event) => {
    const form = event.target.closest('form[data-ajax-form]');
    if (!form) return;
    event.preventDefault();
    const button = form.querySelector('[type="submit"]');
    const errorBox = form.querySelector('[data-form-error]');
    if (errorBox) errorBox.hidden = true;
    if (button) button.disabled = true;
    try {
      await window.admRequest(form.action, { body: new FormData(form), headers: { Accept: 'application/json' } });
      window.location.reload();
    } catch (error) {
      if (error.status === 401) { window.location.href = '/login'; return; }
      if (errorBox) { errorBox.textContent = error.message; errorBox.hidden = false; } else { window.alert(error.message); }
      if (button) button.disabled = false;
    }
  });

  // ---- Clickable rows: keyboard support ---------------------------------
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    const row = event.target.closest('.is-clickable');
    if (!row || event.target !== row) return;
    event.preventDefault();
    row.click();
  });

  // ---- Plan editor ------------------------------------------------------
  // Rows carry data-open-plan with the editable fields as JSON; an empty
  // value opens the "new plan" form.
  document.addEventListener('click', async (event) => {
    const del = event.target.closest('[data-plan-delete]');
    if (del) {
      const form = document.getElementById('adm-plan-form');
      if (!confirm('Удалить тариф? Действующие подписки сохранят свои лимиты.')) return;
      del.disabled = true;
      try {
        await window.admRequest(`${form.dataset.planUrl}/delete`, { headers: { Accept: 'application/json' } });
        window.location.reload();
      } catch (error) {
        const box = form.querySelector('[data-form-error]');
        box.textContent = error.message; box.hidden = false; del.disabled = false;
      }
      return;
    }

    const row = event.target.closest('[data-open-plan]');
    if (!row) return;
    const form = document.getElementById('adm-plan-form');
    if (!form) return;
    const plan = row.dataset.openPlan ? JSON.parse(row.dataset.openPlan) : null;
    form.reset();
    form.querySelector('[data-form-error]').hidden = true;
    const deleteButton = form.querySelector('[data-plan-delete]');
    if (plan) {
      form.action = `/plans/${plan.id}`;
      form.dataset.planUrl = `/plans/${plan.id}`;
      form.querySelectorAll('[data-plan-field]').forEach((input) => {
        const value = plan[input.dataset.planField];
        if (input.type === 'checkbox') input.checked = Boolean(value);
        else input.value = value ?? '';
      });
      deleteButton.hidden = false;
    } else {
      form.action = '/plans';
      delete form.dataset.planUrl;
      deleteButton.hidden = true;
    }
    document.getElementById('adm-plan-modal-title').textContent = plan ? `Тариф «${plan.name}»` : 'Новый тариф';
    modal.open('adm-plan-modal');
  });
})();

// ---- Promo code editor -------------------------------------------------
// Same pattern as the plan editor: rows carry data-open-promo with the
// editable fields as JSON; an empty value opens the "new code" form.
(() => {
  const modal = window.admModal;
  document.addEventListener('click', async (event) => {
    const del = event.target.closest('[data-promo-delete]');
    if (del) {
      const form = document.getElementById('adm-promo-form');
      if (!confirm('Удалить промокод вместе с историей активаций?')) return;
      del.disabled = true;
      try {
        await window.admRequest(`${form.dataset.promoUrl}/delete`, { headers: { Accept: 'application/json' } });
        window.location.reload();
      } catch (error) {
        const box = form.querySelector('[data-form-error]');
        box.textContent = error.message; box.hidden = false; del.disabled = false;
      }
      return;
    }

    const row = event.target.closest('[data-open-promo]');
    if (!row) return;
    const form = document.getElementById('adm-promo-form');
    if (!form) return;
    const promo = row.dataset.openPromo ? JSON.parse(row.dataset.openPromo) : null;
    form.reset();
    form.querySelector('[data-form-error]').hidden = true;
    const deleteButton = form.querySelector('[data-promo-delete]');
    if (promo) {
      form.action = `/promo-codes/${promo.id}`;
      form.dataset.promoUrl = `/promo-codes/${promo.id}`;
      form.querySelectorAll('[data-promo-field]').forEach((input) => {
        const value = promo[input.dataset.promoField];
        if (input.type === 'checkbox') input.checked = Boolean(value);
        else input.value = value ?? '';
      });
      deleteButton.hidden = false;
    } else {
      form.action = '/promo-codes';
      delete form.dataset.promoUrl;
      deleteButton.hidden = true;
    }
    document.getElementById('adm-promo-modal-title').textContent = promo ? `Промокод ${promo.code}` : 'Новый промокод';
    modal.open('adm-promo-modal');
  });
})();
